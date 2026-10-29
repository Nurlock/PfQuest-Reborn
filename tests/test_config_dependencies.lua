-- Unit Test: Config UI Parent-Child Dependencies & Grayout
-- Tests pfQuestConfig:IsEntryActive, SetEntryEnabled, and UpdateDependencies

local mock = require("tests.mock_wow_api")
local env = mock.create_env()

-- Setup WoW & pfUI environment mocks
env.pfUI = {
  font_default = "Fonts\\FRIZQT__.TTF",
  api = {
    SkinButton = function(btn) end,
    CreateBackdrop = function(frame) end,
    CreateScrollFrame = function(name, parent)
      return env.CreateFrame("ScrollFrame", name, parent)
    end,
    CreateScrollChild = function(name, parent)
      return env.CreateFrame("Frame", name, parent)
    end,
    SetButtonFontColor = function(btn, r, g, b, a) end,
  }
}
env.pfUI_config = {
  global = {
    font_size = 12,
  }
}
env.pfQuestCompat = {}
env.pfQuest_Loc = setmetatable({}, {
  __index = function(t, k) return k end
})
env.UISpecialFrames = {}
env.GetAddOnInfo = function(name) return name, name end
env.GetAddOnMetadata = function(name, field) return "1.0" end
env.ReloadUI = function() end
env.StaticPopup_Show = function() end
env.pfQuest = {
  ResetAll = function() end,
}
env.GameFontNormal = {}
env.GameFontWhite = {}
env.YES = "Yes"
env.NO = "No"

-- Load config.lua inside our simulated environment
local configChunk, err = loadfile("config.lua")
if not configChunk then
  error("Failed to load config.lua: " .. tostring(err))
end
setfenv(configChunk, env)
configChunk()

local pfQuestConfig = env.pfQuestConfig
local pfQuest_config = env.pfQuest_config
local pfQuest_defconfig = env.pfQuest_defconfig

-- Initialize config
pfQuestConfig:LoadConfig()
pfQuestConfig:CreateConfigEntries(pfQuest_defconfig)

print("[TEST] Verifying tab layout: 9 tabs in frequency order...")
local tabKeys = {}
for _, tabInfo in ipairs(pfQuestConfig.tabList) do
  table.insert(tabKeys, tabInfo.key)
end
local expectedTabs = {
  "Quests", "Tracker", "Map & Minimap", "Group Sync & Chat", "Loot Panel",
  "Nameplates", "Automation", "General", "User Data",
}
assert(table.getn(tabKeys) == table.getn(expectedTabs),
  "expected " .. table.getn(expectedTabs) .. " tabs, got " .. table.getn(tabKeys))
for i, expected in ipairs(expectedTabs) do
  assert(tabKeys[i] == expected,
    "tab " .. i .. " should be '" .. expected .. "', got '" .. tostring(tabKeys[i]) .. "'")
end
print("  ✓ PASS: Tab order verified (" .. table.concat(tabKeys, " / ") .. ")")

print("[TEST] Verifying subheaders render as non-interactive accent captions...")
local subheaderCount = 0
for _, frame in ipairs(pfQuestConfig.entryFrames) do
  if frame.data and frame.data.type == "subheader" then
    subheaderCount = subheaderCount + 1
    assert(frame.input == nil, "subheader '" .. tostring(frame.data.text) .. "' must have no input control")
    assert(frame.enabled == true, "subheader '" .. tostring(frame.data.text) .. "' must stay enabled")
  end
end
assert(subheaderCount >= 8, "expected at least 8 subheaders, got " .. subheaderCount)
print("  ✓ PASS: " .. subheaderCount .. " subheaders render without inputs and stay enabled")

print("[TEST] Verifying mindropchance moved under Loot Panel...")
local lootTab = nil
for _, tabInfo in ipairs(pfQuestConfig.tabList) do
  if tabInfo.key == "Loot Panel" then lootTab = tabInfo break end
end
assert(lootTab, "Loot Panel tab must exist")
local foundDropChance = false
for _, data in ipairs(lootTab.entries) do
  if data.config == "mindropchance" then foundDropChance = true break end
