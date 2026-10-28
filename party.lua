-- party.lua: everything shared. Owns party sync state (partyQuestData),
-- the pfqe wire, and orchestration into the map/database/quest owners.
-- Display-only code (tooltip hooks) lives in partytooltip.lua and reads
-- this layer through pfQuest.partyapi like any other consumer.

local partyQuestData = {}
local lastBroadcastState = {}
local previousQuestList = {}
local debugMode = false

local function GetDBLoc(category)
    return pfDB and pfDB[category] and (pfDB[category]["loc"] or pfDB[category]["enUS"])
end

-- pfQuest_config defaults come from config.lua; nothing to init here.

local function IsInGroup()
    return (GetNumRaidMembers and GetNumRaidMembers() > 0) or (GetNumPartyMembers and GetNumPartyMembers() > 0)
end

-- Epoch parity + flood safety: sync traffic always goes to PARTY.
-- In a raid that is the sender's subgroup (same as Epoch); raid-wide
-- broadcasts from 40 clients would storm the addon channel every debounce.
local function GetGroupDistribution()
  if IsInGroup() then return "PARTY" end
  return nil
end

local function IsSyncEnabled()
    if pfQuest_config then
        if pfQuest_config["epochgroupsync"] == "0" then return false end
    end
    return true
end

local function IsTooltipEnabled()
    if not IsSyncEnabled() then return false end
    if pfQuest_config then
        if pfQuest_config["showpartytooltips"] == "0" then return false end
    end
    return true
end

local function DeletePartyQuestNodes(questId, sender)
    local pfMap = _G.pfMap
    if not pfMap then return end
    local pfDB = _G.pfDB
    local numQId = tonumber(questId)
    local qData = pfDB and pfDB.quests and pfDB.quests.loc and (pfDB.quests.loc[questId] or (numQId and pfDB.quests.loc[numQId]))
    local qTitle = qData and qData.T or (type(questId) == "string" and questId) or (questId and ("Quest " .. tostring(questId)))
    local nodeTitle = (qTitle and sender) and (qTitle .. " (" .. sender .. ")") or qTitle

    if pfMap.DeleteNode then
        if nodeTitle then
            pfMap:DeleteNode("PARTY", nodeTitle)
        end
        if qTitle then
            pfMap:DeleteNode("PARTY", qTitle)
        end
    end

    -- Store surgery (nodes + reverse indexes) lives in map.lua.
    if pfMap.DeleteNodesWhere then
        pfMap:DeleteNodesWhere("PARTY", function(title, node)
            return (not sender or node.partyMember == sender) and
                (not questId or node.questid == questId or (numQId and node.questid == numQId) or
                node.quest == qTitle or title == nodeTitle or title == qTitle)
        end)
    end
end

-- Batch delete: one store scan for a whole inbound batch instead of one per
-- quest. Same match rule as the single delete, OR-ed over every spec.
local function DeletePartyQuestsNodes(specs, sender)
    local pfMap = _G.pfMap
    if not pfMap then return end
    if pfMap.DeleteNode then
        for _, spec in ipairs(specs) do
            if spec.nodeTitle then pfMap:DeleteNode("PARTY", spec.nodeTitle) end
            if spec.qTitle then pfMap:DeleteNode("PARTY", spec.qTitle) end
        end
    end
    if pfMap.DeleteNodesWhere then
        pfMap:DeleteNodesWhere("PARTY", function(title, node)
            if sender and node.partyMember ~= sender then return false end
            for _, spec in ipairs(specs) do
                if (not spec.qidRaw) or node.questid == spec.qidRaw
                    or (spec.numQId and node.questid == spec.numQId)
                    or node.quest == spec.qTitle
                    or title == spec.nodeTitle or title == spec.qTitle then
                    return true
                end
            end
            return false
        end)
    end
end

-- Resolve a quest id/title pair the way the map push needs it. Shared by the
-- single-quest path and the batch path so they can never disagree.
local function ResolveQuestSpec(questId, questTitle)
    local numQId = tonumber(questId)
    local pfDB = _G.pfDB
    local qTitle = questTitle
    local qId = numQId
    if not qTitle then
        local qData = pfDB and pfDB.quests and pfDB.quests.loc and (pfDB.quests.loc[questId] or (numQId and pfDB.quests.loc[numQId]))
        qTitle = qData and qData.T
    end
    if not qTitle and type(questId) == "string" then qTitle = questId end
    if not qTitle and numQId then qTitle = "Quest " .. tostring(numQId) end
    if not qTitle then return nil end
    if not qId and pfDB and pfDB.quests and pfDB.quests.loc and qTitle then
        for id, data in pairs(pfDB.quests.loc) do
            if data and data.T == qTitle then qId = tonumber(id) or id break end
        end
    end
    return qTitle, qId, numQId
end

local function PartyPushAllowed(playerName)
    if not IsInGroup() or not IsSyncEnabled() then return false end
    if pfQuest_config and pfQuest_config["showpartyobjectives"] == "0" then return false end
    if not playerName or playerName == UnitName("player") then return false end
    return true
end

local function OwnsQuest(questId, qId, qTitle)
    return pfQuest and (pfQuest:HasQuest(questId) or pfQuest:HasQuest(qId) or pfQuest:HasQuest(qTitle))
end

-- Finished-target blacklist for one quest/player. Shared by single and batch adds.
local function ComputePartyDone(qTitle, qId, playerName)
    local partyDone = nil
    local targets = partyQuestData and partyQuestData[playerName]
    if targets then
        for targetName, list in pairs(targets) do
            local tAny, tDone = false, true
            for _, data in ipairs(list) do
                if data.quest == qTitle and (not qId or not data.questId or data.questId == qId) then
                    tAny = true
                    if not (data.total and data.total >= 1 and data.current and data.current >= data.total) then
                        tDone = false
                    end
                end
            end
            if tAny and tDone then
                partyDone = partyDone or {}
                partyDone[targetName] = true
            end
        end
    end
    return partyDone
end

-- Add-half of the map push: pins only, no delete, no redraw. Returns true
-- when pins were drawn. Defined before the wrapper: Lua resolves the
-- upvalue at compile time, so a later local would read as a global.
local function AddPartyQuestNodes(qId, qTitle, playerName, partyDone)
    local pfDatabase = _G.pfDatabase
    if not (_G.pfMap and pfDatabase and pfDatabase.SearchQuestID and qId) then return false end
    pfDatabase:SearchQuestID(qId, {
        addon = "PARTY",
        partyMember = playerName,
        title = qTitle .. " (" .. playerName .. ")",
        quest = qTitle,
        questid = qId,
        color = playerName,
        partyDone = partyDone,
    })
    return true
