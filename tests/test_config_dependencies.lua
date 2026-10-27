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

print("[TEST] Verifying initial state: Experimental Features disabled by default...")
assert(pfQuest_config["experimental"] == "0", "experimental should default to '0'")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["experimental"]) == true, "Master toggle itself must be active")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["questiegroup"]) == false, "questiegroup must be inactive when experimental=0")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["epochgroupsync"]) == false, "epochgroupsync must be inactive when experimental=0")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["showpartyobjectives"]) == false, "showpartyobjectives must be inactive when experimental=0")
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["showpartytooltips"]) == false, "showpartytooltips must be inactive when experimental=0")

-- questannounce is now unified under Chat Announcements (active regardless of experimental)
assert(pfQuestConfig:IsEntryActive(pfQuestConfig.configMap["questannounce"]) == true, "questannounce must be active under Chat Announcements")

-- Helper to find frame by config key
local function GetFrame(configKey)
  for _, frame in ipairs(pfQuestConfig.entryFrames) do
    if frame.data and frame.data.config == configKey then
      return frame
    end
  end
  error("Frame not found for config: " .. tostring(configKey))
end

local expFrame = GetFrame("experimental")
local groupFrame = GetFrame("questiegroup")
local epochGroupFrame = GetFrame("epochgroupsync")
local objFrame = GetFrame("showpartyobjectives")
local tooltipFrame = GetFrame("showpartytooltips")

-- Verify visual graying out and disabled status on all 4 children
local expChildren = { groupFrame, epochGroupFrame, objFrame, tooltipFrame }
for _, frame in ipairs(expChildren) do
  assert(frame.enabled == false, "Frame for " .. frame.data.config .. " should have frame.enabled == false")
  assert(frame.input:IsEnabled() == false, "Input for " .. frame.data.config .. " should be disabled")
  assert(frame.input:IsMouseEnabled() == false, "Input for " .. frame.data.config .. " should have mouse disabled")
  local r, g, b = frame.caption:GetTextColor()
  assert(r == 0.5 and g == 0.5 and b == 0.5, "Caption for " .. frame.data.config .. " should be grayed out (0.5, 0.5, 0.5)")
end
print("  ✓ PASS: All 4 experimental sub-features are properly grayed out and disabled initially")

print("[TEST] Simulating enabling master Experimental toggle...")
expFrame.input:SetChecked(true)
expFrame.input:FireScript("OnClick")

assert(pfQuest_config["experimental"] == "1", "experimental config should now be '1'")
assert(groupFrame.enabled == true, "questiegroup should now be enabled")
assert(epochGroupFrame.enabled == true, "epochgroupsync should now be enabled")
assert(objFrame.enabled == true, "showpartyobjectives should now be enabled")
assert(tooltipFrame.enabled == true, "showpartytooltips should now be enabled")
print("  ✓ PASS: Toggling master switch dynamically enables child options")

print("[TEST] Simulating disabling master Experimental toggle...")
expFrame.input:SetChecked(false)
expFrame.input:FireScript("OnClick")
assert(groupFrame.enabled == false, "questiegroup should now be disabled")
assert(epochGroupFrame.enabled == false, "epochgroupsync should now be disabled")
assert(objFrame.enabled == false, "showpartyobjectives should now be disabled")
assert(tooltipFrame.enabled == false, "showpartytooltips should now be disabled")
print("  ✓ PASS: Disabling master switch dynamically disables all child options")

print("[TEST] Verifying click prevention on disabled checkbox...")
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
assert(arrowFrame.enabled == false, "arrow must be disabled when routes=0")
assert(arrowScaleFrame.enabled == false, "arrowscale must remain disabled when routes=0")
print("  ✓ PASS: Routes hierarchy and slider disabling verified")

print("test_config_dependencies PASSED successfully!")
