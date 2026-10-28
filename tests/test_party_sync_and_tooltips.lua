-- Test Suite: Pure pfQuest-epoch Party Sync & Tooltips
-- Verifies pfqe protocol (V1 batches, REMOVEQ, PFQUEST_SYNC_REQUEST), raid support, and tooltips.

local mock = require("tests.mock_wow_api")
local env = mock.create_env()
env.UnitInParty = function(u)
  return u == "PartyFriend" or u == "EpochFriend" or u == "IdFriend"
      or u == "ColonFriend" or u == "BurstFriend" or u == "WireFriend" or u == "BatchFriend" or u == "GoldFriend"
      or nil
end
env.UnitInRaid = function(u) return nil end

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
  ["epochgroupsync"] = "1",
  ["showpartytooltips"] = "1",
  ["epochShowPartyProgress"] = "1",
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
  queue = {},
  queueHead = 1,
  queueTail = 1,
  queueCount = 0,
}

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")
load_file("quest.lua")
load_file("announce.lua")

-- Setup mock party
env.GetNumPartyMembers = function() return 2 end
env.GetNumRaidMembers = function() return 0 end
env.UnitName = function(u)
  if u == "player" then return "LocalPlayer" end
  if u == "party1" then return "PartyFriend" end
  if u == "party2" then return "EpochFriend" end
  return "PartyFriend"
end
env.UnitClass = function(u)
  return "Warrior", "WARRIOR"
end

env.GetQuestLogTitle = function(index)
  if index == 1 then return "Defias Hunt", 10, "Elite", false, false, 0 end
  return nil
end
env.pfQuestCompat = env.pfQuestCompat or {}
env.pfQuestCompat.GetQuestLogTitle = env.GetQuestLogTitle
env.GetNumQuestLogEntries = function() return 1 end
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
  ["end"] = { U = { 240 } },
  ["obj"] = { U = { 116 } },
}
env.pfDB.units = env.pfDB.units or { loc = {} }
env.pfDB.units.loc[240] = "Marshal Dughan"
env.pfDB.units.loc[116] = "Defias Bandit"
env.pfDB.units.loc[241] = "Goldshire Guard"
env.pfDatabase = env.pfDatabase or {}
local searchedQuestIds = {}
env.pfDatabase.SearchQuestID = function(self, qid, meta)
  table.insert(searchedQuestIds, { qid = qid, meta = meta })
end
env.pfMap = env.pfMap or {}
env.pfMap.queue_update = nil
env.pfMap.DeleteNode = env.pfMap.DeleteNode or function(self, addon, title) end

local sentAddonMessages = {}
env.SendAddonMessage = function(pfx, text, dist, target)
  table.insert(sentAddonMessages, { prefix = pfx, text = text, dist = dist, target = target })
end

env.UnitIsPlayer = function(u) return false end

-- Load pure pfQuest-epoch tooltip and comms module
load_file("pfQuest-tooltip.lua")

local epoch = env.pfQuest.epochComms
assert(epoch, "pfQuest.epochComms must be loaded")
epoch.HookGameTooltip()

print("[TEST] 1. Verifying inbound pfqe V1 batch message...")
epoch.ProcessQuestData("PartyFriend", "V1|U116Q100:4:10;")
local pData = epoch.partyQuestData["PartyFriend"]
assert(pData ~= nil, "PartyFriend data must exist")
assert(pData["Defias Bandit"] ~= nil, "Target 'Defias Bandit' must be mapped")
local obj = pData["Defias Bandit"][1]
assert(obj.quest == "Defias Hunt", "Quest must be 'Defias Hunt'")
assert(obj.current == 4, "Current count must be 4")
assert(obj.total == 10, "Total count must be 10")
print("  ✓ PASS: Inbound pfqe V1 batch parsed into partyQuestData")

print("[TEST] 2. Verifying GameTooltip unit hover shows party progress...")
local testTip = env.GameTooltip
testTip.lines = {}
testTip.AddLine = function(self, text, r, g, b)
  table.insert(self.lines, text)
end
testTip.GetUnit = function(self)
  return "Defias Bandit", "target"
end
testTip.Show = function(self) self.shown = true end

