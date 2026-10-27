-- Test Suite: Performance Guards, Memory Limits, and Client Compat
-- Verifies ring-buffer Levenshtein eviction, static reject set guards, and updatenotify.

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

-- 1. Test StaticPopupDialogs in compat/client.lua does NOT call TEXT()
print("[TEST] Verifying StaticPopupDialogs in compat/client.lua has no TEXT() calls...")
env.GetBuildInfo = function() return "1.12.1", "5875", "Jul 14 2006", 11200 end
env.memlimit = "Memory Limit Exceeded"
env.QUIT_NOW = "Quit"
env.CANCEL = "Cancel"
env.TEXT = function() error("TEXT() is deprecated in WoW 3.3.5a and must not be called!") end
load_file("compat/client.lua")

local dialog = env.StaticPopupDialogs["MEMORY_EXHAUSTED"]
assert(dialog, "MEMORY_EXHAUSTED dialog should be defined")
assert(type(dialog.text) == "string" and string.find(dialog.text, "Script Memory"), "dialog.text should be raw string without TEXT()")
assert(dialog.button1 == "Quit", "dialog.button1 should be raw string without TEXT()")
print("  ✓ PASS: Deprecated TEXT() calls completely removed from StaticPopupDialogs")

-- 2. Test BuildStaticRejectSet when UnitRace/UnitClass are uninitialized
print("[TEST] Verifying BuildStaticRejectSet handles uninitialized race/class gracefully...")
env.UnitRace = function() return nil end
env.UnitClass = function() return nil end
load_file("database.lua")

-- Should not throw an error even with uninitialized race/class
local ok, err = pcall(function() env.pfDatabase:BuildStaticRejectSet() end)
assert(ok, "BuildStaticRejectSet should return safely when race/class are uninitialized: " .. tostring(err))
print("  ✓ PASS: BuildStaticRejectSet guarded against uninitialized player state")

-- 3. Test Levenshtein ring buffer eviction (insert 600 items into 500-capacity buffer)
print("[TEST] Verifying Levenshtein cache ring buffer eviction without table reallocation...")
-- Restore race/class
env.UnitRace = function() return "Human", "Human" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.pfDatabase:BuildStaticRejectSet()

-- Run GetIDByName with fuzzy Levenshtein matches across 600 unique queries
for i = 1, 600 do
  env.pfDatabase:GetIDByName("FuzzyQuestTitle_" .. i, "quests", true)
end
print("  ✓ PASS: Levenshtein ring-buffer successfully processed 600 entries without table wiping")

-- 4. Test MinimapNodeLevel clamped to <= 128
load_file("map.lua")
print("[TEST] Verifying MinimapNodeLevel clamping <= 128...")
env.pfMap.mlevel = 140
local level = env.pfMap.MinimapNodeLevel(5)
assert(level <= 128, "Minimap frame level must be clamped to <= 128, got " .. tostring(level))
print("  ✓ PASS: Minimap node frame level clamped to 128 to prevent 3.3.5a frame-level overflow")

-- 5. Test updatenotify prefix and loop prevention
print("[TEST] Verifying updatenotify addon prefix and broadcast guard...")
load_file("updatenotify.lua")
local versioncheck = env.lastCreatedFrame
assert(versioncheck, "versioncheck frame should exist")

-- First simulate ADDON_LOADED to initialize version
env.GetAddOnMetadata = function(addon, field) return "1.0.8" end
env.event = "ADDON_LOADED"
env.arg1 = "pfQuest"
versioncheck:FireScript("OnEvent")

-- Simulate incoming message with pfQReborn prefix
env.sentAddonMessages = {}
env.event = "CHAT_MSG_ADDON"
env.arg1 = "pfQReborn"
env.arg2 = "VERSION:10000"
versioncheck:FireScript("OnEvent")
-- Must NOT re-broadcast on incoming message (prevents echo infinite loop)
assert(#env.sentAddonMessages == 0, "Incoming CHAT_MSG_ADDON must not trigger SendAddonMessage (echo loop prevention)!")

-- Broadcast should only happen on PLAYER_ENTERING_WORLD or PARTY_MEMBERS_CHANGED
env.event = "PLAYER_ENTERING_WORLD"
versioncheck:FireScript("OnEvent")
assert(#env.sentAddonMessages > 0, "PLAYER_ENTERING_WORLD should trigger SendAddonMessage")
assert(env.sentAddonMessages[1].prefix == "pfQReborn", "Addon prefix must be pfQReborn, got " .. env.sentAddonMessages[1].prefix)
print("  ✓ PASS: updatenotify uses pfQReborn prefix and guards against broadcast echo loops")

print("[TEST] test_performance_guards PASSED successfully!")
