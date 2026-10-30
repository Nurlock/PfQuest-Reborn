-- pfQuest Reborn: Nameplate Quest Objective Icons
-- Displays sword (slay) and bag (loot) markers on enemy nameplates for active quest objectives

local questObjectives = {}
local nameplateFrames = {}
local iconFrames = {}
local unusedIconFrames = {}
local frameCount = 0

local ICON_SIZE = 16
local NAMEPLATE_BORDER = "Interface\\Tooltips\\Nameplate-Border"

local function GetSlayIcon()
  local path = pfQuestConfig and pfQuestConfig.path or "Interface\\AddOns\\pfQuest-Reborn"
  return path .. "\\img\\slay"
end

local function GetLootIcon()
  local path = pfQuestConfig and pfQuestConfig.path or "Interface\\AddOns\\pfQuest-Reborn"
  return path .. "\\img\\loot"
end

pfQuestNameplates = {
  questObjectives = questObjectives,
}

local function ScanQuestObjectives()
  for k in pairs(questObjectives) do
    questObjectives[k] = nil
  end

  if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
    return
  end

  local questLoc = pfDB["quests"]["loc"] or pfDB["quests"]["enUS"]
  local unitLoc = pfDB["units"] and (pfDB["units"]["loc"] or pfDB["units"]["enUS"])
  local itemLoc = pfDB["items"] and (pfDB["items"]["loc"] or pfDB["items"]["enUS"])

  if not questLoc then
    return
  end

  local swordIcon = GetSlayIcon()
  local bagIcon = GetLootIcon()

  local activeQuests = {}
  local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  for qid = 1, numEntries do
    -- Note: 3.3.5a returns questID as 9th value; older clients return 8 (nil
    -- here) and fall through to the lookups below.
    local questTitle, _, _, _, isHeader, _, complete, _, logQuestId = GetQuestLogTitle(qid)
    if questTitle and not isHeader and complete ~= 1 then
      -- Direct ID from the client: zero lookups. Non-3.3.5a clients get nil
      -- and use the link / log / index / scan fallbacks below.
      local questId = (type(logQuestId) == "number" and logQuestId > 0) and logQuestId or nil
      if not questId and GetQuestLink then
        local link = GetQuestLink(qid)
        questId = link and tonumber(string.match(link, "quest:(%d+)"))
      end
      if not questId and pfQuest and pfQuest.GetIdByLog then
        questId = pfQuest:GetIdByLog(qid, questTitle)
      end
      if not questId and questLoc then
        -- O(1) title lookup via the shared name index (rebuilt on locale
        -- detection); the linear scan below is fallback only. This runs on
        -- every QUEST_LOG_UPDATE, i.e. every quest kill/loot tick.
        local byName = pfDatabase.nameIndex["quests"] and pfDatabase.nameIndex["quests"][questTitle]
        questId = byName and byName[1]
        if not questId then
          for qId, qData in pairs(questLoc) do
            if qData.T == questTitle then
              questId = qId
              break
            end
          end
        end
      end

      if questId then
        activeQuests[questId] = activeQuests[questId] or {}
        local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(qid) or 0
        for i = 1, numObjectives do
          local text, objType, finished = GetQuestLogLeaderBoard(i, qid)
          if text and not finished then
            local objName, current, total = string.match(text, "(.*):%s*(%d+)%s*/%s*(%d+)")
            if objName then
              objName = string.gsub(objName, "^%s*(.-)%s*$", "%1")
              table.insert(activeQuests[questId], {
                objective = objName,
                current = tonumber(current) or 0,
                total = tonumber(total) or 1
              })
            end
          end
        end
      end
    end
  end

  for questId, activeObjs in pairs(activeQuests) do
    local questData = pfDB["quests"]["data"][questId]
    if questData and questData["obj"] then
      if questData["obj"]["U"] then
        for _, unitId in pairs(questData["obj"]["U"]) do
          if unitLoc and unitLoc[unitId] then
            local targetName = unitLoc[unitId]

            -- No counted objectives yet (quest just accepted, server has not
            -- populated the leaderboards): everything is still needed.
            local objectives = activeObjs
            if table.getn(objectives) == 0 then
              objectives = { { objective = targetName, current = 0, total = 1 } }
            end
            for _, activeObj in ipairs(objectives) do
              local objNameBase = activeObj.objective:gsub(" slain$", ""):gsub(" killed$", "")
              if objNameBase == targetName or string.find(activeObj.objective, targetName, 1, true) then
                if activeObj.current < activeObj.total then
                  questObjectives[targetName] = swordIcon
                end
              end
            end
          end
        end
      end

      if questData["obj"]["I"] then
        for _, itemId in pairs(questData["obj"]["I"]) do
          local itemName = itemLoc and itemLoc[itemId]
          local itemData = pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][itemId]

          if itemData and itemData["U"] then
            for unitId in pairs(itemData["U"]) do
              if unitLoc and unitLoc[unitId] then
                local npcName = unitLoc[unitId]

            -- Same fallback: unpopulated log means 0/x everywhere.
            local objectives = activeObjs
            if table.getn(objectives) == 0 and itemName then
              objectives = { { objective = itemName, current = 0, total = 1 } }
            end
            for _, activeObj in ipairs(objectives) do
                  if itemName and string.find(activeObj.objective, itemName, 1, true) then
                    if activeObj.current < activeObj.total then
                      questObjectives[npcName] = bagIcon
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

