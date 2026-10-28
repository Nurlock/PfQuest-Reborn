-- Unit Test: Wizard Lifecycle, First-Run Detection & /db query proposal
-- Tests pfQuestInit behavior on first-run vs subsequent /reload

local mock = require("tests.mock_wow_api")

local function setup_env(initialConfig)
  local env = mock.create_env()

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
    global = { font_size = 12 },
    appearance = { border = { default = "3" } },
  }
  env.pfQuestCompat = {
    gfind = string.gmatch,
  }
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
  env.pfDatabase = {
    queryServerCalled = 0,
    QueryServer = function(self)
      self.queryServerCalled = self.queryServerCalled + 1
    end,
  }
  env.GameFontNormal = {}
  env.GameFontWhite = {}
  env.YES = "Yes"
  env.NO = "No"

  if initialConfig then
    env.pfQuest_config = initialConfig
  end

  local configChunk = loadfile("config.lua")
  setfenv(configChunk, env)
  configChunk()

  return env
end

print("[TEST] Scenario 1: Fresh character / first run...")
local env1 = setup_env(nil)
local pfQuestConfig1 = env1.pfQuestConfig
local pfQuestInit1 = env1.pfQuestInit

-- Fire ADDON_LOADED for core addon
env1.arg1 = "pfQuest-Reborn"
pfQuestConfig1:FireScript("OnEvent")

assert(pfQuestConfig1.isFirstRun == true, "First run should be detected when config is fresh")
assert(env1.pfQuest_config.welcome ~= "1", "Welcome flag should not be set yet on first run")

-- Fire PLAYER_ENTERING_WORLD
pfQuestInit1:FireScript("OnEvent")
assert(pfQuestInit1:IsShown() == true, "pfQuestInit wizard must show on first run")

-- Check controls on wizard
assert(pfQuestInit1.querybox ~= nil, "Query box must exist on pfQuestInit")
assert(pfQuestInit1.trackerbox ~= nil, "Tracker box must exist on pfQuestInit")
assert(pfQuestInit1.groupbox ~= nil, "Group sync box must exist on pfQuestInit")
assert(pfQuestInit1.close ~= nil, "Close button must exist on pfQuestInit")

-- Verify tracker + group sync default to enabled
pfQuestInit1:FireScript("OnShow")
assert(pfQuestInit1.trackerbox:GetChecked(), "Tracker box must default to checked")
assert(pfQuestInit1.groupbox:GetChecked(), "Group sync box must default to checked")

-- Uncheck both, verify save writes them as disabled
pfQuestInit1.trackerbox:SetChecked(false)
pfQuestInit1.trackerbox:FireScript("OnClick")
pfQuestInit1.groupbox:SetChecked(false)
pfQuestInit1.groupbox:FireScript("OnClick")

-- Verify clicking Save & Close triggers pfDatabase:QueryServer()
pfQuestInit1.save:FireScript("OnClick")
assert(env1.pfDatabase.queryServerCalled == 1, "pfDatabase:QueryServer() must be called on first run save")
assert(env1.pfQuest_config.welcome == "1", "Welcome flag must be set to 1 after Save & Close")
assert(env1.pfQuest_config.showtracker == "0", "Unchecking tracker must write showtracker=0")
assert(env1.pfQuest_config.epochgroupsync == "0", "Unchecking group sync must write epochgroupsync=0")
assert(pfQuestInit1:IsShown() == false, "Wizard must be hidden after Save & Close")
print("  ✓ PASS: First-run properly displays wizard and triggers /db query on Save & Close")

print("[TEST] Scenario 2: Non-first run / reload scenario...")
local env2 = setup_env({ ["showspawn"] = "1", ["routes"] = "1" })
local pfQuestConfig2 = env2.pfQuestConfig
local pfQuestInit2 = env2.pfQuestInit

-- Fire ADDON_LOADED with existing configuration
env2.arg1 = "pfQuest-Reborn"
pfQuestConfig2:FireScript("OnEvent")

assert(pfQuestConfig2.isFirstRun == false, "Must detect non-first run when config already exists")
assert(env2.pfQuest_config.welcome == "1", "Welcome flag must be auto-set to 1 for existing users")

-- Fire PLAYER_ENTERING_WORLD (as in /reload)
pfQuestInit2:FireScript("OnEvent")
assert(pfQuestInit2:IsShown() == false, "pfQuestInit wizard must NOT show on /reload when not first run")
print("  ✓ PASS: Wizard is completely suppressed on /reload for non-first runs")

print("[TEST] Scenario 3: Closing wizard via 'X' sets welcome=1 to prevent /reload re-popup...")
local env3 = setup_env(nil)
local pfQuestConfig3 = env3.pfQuestConfig
local pfQuestInit3 = env3.pfQuestInit

env3.arg1 = "pfQuest-Reborn"
pfQuestConfig3:FireScript("OnEvent")
pfQuestInit3:FireScript("OnEvent")
assert(pfQuestInit3:IsShown() == true, "Wizard shown initially")

-- Click close button
pfQuestInit3.close:FireScript("OnClick")
assert(env3.pfQuest_config.welcome == "1", "Closing wizard must set welcome=1")
assert(pfQuestInit3:IsShown() == false, "Wizard must hide on close")

-- Subsequent reload:
pfQuestInit3:FireScript("OnEvent")
assert(pfQuestInit3:IsShown() == false, "Must not show on subsequent reload after close")
print("  ✓ PASS: Dismissing wizard persists welcome=1 and prevents re-popup on /reload")

print("test_wizard_lifecycle PASSED successfully!")