end

local function UpdatePartyMapNodes(questId, playerName, questTitle)
    if not PartyPushAllowed(playerName) then return end

    local qTitle, qId = ResolveQuestSpec(questId, questTitle)
    if not qTitle then return end

    if OwnsQuest(questId, qId, qTitle) then
        DeletePartyQuestNodes(questId or qTitle, playerName)
        return
    end

    -- Objectives only: finished targets are blacklisted via partyDone so
    -- DONE objectives never draw. Completion state is never shared.
    local partyDone = ComputePartyDone(qTitle, qId, playerName)

    local pfMap = _G.pfMap
    DeletePartyQuestNodes(questId or qTitle, playerName)
    if AddPartyQuestNodes(qId, qTitle, playerName, partyDone) and pfMap then
        pfMap:RequestUpdate()
    end
end


local myQuestMappings = {}

local function CleanupPartyData()
    local validPlayers = {}

    local myName = UnitName("player")
    if myName then
        validPlayers[myName] = true
    end

    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if numRaid > 0 then
        for i = 1, numRaid do
            local name = UnitName("raid" .. i)
            if name then
                validPlayers[name] = true
            end
        end
    else
        for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
            local name = UnitName("party" .. i)
            if name then
                validPlayers[name] = true
            end
        end
    end

    for playerName in pairs(partyQuestData) do
        if not validPlayers[playerName] then
            partyQuestData[playerName] = nil
            DeletePartyQuestNodes(nil, playerName)
        end
    end
end

-- One scan of the player's quest log into {[title] = {{objective, current,
-- total}}}. Rebuild, sync deltas and pin tooltips all share it so the
-- leader-board parse rule lives in exactly one place.
local function GetLogObjectives()
    local byTitle = {}
    for qid = 1, GetNumQuestLogEntries() do
        local questTitle = pfQuestCompat.GetQuestLogTitle(qid)
        if questTitle then
            local list = {}
            byTitle[questTitle] = list
            for i = 1, GetNumQuestLeaderBoards(qid) or 0 do
                local text = GetQuestLogLeaderBoard(i, qid)
                if text then
                    local objName, current, total = string.match(text, "(.*):%s*(%d+)%s*/%s*(%d+)")
                    if objName then
                        table.insert(list, {
                            objective = string.gsub(objName, "^%s*(.-)%s*$", "%1"),
                            current = tonumber(current),
                            total = tonumber(total),
                        })
                    end
                end
            end
        end
    end
    return byTitle
end

