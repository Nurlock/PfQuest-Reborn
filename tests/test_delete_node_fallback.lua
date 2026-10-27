-- Test Suite: Map DeleteNode Fast-Path, Fallback Scan, and Cache Invalidation
-- Ensures no node can become an immortal ghost pin on map or minimap.

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
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")

print("[TEST] Verifying DeleteNode with coordinate containing multiple titles...")
-- Add two nodes at the exact same coordinate (zone 1, coords 25.0|35.0)
env.pfMap:AddNode({
  addon = "PFTEST",
  zone = 1,
  x = "25.0",
  y = "35.0",
  title = "Quest Alpha",
  texture = "Interface\\AddOns\\pfQuest\\img\\available_c",
})
env.pfMap:AddNode({
  addon = "PFTEST",
  zone = 1,
  x = "25.0",
  y = "35.0",
  title = "Quest Beta",
  texture = "Interface\\AddOns\\pfQuest\\img\\available_c",
})

local coordNode = env.pfMap.nodes["PFTEST"][1]["25.0|35.0"]
assert(coordNode["Quest Alpha"], "Quest Alpha should be at 25.0|35.0")
assert(coordNode["Quest Beta"], "Quest Beta should be at 25.0|35.0")

-- Delete Quest Alpha: Quest Beta MUST survive, dirtyNodes must be marked
env.pfMap:DeleteNode("PFTEST", "Quest Alpha")
assert(not coordNode["Quest Alpha"], "Quest Alpha must be deleted")
assert(coordNode["Quest Beta"], "Quest Beta must survive at 25.0|35.0")
assert(env.pfMap.dirtyNodes[coordNode], "dirtyNodes must be set for surviving coord")
assert(env.pfMap.dirtyMaps[1], "dirtyMaps must be set for zone 1")
print("  ✓ PASS: Multi-title coordinate partially pruned without destroying remaining titles")

print("[TEST] Verifying DeleteNode fallback when titleIndex has a miss...")
-- Manually corrupt/clear titleIndex to simulate an index miss
env.pfMap.titleIndex["PFTEST"]["Quest Beta"] = nil

-- Now delete Quest Beta. The fallback scan over pfMap.nodes MUST catch it!
env.pfMap:DeleteNode("PFTEST", "Quest Beta")
assert(not env.pfMap.nodes["PFTEST"][1]["25.0|35.0"],
  "Coordinate 25.0|35.0 should be nil after Quest Beta is deleted via fallback scan!")
print("  ✓ PASS: Fallback scan successfully deletes orphaned node on titleIndex miss")

print("[TEST] Verifying DeleteNode unifiedcache invalidation...")
env.pfMap.unifiedcache["Test Cache Title"] = { dummy = true }
env.pfMap:DeleteNode("PFTEST", "Test Cache Title")
assert(env.pfMap.unifiedcache["Test Cache Title"] == nil,
  "DeleteNode must invalidate pfMap.unifiedcache for the deleted title!")
print("  ✓ PASS: unifiedcache properly purged on DeleteNode")

print("[TEST] test_delete_node_fallback PASSED successfully!")
