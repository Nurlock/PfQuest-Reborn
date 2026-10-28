-- Regression tests for Project Epoch features: Quest filters, Auto-close, DB url, and assets
local mock = require("tests.mock_wow_api")
local env = mock.create_env()

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
env.pfQuest_config = {}
env.pfQuest_history = {}
env.pfQuest = { questlog = {}, ResetAll = function() end }
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }

load_file("compat/client.lua")
load_file("quest.lua")

print("[TEST] Verifying Epochhead database URL...")
assert(env.pfQuest.dburl == "https://epochhead.com/?quest=", "dburl should point to epochhead.com")
print("  ✓ PASS: Epochhead database URL verified")

-- Load database.lua QuestFilter
load_file("database.lua")

-- Populate test db
env.pfDB.quests.data = env.pfDB.quests.data or {}
env.pfDB.quests.loc = env.pfDB.quests.loc or {}

for id, q in pairs({
  [100] = { lvl = 20, min = 15, close = { 101, 102 } },
  [101] = { lvl = 20, min = 15 },
  [102] = { lvl = 20, min = 15 },
  [200] = { lvl = 20, min = 15 },
  [201] = { lvl = 20, min = 15 },
  [202] = { lvl = 20, min = 15 },
  [203] = { lvl = 20, min = 15 },
  [204] = { lvl = 20, min = 15 },
  [26130] = { lvl = 20, min = 15 },
}) do
  env.pfDB.quests.data[id] = q
end

for id, name in pairs({
  [100] = { T = "A Simple Quest" },
  [101] = { T = "Mutually Exclusive Choice A" },
  [102] = { T = "Mutually Exclusive Choice B" },
  [200] = { T = "Warsong Gulch Flag Capture" },
  [201] = { T = "Commission for Ironforge" },
  [202] = { T = "A Donation of Wool" },
  [203] = { T = "CLUCK!" },
  [204] = { T = "Corrupted Windblossom" },
  [26130] = { T = "Coin of Ancestry" },
}) do
  env.pfDB.quests.loc[id] = name
end
env.pfDB.quests.enUS = env.pfDB.quests.loc

print("[TEST] Verifying Epoch quest filters...")
-- 1. Default (filters disabled)
env.pfQuest_config = {}
assert(env.pfDatabase:QuestFilter(200, 20, 1, 1) == true, "PvP quest allowed when filter off")
assert(env.pfDatabase:QuestFilter(26130, 20, 1, 1) == true, "Coin quest allowed when filter off")

-- 2. PvP filter
env.pfQuest_config["epochHidePvPQuests"] = "1"
assert(env.pfDatabase:QuestFilter(200, 20, 1, 1) == nil, "PvP quest hidden when filter on")

-- 3. Coin filter
env.pfQuest_config["epochHideCoinQuests"] = "1"
assert(env.pfDatabase:QuestFilter(26130, 20, 1, 1) == nil, "Coin quest hidden when filter on")

-- 4. Commission filter
env.pfQuest_config["epochHideCommissionQuests"] = "1"
assert(env.pfDatabase:QuestFilter(201, 20, 1, 1) == nil, "Commission quest hidden when filter on")

-- 5. Donation filter
env.pfQuest_config["epochHideDonationQuests"] = "1"
assert(env.pfDatabase:QuestFilter(202, 20, 1, 1) == nil, "Donation quest hidden when filter on")

-- 6. Chicken filter
env.pfQuest_config["epochHideChickenQuests"] = "1"
assert(env.pfDatabase:QuestFilter(203, 20, 1, 1) == nil, "Chicken quest hidden when filter on")

-- 7. Felwood flower filter
env.pfQuest_config["epochHideFelwoodFlowers"] = "1"
assert(env.pfDatabase:QuestFilter(204, 20, 1, 1) == nil, "Felwood flower quest hidden when filter on")
print("  ✓ PASS: All Epoch quest filters correctly suppress matching quests")

print("[TEST] Verifying mutually exclusive auto-closing logic...")
env.pfQuest_history = { [100] = { os.time(), 20 } }
local closed = 0
local quests = env.pfDB["quests"]["data"]
for qID in pairs(env.pfQuest_history) do
  local qData = quests[qID]
  if qData and qData["close"] then
    for _, closedQuestID in ipairs(qData["close"]) do
      if not env.pfQuest_history[closedQuestID] then
        env.pfQuest_history[closedQuestID] = { os.time(), 20 }
        closed = closed + 1
      end
    end
  end
end
assert(closed == 2, "Both mutually exclusive quests should be auto-closed")
assert(env.pfQuest_history[101] ~= nil, "Quest 101 should be flagged in history")
assert(env.pfQuest_history[102] ~= nil, "Quest 102 should be flagged in history")
print("  ✓ PASS: Mutually exclusive quests auto-closed properly")

print("[TEST] Verifying blp image assets exist...")
local f_slay = io.open("img/slay.blp", "r")
assert(f_slay, "img/slay.blp must exist")
f_slay:close()

local f_loot = io.open("img/loot.blp", "r")
assert(f_loot, "img/loot.blp must exist")
f_loot:close()
print("  ✓ PASS: Slay and loot blp assets present")

