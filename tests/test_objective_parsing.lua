-- Test Suite: Objective Completion Parsing & Node Filtering
-- Tests parsing of monsters, objects, items, non-"slain" verbs, and leaderboards without numbers.

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
env.pfQuest_config = {
  ["allquestgivers"] = "1",
  ["currentquestgivers"] = "1",
  ["trackingmethod"] = 1,
  ["showlowlevel"] = "1",
  ["showhighlevel"] = "1",
  ["mindropchance"] = 0,
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")

-- Setup a test quest with:
-- 1. A standard kill mob (Unit 1001, "Defias Thug")
-- 2. A non-"slain" verb mob (Unit 1002, "Sickly Gazelle")
-- 3. An interactive game object (Object 2001, "Northshire Water Valve")
-- 4. An item objective (Item 3001, "Garrick's Head", dropped by Unit 1003)
local questId = 500
env.pfDB.quests.data[questId] = {
  lvl = 3,
  min = 1,
  ["start"] = { ["U"] = { 823 } },
  ["end"] = { ["U"] = { 823 } },
  ["obj"] = {
    ["U"] = { 1001, 1002 },
    ["O"] = { 2001 },
    ["I"] = { 3001 },
  }
}
env.pfDB.quests.loc[questId] = { T = "Multi-Objective Test Quest" }

env.pfDB.units.data[1001] = { coords = { { 30.0, 30.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1001] = "Defias Thug"

env.pfDB.units.data[1002] = { coords = { { 32.0, 32.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1002] = "Sickly Gazelle"

env.pfDB.objects.data[2001] = { coords = { { 34.0, 34.0, 1, 0 } }, fac = "A" }
env.pfDB.objects.loc[2001] = "Northshire Water Valve"

env.pfDB.items.data[3001] = { ["U"] = { [1003] = 100 } }
env.pfDB.items.loc[3001] = "Garrick's Head"

env.pfDB.units.data[1003] = { coords = { { 36.0, 36.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1003] = "Garrick Padfoot"

env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

print("[TEST] Objective parsing scenario: In-progress quest (0/10 Thugs, 0/4 Gazelles, 0/1 Valve, 0/1 Head)...")
env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 0/10", type = "monster", done = nil },
      [2] = { text = "Sickly Gazelle healed: 0/4", type = "monster", done = nil },
      [3] = { text = "Northshire Water Valve turned: 0/1", type = "object", done = nil },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta)

-- Verify all 4 objectives placed nodes
assert(env.pfMap.nodes["PFQUEST"][1]["30|30"], "Defias Thug node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["32|32"], "Sickly Gazelle node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["34|34"], "Water Valve node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Garrick Padfoot drop node should be present")
print("  ✓ PASS: In-progress objectives successfully placed on map")

print("[TEST] Objective parsing scenario: Partial completion (Defias Thugs 10/10 DONE, Water Valve 1/1 DONE)...")
env.pfMap:DeleteNode("PFQUEST", "Multi-Objective Test Quest")

env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 10/10", type = "monster", done = 1 },
      [2] = { text = "Sickly Gazelle healed: 2/4", type = "monster", done = nil },
      [3] = { text = "Northshire Water Valve turned: 1/1", type = "object", done = 1 },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta2 = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta2)

-- Assert finished objectives (Defias Thug & Water Valve) are NOT added
assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["30|30"],
  "Completed Defias Thug (10/10 slain) node MUST be hidden!")
assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["34|34"],
  "Completed Water Valve (1/1 object) node MUST be hidden!")

-- Assert remaining incomplete objectives (Gazelle & Garrick's Head) ARE still present
assert(env.pfMap.nodes["PFQUEST"][1]["32|32"], "Incomplete Sickly Gazelle (2/4 healed) node MUST be shown!")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Incomplete Garrick Padfoot drop node MUST be shown!")
print("  ✓ PASS: Completed kill mob and completed game object correctly filtered out")

print("[TEST] Objective parsing scenario: Non-slain verb completion (Sickly Gazelle 4/4 healed DONE)...")
env.pfMap:DeleteNode("PFQUEST", "Multi-Objective Test Quest")

env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 10/10", type = "monster", done = 1 },
      [2] = { text = "Sickly Gazelle healed: 4/4", type = "monster", done = 1 },
      [3] = { text = "Northshire Water Valve turned: 1/1", type = "object", done = 1 },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta3 = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta3)

assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["32|32"],
  "Completed Sickly Gazelle (4/4 healed, non-slain verb) node MUST be hidden!")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Only Garrick Padfoot drop node should remain")
print("  ✓ PASS: Non-slain verb ('healed') properly parsed as DONE and node removed")

print("[TEST] test_objective_parsing PASSED successfully!")