pfQuestNameplates.Scan = ScanQuestObjectives

local function IsNameplate(frame)
  if not frame then return false end

  if frame.GetRegions then
    local _, borderRegion = frame:GetRegions()
    if borderRegion and borderRegion.GetObjectType and borderRegion:GetObjectType() == "Texture" then
      if borderRegion.GetTexture and borderRegion:GetTexture() == NAMEPLATE_BORDER then
        return true
      end
    end
  end

  if frame.UnitFrame or frame.extended or frame.aloftData or frame.kui then
    return true
  end

  return false
end

local cachedScale, cachedX, cachedY = 1, -25, -5

local function UpdateCachedSettings()
  cachedScale = (pfQuest_config and pfQuest_config["nameplateScale"]) and tonumber(pfQuest_config["nameplateScale"]) or 1
  cachedX = (pfQuest_config and pfQuest_config["nameplateX"]) and tonumber(pfQuest_config["nameplateX"]) or -25
  cachedY = (pfQuest_config and pfQuest_config["nameplateY"]) and tonumber(pfQuest_config["nameplateY"]) or -5
end

local function GetIconFrame(nameplateFrame)
  if iconFrames[nameplateFrame] then
    return iconFrames[nameplateFrame]
  end

  if frameCount >= 300 then
    return nil
  end

  local frame = table.remove(unusedIconFrames)

  if not frame then
    frame = CreateFrame("Frame")
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetAllPoints(frame)
    frameCount = frameCount + 1
  end

  frame:SetParent(nameplateFrame)
  frame:SetFrameStrata("BACKGROUND")
  frame:SetFrameLevel(1)
  frame:SetWidth(ICON_SIZE * cachedScale)
  frame:SetHeight(ICON_SIZE * cachedScale)
  frame:SetPoint("LEFT", cachedX, cachedY)
  if frame.EnableMouse then frame:EnableMouse(false) end

  iconFrames[nameplateFrame] = frame
  return frame
end

local function RemoveIconFrame(nameplateFrame)
  local frame = iconFrames[nameplateFrame]
  if not frame then
    return
  end

  frame.Icon:SetTexture(nil)
  frame:Hide()
  frame.lastIcon = nil
  table.insert(unusedIconFrames, frame)
  iconFrames[nameplateFrame] = nil
end

