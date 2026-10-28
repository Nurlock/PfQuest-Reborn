-- pfQuest Reborn: Objective Progress Chat Announcements
-- Announces individual quest objective updates to group chat with clickable item links

local L = pfQuest_Loc or setmetatable({}, { __index = function(_, k) return k end })

pfQuestAnnounce = {}

local objectiveState = {}

-- One scan per objective name, rebuilt when the log changes. UI_INFO_MESSAGE
-- fires per loot tick; two full log scans per tick does not scale in raids.
local objectiveCache = {}

local function GetQuestNameForObjective(objectiveName)
  local numQuestLogEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  for i = 1, numQuestLogEntries do
    local questTitle, _, _, _, isHeader = GetQuestLogTitle(i)
    if not isHeader and questTitle then
      local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
      for j = 1, numObjectives do
        local description = GetQuestLogLeaderBoard(j, i)
        if description then
          local objName = string.match(description, "(.*):%s*[-%d]+%s*/%s*[-%d]+%s*$")
          if objName and string.find(string.lower(objName), string.lower(objectiveName), 1, true) then
            local link = GetQuestLink and GetQuestLink(i)
            return link or questTitle
          end
        end
      end
    end
  end
  return nil
end

local function GetItemIdForObjective(objectiveName)
  local numQuestLogEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  for i = 1, numQuestLogEntries do
    local questTitle, _, _, _, isHeader = GetQuestLogTitle(i)
    if not isHeader and questTitle then
      local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
      for j = 1, numObjectives do
        local description = GetQuestLogLeaderBoard(j, i)
        if description then
          local objName = string.match(description, "(.*):%s*[-%d]+%s*/%s*[-%d]+%s*$")
          if objName and string.find(string.lower(objName), string.lower(objectiveName), 1, true) then
            local link = GetQuestLink and GetQuestLink(i)
            local questId = link and tonumber(string.match(link, "quest:(%d+)"))
            if questId and pfDB and pfDB["quests"] and pfDB["quests"]["data"] then
              local qData = pfDB["quests"]["data"][questId]
              if qData and qData["obj"] and qData["obj"]["I"] then
                for _, itemId in pairs(qData["obj"]["I"]) do
                  local iname = GetItemInfo(itemId)
                  if iname and string.find(string.lower(objectiveName), string.lower(iname), 1, true) then
                    return itemId
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return nil
end

pfQuestAnnounce.OnQuestUpdate = function(message)
  local inParty = (GetNumPartyMembers and GetNumPartyMembers() > 0) or (GetNumRaidMembers and GetNumRaidMembers() > 0)
  if not inParty then
    return
  end

  if not message or type(message) ~= "string" then
    return
  end

  local itemName, numItems, numNeeded = string.match(message, "(.*):%s*([-%d]+)%s*/%s*([-%d]+)%s*$")
  if not (itemName and numItems and numNeeded) then
    return
  end

  local iNumItems = tonumber(numItems) or 0
  local iNumNeeded = tonumber(numNeeded) or 1
  local stillNeeded = iNumNeeded - iNumItems

  if not objectiveState[itemName] then
    objectiveState[itemName] = { lastCount = 0, announced = false }
  end

  if objectiveState[itemName].lastCount == iNumItems then
    return
  end
  objectiveState[itemName].lastCount = iNumItems

  local announceFinished = not pfQuest_config or pfQuest_config["epochannounceFinished"] ~= "0"
  local announceRemaining = pfQuest_config and pfQuest_config["epochannounceRemaining"] == "1"

  if stillNeeded < 1 then
    if not announceFinished or objectiveState[itemName].announced then
      return
    end
  else
    objectiveState[itemName].announced = false
    if not announceRemaining then
      return
    end
  end

  local cached = objectiveCache[itemName]
  local questName, itemId
  if cached then
    questName, itemId = cached.questName, cached.itemId
  else
    questName = GetQuestNameForObjective(itemName)
    itemId = GetItemIdForObjective(itemName)
    objectiveCache[itemName] = { questName = questName, itemId = itemId }
  end
  local itemLink = nil
  if itemId and GetItemInfo then
    local _, link = GetItemInfo(itemId)
    itemLink = link
  end

  local outMessage = nil
  local showItem = pfQuest_config and pfQuest_config["epochannounceShowItem"] ~= "0"

  if stillNeeded < 1 then
    objectiveState[itemName].announced = true
    local display = (showItem and itemLink) or itemName
    if questName then
      outMessage = "Finished " .. display .. " for " .. questName .. "."
    else
      outMessage = "Finished " .. display .. "."
    end
  else
    local display = (showItem and itemLink) or itemName
    if questName then
      outMessage = display .. " for " .. questName .. " (" .. stillNeeded .. " left)"
    else
      outMessage = display .. " (" .. stillNeeded .. " left)"
    end
  end

  if outMessage and outMessage ~= "" and SendChatMessage then
    local channel = "PARTY" -- never RAID: one subgroup's chat, no 40-client storm
    SendChatMessage(outMessage, channel)
  end
  return outMessage
end

pfQuestAnnounce.AnnounceQuest = function(questId, title, isTurnIn)
  if pfQuest_config and pfQuest_config["questannounce"] == "0" then
    return
  end
  local inParty = (GetNumPartyMembers and GetNumPartyMembers() > 0) or (GetNumRaidMembers and GetNumRaidMembers() > 0)
  if not inParty then
    return
  end
  local channel = "PARTY" -- never RAID: one subgroup's chat, no 40-client storm
  local qTitle = title
  local numericId = tonumber(questId) or 0
  local level = 0
  if pfDB and pfDB.quests then
    if pfDB.quests.loc and pfDB.quests.loc[numericId] then
      qTitle = pfDB.quests.loc[numericId].T
    end
    if pfDB.quests.data and pfDB.quests.data[numericId] then
      level = pfDB.quests.data[numericId].lvl or 0
    end
  end
  if not qTitle and pfQuest and pfQuest.questlog and pfQuest.questlog[questId] then
    qTitle = pfQuest.questlog[questId].title
  end
  qTitle = qTitle or (type(questId) == "string" and questId) or ("Quest " .. tostring(questId))
  local questLink
  if _G and _G.GetQuestLink and pfQuest and pfQuest.questlog and pfQuest.questlog[questId] and pfQuest.questlog[questId].qlogid then
    questLink = _G.GetQuestLink(pfQuest.questlog[questId].qlogid)
  end
  if not questLink and numericId > 0 then
    questLink = string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", numericId, level, qTitle)
  else
    questLink = questLink or ("[" .. qTitle .. "]")
  end
  local action = isTurnIn and "Quest Turned In" or "Quest Completed"
  local msg = "{rt1} pfQuest: " .. action .. ": " .. questLink .. "!"
  if SendChatMessage then
    SendChatMessage(msg, channel)
  end
end

local frame = CreateFrame("Frame", "pfQuestAnnounceFrame")
frame:RegisterEvent("UI_INFO_MESSAGE")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function(self, event, msg)
  if event == "QUEST_LOG_UPDATE" then
    objectiveCache = {}
  elseif event == "UI_INFO_MESSAGE" and msg then
    pfQuestAnnounce.OnQuestUpdate(msg)
  end
end)