local function RebuildQuestMappings()
    if debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Checking pfDB...")
        print("  pfDB exists: " .. tostring(pfDB ~= nil))
        if pfDB then
            print("  pfDB type: " .. type(pfDB))
            print("  pfDB.quests exists: " .. tostring(pfDB.quests ~= nil))
            if pfDB.quests then
                print("  pfDB.quests.data exists: " .. tostring(pfDB.quests.data ~= nil))
            end
        end
        print("  pfQuestCompat exists: " .. tostring(pfQuestCompat ~= nil))
        print("  pfMap exists: " .. tostring(pfMap ~= nil))
    end

    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - pfDB not available")
        end
        return
    end

    if debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Starting quest mapping rebuild")
    end

    local activeQuests = GetLogObjectives()
    if debugMode then
        for questTitle, objectives in pairs(activeQuests) do
            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Found quest: " .. questTitle .. " with " .. table.getn(objectives) .. " objectives")
            for _, o in ipairs(objectives) do
                print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Objective: " .. o.objective .. " (" .. o.current .. "/" .. o.total .. ")")
            end
        end
    end

    if not GetDBLoc("quests") then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - No enUS localization table found")
        end
        return
    end

    for questId, localizedData in pairs(GetDBLoc("quests")) do
        local questTitle = localizedData["T"]

        if questTitle and activeQuests[questTitle] then
            if debugMode then
                print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Matching quest: " .. questTitle .. " (ID: " .. questId .. ")")
            end

            local questData = pfDB["quests"]["data"][questId]
            if questData and questData["obj"] then
                if debugMode then
                    print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Quest has obj table")
                end

                if questData["obj"]["U"] then
                    for _, unitId in pairs(questData["obj"]["U"]) do
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Found unit objective: Unit ID " .. tostring(unitId))
                        end

                        if GetDBLoc("units") and GetDBLoc("units")[unitId] then
                            local targetName = GetDBLoc("units")[unitId]

                            if debugMode then
                                print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Unit name: " .. targetName)
                            end

                            for _, activeObj in ipairs(activeQuests[questTitle]) do
                                if debugMode then
                                    print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Checking if quest log objective matches...")
                                    print("    Quest log: \"" .. activeObj.objective .. "\"")
                                    print("    Target name: \"" .. targetName .. "\"")
                                end

                                local objNameBase = activeObj.objective:gsub(" slain$", ""):gsub(" killed$", "")
                                if objNameBase == targetName or activeObj.objective:find(targetName, 1, true) then
                                    if not myQuestMappings[targetName] then
                                        myQuestMappings[targetName] = {}
                                    end

                                    local found = false
                                    for _, data in ipairs(myQuestMappings[targetName]) do
                                        if data.quest == questTitle and data.objective == activeObj.objective then
                                            data.current = activeObj.current
                                            data.total = activeObj.total
                                            data.questId = questId
                                            data.targetId = unitId
                                            data.targetType = "U"
                                            found = true
                                            break
                                        end
                                    end

                                    if not found then
                                        table.insert(myQuestMappings[targetName], {
                                            quest = questTitle,
                                            questId = questId,
                                            objective = activeObj.objective,
                                            current = activeObj.current,
                                            total = activeObj.total,
                                            targetId = unitId,
                                            targetType = "U"
                                        })
                                    end

                                    if debugMode then
                                        print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Added " .. targetName .. " -> " .. questTitle .. " (" .. activeObj.objective .. ": " .. activeObj.current .. "/" .. activeObj.total .. ")")
                                    end
                                end
                            end
                        end
                    end
                end

                if questData["obj"]["I"] then
                    for _, itemId in pairs(questData["obj"]["I"]) do
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Found item objective: Item ID " .. tostring(itemId))
                        end

                        local itemName = nil
                        if GetDBLoc("items") and GetDBLoc("items")[itemId] then
                            itemName = GetDBLoc("items")[itemId]

                            if debugMode then
                                print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Item name: " .. itemName)
                            end
                        end

                        if pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][itemId] then
                            local itemData = pfDB["items"]["data"][itemId]

                            if itemData["U"] then
                                for unitId, dropRate in pairs(itemData["U"]) do
                                    if GetDBLoc("units") and GetDBLoc("units")[unitId] then
                                        local npcName = GetDBLoc("units")[unitId]

                                        if debugMode then
                                            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - NPC " .. npcName .. " drops " .. (itemName or "item " .. itemId) .. " (" .. dropRate .. "%)")
                                        end

                                        for _, activeObj in ipairs(activeQuests[questTitle]) do
                                            if itemName and activeObj.objective:find(itemName, 1, true) then
                                                if not myQuestMappings[npcName] then
                                                    myQuestMappings[npcName] = {}
                                                end

                                                local found = false
                                                for _, data in ipairs(myQuestMappings[npcName]) do
                                                    if data.quest == questTitle and data.objective == activeObj.objective then
                                                        data.current = activeObj.current
                                                        data.total = activeObj.total
                                                        data.questId = questId
                                                        data.targetId = unitId
                                                        data.itemId = itemId
                                                        data.targetType = "I"
                                                        found = true
                                                        break
                                                    end
                                                end

                                                if not found then
                                                    table.insert(myQuestMappings[npcName], {
                                                        quest = questTitle,
                                                        questId = questId,
                                                        objective = activeObj.objective,
                                                        current = activeObj.current,
                                                        total = activeObj.total,
                                                        targetId = unitId,
                                                        itemId = itemId,
                                                        targetType = "I"
                                                    })
                                                end

                                                if debugMode then
                                                    print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Mapped NPC " .. npcName .. " -> " .. questTitle .. " (" .. activeObj.objective .. ")")
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            if itemData["O"] then
                                for objectId, dropRate in pairs(itemData["O"]) do
                                    if GetDBLoc("objects") and GetDBLoc("objects")[objectId] then
                                        local objName = GetDBLoc("objects")[objectId]

                                        if debugMode then
                                            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Object " .. objName .. " contains " .. (itemName or "item " .. itemId) .. " (" .. dropRate .. "%)")
                                        end

                                        for _, activeObj in ipairs(activeQuests[questTitle]) do
                                            if itemName and activeObj.objective:find(itemName, 1, true) then
                                                if not myQuestMappings[objName] then
                                                    myQuestMappings[objName] = {}
                                                end

                                                local found = false
                                                for _, data in ipairs(myQuestMappings[objName]) do
                                                    if data.quest == questTitle and data.objective == activeObj.objective then
                                                        data.current = activeObj.current
                                                        data.total = activeObj.total
                                                        data.questId = questId
                                                        data.targetId = objectId
                                                        data.itemId = itemId
                                                        data.targetType = "I"
                                                        found = true
                                                        break
                                                    end
                                                end

                                                if not found then
                                                    table.insert(myQuestMappings[objName], {
                                                        quest = questTitle,
                                                        questId = questId,
                                                        objective = activeObj.objective,
                                                        current = activeObj.current,
                                                        total = activeObj.total,
                                                        targetId = objectId,
                                                        itemId = itemId,
                                                        targetType = "I"
                                                    })
                                                end

                                                if debugMode then
                                                    print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Mapped object " .. objName .. " -> " .. questTitle .. " (" .. activeObj.objective .. ")")
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if questData["obj"]["O"] then
                    for _, objectId in pairs(questData["obj"]["O"]) do
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Found object objective: Object ID " .. tostring(objectId))
                        end

                        if GetDBLoc("objects") and GetDBLoc("objects")[objectId] then
                            local objectName = GetDBLoc("objects")[objectId]

                            if debugMode then
                                print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Object name: " .. objectName)
                            end

                            for _, activeObj in ipairs(activeQuests[questTitle]) do
                                if activeObj.objective:find(objectName, 1, true) then
                                    if not myQuestMappings[objectName] then
                                        myQuestMappings[objectName] = {}
                                    end

                                    local found = false
                                    for _, data in ipairs(myQuestMappings[objectName]) do
                                        if data.quest == questTitle and data.objective == activeObj.objective then
                                            data.current = activeObj.current
                                            data.total = activeObj.total
                                            data.questId = questId
                                            data.targetId = objectId
                                            data.targetType = "O"
                                            found = true
                                            break
                                        end
                                    end

                                    if not found then
                                        table.insert(myQuestMappings[objectName], {
                                            quest = questTitle,
                                            questId = questId,
                                            objective = activeObj.objective,
                                            current = activeObj.current,
                                            total = activeObj.total,
                                            targetId = objectId,
                                            targetType = "O"
                                        })
                                    end

                                    if debugMode then
                                        print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Added " .. objectName .. " -> " .. questTitle .. " (" .. activeObj.objective .. ": " .. activeObj.current .. "/" .. activeObj.total .. ")")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if debugMode then
        local count = 0
        for _ in pairs(myQuestMappings) do count = count + 1 end
        print("|cff33ffccpf|cffffffffQuest:|r REBUILD - Complete. Total target mappings: " .. count)
    end
end

local function CaptureMyQuestData(targetKey, questTitle, objectiveText, current, total)
    if debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r CAPTURE - Key: " .. tostring(targetKey) .. ", Quest: " .. tostring(questTitle) .. ", Obj: " .. tostring(objectiveText) .. ", Progress: " .. current .. "/" .. total)
    end

    if not myQuestMappings[targetKey] then
        myQuestMappings[targetKey] = {}
    end

    local found = false
    for _, data in ipairs(myQuestMappings[targetKey]) do
        if data.quest == questTitle and data.objective == objectiveText then
            data.current = current
            data.total = total
            found = true
            break
        end
    end

    if not found then
        table.insert(myQuestMappings[targetKey], {
            quest = questTitle,
            objective = objectiveText,
            current = current,
            total = total
        })
    end
end