-- Simulate hover
testTip:FireScript("OnTooltipSetUnit")
local foundProgress = false
for _, line in ipairs(testTip.lines) do
  if string.find(line, "PartyFriend") and string.find(line, "4/10") then
    foundProgress = true
  end
end
assert(foundProgress, "Tooltip must include party member and objective progress 4/10")
print("  ✓ PASS: Unit tooltip displays colored party member progress")

print("[TEST] 1b. Verifying inbound V1 batch draws party map nodes...")
assert(#searchedQuestIds > 0, "Inbound V1 must trigger SearchQuestID for party map nodes")
local foundNode = false
for _, s in ipairs(searchedQuestIds) do
  if s.qid == 100 and s.meta and s.meta.addon == "PARTY" and s.meta.partyMember == "PartyFriend" then
    foundNode = true
  end
end
assert(foundNode, "SearchQuestID must be called for quest 100 with PARTY/PartyFriend meta")
print("  ✓ PASS: Inbound V1 batch wires party map node creation")

print("[TEST] 1c. Verifying pfMap tooltip wrapper does not crash on party data...")
local fakeMeta = { quest = "Defias Hunt", item = {}, partyMember = "PartyFriend" }
env.pfMap.ShowTooltip(nil, fakeMeta, env.GameTooltip)
print("  ✓ PASS: pfMap tooltip wrapper runs with party data present")

print("[TEST] 3. Verifying inbound REMOVEQ message purges quest data...")
epoch.ProcessQuestData("PartyFriend", "REMOVEQ:100:Defias Hunt")
assert(pData["Defias Bandit"] == nil, "Defias Hunt objective should be purged after REMOVEQ")
print("  ✓ PASS: Inbound REMOVEQ cleanly purges party quest data")

print("[TEST] 4. Verifying outbound pfqe V1 broadcast via ShareQuestData...")
sentAddonMessages = {}
epoch.RebuildQuestMappings()
epoch.ShareQuestData(true)

local foundOutboundV1 = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "V1|") and string.find(msg.text, "U116Q100:3:10;") then
    foundOutboundV1 = true
    assert(msg.dist == "PARTY", "Message must be sent to PARTY distribution")
  end
end
assert(foundOutboundV1, "ShareQuestData must broadcast V1 entry for U116Q100:3:10;")
print("  ✓ PASS: Outbound pfqe quest update correctly formatted and transmitted")

print("[TEST] 5. Verifying PFQUEST_SYNC_REQUEST inbound triggers response...")
sentAddonMessages = {}
env.arg1 = "PFQUEST_SYNC_REQUEST"
env.arg2 = "1"
env.arg3 = "PARTY"
env.arg4 = "PartyFriend"
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")

local syncReplied = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "V1|") then
    syncReplied = true
  end
end
assert(syncReplied, "PFQUEST_SYNC_REQUEST from party member must trigger full quest list broadcast on pfqe")
print("  ✓ PASS: Inbound PFQUEST_SYNC_REQUEST triggers pfqe broadcast")

print("[TEST] 6. Verifying raid distribution routing...")
env.GetNumRaidMembers = function() return 10 end
sentAddonMessages = {}
epoch.ShareQuestData(true)
local foundRaidMsg = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and msg.dist == "RAID" then
    foundRaidMsg = true
  end
end
assert(foundRaidMsg, "ShareQuestData must route to RAID channel when in a raid")
print("  ✓ PASS: Raid distribution cleanly routed to RAID channel")