local function OnNameplateShow(nameplateFrame)
  if not pfQuest_config or pfQuest_config["epochnameplatesEnabled"] ~= "1" then
    return
  end

  local nameText = nameplateFrames[nameplateFrame]
  if not nameText or not nameText.GetText then return end

  local unitName = nameText:GetText()
  if not unitName then return end

  local icon = questObjectives[unitName]

  if icon then
    local frame = GetIconFrame(nameplateFrame)
    if frame then
      if frame.lastIcon ~= icon then
        frame.Icon:SetTexture(icon)
        frame.lastIcon = icon
      end
      frame:Show()
    end
  else
    RemoveIconFrame(nameplateFrame)
  end
end

local function OnNameplateHide(nameplateFrame)
  RemoveIconFrame(nameplateFrame)
end

local function ScanWorldFrameChildren(...)
  local numFrames = select('#', ...)

  for i = 1, numFrames do
    local frame = select(i, ...)

    if frame and not nameplateFrames[frame] and IsNameplate(frame) then
      local nameText = select(7, frame:GetRegions())
      if nameText and nameText.GetObjectType and nameText:GetObjectType() == "FontString" then
        nameplateFrames[frame] = nameText

        if frame.HookScript then
          frame:HookScript("OnShow", OnNameplateShow)
          frame:HookScript("OnHide", OnNameplateHide)
        end

        if frame:IsShown() then
          OnNameplateShow(frame)
        end
      end
    end
  end
end

local function UpdateAllNameplates()
  for frame in pairs(nameplateFrames) do
    if frame:IsShown() then
      OnNameplateShow(frame)
    end
  end
end

local function RedrawAllIcons()
  UpdateCachedSettings()

  for _, iconFrame in pairs(iconFrames) do
    iconFrame:SetWidth(ICON_SIZE * cachedScale)
    iconFrame:SetHeight(ICON_SIZE * cachedScale)
    iconFrame:ClearAllPoints()
    iconFrame:SetPoint("LEFT", cachedX, cachedY)
  end
end

local lastNumChildren = 0
local SCAN_INTERVAL = 0.2
local ticker = nil

local function StartNameplateWatcher()
  if ticker then return end

  UpdateCachedSettings()

  ticker = CreateFrame("Frame")
  ticker.elapsed = 0
  ticker:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + (elapsed or 0)

    if self.elapsed >= SCAN_INTERVAL then
      if WorldFrame and WorldFrame.GetNumChildren then
        local numChildren = WorldFrame:GetNumChildren()
        if numChildren ~= lastNumChildren then
          lastNumChildren = numChildren
          ScanWorldFrameChildren(WorldFrame:GetChildren())
        end
      end
      self.elapsed = 0
    end
  end)
end

local function StopNameplateWatcher()
  if ticker then
    ticker:SetScript("OnUpdate", nil)
    ticker = nil
  end
end

pfQuestNameplates.Start = StartNameplateWatcher
pfQuestNameplates.Stop = StopNameplateWatcher
pfQuestNameplates.Redraw = RedrawAllIcons

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function()
  ScanQuestObjectives()
  UpdateAllNameplates()
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  ScanQuestObjectives()
  if pfQuest_config and pfQuest_config["epochnameplatesEnabled"] ~= "0" then
    StartNameplateWatcher()
  end
end)

if pfQuestConfig and pfQuestConfig.HookScript then
  pfQuestConfig:HookScript("OnHide", RedrawAllIcons)
end

-- Slash command
SlashCmdList = SlashCmdList or {}
SLASH_PFQUESTNP1 = "/pfqnp"
SlashCmdList["PFQUESTNP"] = function(msg)
  if msg == "scan" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest:|r Scanning nameplate quest objectives...")
    ScanQuestObjectives()
    UpdateAllNameplates()
  elseif msg == "on" then
    pfQuest_config["epochnameplatesEnabled"] = "1"
    StartNameplateWatcher()
    UpdateAllNameplates()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest:|r Nameplate icons enabled.")
  elseif msg == "off" then
    pfQuest_config["epochnameplatesEnabled"] = "0"
    StopNameplateWatcher()
    for frame in pairs(iconFrames) do
      RemoveIconFrame(frame)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest:|r Nameplate icons disabled.")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest Nameplates:|r /pfqnp [on|off|scan]")
  end
end
