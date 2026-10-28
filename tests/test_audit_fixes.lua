-- Audit fix check: REMOVEQ with markup in the title must still purge.
-- Stored titles are sanitized, so the remove path must sanitize before compare.
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
env.pfQuest_config = { ["epochgroupsync"] = "1" }
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("pfQuest-tooltip.lua")

local epoch = env.pfQuest.epochComms
assert(epoch, "epochComms hooks must be exposed")

print("[TEST] Markup-titled REMOVEQ purges sanitized entries...")
epoch.StorePartyObjective("MarkupFriend", "Defias Bandit", 100, "|cffff0000Defias Hunt|r", "Slain: 3/10", 3, 10)
assert(epoch.partyQuestData["MarkupFriend"] ~= nil, "setup: MarkupFriend data must exist")
epoch.HandlePfqeMessage("MarkupFriend", "REMOVEQ:100:|cffff0000Defias Hunt|r")
assert(epoch.partyQuestData["MarkupFriend"] == nil, "markup REMOVEQ must purge the sanitized entry (no ghost pins)")
print("  PASS: markup REMOVEQ purges")