-- Tooltip entry point: fold the hovered target's own-log objectives into our
-- outbound mappings so the pins we share stay warm. Display passes meta in;
-- party owns the mutation.
local function CaptureTooltipTarget(meta, tooltipName, targetKey)
    if not (meta and meta["quest"] and targetKey) then return end
    if not (IsInGroup() and IsTooltipEnabled()) then return end
    local cached = GetLogObjectives()[meta["quest"]]
    if not cached then return end
    for _, obj in ipairs(cached) do
        if string.len(obj.objective) > 0 then
            CaptureMyQuestData(targetKey, meta["quest"], obj.objective, obj.current, obj.total)
            if tooltipName and tooltipName ~= targetKey then
                CaptureMyQuestData(tooltipName, meta["quest"], obj.objective, obj.current, obj.total)
            end
        end
    end
end

local function BuildStateString(targetKey, questData)
    return string.format("%s:%s:%d:%d",
        targetKey,
        questData.quest,
        questData.current,
        questData.total)
end

-- Check-key for the delta gate. Item objectives share one wire slot per
-- quest+objective (max-progress merge), so they share one key too; otherwise
-- a merged entry would re-broadcast every pass. Everything else keys on
-- its own target.
local function BroadcastCheckKey(targetKey, data)
    if data.targetType == "I" and data.questId then
        return "C" .. data.questId .. ":" .. (data.objective or "") .. ":" .. data.current .. ":" .. data.total
    end
    return BuildStateString(targetKey, data)
end

-- Drop entries whose quest left the log. Shared by our mappings and our mirror.
local function PruneInactive(map, activeQuests)
    for targetKey, quests in pairs(map) do
        local i = 1
        while i <= table.getn(quests) do
            if not activeQuests[quests[i].quest] then
                table.remove(quests, i)
            else
                i = i + 1
            end
        end

        if table.getn(quests) == 0 then
            map[targetKey] = nil
        end
    end
end

local function BroadcastQuestRemove(questId, questTitle)
    if not IsInGroup() or not IsSyncEnabled() then return end
    local title = questTitle
    local qid = tonumber(questId)
    if not title and qid and GetDBLoc("quests") and GetDBLoc("quests")[qid] then
        title = GetDBLoc("quests")[qid]["T"]
    end
    if not qid and title then
        for targetKey, quests in pairs(myQuestMappings) do
            for _, questData in ipairs(quests) do
                if questData.quest == title and questData.questId then
                    qid = questData.questId
                    break
                end
            end
            if qid then break end
        end
    end
    if not qid or not title then return end
    local channel = GetGroupDistribution() or "PARTY"
    SendAddonMessage("pfqe", string.format("REMOVEQ:%d:%s", qid, title), channel)
end
local function ShareQuestData(forceFullSync)
    if not IsInGroup() or not IsSyncEnabled() then
        return
    end

    local channel = GetGroupDistribution() or "PARTY"
    local myName = UnitName("player")

    local logObjectives = GetLogObjectives()
    local activeQuests = {}
    for questTitle in pairs(logObjectives) do
        activeQuests[questTitle] = true
    end

    for questTitle in pairs(previousQuestList) do
        if not activeQuests[questTitle] then
            local questId = nil

            for targetKey, quests in pairs(myQuestMappings) do
                for _, questData in ipairs(quests) do
                    if questData.quest == questTitle and questData.questId then
                        questId = questData.questId
                        break
                    end
                end
                if questId then break end
            end

            if questId then
                local msg = string.format("REMOVEQ:%d:%s", questId, questTitle)
                SendAddonMessage("pfqe", msg, channel)

                if debugMode then
                    print("|cff33ffccpf|cffffffffQuest:|r REMOVE broadcast - Quest: " .. questTitle .. " (ID: " .. questId .. ")")
                end
            end
        end
    end

    previousQuestList = activeQuests

    PruneInactive(myQuestMappings, activeQuests)

    -- Own mirror must die with the quest too, or our tooltip outlives our log.
    if myName and partyQuestData[myName] then
        PruneInactive(partyQuestData[myName], activeQuests)
        if next(partyQuestData[myName]) == nil then partyQuestData[myName] = nil end
    end

    for targetKey, quests in pairs(myQuestMappings) do
        for _, questData in ipairs(quests) do
            local cached = logObjectives[questData.quest]
            if cached then
                for _, obj in ipairs(cached) do
                    if obj.objective == questData.objective then
                        questData.current = obj.current
                        questData.total = obj.total
                    end
                end
            end
        end
    end

    local changedEntries = {}
    local consolidatedObjectives = {}
    local sentKeys = {} -- check-keys covered by this pass (marked in the delta loop)

    for targetKey, quests in pairs(myQuestMappings) do
        for _, data in ipairs(quests) do
            local checkKey = BroadcastCheckKey(targetKey, data)

            if forceFullSync or not lastBroadcastState[checkKey] then
                if data.questId and data.targetId and data.targetType then
                    sentKeys[checkKey] = true -- covered below: it ships in this pass

                    if data.targetType == "I" then
                        local objKey = data.questId .. ":" .. data.objective

                        if not consolidatedObjectives[objKey] then
                            consolidatedObjectives[objKey] = {
                                questId = data.questId,
                                objective = data.objective,
                                quest = data.quest,
                                current = data.current,
                                total = data.total,
                                targetType = "I",
                                targetId = data.itemId or data.targetId
                            }
                        else
                            if data.current > consolidatedObjectives[objKey].current then
                                consolidatedObjectives[objKey].current = data.current
                            end
                        end
                    else
                        table.insert(changedEntries, {
                            targetKey = targetKey,
                            targetType = data.targetType,
                            targetId = data.targetId,
                            questId = data.questId,
                            current = data.current,
                            total = data.total,
                            quest = data.quest,
                            objective = data.objective
                        })
                    end

                    if debugMode then
                        print("|cff33ffccpf|cffffffffQuest:|r DELTA - Changed: " .. targetKey .. " -> " .. data.quest .. " (" .. data.current .. "/" .. data.total .. ")")
                    end
                end
            end
        end
    end

    for _, entry in pairs(consolidatedObjectives) do
        table.insert(changedEntries, entry)
    end

    if table.getn(changedEntries) == 0 then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r BROADCAST - No changes, skipping")
        end
        return
    end

    local messages = {}
    local currentBatch = "V1|"

    if debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r BROADCAST - Building batches for " .. table.getn(changedEntries) .. " changed entries")
    end

    for _, entry in ipairs(changedEntries) do
        -- Compact format: UxxxQyyy:cc:tt; or OxxxQyyy:cc:tt;
        local entryStr = string.format("%s%dQ%d:%d:%d;",
            entry.targetType,
            entry.targetId,
            entry.questId,
            entry.current,
            entry.total)

        if string.len(currentBatch) + string.len(entryStr) > 250 then
            table.insert(messages, currentBatch)

            if debugMode then
                print("BATCH split at " .. string.len(currentBatch) .. " chars")
            end

            currentBatch = "V1|" .. entryStr
        else
            currentBatch = currentBatch .. entryStr
        end
    end

    if string.len(currentBatch) > 3 then
        table.insert(messages, currentBatch)
    end

    if debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r BROADCAST - Sending " .. table.getn(messages) .. " batched message(s) to " .. channel)
    end

    for i, msg in ipairs(messages) do
        SendAddonMessage("pfqe", msg, channel)

        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r   Batch " .. i .. " (" .. string.len(msg) .. " chars): " .. msg)
        end
    end

    -- Only keys covered this pass count as broadcast. Skipped entries (no IDs
    -- yet) stay absent so a later DB load retries them; stale keys for dead
    -- quests drop out so re-accepted progress re-broadcasts cleanly.
    local prevBroadcastState = lastBroadcastState
    lastBroadcastState = {}
    for targetKey, quests in pairs(myQuestMappings) do
        for _, data in ipairs(quests) do
            local checkKey = BroadcastCheckKey(targetKey, data)
            if sentKeys[checkKey] then
                lastBroadcastState[checkKey] = true
            elseif prevBroadcastState[checkKey] and data.questId and data.targetId and data.targetType then
                lastBroadcastState[checkKey] = true
            end
        end
    end

    for _, entry in ipairs(changedEntries) do
        if entry.targetKey then
            if not partyQuestData[myName] then
                partyQuestData[myName] = {}
            end
            if not partyQuestData[myName][entry.targetKey] then
                partyQuestData[myName][entry.targetKey] = {}
            end

            local found = false
            for i, existing in ipairs(partyQuestData[myName][entry.targetKey]) do
                if existing.quest == entry.quest and existing.objective == entry.objective then
                    partyQuestData[myName][entry.targetKey][i].current = entry.current
                    partyQuestData[myName][entry.targetKey][i].total = entry.total
                    partyQuestData[myName][entry.targetKey][i].lastUpdate = GetTime()
                    found = true
                    break
                end
            end

            if not found then
                table.insert(partyQuestData[myName][entry.targetKey], {
                    quest = entry.quest,
                    objective = entry.objective,
                    current = entry.current,
                    total = entry.total,
                    lastUpdate = GetTime()
                })
            end
        end
    end
