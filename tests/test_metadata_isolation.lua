-- Test Suite: Metadata Isolation and Shared Table Cleanup
-- Ensures meta table properties (title, itemreq, item, droprate, sellcount) do not leak across entities.

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

-- Setup mock data
env.pfDB.units.data[10] = { coords = { { 10.0, 10.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[10] = "First Mob"

env.pfDB.units.data[20] = { coords = { { 20.0, 20.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[20] = "Second Mob"

env.pfDB.objects.data[30] = { coords = { { 30.0, 30.0, 1, 0 } }, fac = "A" }
env.pfDB.objects.loc[30] = "First Object"

-- 1. Test SearchMobID: meta["title"] should not persist on caller's meta table when caller passed nil
print("[TEST] Verifying SearchMobID non-destructive title assignment...")
local sharedMeta = { ["addon"] = "PFTEST" }
env.pfDatabase:SearchMobID(10, sharedMeta)
assert(sharedMeta["title"] == nil, "SearchMobID must restore meta.title to nil if caller passed nil!")
assert(env.pfMap.nodes["PFTEST"][1]["10|10"]["First Mob"], "Node at 10|10 should be keyed by 'First Mob'")

-- Calling on second mob with same sharedMeta should use Second Mob's name, not First Mob
env.pfDatabase:SearchMobID(20, sharedMeta)
assert(sharedMeta["title"] == nil, "SearchMobID must restore meta.title to nil after second call!")
assert(env.pfMap.nodes["PFTEST"][1]["20|20"]["Second Mob"], "Node at 20|20 should be keyed by 'Second Mob', NOT 'First Mob'!")
assert(not env.pfMap.nodes["PFTEST"][1]["20|20"]["First Mob"], "Node at 20|20 must NOT leak 'First Mob'!")
print("  ✓ PASS: SearchMobID does not leak title onto shared caller meta")

-- 2. Test SearchObjectID: meta["title"] non-destructive restoration
print("[TEST] Verifying SearchObjectID non-destructive title assignment...")
local sharedObjMeta = { ["addon"] = "PFTEST_OBJ" }
env.pfDatabase:SearchObjectID(30, sharedObjMeta)
assert(sharedObjMeta["title"] == nil, "SearchObjectID must restore meta.title to nil!")
assert(env.pfMap.nodes["PFTEST_OBJ"][1]["30|30"]["First Object"], "Node at 30|30 should be keyed by 'First Object'")
print("  ✓ PASS: SearchObjectID does not leak title onto shared caller meta")

-- 3. Test Quest with itemreq: ensure meta.itemreq does NOT leak into creature objectives
print("[TEST] Verifying itemreq isolation in SearchQuestID...")
local questId = 600
env.pfDB.quests.data[questId] = {
  lvl = 5,
  min = 1,
  ["start"] = { ["U"] = { 823 } },
  ["obj"] = {
    ["IR"] = { 5001 },
    ["U"] = { 20 },
  }
}
env.pfDB.quests.loc[questId] = { T = "Itemreq Test Quest" }
env.pfDB.items.loc[5001] = "Special Douse Torch"
env.pfDB["quests-itemreq"] = env.pfDB["quests-itemreq"] or {}
env.pfDB["quests-itemreq"]["data"] = env.pfDB["quests-itemreq"]["data"] or {}
env.pfDB["quests-itemreq"]["data"][5001] = { [-30] = 1234 } -- target is object 30

env.pfDatabase.Reload()
local qMeta = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Itemreq Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Special Douse Torch used: 0/1", type = "event", done = nil },
      [2] = { text = "Second Mob slain: 0/5", type = "monster", done = nil },
    }
  }
})

env.pfDatabase:SearchQuestID(questId, qMeta)

-- Second Mob node should NOT have itemreq set
local mobNode = env.pfMap.nodes["PFQUEST"][1]["20|20"]["Itemreq Test Quest"]
assert(mobNode, "Second Mob node should exist")
assert(not mobNode.itemreq, "Ordinary kill mob MUST NOT inherit meta.itemreq from earlier item requirement!")
assert(qMeta.itemreq == nil, "Caller's qMeta.itemreq must be nil upon SearchQuestID completion!")
print("  ✓ PASS: meta.itemreq isolated and cleaned up properly")

print("[TEST] test_metadata_isolation PASSED successfully!")