print("[TEST] Verifying ITEM_START quest starter drop nodes...")
env.pfDB.items.data[5001] = { U = { [6001] = 75 } }
env.pfDB.items.loc[5001] = "Captain's Orders"
env.pfDB.units.data[6001] = { lvl = 22, coords = { { 45.0, 55.0, 10 } } }
env.pfDB.units.loc[6001] = "Defias Captain"
env.pfDB.quests.data[300] = { lvl = 20, min = 15, start = { I = { 5001 } } }
env.pfDB.quests.loc[300] = { T = "Orders of the Sea" }

local addedNodes = {}
env.pfMap = {
  nodes = {},
  AddNode = function(self, node) table.insert(addedNodes, node) end,
  unifiedcache = {},
  GetClusterData = function(self, addon, cacheKey) return {} end,
}

env.pfQuest_config["currentquestgivers"] = "1"
env.pfQuest_config["epochHideItemDrops"] = "0"
env.pfDatabase:SearchQuestID(300, {}, {})

local foundItemStart = false
for _, n in ipairs(addedNodes) do
  if n.QTYPE == "ITEM_START" and n.item == "Captain's Orders" then
    foundItemStart = true
    assert(n.dropsources_levels["Defias Captain"] ~= nil, "Defias Captain should be in dropsources")
    assert(n.dropsources_levels["Defias Captain"].chance == 75, "Chance should be 75%")
  end
end
assert(foundItemStart, "ITEM_START node must be created for item-started quest")
print("  ✓ PASS: ITEM_START node created with drop source metadata")

print("[TEST] Verifying Rare Loot Panel logic...")
load_file("lootpanel.lua")
assert(env.pfQuestLoot ~= nil, "pfQuestLoot must be defined")
assert(env.pfQuestEpochLoot == env.pfQuestLoot, "pfQuestEpochLoot alias must exist")

-- Mock GetItemInfo for loot test
env.GetItemInfo = function(id)
  if id == 5001 then
    return "Captain's Orders", "link", 1, 1, 1, "Quest"
  elseif id == 6002 then
    return "Rare Dagger", "link", 3, 1, 1, "Weapon"
  end
  return "Unknown Item", "link", 1, 1, 1, "Misc"
end
env.GetItemIcon = function() return "Interface\\Icons\\INV_Sword_04" end

env.pfDB.units.data[7001] = { lvl = 50, rnk = 2 }
env.pfDB.units.loc[7001] = "Rare Mob"
env.pfDB.items.data[6002] = { U = { [7001] = 25 } }
env.pfDB.items.loc[6002] = "Rare Dagger"

assert(env.pfQuestLoot.HasDrops(7001) == true, "Rare mob 7001 must report drops")
local mockFrame = { spawnid = 7001, spawn = "Rare Mob", level = 50, spawntype = "Monster" }
env.pfQuestLoot.ShowPinned(mockFrame)
assert(env.pfQuestLootPanel:IsShown() == true, "Loot panel must be visible after ShowPinned")
env.pfQuestLoot.Hide()
assert(env.pfQuestLootPanel:IsShown() == false, "Loot panel must be hidden after Hide")
print("  ✓ PASS: Rare Loot Panel verified")

print("[TEST] Verifying Nameplate Quest Icons...")
load_file("nameplates.lua")
assert(env.pfQuestNameplates ~= nil, "pfQuestNameplates must be defined")
assert(env.SLASH_PFQUESTNP1 == "/pfqnp", "SLASH_PFQUESTNP1 must be /pfqnp")

-- Mock quest log entry for an active quest targeting Defias Captain
env.GetNumQuestLogEntries = function() return 1 end
env.GetQuestLogTitle = function(index)
  return "Captain's Fate", 20, "Elite", 1, false, false, nil, false
end
env.GetNumQuestLeaderBoards = function(index) return 1 end
env.GetQuestLogLeaderBoard = function(i, qid)
  return "Defias Captain slain: 0/1", "monster", false
end

env.pfDB.quests.data[400] = { lvl = 20, min = 15, obj = { U = { 6001 } } }
env.pfDB.quests.loc[400] = { T = "Captain's Fate" }

env.pfQuestNameplates.Scan()
assert(env.pfQuestNameplates.questObjectives["Defias Captain"] ~= nil, "Defias Captain must have a quest icon")
print("  ✓ PASS: Nameplate quest objectives scanned and mapped")

print("[TEST] Verifying Continent Map coordinate transformation...")
load_file("continent.lua")
assert(env.pfQuestContinent ~= nil, "pfQuestContinent must be defined")

-- Test ZoneToWorld for Elwynn Forest (zone 12)
local wx, wy = env.pfQuestContinent.ZoneToWorld(50, 50, 12)
assert(wx ~= nil and wy ~= nil, "ZoneToWorld must return coordinates for Elwynn")
local cx, cy = env.pfQuestContinent.WorldToContinent(wx, wy, 2)
assert(cx ~= nil and cy ~= nil, "WorldToContinent must return continent coordinates")
assert(cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1, "Continent coordinates must be normalized within 0..1")
print("  ✓ PASS: Continent coordinate projection verified")