print("[TEST] 7. Verifying config toggles...")
env.pfQuest_config["epochgroupsync"] = "0"
assert(epoch.IsSyncEnabled() == false, "epochgroupsync=0 must disable sync")
sentAddonMessages = {}
epoch.ShareQuestData(true)
assert(#sentAddonMessages == 0, "No messages should be sent when epochgroupsync=0")

env.pfQuest_config["epochgroupsync"] = "1"
assert(epoch.IsSyncEnabled() == true, "epochgroupsync=1 must enable sync")

print("  ✓ PASS: Protocol enablement correctly governed by epochgroupsync")

print("[TEST] 8. Verifying BroadcastQuestRemove and CleanupPartyData exports...")
assert(epoch.BroadcastQuestRemove ~= nil, "BroadcastQuestRemove must be exported")
env.GetNumRaidMembers = function() return 0 end
env.GetNumPartyMembers = function() return 2 end
sentAddonMessages = {}
epoch.BroadcastQuestRemove(100, "Defias Hunt")
local foundRemove = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and msg.text == "REMOVEQ:100:Defias Hunt" and msg.dist == "PARTY" then
    foundRemove = true
  end
end
assert(foundRemove, "BroadcastQuestRemove must send REMOVEQ:100:Defias Hunt to PARTY")
epoch.CleanupPartyData()
print("  ✓ PASS: BroadcastQuestRemove and CleanupPartyData work")

print("[TEST] 9. Verifying colon-tolerant QUEST parsing...")
env.GetNumRaidMembers = function() return 0 end
env.GetNumPartyMembers = function() return 2 end
env.AdvanceTime(30)
epoch.ProcessQuestData("ColonFriend", "QUEST:Darkshore:Escort: The Missing Diplomat:Escort completed:3:10")
local cData = epoch.partyQuestData["ColonFriend"]
assert(cData ~= nil, "ColonFriend data must exist")
local foundColon = false
for targetKey, quests in pairs(cData) do
  for _, q in ipairs(quests) do
    if q.quest == "Escort: The Missing Diplomat" and q.current == 3 and q.total == 10 then
      foundColon = true
    end
  end
end
assert(foundColon, "QUEST with colons in quest name must parse target/quest/objective/counts")
print("  ✓ PASS: Colon-tolerant QUEST parsing works")

print("[TEST] 10. Verifying out-of-range progress is rejected...")
local beforeCount = 0
for _, quests in pairs(epoch.partyQuestData["Troll"] or {}) do
  beforeCount = beforeCount + table.getn(quests)
end
epoch.ProcessQuestData("Troll", "V1|U116Q100:10:0;")
epoch.ProcessQuestData("Troll", "V1|U116Q100:99999:10;")
local afterCount = 0
for _, quests in pairs(epoch.partyQuestData["Troll"] or {}) do
  afterCount = afterCount + table.getn(quests)
end
assert(afterCount == beforeCount, "Out-of-range entries (total=0, current>total) must be dropped")
assert(epoch.IsValidProgress(3, 10) == true, "3/10 must be valid")
assert(epoch.IsValidProgress(10, 0) == false, "total=0 must be invalid")
assert(epoch.IsValidProgress(11, 10) == false, "current>total must be invalid")
print("  ✓ PASS: Out-of-range progress rejected")

print("[TEST] 11. Verifying REMOVEQ matches on quest ID, not just title...")
epoch.ProcessQuestData("IdFriend", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["IdFriend"] ~= nil, "IdFriend data must exist")
-- inject a same-title entry with a different quest id; REMOVEQ:100 must keep it
table.insert(epoch.partyQuestData["IdFriend"]["Defias Bandit"], {
  quest = "Defias Hunt", questId = 999, objective = "Other", current = 1, total = 5, lastUpdate = 0,
})
epoch.ProcessQuestData("IdFriend", "REMOVEQ:100:Defias Hunt")
local remaining = epoch.partyQuestData["IdFriend"]["Defias Bandit"]
assert(remaining ~= nil and table.getn(remaining) == 1 and remaining[1].questId == 999,
  "REMOVEQ must only remove entries matching the quest ID")
print("  ✓ PASS: REMOVEQ ID-scoped removal works")

print("[TEST] 12. Verifying sent-keys-only broadcast state...")
sentAddonMessages = {}
epoch.ShareQuestData(true)
local sentOnce = #sentAddonMessages
epoch.ShareQuestData(false)
assert(#sentAddonMessages == sentOnce, "Second delta broadcast with no changes must send nothing")
print("  ✓ PASS: Broadcast state only tracks sent keys")

print("[TEST] 13. Verifying REMOVEQ arrives through the real CHAT_MSG_ADDON path...")
epoch.ProcessQuestData("WireFriend", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["WireFriend"] ~= nil, "WireFriend data must exist before removal")
env.AdvanceTime(30)
epoch.PumpSyncTimers()
epoch.HandlePfqeMessage("WireFriend", "REMOVEQ:100:Defias Hunt")
assert(epoch.partyQuestData["WireFriend"] == nil, "direct REMOVEQ must purge")
epoch.ProcessQuestData("WireFriend", "V1|U116Q100:4:10;")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "REMOVEQ:100:Defias Hunt", "PARTY", "WireFriend")
epoch.PumpSyncTimers()
assert(epoch.partyQuestData["WireFriend"] == nil, "trusted REMOVEQ through CHAT_MSG_ADDON must purge")
print("  ✓ PASS: REMOVEQ routed through CHAT_MSG_ADDON and purged")

print("[TEST] 13b. Verifying untrusted REMOVEQ is dropped...")
epoch.ProcessQuestData("StrangerData", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["StrangerData"] ~= nil, "setup: StrangerData must exist")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "REMOVEQ:100:Defias Hunt", "PARTY", "Stranger")
local stillThere = epoch.partyQuestData["StrangerData"]
local strangerTouched = epoch.partyQuestData["Stranger"]
assert(stillThere ~= nil, "untrusted REMOVEQ must not purge other senders' data")
assert(strangerTouched == nil, "untrusted sender must not create party data")
print("  ✓ PASS: Untrusted REMOVEQ dropped")

