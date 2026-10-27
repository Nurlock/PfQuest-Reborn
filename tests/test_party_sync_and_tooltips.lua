-- Test Suite: Party Sync, Lag Spike Batching, Contextual NPC Counts & Ender Tracking
-- Verifies fixes for party objective collection lag, 0/x normalization, reload sync, and quest ender tooltips.

local mock = require("tests.mock_wow_api")
local env = mock.create_env()

local loadstring = loadstring or load

local function load_file(path)
  local f = io.open(path, "r")
  assert(f, "Could not open " .. path)
  local content = f:read("*a")
  f:close()
  local fn, err = loadstring(content, path)
  assert(fn, err)
  setfenv(fn, env)
  return fn()
end

env.pfQuestConfig = env.CreateFrame("Frame", "pfQuestConfig")
env.pfQuestConfig.path = "Interface\\AddOns\\pfQuest"
env.pfQuest_config = {
  ["experimental"] = "1",
  ["questiegroup"] = "1",
  ["showpartyobjectives"] = "1",
  ["showpartytooltips"] = "1",
  ["currentquestgivers"] = "1",
  ["trackingmethod"] = 1,
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = {
  questlog = {},
  collapsedQuestIDs = {},
  announcedQuests = {},
  partyQuests = {},
  partyVisibility = {},
  queue = {},
  queueHead = 1,
  queueTail = 1,
  queueCount = 0,
}

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")
load_file("quest.lua")
load_file("questiecomms.lua")

local comms = env.pfQuest.questieComms
assert(comms, "questieComms must be loaded")

-- Setup mock party
env.GetNumPartyMembers = function() return 2 end
env.UnitName = function(u)
  if u == "player" then return "LocalPlayer" end
  return "PartyFriend"
end

env.GetQuestLogTitle = function(index)
  if index == 1 then return "Defias Hunt", 10, "Elite", false, false, 0 end
  return nil
end
env.pfQuestCompat = env.pfQuestCompat or {}
env.pfQuestCompat.GetQuestLogTitle = env.GetQuestLogTitle
env.GetNumQuestLeaderBoards = function(index)
  if index == 1 then return 1 end
  return 0
end
env.GetQuestLogLeaderBoard = function(objIndex, qlogIndex)
  if qlogIndex == 1 and objIndex == 1 then
    return "Defias Bandit: 3/10", "monster", false
  end
  return nil
end

-- Setup dummy quest in DB
env.pfDB = env.pfDB or {}
env.pfDB.quests = env.pfDB.quests or { loc = {}, data = {} }
env.pfDB.quests.loc[100] = { T = "Defias Hunt" }
env.pfDB.quests.data[100] = {
  lvl = 10,
  min = 5,
  ["end"] = { U = { 240 } }, -- Ender NPC: Marshal Dughan (ID 240)
  ["obj"] = { U = { 116 } }, -- Kill Mob: Defias Bandit (ID 116)
}
env.pfDB.units = env.pfDB.units or { loc = {} }
env.pfDB.units.loc[240] = "Marshal Dughan"
env.pfDB.units.loc[116] = "Defias Bandit"

print("[TEST] 1. Verifying lag spike prevention (no synchronous UpdateNodes on party updates)...")
local updateNodesCalled = 0
local origUpdateNodes = env.pfMap.UpdateNodes
env.pfMap.UpdateNodes = function(self)
  updateNodesCalled = updateNodesCalled + 1
  if origUpdateNodes then origUpdateNodes(self) end
end

-- Simulate incoming party quest update packet
local updatePacket = {
  msgId = 1, -- QC_ID_BROADCAST_QUEST_UPDATE
  quest = {
    id = 100,
    status = "ACT",
    objectives = {
      [1] = {
        type = "m",
        id = 116,
        text = "Defias Bandit",
        collected = 3,
        needed = 10,
        finished = false,
      }
    }
  }
}

comms:OnCommReceived("questie", updatePacket, "PARTY", "PartyFriend")
assert(updateNodesCalled == 0, "UpdateNodes must NOT be called synchronously on party update (was called " .. updateNodesCalled .. " times)")
assert(env.pfMap.queue_update ~= nil, "pfMap.queue_update must be set to coalesce frame redraws")
print("  ✓ PASS: Party objective packet batches updates without synchronous UpdateNodes lag")

print("[TEST] 2. Verifying objective count normalization (lowercase keys & 0/x completion fix)...")
-- Packet where Questie sends lowercase 'collected', 'needed', and 'finished = true'
local finishPacket = {
  msgId = 1,
  quest = {
    id = 100,
    isComplete = true,
    objectives = {
      [1] = {
        type = "m",
        id = 116,
        text = "Defias Bandit",
        collected = 10,
        needed = 10,
        finished = true,
      }
    }
  }
}
comms:OnCommReceived("questie", finishPacket, "PARTY", "PartyFriend")

local partyQuest = env.pfQuest.partyQuests["PartyFriend"][100]
assert(partyQuest, "PartyFriend quest 100 should be recorded")
local obj = partyQuest.objectives[1]
assert(obj.fulfilled == 10, "fulfilled must be 10, got: " .. tostring(obj.fulfilled))
assert(obj.required == 10, "required must be 10, got: " .. tostring(obj.required))
assert(obj.finished == true, "finished must be true")

-- Test packet where finished=true but fulfilled was 0/nil: must normalize fulfilled = required
local zeroFulfilledPacket = {
  msgId = 1,
  quest = {
    id = 100,
    isComplete = true,
    objectives = {
      [1] = {
        type = "m",
        id = 116,
        text = "Defias Bandit",
        fulfilled = 0,
        required = 10,
        finished = true,
      }
    }
  }
}
comms:OnCommReceived("questie", zeroFulfilledPacket, "PARTY", "PartyFriend")
local obj2 = env.pfQuest.partyQuests["PartyFriend"][100].objectives[1]
assert(obj2.fulfilled == 10, "Finished objective must have fulfilled normalized to required (10), got: " .. tostring(obj2.fulfilled))
print("  ✓ PASS: Lowercase key deserialization and completed 0/x normalization verified")

print("[TEST] 3. Verifying /reload party synchronization lifecycle...")
-- Simulate reload: questlog in WoW client has 1 quest, but pfQuest.questlog is not populated yet
env.GetNumQuestLogEntries = function() return 1 end
env.pfQuest.questlog = {}

local sentAddonMessages = {}
env.SendAddonMessage = function(pfx, text, dist, target)
  table.insert(sentAddonMessages, { prefix = pfx, text = text, dist = dist, target = target })
end

-- Fire PLAYER_ENTERING_WORLD before questlog is loaded
comms:GetScript("OnEvent")() -- triggers with event=nil or PLAYER_ENTERING_WORLD simulation
env.event = "PLAYER_ENTERING_WORLD"
-- Trigger PLAYER_ENTERING_WORLD on comms
local commsScript = comms:GetScript("OnEvent")
setfenv(commsScript, env)
commsScript()

-- Must NOT have broadcast an empty quest list
local broadcastEmpty = false
for _, msg in ipairs(sentAddonMessages) do
  if string.find(msg.text, "QC_ID_BROADCAST_FULL_QUESTLIST") or (msg.prefix == "questie" and string.find(msg.text, "rawQuestList")) then
    broadcastEmpty = true
  end
end
assert(not broadcastEmpty, "Empty quest list must NOT be broadcast during PLAYER_ENTERING_WORLD")
print("  ✓ PASS: Empty questlist suppressed during reload before questlog is loaded")

-- Now simulate quest.lua queue completion
env.pfQuest.questlog[100] = { title = "Defias Hunt", qlogid = 1, isComplete = false }
env.pfQuest.needsGroupSync = true
env.pfQuest.queueCount = 0

-- Simulate OnUpdate in quest.lua triggering SyncOnLoginOrReload
if env.pfQuest.needsGroupSync then
  env.pfQuest.needsGroupSync = nil
  comms:SyncOnLoginOrReload()
end
assert(env.pfQuest.partyQuests["LocalPlayer"][100] ~= nil, "Local player quests must be synchronized into partyQuests")
print("  ✓ PASS: Full group sync cleanly executes once quest queue finishes loading")

print("[TEST] 4. Verifying Quest End NPC (NPC_END) tracking & tooltips...")
-- PartyFriend has completed quest 100 which turns in to Marshal Dughan (ID 240)
local testTip = env.CreateFrame("Frame", "TestTooltip")
testTip.lines = {}
testTip.AddLine = function(self, text, r, g, b)
  table.insert(self.lines, text)
end
testTip.NumLines = function(self) return #self.lines end
testTip.GetName = function(self) return "TestTooltip" end

-- Hover over Marshal Dughan in 3D world (ShowWorldTooltip)
comms:ShowWorldTooltip("Marshal Dughan", testTip)
assert(#testTip.lines > 0, "Tooltip lines should be added for Marshal Dughan")
local foundTurnIn = false
local foundBandit = false
for _, line in ipairs(testTip.lines) do
  if string.find(line, "Ready for turn%-in") then
    foundTurnIn = true
  end
  if string.find(line, "Defias Bandit") then
    foundBandit = true
  end
end
assert(foundTurnIn, "Quest ender NPC tooltip must display 'Ready for turn-in'")
assert(not foundBandit, "Quest ender NPC tooltip must NOT dump unrelated kill objectives (Defias Bandit)")
print("  ✓ PASS: Quest ender NPC accurately displays party turn-in readiness without objective bleed")

print("[TEST] 5. Verifying shared quest tooltip displays party progress when quest title already present...")
local sharedTip = env.CreateFrame("Frame", "SharedTooltip")
sharedTip.lines = {
  "Defias Bandit",
  "Level 4",
  "Defias Hunt",
  "  Defias Bandit: 3/10"
}
sharedTip.AddLine = function(self, text, r, g, b)
  table.insert(self.lines, text)
end
sharedTip.NumLines = function(self) return #self.lines end
sharedTip.GetName = function(self) return "SharedTooltip" end
-- Expose text lines via _G naming convention expected by TooltipHasQuest
for i, line in ipairs(sharedTip.lines) do
  env["SharedTooltipTextLeft" .. i] = { GetText = function() return line end }
end

comms:ShowWorldTooltip("Defias Bandit", sharedTip)

local foundPartyLine = false
local headerCount = 0
for _, line in ipairs(sharedTip.lines) do
  if string.find(line, "PartyFriend") and string.find(line, "10/10") then
    foundPartyLine = true
  end
  if string.find(line, "%[!%] Defias Hunt") then
    headerCount = headerCount + 1
  end
end
assert(foundPartyLine, "Party progress must be shown even when quest title was already in tooltip")
assert(headerCount == 0, "Duplicate quest header must NOT be added if quest title was already in tooltip")
print("  ✓ PASS: Shared quest tooltip appends party progress without duplicating quest header")

print("[TEST] 6. Verifying local player quests are indexed on the very first hover...")
-- Clear partyQuests["LocalPlayer"] to simulate first hover state
env.pfQuest.partyQuests["LocalPlayer"] = nil
local firstHoverTip = env.CreateFrame("Frame", "FirstHoverTip")
firstHoverTip.lines = {}
firstHoverTip.AddLine = function(self, text, r, g, b)
  table.insert(self.lines, text)
end
firstHoverTip.NumLines = function(self) return #self.lines end
firstHoverTip.GetName = function(self) return "FirstHoverTip" end

comms:ShowWorldTooltip("Defias Bandit", firstHoverTip)
local foundLocalOnFirstHover = false
for _, line in ipairs(firstHoverTip.lines) do
  if string.find(line, "LocalPlayer") then
    foundLocalOnFirstHover = true
  end
end
assert(foundLocalOnFirstHover, "Local player quests must be indexed into party lookups on very first hover")
print("  ✓ PASS: Local player quests indexed immediately on initial hover")

print("[TEST] 7. Verifying dual-protocol comms: pfqe inbound and outbound sync...")
-- Test inbound pfqe V1 batch message from EpochFriend
comms:OnPfqeReceived("V1|U6001Q100:3:5;", "PARTY", "EpochFriend")
assert(env.pfQuest.partyQuests["EpochFriend"] ~= nil, "EpochFriend party data must exist")
assert(env.pfQuest.partyQuests["EpochFriend"][100] ~= nil, "Quest 100 must be tracked for EpochFriend")
assert(env.pfQuest.partyQuests["EpochFriend"][100].objectives[1].fulfilled == 3, "Fulfilled should be 3")
assert(env.pfQuest.partyQuests["EpochFriend"][100].objectives[1].required == 5, "Required should be 5")

local epochTip = env.CreateFrame("Frame", "EpochTip")
epochTip.lines = {}
epochTip.AddLine = function(self, text) table.insert(self.lines, text) end
epochTip.NumLines = function(self) return #self.lines end
epochTip.GetName = function(self) return "EpochTip" end

comms:ShowWorldTooltip("Defias Bandit", epochTip)
local foundEpochProgress = false
for _, line in ipairs(epochTip.lines) do
  if string.find(line, "EpochFriend") and string.find(line, "3/5") then
    foundEpochProgress = true
  end
end
assert(foundEpochProgress, "EpochFriend progress 3/5 must appear in Defias Bandit tooltip")
print("  ✓ PASS: Inbound pfqe V1 packet deserialized and surfaced in tooltips")

-- Test inbound REMOVEQ message
comms:OnPfqeReceived("REMOVEQ:100:Defias Hunt", "PARTY", "EpochFriend")
assert(env.pfQuest.partyQuests["EpochFriend"][100] == nil, "Quest 100 must be removed after REMOVEQ")
print("  ✓ PASS: Inbound REMOVEQ cleanly purges party quest data")

-- Test outbound BroadcastPfqeQuestUpdate
sentAddonMessages = {}
comms:BroadcastPfqeQuestUpdate(100)
local foundPfqeOut = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "V1|") and string.find(msg.text, "Q100:") then
    foundPfqeOut = true
  end
end
assert(foundPfqeOut, "BroadcastPfqeQuestUpdate must send V1 pfqe packet with quest 100")
print("  ✓ PASS: Outbound pfqe quest update correctly formatted and transmitted")

-- Test PFQUEST_SYNC_REQUEST event handler
sentAddonMessages = {}
env.event = "CHAT_MSG_ADDON"
env.arg1 = "PFQUEST_SYNC_REQUEST"
env.arg2 = "1"
env.arg3 = "PARTY"
env.arg4 = "EpochFriend"
commsScript()
local syncReplied = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "V1|") then
    syncReplied = true
  end
end
assert(syncReplied, "PFQUEST_SYNC_REQUEST must trigger full quest list broadcast on pfqe prefix")
print("  ✓ PASS: PFQUEST_SYNC_REQUEST triggers dual-protocol broadcast")

print("\ntest_party_sync_and_tooltips PASSED successfully!")