end

-- Cap attacker-controlled string lengths: legacy QUEST entries store the
-- sender's target/quest/objective verbatim. Bounds keep one peer from
-- growing partyQuestData without limit.
local MAX_PARTY_NAME_LEN = 128
local MAX_QUEST_TITLE_LEN = 256
local MAX_OBJECTIVE_LEN = 256
local MAX_OBJECTIVES_PER_TARGET = 40

local function SanitizePartyString(s, maxLen)
    if not s then return nil end

    -- Strip chat/tooltip markup so a hostile peer cannot smuggle
    -- clickable links or color codes into GameTooltip lines.
    s = string.gsub(s, "|[cCHhTtRr]", "")
    if string.len(s) > (maxLen or MAX_OBJECTIVE_LEN) then
        s = string.sub(s, 1, maxLen or MAX_OBJECTIVE_LEN)
    end
    if s == "" then return nil end
    return s
end

local function StorePartyObjective(sender, targetName, questId, questTitle, objectiveText, current, total)
    targetName = SanitizePartyString(targetName, MAX_PARTY_NAME_LEN)
    questTitle = SanitizePartyString(questTitle, MAX_QUEST_TITLE_LEN)
    if not targetName or not questTitle then return end
    objectiveText = SanitizePartyString(objectiveText, MAX_OBJECTIVE_LEN)
    if not partyQuestData[sender] then partyQuestData[sender] = {} end
    if not partyQuestData[sender][targetName] then partyQuestData[sender][targetName] = {} end
    local list = partyQuestData[sender][targetName]
    for i, data in ipairs(list) do
        if data.quest == questTitle and (not questId or not data.questId or data.questId == questId) then
            list[i].questId = questId or data.questId
            list[i].objective = objectiveText or data.objective
            list[i].current = current
            list[i].total = total
            list[i].lastUpdate = GetTime()
            return
        end
    end
    if table.getn(list) >= MAX_OBJECTIVES_PER_TARGET then return end
    table.insert(list, {
        quest = questTitle,
        questId = questId,
        objective = objectiveText,
        current = current,
        total = total,
        lastUpdate = GetTime(),
    })
end

local function IsValidProgress(current, total)
    return total and total >= 1 and current and current >= 0 and current <= total
end

local function ParseColonTail(message)
    -- Split "head:<current>:<total>" from the right so names may contain colons.
    local head, current, total = string.match(message, "^(.-):(%d+):(%d+)$")
    if not head then return nil end
    return head, tonumber(current), tonumber(total)
end

local function ParseQuestSpec(head)
    -- Recover QUEST:<target>:<quest>:<objective> with colons allowed in names.
    -- Anchor on the literal prefix. The objective is taken as the segment
    -- after the LAST colon; the target is the segment before the FIRST
    -- colon; the quest is everything between. Ambiguous only when target
    -- itself contains a colon, which unit/object names never do in the DB.
    local body = string.match(head, "^QUEST:(.+)$")
    if not body then return nil end
    local firstColon = string.find(body, ":", 1, true)
    if not firstColon then return nil end
    local revStart = nil
    for i = string.len(body), 1, -1 do
        if string.sub(body, i, i) == ":" then
            revStart = i
            break
        end
    end
    if not revStart or revStart <= firstColon then return nil end
    local targetName = string.sub(body, 1, firstColon - 1)
    local questTitle = string.sub(body, firstColon + 1, revStart - 1)
    local objective = string.sub(body, revStart + 1)
    if string.len(targetName) == 0 or string.len(questTitle) == 0 or string.len(objective) == 0 then
        return nil
    end
    return targetName, questTitle, objective
