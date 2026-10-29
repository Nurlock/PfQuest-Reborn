-- partytooltip.lua: display only. Party tooltip hooks and grouping read
-- shared state through pfQuest.partyapi / pfQuest.partyQuestData;
-- orchestration lives in party.lua.

local function GetClassColor(playerName)
    -- self first (no break: a nameless class falls through to group scan,
    -- same as before), then raid or party members in unit order.
    local units = { "player" }
    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if numRaid > 0 then
        for i = 1, numRaid do units[table.getn(units) + 1] = "raid" .. i end
    else
        for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
            units[table.getn(units) + 1] = "party" .. i
        end
    end
    for _, unit in ipairs(units) do
        if UnitName(unit) == playerName then
            local _, class = UnitClass(unit)
            if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
                local c = RAID_CLASS_COLORS[class]
                return { c.r, c.g, c.b }
            end
            if unit ~= "player" then break end
        end
    end
    return { 1.0, 1.0, 1.0 }
end

-- One grouping/dedupe pass over partyQuestData for a single target.
-- Both tooltip hooks share it so they can never render different lines.
local function BuildQuestGroups(targetKey)
    local questGroups = {}
    for playerName, targets in pairs(pfQuest.partyQuestData or {}) do
        if targets[targetKey] then
            for _, data in ipairs(targets[targetKey]) do
                local group = questGroups[data.quest]
                if not group then
                    group = {}
                    questGroups[data.quest] = group
                end
                local isDuplicate = false
                for _, existing in ipairs(group) do
                    if existing.player == playerName and existing.objective == data.objective then
                        existing.current = data.current
                        existing.total = data.total
                        isDuplicate = true
                        break
                    end
                end
                if not isDuplicate then
                    table.insert(group, {
                        player = playerName,
                        objective = data.objective,
                        current = data.current,
                        total = data.total
                    })
                end
            end
        end
    end
    return questGroups
end

-- Shared renderer: [!] quest header plus one class-colored line per
-- member with a red-yellow-green progress ramp. Skips empty groups
-- instead of printing bare spacer lines.
local function AppendPartyLines(tooltip, questGroups)
    if not next(questGroups) then return end
    tooltip:AddLine(" ")
    for questName, lines in pairs(questGroups) do
        tooltip:AddLine("|cff555555[|cffffcc00!|cff555555]|r " .. questName, 1, 1, 0)
        for _, line in ipairs(lines) do
            local classColor = GetClassColor(line.player)
            local perc = line.current / line.total
            local r, g
            if perc <= 0.5 then
                r, g = 1, perc * 2
            else
                r, g = 2 - perc * 2, 1
            end
            local coloredName = string.format("|cFF%02x%02x%02x%s|r",
                classColor[1] * 255, classColor[2] * 255, classColor[3] * 255, line.player)
            tooltip:AddLine(string.format("|cffaaaaaa- |r%s: %s (%d/%d)",
                coloredName, line.objective, line.current, line.total), r, g, 0)
        end
    end
    tooltip:AddLine(" ")
    tooltip:Show()
end

local function HookGameTooltip()
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        local unitName, unit = self:GetUnit()
        if not unitName or not unit then return end
        if UnitIsPlayer(unit) then return end

        if not pfQuest.partyapi.IsInGroup() or not pfQuest.partyapi.IsTooltipEnabled() then return end

        AppendPartyLines(self, BuildQuestGroups(unitName))
    end)

    return true
end

local function HookPfQuestTooltip()
    if not pfMap or not pfMap.ShowTooltip then
        return false
    end

    if not pfQuestCompat then
        return false
    end

    -- Wrap through map's sanctioned seam instead of overwriting its method.
    pfMap:SetTooltipHook(function(orig, self, meta, tooltip)

        tooltip = tooltip or GameTooltip

        local targetKey = meta.spawn or meta.title

        local tooltipName = nil
        local tooltipText = _G["GameTooltipTextLeft1"]
        if tooltipText and tooltipText:GetText() then
            tooltipName = tooltipText:GetText()
        end

        local inParty = pfQuest.partyapi.IsInGroup()
        local featureEnabled = pfQuest.partyapi.IsTooltipEnabled()

        if inParty and featureEnabled then
            pfQuest.partyapi.CaptureTooltipTarget(meta, tooltipName, targetKey)
        end

        local hasPartyData = false
        local matchedKey = nil

        if inParty and featureEnabled then
            if targetKey then
                for playerName, targets in pairs(pfQuest.partyQuestData or {}) do
                    if targets[targetKey] then
                        hasPartyData = true
                        matchedKey = targetKey
                        break
                    end
                end
            end

            if not hasPartyData and tooltipName then
                for playerName, targets in pairs(pfQuest.partyQuestData or {}) do
                    if targets[tooltipName] then
                        hasPartyData = true
                        matchedKey = tooltipName
                        break
                    end
                end
            end
        end

        if hasPartyData and matchedKey then
            orig(self, meta, tooltip)

            if not select(2, tooltip:GetUnit()) then
                AppendPartyLines(tooltip, BuildQuestGroups(matchedKey))
            end

            tooltip:Show()
        else
            orig(self, meta, tooltip)
        end
    end)

    return true
end

-- Tooltip startup: install hooks (pfDB-gated like before).
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "pfQuest-epoch" or addonName == "pfQuest-Reborn" then
        HookGameTooltip()
        local timer = 0
        self:SetScript("OnUpdate", function()
            timer = timer + 1
            if timer > 10 then
                if HookPfQuestTooltip() then
                    self:SetScript("OnUpdate", nil)
                    self:UnregisterAllEvents()
                elseif timer > 300 then
                    self:SetScript("OnUpdate", nil)
                    self:UnregisterAllEvents()
                end
            end
        end)
    end
end)

-- Publish display entry points on the shared party interface.
if pfQuest.partyapi then
    pfQuest.partyapi.HookGameTooltip = HookGameTooltip
    pfQuest.partyapi.HookPfQuestTooltip = HookPfQuestTooltip
end
