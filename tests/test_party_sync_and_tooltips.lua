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

print("\ntest_party_sync_and_tooltips PASSED successfully!")
