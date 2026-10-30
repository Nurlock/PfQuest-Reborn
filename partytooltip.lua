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
    if not targetKey then return questGroups end
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
            local current = tonumber(line.current) or 0
            local total = tonumber(line.total) or 0
            local perc = (total > 0) and (current / total) or 0
            if perc < 0 then perc = 0 elseif perc > 1 then perc = 1 end
            local r, g
            if perc <= 0.5 then
                r, g = 1, perc * 2
            else
                r, g = 2 - perc * 2, 1
            end
            local coloredName = string.format("|cFF%02x%02x%02x%s|r",
                classColor[1] * 255, classColor[2] * 255, classColor[3] * 255, tostring(line.player or ""))
            tooltip:AddLine(string.format("|cffaaaaaa- |r%s: %s (%d/%d)",
                coloredName, tostring(line.objective or "Objective"), current, total), r, g, 0)
        end
    end
    tooltip:AddLine(" ")
    tooltip:Show()
end

-- HookScript stacks: without this, the epoch+Reborn migration (both folders
-- installed) or a double ADDON_LOADED would render every line twice.
local gameTooltipHooked = false
local function HookGameTooltip()
    if gameTooltipHooked then return true end
    gameTooltipHooked = true
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        local unitName, unit = self:GetUnit()
        if not unitName or not unit then return end
        if UnitIsPlayer(unit) then return end

        if not pfQuest.partyapi.IsInGroup() or not pfQuest.partyapi.IsTooltipEnabled() then return end

        AppendPartyLines(self, BuildQuestGroups(unitName))
    end)

    return true
end

-- Title line of a tooltip frame, whatever frame shows it.
local function GetTooltipTitle(tooltip)
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    local line = (name and _G[name .. "TextLeft1"]) or _G["GameTooltipTextLeft1"]
    if line and line.GetText then
        return line:GetText()
    end
    return nil
end

-- SetTooltipHook wraps (never replaces): without this, the retry ticker below
-- would stack a new wrapper on every tick.
local pfQuestTooltipHooked = false
local function HookPfQuestTooltip()
    if pfQuestTooltipHooked then return true end
    if not pfMap or not pfMap.ShowTooltip then
        return false
    end

    if not pfQuestCompat then
        return false
    end

    -- Wrap through map's sanctioned seam instead of overwriting its method.
    pfQuestTooltipHooked = true
    pfMap:SetTooltipHook(function(orig, self, meta, tooltip)
        tooltip = tooltip or GameTooltip

        local targetKey = meta and (meta.spawn or meta.title)
        local tooltipName = GetTooltipTitle(tooltip)

        orig(self, meta, tooltip)

        -- orig() draws the title line; re-read it for the fallback lookup.
        tooltipName = GetTooltipTitle(tooltip) or tooltipName

        if not (pfQuest.partyapi.IsInGroup() and pfQuest.partyapi.IsTooltipEnabled()) then
            return
        end

        pfQuest.partyapi.CaptureTooltipTarget(meta, tooltipName, targetKey)

        -- A unit tooltip is the game hook's job; never double-render.
        if tooltip.GetUnit and select(2, tooltip:GetUnit()) then
            return
        end

        local questGroups = BuildQuestGroups(targetKey)
        if not next(questGroups) and tooltipName and tooltipName ~= targetKey then
            questGroups = BuildQuestGroups(tooltipName)
        end

        AppendPartyLines(tooltip, questGroups)
    end)

    return true
end

-- Tooltip startup: install hooks (pfDB-gated like before).
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "pfQuest-epoch" or addonName == "pfQuest-Reborn" then
        HookGameTooltip()
        -- pfMap is usually ready by now; only run the ticker when it is not.
        if HookPfQuestTooltip() then
            self:UnregisterAllEvents()
            return
        end
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