end

local function ProcessQuestData(sender, message)
    -- Handle consolidated quest removal (new format: REMOVEQ:questId:questTitle).
    -- Title may itself contain colons, so anchor on the numeric id and take the rest.
    local removeQuestId, removeQuestTitle = string.match(message, "^REMOVEQ:(%d+):(.+)$")
    removeQuestTitle = SanitizePartyString(removeQuestTitle, MAX_QUEST_TITLE_LEN) or ""
    if removeQuestId and removeQuestTitle then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r REMOVEQ from " .. sender .. " - Quest: " .. removeQuestTitle .. " (ID: " .. removeQuestId .. ")")
        end

        if partyQuestData[sender] then
            for targetKey, quests in pairs(partyQuestData[sender]) do
                local i = 1
                while i <= table.getn(quests) do
                    local entry = quests[i]
                    if entry.quest == removeQuestTitle and (not entry.questId or entry.questId == tonumber(removeQuestId)) then
                        table.remove(quests, i)
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Removed from " .. targetKey)
                        end
                    else
                        i = i + 1
                    end
                end

                if table.getn(quests) == 0 then
                    partyQuestData[sender][targetKey] = nil
                end
            end
            if next(partyQuestData[sender]) == nil then
                partyQuestData[sender] = nil
            end
        end

        DeletePartyQuestNodes(removeQuestId or removeQuestTitle, sender)

        return
    end

    -- Handle old format for backwards compatibility (REMOVE:targetKey:questTitle).
    -- The key itself never contains a colon; the title may, so split on the first one.
    local removeTarget, removeQuest = string.match(message, "^REMOVE:([^:]+):(.+)$")
    if removeTarget and removeQuest then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r REMOVE from " .. sender .. " - Key: " .. removeTarget .. ", Quest: " .. removeQuest)
        end

        if partyQuestData[sender] and partyQuestData[sender][removeTarget] then
            local i = 1
            while i <= table.getn(partyQuestData[sender][removeTarget]) do
                if partyQuestData[sender][removeTarget][i].quest == removeQuest then
                    table.remove(partyQuestData[sender][removeTarget], i)
                else
                    i = i + 1
                end
            end

            if table.getn(partyQuestData[sender][removeTarget]) == 0 then
                partyQuestData[sender][removeTarget] = nil
            end
        end

        DeletePartyQuestNodes(removeQuest, sender)

        return
    end

    if string.sub(message, 1, 3) == "V1|" then
        local batch = string.sub(message, 4)

        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r RECEIVE V1 batch from " .. sender .. " (" .. string.len(message) .. " chars)")
        end

        local entries = {}
        for entry in string.gmatch(batch, "([^;]+)") do
            table.insert(entries, entry)
        end

        local touchedQuests = {}

        -- One quest-log scan per batch, shared with rebuild and tooltips.
        local logObjectives = GetLogObjectives()

        for _, entry in ipairs(entries) do
            -- Parse: UxxxQyyy:cc:tt or OxxxQyyy:cc:tt or IxxxQyyy:cc:tt
            local targetType, targetId, questId, current, total =
                string.match(entry, "^([UIO])(%d+)Q(%d+):(%d+):(%d+)$")

            if targetType and targetId and questId and current and total then
                targetId = tonumber(targetId)
                questId = tonumber(questId)
                current = tonumber(current)
                total = tonumber(total)

                if not IsValidProgress(current, total) then
                    if debugMode then
                        print("|cff33ffccpf|cffffffffQuest:|r rejected out-of-range V1 entry: " .. tostring(entry))
                    end
                else
                local questTitle = nil
                local objectiveText = nil
                if GetDBLoc("quests") and GetDBLoc("quests")[questId] then
                    questTitle = GetDBLoc("quests")[questId]["T"]

                    local cached = logObjectives[questTitle]
                    if cached then
                        for _, obj in ipairs(cached) do
                            if obj.total == total then
                                objectiveText = obj.objective
                                break
                            end
                        end
                    end

                    if not objectiveText then
                        -- Fall back to the resolved target name (unit/object) so
                        -- tooltips stay meaningful for quests we don't share.
                        -- targetName is nil here (V1 carries ids, not names);
                        -- resolve it the same way the U/O branches do below.
                        local fallbackName = nil
                        if targetType == "U" and GetDBLoc("units") then
                            fallbackName = GetDBLoc("units")[targetId]
                        elseif targetType == "O" and GetDBLoc("objects") then
                            fallbackName = GetDBLoc("objects")[targetId]
                        end
                        objectiveText = fallbackName or "Quest Objective"
                    end
                end

                if questTitle then touchedQuests[questId] = questTitle end

                if targetType == "I" then
                    if pfDB and pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][targetId] then
                        local itemData = pfDB["items"]["data"][targetId]

                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Expanding item quest - Item ID: " .. targetId)
                        end

                        if itemData["U"] then
                            local npcCount = 0
                            for unitId, dropRate in pairs(itemData["U"]) do
                                if GetDBLoc("units") and GetDBLoc("units")[unitId] then
                                    StorePartyObjective(sender, GetDBLoc("units")[unitId], questId, questTitle, objectiveText, current, total)
                                    npcCount = npcCount + 1
                                end
                            end

                            if debugMode then
                                print("|cff33ffccpf|cffffffffQuest:|r   Expanded to " .. npcCount .. " NPCs for item " .. targetId)
                            end
                        end

                        if itemData["O"] then
                            for objectId, dropRate in pairs(itemData["O"]) do
                                if GetDBLoc("objects") and GetDBLoc("objects")[objectId] then
                                    StorePartyObjective(sender, GetDBLoc("objects")[objectId], questId, questTitle, objectiveText, current, total)
                                end
                            end
                        end
                    else
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Failed to expand item quest - Item ID " .. targetId .. " not found in database")
                        end
                    end
                elseif targetType == "U" then
                    local targetName = nil
                    if GetDBLoc("units") then
                        targetName = GetDBLoc("units")[targetId]
                    end

                    if targetName and questTitle then
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Parsed: U" .. targetId .. "Q" .. questId .. " -> " .. targetName .. ": " .. questTitle .. " (" .. current .. "/" .. total .. ")")
                        end
                        StorePartyObjective(sender, targetName, questId, questTitle, objectiveText, current, total)
                    else
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Failed to resolve: U" .. targetId .. "Q" .. questId)
                        end
                    end
                elseif targetType == "O" then
                    local targetName = nil
                    if GetDBLoc("objects") then
                        targetName = GetDBLoc("objects")[targetId]
                    end

                    if targetName and questTitle then
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Parsed: O" .. targetId .. "Q" .. questId .. " -> " .. targetName .. ": " .. questTitle .. " (" .. current .. "/" .. total .. ")")
                        end
                        StorePartyObjective(sender, targetName, questId, questTitle, objectiveText, current, total)
                    else
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r   Failed to resolve: O" .. targetId .. "Q" .. questId)
                        end
                    end
                end
                end
            else
                if debugMode then
                    print("|cff33ffccpf|cffffffffQuest:|r   Failed to parse entry: " .. entry)
                end
            end
        end

        -- One delete scan for the whole batch, then per-quest adds, one redraw.
        if PartyPushAllowed(sender) and next(touchedQuests) then
            local specs = {}
            for questId, questTitle in pairs(touchedQuests) do
                local qTitle, qId, numQId = ResolveQuestSpec(questId, questTitle)
                if qTitle then
                    table.insert(specs, {
                        qidRaw = questId,
                        qTitle = qTitle,
                        qId = qId,
                        numQId = numQId,
                        nodeTitle = qTitle .. " (" .. sender .. ")",
                    })
                end
            end
            if table.getn(specs) > 0 then
                DeletePartyQuestsNodes(specs, sender)
                local added, pfMap = false, _G.pfMap
                for _, spec in ipairs(specs) do
                    if OwnsQuest(spec.qidRaw, spec.qId, spec.qTitle) then
                        DeletePartyQuestNodes(spec.qidRaw or spec.qTitle, sender)
                    elseif AddPartyQuestNodes(spec.qId, spec.qTitle, sender, ComputePartyDone(spec.qTitle, spec.qId, sender)) then
                        added = true
                    end
                end
                if added and pfMap then pfMap:RequestUpdate() end
            end
        end

        return
    end

    -- Legacy QUEST format: counts are anchored from the right, then the three
    -- name fields are recovered greedily so colons inside names still parse.
    -- NOTE: ParseColonTail requires the message to end in ":<c>:<t>"; the V1|
    -- and REMOVE branches above already returned, so anything reaching here
    -- with a different shape yields nil and falls through silently.
    local tailHead, current, total = ParseColonTail(message)
    if not tailHead then
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r QUEST parse: no trailing counts in (" .. string.len(message) .. " chars)")
        end
        return
    end
    local targetName, questTitle, objective = ParseQuestSpec(tailHead)
    if (not targetName) and debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r QUEST parse failed for: " .. tostring(tailHead))
    end

    if targetName and questTitle and objective and current and total then
        if not IsValidProgress(current, total) then
            if debugMode then
                print("|cff33ffccpf|cffffffffQuest:|r rejected out-of-range QUEST progress: " .. current .. "/" .. total)
            end
            return
        end
        if debugMode then
            print("|cff33ffccpf|cffffffffQuest:|r RECEIVE from " .. sender .. " - Key: " .. targetName .. ", Quest: " .. questTitle .. ", Progress: " .. current .. "/" .. total)
        end

        StorePartyObjective(sender, targetName, nil, questTitle, objective, current, total)

        local legacyQuestId = nil
        for targetKey, quests in pairs(myQuestMappings) do
            for _, data in ipairs(quests) do
                if data.quest == questTitle and data.questId then
                    legacyQuestId = data.questId
                    break
                end
            end
            if legacyQuestId then break end
        end
        UpdatePartyMapNodes(legacyQuestId, sender, questTitle)
    end