print("[TEST] 14. Verifying nil sender and self-echo are dropped...")
local function countEntries(sender)
  local n = 0
  for _, quests in pairs(epoch.partyQuestData[sender] or {}) do n = n + table.getn(quests) end
  return n
end
local beforeSelf = countEntries("LocalPlayer")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", nil)
assert(epoch.partyQuestData[nil] == nil, "nil sender must not create party data")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", "LocalPlayer")
epoch.PumpSyncTimers()
-- ShareQuestData mirrors own progress locally; the wire must add nothing new.
assert(countEntries("LocalPlayer") == beforeSelf, "self-echo must not add party data")
print("  ✓ PASS: Nil sender and self-echo dropped")

print("[TEST] 15. Verifying wrong-channel and GUILD messages are dropped...")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "GUILD", "PartyFriend")
epoch.PumpSyncTimers()
local gcount = 0
if epoch.partyQuestData["PartyFriend"] then
  for _, quests in pairs(epoch.partyQuestData["PartyFriend"]) do gcount = gcount + table.getn(quests) end
end
-- PartyFriend already has legit data from test 1; GUILD dup must not add rows
assert(gcount <= 2, "GUILD-channel pfqe must not be ingested")
print("  ✓ PASS: Wrong-channel messages dropped")

print("[TEST] 16. Verifying throttled V1 is queued, not lost...")
-- BurstFriend is fresh: first batch lands inside the trust+throttle window.
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:5:10;", "PARTY", "BurstFriend")
env.AdvanceTime(0.1)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:7:10;", "PARTY", "BurstFriend")
local function burstCurrent()
  local d = epoch.partyQuestData["BurstFriend"]
  if not d then return nil end
  for _, quests in pairs(d) do
    for _, q in ipairs(quests) do return q.current end
  end
end
assert(burstCurrent() == 5, "first batch applies immediately, second is queued")
env.AdvanceTime(2)
epoch.PumpSyncTimers()
assert(burstCurrent() == 7, "queued newest batch must flush after throttle window")
print("  ✓ PASS: Throttle queues newest batch and flushes it")

print("[TEST] 16b. Verifying multi-batch bursts all arrive in order...")
-- three back-to-back batches (e.g. a split full-sync): first applies,
-- the rest queue as a list, then flush in order via the frame ticker alone
-- (no further events fired).
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:1:10;", "PARTY", "BatchFriend")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U240Q100:2:10;", "PARTY", "BatchFriend")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U241Q100:3:10;", "PARTY", "BatchFriend")
local function batchCount()
  local n = 0
  local d = epoch.partyQuestData["BatchFriend"]
  if d then for _, quests in pairs(d) do n = n + table.getn(quests) end end
  return n
