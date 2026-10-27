-- Test Suite: Questgiver Title Isolation & Acceptance Lifecycle
-- Regression test for the lingering minimap '!' bug on quest acceptance.

local mock = require("tests.mock_wow_api")
local env = mock.create_env()

-- Helper to run code within env
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

-- Initialize minimal required pfQuest environment
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

-- Load compat
load_file("compat/client.lua")

-- Load database
load_file("database.lua")

-- Load map
load_file("map.lua")

-- Populate mock database with Northshire sample data
env.pfDB.quests.data[101] = { lvl = 2, min = 1, ["start"] = { ["U"] = { 1 } } }
env.pfDB.quests.loc[101] = { T = "Kobold Candles" }

env.pfDB.quests.data[783] = { lvl = 1, min = 1, ["start"] = { ["U"] = { 823 } }, ["end"] = { ["U"] = { 197 } } }
env.pfDB.quests.loc[783] = { T = "A Threat Within" }

env.pfDB.units.data[1] = { coords = { { 50.0, 50.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1] = "William Pestle"

env.pfDB.units.data[823] = { coords = { { 48.0, 42.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[823] = "Deputy Willem"

env.pfDB.units.data[197] = { coords = { { 49.0, 40.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[197] = "Marshal McBride"

env.pfQuest = env.pfQuest or { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

print("[TEST] Running SearchQuests...")
local meta = { ["addon"] = "PFQUEST" }
env.pfDatabase:SearchQuests(meta)

-- 1. Assert both questgivers were added
assert(env.pfMap.nodes["PFQUEST"], "pfMap.nodes['PFQUEST'] should exist")
assert(env.pfMap.nodes["PFQUEST"][1], "Map zone 1 nodes should exist")

-- 2. Assert Title Isolation: Deputy Willem MUST be stored under "A Threat Within", NOT "Kobold Candles"
local willemCoords = "48|42"
local willemNode = env.pfMap.nodes["PFQUEST"][1][willemCoords]
assert(willemNode, "Deputy Willem should have a node at 48|42")
assert(willemNode["A Threat Within"], "Node at 48|42 MUST be keyed by 'A Threat Within', not leaked title!")
assert(not willemNode["Kobold Candles"], "Node at 48|42 must NOT have title 'Kobold Candles'!")
assert(env.pfMap.titleIndex["PFQUEST"]["A Threat Within"], "titleIndex must have entry for 'A Threat Within'")
assert(env.pfMap.titleIndex["PFQUEST"]["A Threat Within"][1][willemCoords], "titleIndex must point to 48|42")
print("  ✓ PASS: Questgiver title isolation verified (no leakage across loop iterations)")

-- 3. Simulate accepting quest 783 ("A Threat Within")
print("[TEST] Simulating quest acceptance and DeleteNode('PFQUEST', 'A Threat Within')...")
env.pfQuest.questlog[783] = { title = "A Threat Within", qlogid = 1 }
env.pfMap:DeleteNode("PFQUEST", "A Threat Within")

-- Assert Deputy Willem node is completely gone
assert(not env.pfMap.nodes["PFQUEST"][1][willemCoords], "Deputy Willem's available node MUST be deleted upon acceptance!")
assert(not env.pfMap.titleIndex["PFQUEST"]["A Threat Within"], "titleIndex['PFQUEST']['A Threat Within'] must be cleared!")
print("  ✓ PASS: Starter node properly deleted on quest acceptance")

-- 4. SearchQuestID for active quest adds ender (Marshal McBride)
print("[TEST] Simulating SearchQuestID for active quest 783...")
local qmeta = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(783, qmeta)

local mcbrideCoords = "49|40"
local mcbrideNode = env.pfMap.nodes["PFQUEST"][1][mcbrideCoords]
assert(mcbrideNode, "Marshal McBride (ender) should have a node at 49|40")
assert(mcbrideNode["A Threat Within"], "Marshal McBride node should have title 'A Threat Within'")
print("  ✓ PASS: Quest ender node added for active quest")

-- 5. Run SearchQuests again (Phase 2): active quest ender must NOT be wiped
print("[TEST] Running SearchQuests while quest 783 is active in log...")
env.pfDatabase:SearchQuests({ ["addon"] = "PFQUEST" })

assert(env.pfMap.nodes["PFQUEST"][1][mcbrideCoords], "Marshal McBride node MUST NOT be wiped by SearchQuests Phase 2!")
assert(not env.pfMap.nodes["PFQUEST"][1][willemCoords], "Deputy Willem starter node MUST NOT be re-added while quest is active!")
print("  ✓ PASS: Active quest nodes preserved, completed starter not resurrected")

print("[TEST] test_questgiver_lifecycle PASSED successfully!")