end
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
-- Per-sender inbound throttle: a buggy peer blasting V1 batches must not
-- hold us in SearchQuestID rebuilds. Bursts queue per sender and flush
-- in order; batches are deltas, so newest-wins would lose data.
local lastInboundBySender = {}
-- Inbound burst cap per sender; beyond it the oldest queued batch drops.
-- Normal traffic (even full-sync multi-batch) stays far below this.
local MAX_QUEUED_BATCHES = 16

local pendingInboundBySender = {}
local INBOUND_THROTTLE_SECS = 1

local function IsTrustedSender(sender, channel)
    if type(sender) ~= "string" or sender == "" then return false end
    local myName = UnitName and UnitName("player")
    local clean = string.match(sender, "^([^-]+)") or sender
    if myName and (sender == myName or clean == myName) then return false end
    if channel ~= "PARTY" then return false end -- we only ever send PARTY
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        if UnitInRaid then
            return UnitInRaid(sender) ~= nil
        end
        return true
    end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        if UnitInParty then
            return UnitInParty(sender)
        end
        return true
    end
    return false
end

local function InboundAllowed(sender)
    if not sender then return false end
    local now = GetTime() or 0
    local last = lastInboundBySender[sender] or -INBOUND_THROTTLE_SECS
    if now - last < INBOUND_THROTTLE_SECS then
        return false
    end
    lastInboundBySender[sender] = now
    return true
end

local function HandlePfqeMessage(sender, message)
    if string.sub(message or "", 1, 8) == "REMOVEQ:" then
        ProcessQuestData(sender, message)
    elseif string.sub(message or "", 1, 3) == "V1|" then
        if InboundAllowed(sender) then
            ProcessQuestData(sender, message)
        else
            local queued = pendingInboundBySender[sender]
            if not queued then queued = {} pendingInboundBySender[sender] = queued end
            if table.getn(queued) >= MAX_QUEUED_BATCHES then table.remove(queued, 1) end
            table.insert(queued, message)
            if debugMode then
                print("|cff33ffccpf|cffffffffQuest:|r inbound batch from " .. tostring(sender) .. " queued")
            end
        end
    elseif debugMode then
        print("|cff33ffccpf|cffffffffQuest:|r unknown pfqe batch version (" .. string.sub(message or "", 1, 6) .. ")")
    end
end

local inboundFlushAccum = 0
local inboundFlushLast = nil
local questLogSyncPending = false
local questLogSyncAccum = 0
local questLogSyncLast = nil
local QUEST_LOG_SYNC_DEBOUNCE = 2

