-- Lightweight WoW 3.3.5a API Mock for pfQuest-Reborn unit tests
-- Run with lua5.1

local M = {}

function M.create_env()
  local env = {}
  setmetatable(env, { __index = _G })

  env._G = env
  env.math = math
  env.string = string
  env.table = table

  -- Bitwise support for Lua 5.1
  local bit = _G.bit or {}
  if not bit.band then
    bit.band = function(a, b)
      local result = 0
      local bitval = 1
      while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
          result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
      end
      return result
    end
  end
  env.bit = bit

  -- Standard WoW globals
  env.UNKNOWN = "Unknown"
  env.QUEST_MONSTERS_KILLED = "%s slain: %d/%d"
  env.QUEST_OBJECTS_FOUND = "%s: %d/%d"
  env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

  env.GetBuildInfo = function()
    return "3.3.5", "12340", "Jun 24 2010", 30300
  end

  local cvars = { ["rotateMinimap"] = "0", ["showQuestTrackingTooltips"] = "0" }
  env.GetCVar = function(cvar) return cvars[cvar] or "0" end
  env.SetCVar = function(cvar, val) cvars[cvar] = tostring(val) end

  env.GetQuestDifficultyColor = function(level)
    return { r = 1, g = 1, b = 0 }
  end
  env.StaticPopupDialogs = {}
  _G.StaticPopupDialogs = env.StaticPopupDialogs

  local current_time = 1000.0
  env.GetTime = function() return current_time end
  env.SetTime = function(t) current_time = t end
  env.AdvanceTime = function(dt) current_time = current_time + dt end

  env.GetLocale = function() return "enUS" end
  env.UnitLevel = function(unit) return 1 end
  env.UnitXP = function(unit) return 100 end
  env.UnitRace = function(unit) return "Human", "Human" end
  env.UnitClass = function(unit) return "Warrior", "WARRIOR" end
  env.UnitFactionGroup = function(unit) return "Alliance", "Alliance" end
  env.UnitName = function(unit) return "TestPlayer" end
  env.UnitSex = function(unit) return 2 end

  env.strsub = string.sub
  env.strlen = string.len
  env.strlower = string.lower
  env.strupper = string.upper
  env.strfind = string.find

  env.SecondsToTime = function(sec)
    return string.format("%d min", math.floor(sec / 60))
  end

  env.strsplit = function(delim, str)
    local result = {}
    local pattern = string.format("([^%s]+)", delim)
    for match in string.gmatch(str, pattern) do
      table.insert(result, match)
    end
    return unpack(result)
  end

  -- Frame simulation
  local frameCount = 0
  local function create_mock_frame(fType, name, parent, template)
    frameCount = frameCount + 1
    local f = {
      _type = fType or "Frame",
      _name = name or ("MockFrame_" .. frameCount),
      _parent = parent,
      _shown = true,
      _scripts = {},
      _level = 1,
      _scale = 1,
      _points = {},
      _width = 100,
      _height = 100,
      _text = "",
      _id = 0,
      _enabled = true,
      _checked = false,
      _value = 0,
      _mouseEnabled = true,
      _alpha = 1,
      _textColor = { 1, 1, 1, 1 },
    }

    function f:GetChildren() return end
    function f:IsObjectType(t) return self._type == t end
    function f:GetModel() return nil end
    function f:GetParent() return self._parent end
    function f:SetParent(p) self._parent = p end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:IsVisible() return self._shown end
    function f:SetWidth(w) self._width = w end
    function f:GetWidth() return self._width end
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height end
    function f:SetScale(s) self._scale = s end
    function f:GetScale() return self._scale end
    function f:GetEffectiveScale() return self._scale end
    function f:SetFrameLevel(l) self._level = l end
    function f:GetFrameLevel() return self._level end
    function f:SetFrameStrata() end
    function f:GetFrameStrata() return "MEDIUM" end
    function f:SetID(id) self._id = id end
    function f:GetID() return self._id end
    function f:SetPoint(point, rel, relPoint, x, y)
      table.insert(self._points, { point, rel, relPoint, x, y })
    end
    function f:ClearAllPoints() self._points = {} end
    function f:SetAllPoints() end
    function f:EnableMouse(b) self._mouseEnabled = (b ~= false) end
    function f:IsMouseEnabled() return self._mouseEnabled end
    function f:Enable() self._enabled = true end
    function f:Disable() self._enabled = false end
    function f:IsEnabled() return self._enabled ~= false end
    function f:SetChecked(val)
      if val == nil then
        self._checked = true
      else
        self._checked = (val == true or val == 1 or val == "1")
      end
    end
    function f:GetChecked() return self._checked end
    function f:SetValue(v) self._value = v end
    function f:GetValue() return self._value or 0 end
    function f:SetFontObject() end
    function f:SetTextInsets() end
    function f:SetOrientation() end
    function f:SetMinMaxValues(min, max) self._min = min self._max = max end
    function f:SetValueStep(s) self._step = s end
    function f:SetThumbTexture() end
    function f:GetThumbTexture() return create_mock_frame("Texture") end
    function f:SetAutoFocus() end
    function f:ClearFocus() end
    function f:SetClampedToScreen() end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:SetMovable() end
    function f:SetBackdropBorderColor() end
    function f:SetVerticalScroll(v) self._vscroll = v end
    function f:GetVerticalScroll() return self._vscroll or 0 end
    function f:SetNormalTexture() end
    function f:GetNormalTexture() return nil end
    function f:GetPushedTexture() return nil end
    function f:GetHighlightTexture() return nil end
    function f:SetPushedTexture() end
    function f:SetHighlightTexture() end
    function f:SetTexCoord() end
    function f:SetDesaturated() end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha or 1 end

    function f:SetScript(handler, fn)
      -- Mirror WoW chaining: a second SetScript on the same handler must
      -- not silently drop the first (eventFrame sets OnEvent then OnUpdate).
      local prev = self._scripts[handler]
      if prev and fn then
        self._scripts[handler] = function(...)
          prev(...)
          fn(...)
        end
      else
        self._scripts[handler] = fn
      end
    end
    function f:GetScript(handler)
      return self._scripts[handler]
    end
    function f:HookScript(handler, fn)
      local prev = self._scripts[handler]
      if prev then
        self._scripts[handler] = function(...)
          prev(...)
          fn(...)
        end
      else
        self._scripts[handler] = fn
      end
    end
    function f:FireScript(handler, ...)
      local fn = self._scripts[handler]
      if fn then
        -- In WoW 3.3.5a, OnUpdate/OnEvent passes `this`
        local prevThis = env.this
        env.this = self
        local ok, err = pcall(fn, self, ...)
        env.this = prevThis
        if not ok then error(err) end
      end
    end

    function f:RegisterEvent(event) end
    function f:UnregisterEvent(event) end
    function f:UnregisterAllEvents() end

    function f:CreateFontString(name, layer, inherit)
      return create_mock_frame("FontString", name, self, inherit)
    end
    function f:CreateTexture(name, layer, inherit)
      return create_mock_frame("Texture", name, self, inherit)
    end
    function f:SetFont() end
    function f:SetText(t) self._text = t end
    function f:GetText() return self._text end
    function f:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
    function f:GetTextColor() return unpack(self._textColor or { 1, 1, 1, 1 }) end
    function f:SetJustifyH() end
    function f:SetJustifyV() end
    function f:SetTexture() end
    function f:SetVertexColor() end
    function f:SetZoom() end
    function f:GetZoom() return 0 end
    function f:HighlightText() end

    if name then env[name] = f end
    env.lastCreatedFrame = f
    return f
  end

  env.CreateFrame = create_mock_frame
  env.UIParent = create_mock_frame("Frame", "UIParent")
  env.WorldMapFrame = create_mock_frame("Frame", "WorldMapFrame")
  env.WorldMapButton = create_mock_frame("Frame", "WorldMapButton", env.WorldMapFrame)
  env.WorldMapDetailFrame = create_mock_frame("Frame", "WorldMapDetailFrame", env.WorldMapFrame)
  env.Minimap = create_mock_frame("Frame", "Minimap")
  env.GameTooltip = create_mock_frame("Frame", "GameTooltip")

  env.NUM_CHAT_WINDOWS = 7
  for i = 1, 7 do
    env["ChatFrame" .. i] = create_mock_frame("Frame", "ChatFrame" .. i)
    env["ChatFrame" .. i].AddMessage = function() end
    _G["ChatFrame" .. i] = env["ChatFrame" .. i]
  end
  _G.NUM_CHAT_WINDOWS = 7

  -- Quest Log mock data
  local questLog = {}
  env.SetMockQuestLog = function(log) questLog = log end

  env.GetNumQuestLogEntries = function()
    local headers = 0
    local quests = 0
    for _, q in ipairs(questLog) do
      if q.isHeader then headers = headers + 1 else quests = quests + 1 end
    end
    return #questLog, quests
  end

  env.GetQuestLogTitle = function(index)
    local q = questLog[index]
    if not q then return nil end
    return q.title, q.level or 1, q.tag, q.group, q.isHeader, q.isCollapsed, q.isComplete, q.isDaily
  end

  env.GetNumQuestLeaderBoards = function(index)
    local q = questLog[index]
    if not q or not q.objectives then return 0 end
    return #q.objectives
  end

  env.GetQuestLogLeaderBoard = function(objIndex, questIndex)
    local q = questLog[questIndex]
    if not q or not q.objectives or not q.objectives[objIndex] then return nil end
    local obj = q.objectives[objIndex]
    return obj.text, obj.type, obj.done
  end

  env.IsQuestWatched = function(index)
    local q = questLog[index]
    return q and q.watched or false
  end

  env.GetQuestLink = function(index)
    local q = questLog[index]
    if not q or not q.id then return nil end
    return string.format("|cffffff00|Hquest:%d:1|h[%s]|h|r", q.id, q.title or "Quest")
  end

  env.GetQuestLogSelection = function() return 1 end
  env.SelectQuestLogEntry = function(index) end
  env.GetQuestLogQuestText = function() return "Description", "Objectives text" end

  env.SendAddonMessage = function(prefix, msg, channel, target)
    env.sentAddonMessages = env.sentAddonMessages or {}
    table.insert(env.sentAddonMessages, { prefix = prefix, msg = msg, channel = channel, target = target })
  end

  env.GetPlayerMapPosition = function(unit) return 0.5, 0.5 end
  env.GetRealZoneText = function() return "Elwynn Forest" end
  env.GetSubZoneText = function() return "Northshire Valley" end
  env.GetMapInfo = function() return "Elwynn" end
  env.GetCurrentMapZone = function() return 1 end
  env.GetCurrentMapContinent = function() return 1 end
  env.GetNumSkillLines = function() return 0 end
  env.GetSkillLineInfo = function(index) return nil end

  return env
end

return M