end
assert(foundDropChance, "mindropchance must live under Loot Panel")
print("  ✓ PASS: mindropchance is under Loot Panel")

print("[TEST] Verifying Group Sync gating: children follow epochgroupsync master...")
assert(pfQuest_config["epochgroupsync"] == "1", "epochgroupsync should default to '1'")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["epochgroupsync"]) == true, "epochgroupsync master itself must be active")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["showpartyobjectives"]) == true, "showpartyobjectives must be active when epochgroupsync=1")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["showpartytooltips"]) == true, "showpartytooltips must be active when epochgroupsync=1")

-- questannounce lives under Group Sync & Chat > Announcements (active regardless of experimental)
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["questannounce"]) == true, "questannounce must be active under Announcements")

-- Helper to find frame by config key
local function GetFrame(configKey)
  for _, frame in ipairs(pfQuestConfig.entryFrames) do
    if frame.data and frame.data.config == configKey then
      return frame
    end
  end
  error("Frame not found for config: " .. tostring(configKey))
end

local syncFrame = GetFrame("epochgroupsync")
local objFrame = GetFrame("showpartyobjectives")
local tooltipFrame = GetFrame("showpartytooltips")

-- Verify children enabled by default (no experimental gate)
local syncChildren = { objFrame, tooltipFrame }
for _, frame in ipairs(syncChildren) do
  assert(frame.enabled == true, "Frame for " .. frame.data.config .. " should be enabled when epochgroupsync=1")
end
print("  ✓ PASS: Both party-sync children enabled when master is on")

print("[TEST] Simulating disabling Group Sync master toggle...")
syncFrame.input:SetChecked(false)
syncFrame.input:FireScript("OnClick")

assert(pfQuest_config["epochgroupsync"] == "0", "epochgroupsync config should now be '0'")
assert(objFrame.enabled == false, "showpartyobjectives should now be disabled")
assert(tooltipFrame.enabled == false, "showpartytooltips should now be disabled")
print("  ✓ PASS: Disabling master switch dynamically disables child options")

print("[TEST] Simulating re-enabling Group Sync master toggle...")
syncFrame.input:SetChecked(true)
syncFrame.input:FireScript("OnClick")
assert(objFrame.enabled == true, "showpartyobjectives should now be enabled")
assert(tooltipFrame.enabled == true, "showpartytooltips should now be enabled")
print("  ✓ PASS: Toggling master switch dynamically enables child options")

print("[TEST] Verifying click prevention on disabled checkbox...")
syncFrame.input:SetChecked(false)
syncFrame.input:FireScript("OnClick")
assert(objFrame.enabled == false, "precondition: child must be disabled")
local savedVal = pfQuest_config["showpartyobjectives"]
objFrame.input:SetChecked(not objFrame.input:GetChecked())
objFrame.input:FireScript("OnClick")
assert(pfQuest_config["showpartyobjectives"] == savedVal, "Disabled checkbox click must not change pfQuest_config")
print("  ✓ PASS: Clicks on disabled controls are ignored")

print("[TEST] Verifying Routes hierarchy & Arrow scale slider grayout...")
local routesFrame = GetFrame("routes")
local arrowFrame = GetFrame("arrow")
local arrowScaleFrame = GetFrame("arrowscale")

assert(routesFrame.enabled == true, "routes master should be enabled")
assert(arrowScaleFrame.enabled == true, "arrowscale slider should be enabled when routes=1 and arrow=1")

-- Disable arrow
arrowFrame.input:SetChecked(false)
arrowFrame.input:FireScript("OnClick")
assert(arrowScaleFrame.enabled == false, "arrowscale slider must be disabled when arrow=0")
assert(arrowScaleFrame.input:IsMouseEnabled() == false, "arrowscale slider mouse must be disabled")

-- Disable all routes
routesFrame.input:SetChecked(false)
routesFrame.input:FireScript("OnClick")
assert(arrowFrame.enabled == true, "arrow must stay enabled when routes=0 (own Navigation category)")
assert(arrowScaleFrame.enabled == false, "arrowscale must remain disabled when arrow=0")
print("  ✓ PASS: Routes hierarchy and slider disabling verified")

print("test_config_dependencies PASSED successfully!")