local function FlushPendingInbound(elapsed)
    inboundFlushAccum = inboundFlushAccum + (elapsed or 0)
    if inboundFlushAccum < INBOUND_THROTTLE_SECS then return end
    inboundFlushAccum = 0
    if not IsSyncEnabled() then return end
    for sender, queued in pairs(pendingInboundBySender) do
        pendingInboundBySender[sender] = nil
        if IsTrustedSender(sender, GetGroupDistribution()) and InboundAllowed(sender) then
            for _, message in ipairs(queued) do
                ProcessQuestData(sender, message)
            end
        end
    end
end

-- Test hook: advance pending timers without a frame tick.
-- Uses GetTime deltas so mocked AdvanceTime drives it deterministically.
-- Slow safety net: a full re-share every few minutes while grouped heals
-- anything missed (reloads, dropped batches). Idle cost is ~zero: with no
-- changes ShareQuestData sends nothing.
local fullSyncLast = nil
local FULL_SYNC_INTERVAL_SECS = 300

local function PumpSyncTimers()
    -- Sync tracing follows /db debug live (prints are everywhere below).
    debugMode = pfQuest_config and pfQuest_config.debug and true or false
    local now = (GetTime and GetTime()) or 0
    if inboundFlushLast == nil then inboundFlushLast = now end
    if questLogSyncLast == nil then questLogSyncLast = now end
    FlushPendingInbound(now - inboundFlushLast)
    inboundFlushLast = now
    questLogSyncAccum = questLogSyncAccum + (now - questLogSyncLast)
    questLogSyncLast = now
    if questLogSyncPending and questLogSyncAccum >= QUEST_LOG_SYNC_DEBOUNCE then
        questLogSyncPending = false
        questLogSyncAccum = 0
        if IsInGroup() and IsSyncEnabled() then
            RebuildQuestMappings()
            ShareQuestData()
        end
    end
    if fullSyncLast == nil then fullSyncLast = now end
    if IsInGroup() and IsSyncEnabled() and now - fullSyncLast >= FULL_SYNC_INTERVAL_SECS then
        fullSyncLast = now
        RebuildQuestMappings()
        ShareQuestData(true)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        -- Real 3.3.5a client sets bare arg1..arg4 globals; tests pass varargs.
        local prefix, message, channel, sender = a1 or arg1, a2 or arg2, a3 or arg3, a4 or arg4
        if prefix == "pfqe" then
            if IsSyncEnabled() and IsTrustedSender(sender, channel) then
                HandlePfqeMessage(sender, message)
            end
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        CleanupPartyData()
        if IsInGroup() and IsSyncEnabled() then
            RebuildQuestMappings()
            ShareQuestData(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        CleanupPartyData()
        if IsInGroup() and IsSyncEnabled() then
            RebuildQuestMappings()
            -- One request per login: pulls full state from peers that never
            -- push unprompted (Epoch has no periodic share). We never answer
            -- requests, so this cannot amplify into a storm.
            SendAddonMessage("PFQUEST_SYNC_REQUEST", "1", GetGroupDistribution() or "PARTY")
            ShareQuestData(true)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        -- Debounce: kills/loot fire this per tick; rebuild+share at most
        -- once per QUEST_LOG_SYNC_DEBOUNCE seconds, flushed by OnUpdate.
        if IsInGroup() and IsSyncEnabled() then
            questLogSyncPending = true
        end
    end
    -- Pump pending inbound + debounced quest-log sync on every event tick.
    -- (The frame ticker below covers quiet periods with no events.)
    PumpSyncTimers()
end)

-- Frame ticker so debounced sync and inbound flushes do not stall when
-- no events fire after a kill (OnUpdate and OnEvent coexist on one frame).
eventFrame:SetScript("OnUpdate", function()
    PumpSyncTimers()
end)

local configExtenderFrame = CreateFrame("Frame")
configExtenderFrame:RegisterEvent("ADDON_LOADED")
configExtenderFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "pfQuest-epoch" or addonName == "pfQuest-Reborn" then
        -- (config defaults already applied by config.lua)

        if IsInGroup() and IsSyncEnabled() then
            RebuildQuestMappings()
            if debugMode then
                print("|cff33ffccpf|cffffffffQuest:|r Addon loaded, rebuilding and sharing")
            end
            ShareQuestData(true)
        end

        local timer = 0
        local rebuildRetries = 0
        self:SetScript("OnUpdate", function()
            timer = timer + 1

            if rebuildRetries < 50 and (not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"]) then
                if timer % 5 == 0 then
                    rebuildRetries = rebuildRetries + 1
                    if pfDB and pfDB["quests"] and pfDB["quests"]["data"] then
                        if debugMode then
                            print("|cff33ffccpf|cffffffffQuest:|r pfDB now available, rebuilding quest mappings")
                        end
                        RebuildQuestMappings()
                        if IsInGroup() and IsSyncEnabled() then
                            ShareQuestData(true)
                        end
                        self:SetScript("OnUpdate", nil)
                        self:UnregisterAllEvents()
                    end
                end
            end

            if timer > 300 then
                self:SetScript("OnUpdate", nil)
                self:UnregisterAllEvents()
            end
        end)
    end
end)

-- Expose module interface
pfQuest.partyQuestData = partyQuestData
pfQuest.partyapi = {
    eventFrame = eventFrame,
    configExtenderFrame = configExtenderFrame,
    ProcessQuestData = ProcessQuestData,
    StorePartyObjective = StorePartyObjective,
    IsValidProgress = IsValidProgress,
    ParseColonTail = ParseColonTail,
    ParseQuestSpec = ParseQuestSpec,
    ShareQuestData = ShareQuestData,
    BroadcastQuestRemove = BroadcastQuestRemove,
    RebuildQuestMappings = RebuildQuestMappings,
    CleanupPartyData = CleanupPartyData,
    IsInGroup = IsInGroup,
    IsSyncEnabled = IsSyncEnabled,
    IsTooltipEnabled = IsTooltipEnabled,
    GetGroupDistribution = GetGroupDistribution,
    IsTrustedSender = IsTrustedSender,
    InboundAllowed = InboundAllowed,
    HandlePfqeMessage = HandlePfqeMessage,
    CaptureTooltipTarget = CaptureTooltipTarget,
    PumpSyncTimers = PumpSyncTimers,
    partyQuestData = partyQuestData,
    myQuestMappings = myQuestMappings,
}