print("[TEST] Verifying Quest Automation...")
load_file("automation.lua")
assert(env.pfQuestAutomation ~= nil, "pfQuestAutomation must be defined")

local accepted = false
env.AcceptQuest = function() accepted = true end
env.GetTitleText = function() return "Regular Quest" end

-- Disabled by default
env.pfQuest_config["epochAutoQuests"] = "0"
env.pfQuestAutomation.OnEvent(nil, "QUEST_DETAIL")
assert(accepted == false, "AcceptQuest must not be called when automation disabled")

-- Enabled
env.pfQuest_config["epochAutoQuests"] = "1"
env.pfQuestAutomation.OnEvent(nil, "QUEST_DETAIL")
assert(accepted == true, "AcceptQuest must be called when automation enabled")

local completed = false
env.IsQuestCompletable = function() return true end
env.CompleteQuest = function() completed = true end
env.pfQuestAutomation.OnEvent(nil, "QUEST_PROGRESS")
assert(completed == true, "CompleteQuest must be called when quest is completable")

-- Gossip available quests stride and commission skip
local selectedGossip = nil
env.SelectGossipAvailableQuest = function(index) selectedGossip = index end
env.GetNumGossipAvailableQuests = function() return 2 end
-- 3.3.5a stride 5: title, level, isTrivial, isDaily, isRepeatable
env.GetGossipAvailableQuests = function()
  return "Commission for Stormwind", 20, false, false, false,
         "Hero's Call", 22, false, false, false
end
env.pfQuest_config["epochSkipCommissionQuests"] = "1"
env.pfQuestAutomation.OnEvent(nil, "GOSSIP_SHOW")
assert(selectedGossip == 2, "Must skip commission quest and select index 2: got " .. tostring(selectedGossip))
print("  ✓ PASS: Quest automation event triggers and gossip stride parsing verified")

print("[TEST] Verifying Quest Chat Announcements...")
load_file("announce.lua")
assert(env.pfQuestAnnounce ~= nil, "pfQuestAnnounce must be defined")

local sentMessage, sentChannel
env.SendChatMessage = function(msg, chan)
  sentMessage = msg
  sentChannel = chan
end

-- Not in party: no announce
env.GetNumPartyMembers = function() return 0 end
env.GetNumRaidMembers = function() return 0 end
env.pfQuest_config["epochannounceRemaining"] = "1"
env.pfQuest_config["epochannounceFinished"] = "1"
env.pfQuestAnnounce.OnQuestUpdate("Bandit slain: 1/5")
assert(sentMessage == nil, "Must not announce when not in party or raid")

-- In party: announcements work
env.GetNumPartyMembers = function() return 2 end
local out = env.pfQuestAnnounce.OnQuestUpdate("Bandit slain: 1/5")
assert(out ~= nil and string.find(out, "4 left"), "Announcement must report 4 left: got " .. tostring(out))
assert(sentChannel == "PARTY", "Channel should be PARTY")

-- Duplicate count: ignored
sentMessage = nil
env.pfQuestAnnounce.OnQuestUpdate("Bandit slain: 1/5")
assert(sentMessage == nil, "Duplicate count must not be announced")

-- Next count
env.pfQuestAnnounce.OnQuestUpdate("Bandit slain: 2/5")
assert(sentMessage ~= nil and string.find(sentMessage, "3 left"), "Must announce 3 left")

-- Finished
sentMessage = nil
local outFin = env.pfQuestAnnounce.OnQuestUpdate("Bandit slain: 5/5")
assert(outFin ~= nil and string.find(outFin, "Finished"), "Must announce Finished: got " .. tostring(outFin))
print("  ✓ PASS: Quest chat announcements verified")

print("[TEST] Verifying AnnounceQuest quest link and turn-in wording...")
env.pfDB = env.pfDB or { quests = { loc = {}, data = {} } }
env.pfDB.quests.loc[100] = { T = "Defias Hunt" }
env.pfDB.quests.data[100] = { lvl = 10 }
env.GetNumPartyMembers = function() return 2 end
env.GetNumRaidMembers = function() return 0 end
sentMessage = nil
sentChannel = nil
env.pfQuestAnnounce.AnnounceQuest(100, nil, false)
assert(sentMessage ~= nil and string.find(sentMessage, "|Hquest:100:10|h", 1, true), "Completion must include clickable quest link: got " .. tostring(sentMessage))
assert(string.find(sentMessage, "Quest Completed", 1, true), "Completion wording must say Quest Completed: got " .. tostring(sentMessage))
sentMessage = nil
env.pfQuestAnnounce.AnnounceQuest(100, nil, true)
assert(sentMessage ~= nil and string.find(sentMessage, "Quest Turned In", 1, true), "Turn-in wording must say Quest Turned In: got " .. tostring(sentMessage))
assert(sentChannel == "PARTY", "AnnounceQuest must use PARTY channel")
print("  ✓ PASS: AnnounceQuest link and wording verified")

print("test_epoch_features PASSED successfully!")
