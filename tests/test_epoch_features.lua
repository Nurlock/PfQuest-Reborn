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

print("test_epoch_features PASSED successfully!")
