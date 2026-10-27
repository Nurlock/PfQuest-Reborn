-- pfQuest Reborn: Quest Automation
-- Optional auto-acceptance and completion of quests, low-level skips, and turn-ins

local L = pfQuest_Loc or setmetatable({}, { __index = function(_, k) return k end })

pfQuestAutomation = {}

local questLogFrame = CreateFrame("Frame", "pfQuestAutomationFrame")
questLogFrame:RegisterEvent("QUEST_DETAIL")
questLogFrame:RegisterEvent("GOSSIP_SHOW")
questLogFrame:RegisterEvent("QUEST_COMPLETE")
questLogFrame:RegisterEvent("QUEST_GREETING")
questLogFrame:RegisterEvent("QUEST_PROGRESS")

local function CompleteQuestWithRewards()
  if GetNumQuestChoices and GetNumQuestChoices() == 0 then
    if GetQuestReward then GetQuestReward() end
  end
end

local function SkipLowLevelQuest(isLowLevel)
  return pfQuest_config and pfQuest_config["epochAutoQuestsSkipLowLevel"] == "1" and isLowLevel
end

local function IsTrivialQuest()
  local title = GetTitleText and GetTitleText()
  return title and string.find(string.lower(title), "low level") ~= nil
end

pfQuestAutomation.OnEvent = function(self, event, ...)
  if not pfQuest_config or pfQuest_config["epochAutoQuests"] ~= "1" then
    return
  end

  if IsShiftKeyDown and IsShiftKeyDown() then
    return
  end

  if event == "QUEST_PROGRESS" then
    if IsQuestCompletable and IsQuestCompletable() then
      if CompleteQuest then CompleteQuest() end
    end

  elseif event == "QUEST_COMPLETE" then
    if GetNumQuestChoices and GetNumQuestChoices() == 0 then
      if GetQuestReward then GetQuestReward() end
    elseif QuestFrameRewardPanel and QuestFrameRewardPanel.itemChoice and QuestFrameRewardPanel.itemChoice > 0 then
      if GetQuestReward then GetQuestReward(QuestFrameRewardPanel.itemChoice) end
    end

  elseif event == "QUEST_GREETING" then
    local numActiveQuests = GetNumActiveQuests and GetNumActiveQuests() or 0
    for i = 1, numActiveQuests do
      local title, completed = GetActiveTitle(i)
      if completed then
        if SelectActiveQuest then SelectActiveQuest(i) end
        CompleteQuestWithRewards()
      end
    end

    local numAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    if numAvailable >= 1 and (not GetAvailableQuestInfo or not GetAvailableQuestInfo(1)) then
      if SelectAvailableQuest then SelectAvailableQuest(1) end
    end

  elseif event == "QUEST_DETAIL" then
    if not IsTrivialQuest() then
      if AcceptQuest then AcceptQuest() end
    end

  elseif event == "GOSSIP_SHOW" then
    local skipCommission = pfQuest_config and pfQuest_config["epochSkipCommissionQuests"] == "1"
    local numAvailable = GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
    for i = 1, numAvailable do
      local title, _, isLowLevel = GetGossipAvailableQuests(i)
      if not (SkipLowLevelQuest(isLowLevel) or (skipCommission and title and string.find(title, "Commission"))) then
        if SelectGossipAvailableQuest then SelectGossipAvailableQuest(i) end
      end
    end

    local numGossipActiveQuests = GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
    for i = 1, numGossipActiveQuests do
      local activeQuests = { GetGossipActiveQuests() }
      if activeQuests[i * 4] == 1 then
        if SelectGossipActiveQuest then SelectGossipActiveQuest(i) end
      end
    end

    if pfQuest_config and pfQuest_config["epochAutomateRuneclothDonations"] == "1" and numGossipActiveQuests == 1 then
      local title = GetGossipActiveQuests(1)
      if title and string.find(title, "Additional Runecloth") then
        if SelectGossipActiveQuest then SelectGossipActiveQuest(1) end
      end
    end
  end
end

questLogFrame:SetScript("OnEvent", pfQuestAutomation.OnEvent)
