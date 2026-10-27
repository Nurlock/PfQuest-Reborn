-- pfQuest Reborn: Objective Progress Chat Announcements
-- Announces individual quest objective updates to group chat with clickable item links

local L = pfQuest_Loc or setmetatable({}, { __index = function(_, k) return k end })

pfQuestAnnounce = {}

local objectiveState = {}

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

  local questName = GetQuestNameForObjective(itemName)
  local itemId = GetItemIdForObjective(itemName)
  local itemLink = nil
  if itemId and GetItemInfo then
    local _, link = GetItemInfo(itemId)
    itemLink = link
  end

  local outMessage = nil
  local showItem = pfQuest_config and pfQuest_config["epochannounceShowItem"] ~= "0"

  if stillNeeded < 1 then
    if pfQuest_config and pfQuest_config["epochannounceFinished"] ~= "0" then
      if not objectiveState[itemName].announced then
        objectiveState[itemName].announced = true
        local display = (showItem and itemLink) or itemName
        if questName then
          outMessage = "Finished " .. display .. " for " .. questName .. "."
        else
          outMessage = "Finished " .. display .. "."
        end
      end
    end
  else
    objectiveState[itemName].announced = false
    if pfQuest_config and pfQuest_config["epochannounceRemaining"] == "1" then
      local display = (showItem and itemLink) or itemName
      if questName then
        outMessage = display .. " for " .. questName .. " (" .. stillNeeded .. " left)"
      else
        outMessage = display .. " (" .. stillNeeded .. " left)"
      end
    end
  end

  if outMessage and outMessage ~= "" and SendChatMessage then
    local channel = (GetNumRaidMembers and GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    SendChatMessage(outMessage, channel)
  end
  return outMessage
end

local frame = CreateFrame("Frame", "pfQuestAnnounceFrame")
frame:RegisterEvent("UI_INFO_MESSAGE")
frame:SetScript("OnEvent", function(self, event, msg)
  if event == "UI_INFO_MESSAGE" and msg then
    pfQuestAnnounce.OnQuestUpdate(msg)
  end
end)