end
assert(batchCount() >= 1, "first batch of burst must apply immediately")
env.AdvanceTime(2)
-- ticker only: proves the flush does not depend on another event arriving
epoch.eventFrame:FireScript("OnUpdate")
assert(batchCount() == 3, "all three queued batches must flush in order, got " .. batchCount())
print("  ✓ PASS: Multi-batch bursts flush fully via ticker")

print("[TEST] 16c. Verifying party ender marker follows sender progress...")
local function lastPartyMeta()
  for i = table.getn(searchedQuestIds), 1, -1 do
    if searchedQuestIds[i].meta and searchedQuestIds[i].meta.addon == "PARTY" then
      return searchedQuestIds[i].meta
    end
  end
end
-- 0/10: unfinished must NOT request the gold turn-in look
epoch.ProcessQuestData("GoldFriend", "V1|U116Q100:0:10;")
local m0 = lastPartyMeta()
assert(m0 and m0.partyComplete == false, "0/10 party quest must mark partyComplete=false")
assert(not m0.partyDone or not m0.partyDone["Defias Bandit"], "0/10 target must not be marked done")
-- 10/10: proven complete may use the gold turn-in look
env.AdvanceTime(2)
epoch.PumpSyncTimers()
epoch.ProcessQuestData("GoldFriend", "V1|U116Q100:10:10;")
local m1 = lastPartyMeta()
assert(m1 and m1.partyComplete == true, "10/10 party quest must mark partyComplete=true")
assert(m1.partyDone and m1.partyDone["Defias Bandit"], "10/10 target must be marked done")
print("  ✓ PASS: Party ender marker follows sender progress")

print("[TEST] 19. Verifying periodic full re-sync while grouped...")
sentAddonMessages = {}
epoch.RebuildQuestMappings()
env.AdvanceTime(400)
epoch.PumpSyncTimers()
assert(#sentAddonMessages > 0, "idle grouped client must full-share every few minutes")
print("  ✓ PASS: Periodic full re-sync fires")

print("[TEST] 17. Verifying QUEST_LOG_UPDATE is debounced...")
sentAddonMessages = {}
env.AdvanceTime(30)
for i = 1, 5 do
  epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE")
end
assert(#sentAddonMessages == 0, "rapid QUEST_LOG_UPDATE ticks must not broadcast synchronously")
epoch.PumpSyncTimers()
local afterDebounce = #sentAddonMessages
assert(afterDebounce >= 0, "debounced flush must run without error")
print("  ✓ PASS: QUEST_LOG_UPDATE debounced")

print("[TEST] 18. Verifying DeleteNodesWhere cleans every index...")
local pfMap = env.pfMap
assert(pfMap.DeleteNodesWhere ~= nil, "map must expose DeleteNodesWhere")
pfMap:AddNode({ addon = "PARTY", zone = 1, x = 0.5, y = 0.5,
  title = "Defias Hunt (WireFriend)", quest = "Defias Hunt", questid = 100 })
pfMap:AddNode({ addon = "PARTY", zone = 1, x = 0.6, y = 0.6,
  title = "Other Quest (WireFriend)", quest = "Other Quest", questid = 200 })
assert(pfMap.nodes["PARTY"] ~= nil, "setup: PARTY nodes must exist")
local dead = "Defias Hunt (WireFriend)"
local wiped = pfMap:DeleteNodesWhere("PARTY", function(title)
  return title == dead or string.sub(title, 1, string.len(dead) + 1) == dead .. "\1"
end)
assert(wiped == true, "DeleteNodesWhere must report removals")
assert(pfMap.titleIndex["PARTY"] == nil or pfMap.titleIndex["PARTY"]["Defias Hunt"] == nil,
  "title index must not keep the deleted title")
local leftover = false
for _, coords in pairs(pfMap.nodes["PARTY"][1] or {}) do
  for title in pairs(coords) do
    if title == dead or string.sub(title, 1, string.len(dead) + 1) == dead .. "\1" then leftover = true end
  end
end
assert(leftover == false, "nodes store must not keep the deleted title")
assert(pfMap:DeleteNodesWhere("PARTY", function() return false end) == false,
  "DeleteNodesWhere must report no-ops")
print("  ✓ PASS: DeleteNodesWhere removes title + indexes")

print("\ntest_party_sync_and_tooltips PASSED successfully!")
