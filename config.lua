-- multi api compat
local compat = pfQuestCompat
local L = pfQuest_Loc

-- Performance: cache frequently-used globals
local pairs = pairs
local getn = table.getn

pfQuest_history = pfQuest_history or {}
pfQuest_colors = pfQuest_colors or {}
pfQuest_config = pfQuest_config or {}

local reset = {
  config = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the configuration?"]
    dialog.OnAccept = function()
      pfQuest_config = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  history = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the quest history?"]
    dialog.OnAccept = function()
      pfQuest_history = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  cache = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the caches?"]
    dialog.OnAccept = function()
      pfQuest_questcache = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  everything = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset everything?"]
    dialog.OnAccept = function()
      pfQuest_config, pfBrowser_fav, pfQuest_history, pfQuest_colors, pfQuest_server, pfQuest_questcache = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
}

-- default config
pfQuest_defconfig = {
  { -- 1: All Quests; 2: Tracked; 3: Manual; 4: Hide
    config = "trackingmethod",
    text = nil,
    default = 1,
    type = nil,
  },
  {
    config = "trackerquestsort",
    text = nil,
    default = "level",
    type = nil,
  },

  { text = L["General"], default = nil, type = "header" },
  { text = L["Enable World Map Menu"], default = "1", type = "checkbox", config = "worldmapmenu" },
  { text = L["Enable Minimap Button"], default = "1", type = "checkbox", config = "minimapbutton" },
  -- Default the pfQuest tracker OFF when GW2 UI is present -- GW2 UI has its
  -- own quest tracker and the maintainer wants that one used instead. Only a
  -- NEW/never-set value picks this up (existing saved configs keep their
  -- choice), and standalone installs still default it ON.
  { text = L["Enable Quest Tracker"], default = (pfQuestTheme and pfQuestTheme.gw2) and "0" or "1", type = "checkbox", config = "showtracker" },
  { text = L["Enable Quest Log Buttons"], default = "1", type = "checkbox", config = "questlogbuttons" },
  { text = L["Enable Quest Link Support"], default = "1", type = "checkbox", config = "questlinks" },
  { text = L["Show Database IDs"], default = "0", type = "checkbox", config = "showids" },
  { text = L["Draw Favorites On Login"], default = "0", type = "checkbox", config = "favonlogin" },
  { text = L["Minimum Item Drop Chance"], default = "1", type = "text", config = "mindropchance" },
  { text = L["Show Tooltips"], default = "1", type = "checkbox", config = "showtooltips" },
  { text = L["Show Help On Tooltips"], default = "1", type = "checkbox", config = "tooltiphelp" },
  { text = L["Show Level On Quest Tracker"], default = "1", type = "checkbox", config = "trackerlevel" },
  { text = L["Show Level On Quest Log"], default = "0", type = "checkbox", config = "questloglevel" },

  { text = L["Questing"], default = nil, type = "header" },
  { text = L["Quest Tracker Visibility"], default = "0", type = "text", config = "trackeralpha" },
  { text = L["Quest Tracker Font Size"], default = "12", type = "text", config = "trackerfontsize" },
  { text = L["Quest Tracker Max Width"], default = "300", type = "text", config = "trackerwidth" },
  { text = L["Quest Tracker Scale"], default = "1", type = "text", config = "trackerscale" },
  { text = L["Quest Tracker Progress Bars"], default = "1", type = "checkbox", config = "trackerbars" },
  { text = L["Quest Tracker Unfold Objectives"], default = "0", type = "checkbox", config = "trackerexpand" },
  { text = L["Quest Objective Spawn Points (World Map)"], default = "1", type = "checkbox", config = "showspawn" },
  {
    text = L["Quest Objective Spawn Points (Mini Map)"],
    default = "1",
    type = "checkbox",
    config = "showspawnmini",
  },
  { text = L["Quest Objective Icons (World Map)"], default = "1", type = "checkbox", config = "showcluster" },
  { text = L["Quest Objective Icons (Mini Map)"], default = "0", type = "checkbox", config = "showclustermini" },
  { text = L["Display Available Quest Givers"], default = "1", type = "checkbox", config = "allquestgivers" },
  { text = L["Display Current Quest Givers"], default = "1", type = "checkbox", config = "currentquestgivers" },
  { text = L["Display Low Level Quest Givers"], default = "0", type = "checkbox", config = "showlowlevel" },
  { text = L["Display Level+3 Quest Givers"], default = "0", type = "checkbox", config = "showhighlevel" },
  { text = L["Display Event & Daily Quests"], default = "0", type = "checkbox", config = "showfestival" },
  { text = L["Hide PvP & Battleground Quests"], default = "0", type = "checkbox", config = "epochHidePvPQuests" },
  { text = L["Hide Commission Quests"], default = "0", type = "checkbox", config = "epochHideCommissionQuests" },
  { text = L["Hide Coin Quests"], default = "0", type = "checkbox", config = "epochHideCoinQuests" },
  { text = L["Hide Cloth Donation Quests"], default = "0", type = "checkbox", config = "epochHideDonationQuests" },
  { text = L["Hide Chicken Quests"], default = "0", type = "checkbox", config = "epochHideChickenQuests" },
  { text = L["Hide Corrupted Felwood Plant Quests"], default = "0", type = "checkbox", config = "epochHideFelwoodFlowers" },

  { text = L["Map & Minimap"], default = nil, type = "header" },
  { text = L["Enable Minimap Nodes"], default = "1", type = "checkbox", config = "minimapnodes" },
  { text = L["Use Icons For Tracking Nodes"], default = "1", type = "checkbox", config = "trackingicons" },
  { text = L["Use Monochrome Cluster Icons"], default = "0", type = "checkbox", config = "clustermono" },
  { text = L["Use Cut-Out Minimap Node Icons"], default = "1", type = "checkbox", config = "cutoutminimap" },
  { text = L["Use Cut-Out World Map Node Icons"], default = "0", type = "checkbox", config = "cutoutworldmap" },
  { text = L["Color Map Nodes By Spawn"], default = "0", type = "checkbox", config = "spawncolors" },
  { text = L["World Map Node Transparency"], default = "1.0", type = "text", config = "worldmaptransp" },
  { text = L["Minimap Node Transparency"], default = "1.0", type = "text", config = "minimaptransp" },
  { text = L["World Map Node Size"], default = "14", type = "slider", config = "worldmapNodeSize", min = 8, max = 24, step = 1, format = "%dpx" },
  { text = L["Minimap Node Size"], default = "14", type = "slider", config = "minimapNodeSize", min = 8, max = 24, step = 1, format = "%dpx" },
  { text = L["Node Fade Transparency"], default = "0.3", type = "text", config = "nodefade" },
  { text = L["Highlight Nodes On Mouseover"], default = "1", type = "checkbox", config = "mouseover" },

  { text = L["Routes"], default = nil, type = "header" },
  { text = L["Show Route Between Objects"], default = "1", type = "checkbox", config = "routes" },
  { text = L["Include Unified Quest Locations"], default = "1", type = "checkbox", config = "routecluster", parent = "routes" },
  { text = L["Include Quest Enders"], default = "1", type = "checkbox", config = "routeender", parent = "routes" },
  { text = L["Include Quest Starters"], default = "0", type = "checkbox", config = "routestarter", parent = "routes" },
  { text = L["Show Route On Minimap"], default = "0", type = "checkbox", config = "routeminimap", parent = "routes" },
  { text = L["Show Arrow Along Routes"], default = "1", type = "checkbox", config = "arrow", parent = "routes" },
  { text = L["Arrow Scale"], default = "1.0", type = "slider", config = "arrowscale", min = 0.5, max = 3.0, step = 0.1, parent = "arrow" },

  { text = L["Experimental Features"], default = nil, type = "header" },
  { text = L["Enable Experimental Features"], default = "0", type = "checkbox", config = "experimental" },
  { text = L["Enable Questie Group Sync"], default = "1", type = "checkbox", config = "questiegroup", parent = "experimental" },
  { text = L["Show Party Objectives On Map"], default = "1", type = "checkbox", config = "showpartyobjectives", parent = "questiegroup" },
  { text = L["Show Party Progress In Tooltips"], default = "1", type = "checkbox", config = "showpartytooltips", parent = "questiegroup" },
  { text = L["Announce Quest Completion to Party"], default = "1", type = "checkbox", config = "questannounce", parent = "questiegroup" },

  { text = L["Rare Loot Panel"], default = nil, type = "header" },
  { text = L["Include Pooled Loot"], default = "1", type = "checkbox", config = "epochLootPanelShowReference" },
  { text = L["Include Unknown Drop Chance"], default = "0", type = "checkbox", config = "epochLootPanelShowUnknownChance" },
  { text = L["Show Armor & Weapons"], default = "1", type = "checkbox", config = "epochLootPanelShowEquip" },
  { text = L["Show Quest Items"], default = "1", type = "checkbox", config = "epochLootPanelShowQuestItems" },
  { text = L["Show Quest Starters"], default = "1", type = "checkbox", config = "epochLootPanelShowQuestStarters" },
  { text = L["Show Recipe Scrolls"], default = "1", type = "checkbox", config = "epochLootPanelShowRecipes" },
  { text = L["Show Grey Quality Items"], default = "1", type = "checkbox", config = "epochLootPanelShowGrey" },
  { text = L["Show White Quality Items"], default = "1", type = "checkbox", config = "epochLootPanelShowWhite" },

  { text = L["User Data"], default = nil, type = "header" },
  { text = L["Reset Configuration"], default = "1", type = "button", func = reset.config },
  { text = L["Reset Quest History"], default = "1", type = "button", func = reset.history },
  { text = L["Reset Cache"], default = "1", type = "button", func = reset.cache },
  { text = L["Reset Everything"], default = "1", type = "button", func = reset.everything },
}

StaticPopupDialogs["PFQUEST_RESET"] = {
  button1 = YES,
  button2 = NO,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

pfQuestConfig = CreateFrame("Frame", "pfQuestConfig", UIParent)
pfQuestConfig:Hide()
pfQuestConfig:SetWidth(620)
pfQuestConfig:SetHeight(500)
pfQuestConfig:SetPoint("CENTER", 0, 0)
pfQuestConfig:SetFrameStrata("HIGH")
pfQuestConfig:SetMovable(true)
pfQuestConfig:EnableMouse(true)
pfQuestConfig:SetClampedToScreen(true)

pfQuestConfig:SetScript("OnMouseDown", function()
  this:StartMoving()
end)

pfQuestConfig:SetScript("OnMouseUp", function()
  this:StopMovingOrSizing()
end)

pfQuestConfig:SetScript("OnShow", function()
  if not pfQuestConfig.initialized then
    pfQuestConfig.initialized = true
    pfQuestConfig:LoadConfig()
    pfQuestConfig:MigrateHistory()
    pfQuestConfig:CreateConfigEntries(pfQuest_defconfig)
  end
  this:UpdateConfigEntries()
end)

pfQuestConfig.vpos = 40

-- Reforged: route the config window through the shared theme (flat panel +
-- accent header strip) like the browser/journal, instead of the bare pfUI
-- backdrop that left it looking unstyled and near-transparent (QA: the
-- settings window showed the game world through it). Picks up the GW2
-- palette automatically when GW2 UI is installed.
if pfQuestTheme and pfQuestTheme.SkinPanel then
  pfQuestTheme.SkinPanel(pfQuestConfig)
  pfQuestTheme.HeaderStrip(pfQuestConfig, 26)
else
  pfUI.api.CreateBackdrop(pfQuestConfig, nil, true, 0.75)
end
table.insert(UISpecialFrames, "pfQuestConfig")

-- detect current addon path. Reforged: try the REAL folder name first,
-- parsed from this file's load path -- it works for ANY folder name (zip
-- extractors love to append version suffixes); the known-name probe stays
-- as the fallback.
local candidates = {}
local real = debugstack and string.match(debugstack(1) or "", "AddOns\\(.-)\\")
if real then table.insert(candidates, real) end
for _, name in pairs({ "-Reborn", "-Reforged", "", "-master", "-tbc", "-wotlk", "-turtle" }) do
  table.insert(candidates, string.format("pfQuest%s", name))
end
for _, current in pairs(candidates) do
  local _, title = GetAddOnInfo(current)
  if title then
    pfQuestConfig.addonName = current
    pfQuestConfig.path = "Interface\\AddOns\\" .. current
    pfQuestConfig.version = tostring(GetAddOnMetadata(current, "Version"))
    break
  end
end

-- fallback if no matching addon found
if not pfQuestConfig.path then
  pfQuestConfig.path = "Interface\\AddOns\\pfQuest-Reborn"
  pfQuestConfig.addonName = pfQuestConfig.addonName or "pfQuest-Reborn"
  pfQuestConfig.version = "unknown"
end

pfQuestConfig.title = pfQuestConfig:CreateFontString("Status", "LOW", "GameFontNormal")
pfQuestConfig.title:SetFontObject(GameFontWhite)
pfQuestConfig.title:SetPoint("TOP", pfQuestConfig, "TOP", 0, -8)
pfQuestConfig.title:SetJustifyH("LEFT")
pfQuestConfig.title:SetFont(pfUI.font_default, 14)
pfQuestConfig.title:SetText("|cff33ffccpf|rQuest " .. L["Config"])

pfQuestConfig.close = CreateFrame("Button", "pfQuestConfigClose", pfQuestConfig)
pfQuestConfig.close:SetPoint("TOPRIGHT", -5, -5)
pfQuestConfig.close:SetHeight(20)
pfQuestConfig.close:SetWidth(20)
pfQuestConfig.close.texture = pfQuestConfig.close:CreateTexture("pfQuestionDialogCloseTex")
pfQuestConfig.close.texture:SetTexture(pfQuestConfig.path .. "\\compat\\close")
pfQuestConfig.close.texture:ClearAllPoints()
pfQuestConfig.close.texture:SetPoint("TOPLEFT", pfQuestConfig.close, "TOPLEFT", 4, -4)
pfQuestConfig.close.texture:SetPoint("BOTTOMRIGHT", pfQuestConfig.close, "BOTTOMRIGHT", -4, 4)

pfQuestConfig.close.texture:SetVertexColor(1, 0.25, 0.25, 1)
pfUI.api.SkinButton(pfQuestConfig.close, 1, 0.5, 0.5)
pfQuestConfig.close:SetScript("OnClick", function()
  this:GetParent():Hide()
end)

pfQuestConfig.welcome = CreateFrame("Button", "pfQuestConfigWelcome", pfQuestConfig)
pfQuestConfig.welcome:SetWidth(150)
pfQuestConfig.welcome:SetHeight(26)
pfQuestConfig.welcome:SetPoint("BOTTOMLEFT", 10, 10)
pfQuestConfig.welcome:SetScript("OnClick", function()
  pfQuestConfig:Hide()
  pfQuestInit:Show()
end)
pfQuestConfig.welcome.text = pfQuestConfig.welcome:CreateFontString("Caption", "LOW", "GameFontWhite")
pfQuestConfig.welcome.text:SetAllPoints(pfQuestConfig.welcome)
pfQuestConfig.welcome.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuestConfig.welcome.text:SetText(L["Welcome Screen"])
pfUI.api.SkinButton(pfQuestConfig.welcome)

pfQuestConfig.save = CreateFrame("Button", "pfQuestConfigReload", pfQuestConfig)
pfQuestConfig.save:SetWidth(150)
pfQuestConfig.save:SetHeight(26)
pfQuestConfig.save:SetPoint("BOTTOMRIGHT", -10, 10)
pfQuestConfig.save:SetScript("OnClick", ReloadUI)
pfQuestConfig.save.text = pfQuestConfig.save:CreateFontString("Caption", "LOW", "GameFontWhite")
pfQuestConfig.save.text:SetAllPoints(pfQuestConfig.save)
pfQuestConfig.save.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuestConfig.save.text:SetText(L["Save & Close"])
pfUI.api.SkinButton(pfQuestConfig.save)

-- sidebar frame (left navigation for tabs)
pfQuestConfig.sidebar = CreateFrame("Frame", "pfQuestConfigSidebar", pfQuestConfig)
pfQuestConfig.sidebar:SetWidth(150)
pfQuestConfig.sidebar:SetPoint("TOPLEFT", pfQuestConfig, "TOPLEFT", 10, -32)
pfQuestConfig.sidebar:SetPoint("BOTTOMLEFT", pfQuestConfig, "BOTTOMLEFT", 10, 42)
if pfQuestTheme and pfQuestTheme.SkinPanel then
  pfQuestTheme.SkinPanel(pfQuestConfig.sidebar, 0.5)
else
  pfUI.api.CreateBackdrop(pfQuestConfig.sidebar, nil, true, 0.5)
end

-- content frame (right panel for active tab settings)
pfQuestConfig.content = CreateFrame("Frame", "pfQuestConfigContent", pfQuestConfig)
pfQuestConfig.content:SetPoint("TOPLEFT", pfQuestConfig.sidebar, "TOPRIGHT", 8, 0)
pfQuestConfig.content:SetPoint("BOTTOMRIGHT", pfQuestConfig, "BOTTOMRIGHT", -10, 42)
if pfQuestTheme and pfQuestTheme.SkinPanel then
  pfQuestTheme.SkinPanel(pfQuestConfig.content, 0.5)
else
  pfUI.api.CreateBackdrop(pfQuestConfig.content, nil, true, 0.5)
end

pfQuestConfig.contentScroll = pfUI.api.CreateScrollFrame("pfQuestConfigContentScroll", pfQuestConfig.content)
pfQuestConfig.contentScroll:SetPoint("TOPLEFT", pfQuestConfig.content, "TOPLEFT", 4, -4)
pfQuestConfig.contentScroll:SetPoint("BOTTOMRIGHT", pfQuestConfig.content, "BOTTOMRIGHT", -4, 4)
pfQuestConfig.contentChild = pfUI.api.CreateScrollChild("pfQuestConfigContentChild", pfQuestConfig.contentScroll)
pfQuestConfig.contentChild:SetWidth(434)

pfQuestConfig.tabButtons = {}
pfQuestConfig.tabPanels = {}
pfQuestConfig.entryFrames = {}
pfQuestConfig.tabList = {}
pfQuestConfig.selectedTab = nil

function pfQuestConfig:SelectTab(tabKey)
  self.selectedTab = tabKey
  local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }

  for _, tabInfo in ipairs(self.tabList) do
    local btn = self.tabButtons[tabInfo.key]
    local panel = self.tabPanels[tabInfo.key]
    if tabInfo.key == tabKey then
      if btn then
        btn.selected = true
        pfUI.api.SetButtonFontColor(btn, a[1], a[2], a[3], 1)
        if btn.caption then
          btn.caption:SetTextColor(a[1], a[2], a[3], 1)
        end
        local border = btn.backdrop or btn
        if border.SetBackdropBorderColor then
          border:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        end
      end
      if panel then
        panel:Show()
        self.contentChild:SetHeight(math.max(panel.contentHeight or 380, 400))
      end
    else
      if btn then
        btn.selected = false
        pfUI.api.SetButtonFontColor(btn, 0.75, 0.75, 0.75, 0.9)
        if btn.caption then
          btn.caption:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end
        local border = btn.backdrop or btn
        if border.SetBackdropBorderColor then
          border:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)
        end
      end
      if panel then
        panel:Hide()
      end
    end
  end

  if self.contentScroll then
    self.contentScroll:SetVerticalScroll(0)
    if self.contentScroll.UpdateScrollState then
      self.contentScroll:UpdateScrollState()
    end
  end
end

function pfQuestConfig:LoadConfig()
  if not pfQuest_config then
    pfQuest_config = {}
  end
  for id, data in pairs(pfQuest_defconfig) do
    if data.config and not pfQuest_config[data.config] then
      pfQuest_config[data.config] = data.default
    end
  end
end

function pfQuestConfig:MigrateHistory()
  if not pfQuest_history then
    return
  end

  local match = false

  for entry, data in pairs(pfQuest_history) do
    if type(entry) == "string" then
      for id in pairs(pfDatabase:GetIDByName(entry, "quests")) do
        pfQuest_history[id] = { 0, 0 }
        pfQuest_history[entry] = nil
        match = true
      end
    elseif data == true then
      pfQuest_history[entry] = { 0, 0 }
    elseif type(data) == "table" and not data[1] then
      pfQuest_history[entry] = { 0, 0 }
    end
  end

  if match == true then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: " .. L["Quest history migration completed."])
  end
end

local configframes = {}

function pfQuestConfig:CreateConfigEntries(config)
  -- Cleanup any previously created frames
  if self.entryFrames then
    for _, frame in pairs(self.entryFrames) do
      if frame.Hide then frame:Hide() end
      if frame.SetParent then frame:SetParent(nil) end
    end
  end
  if self.tabButtons then
    for _, btn in pairs(self.tabButtons) do
      if btn.Hide then btn:Hide() end
      if btn.SetParent then btn:SetParent(nil) end
    end
  end
  if self.tabPanels then
    for _, pnl in pairs(self.tabPanels) do
      if pnl.Hide then pnl:Hide() end
      if pnl.SetParent then pnl:SetParent(nil) end
    end
  end

  self.entryFrames = {}
  self.tabButtons = {}
  self.tabPanels = {}
  self.tabList = {}
  self.configMap = {}
  configframes = {}

  for _, data in ipairs(config) do
    if data.config then
      self.configMap[data.config] = data
    end
  end

  -- Parse config items into tabs
  local currentTabKey = nil
  local tabOrder = {}
  local tabMap = {}

  for _, data in ipairs(config) do
    if data.type == "header" then
      local raw = data.tab or data.text
      local clean = string.gsub(raw, "|c%x%x%x%x%x%x%x%x", "")
      clean = string.gsub(clean, "|r", "")
      clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")

      currentTabKey = clean
      if not tabMap[currentTabKey] then
        local tabInfo = { key = currentTabKey, title = data.text, cleanTitle = clean, entries = {} }
        tabMap[currentTabKey] = tabInfo
        table.insert(tabOrder, tabInfo)
      end
    elseif data.type then
      local targetKey = data.tab or currentTabKey
      if not targetKey then
        targetKey = "General"
        if not tabMap[targetKey] then
          local tabInfo = { key = targetKey, title = targetKey, cleanTitle = targetKey, entries = {} }
          tabMap[targetKey] = tabInfo
          table.insert(tabOrder, tabInfo)
        end
      end
      if tabMap[targetKey] then
        table.insert(tabMap[targetKey].entries, data)
      end
    end
  end

  self.tabList = tabOrder

  -- Build tab buttons directly in sidebar
  local tabBtnHeight = 26
  local tabBtnSpacing = 3
  local startY = -6

  for i, tabInfo in ipairs(tabOrder) do
    local btn = CreateFrame("Button", "pfQuestConfigTab" .. i, self.sidebar)
    btn:SetHeight(tabBtnHeight)
    btn:SetPoint("TOPLEFT", self.sidebar, "TOPLEFT", 5, startY - (i - 1) * (tabBtnHeight + tabBtnSpacing))
    btn:SetPoint("TOPRIGHT", self.sidebar, "TOPRIGHT", -5, startY - (i - 1) * (tabBtnHeight + tabBtnSpacing))

    pfUI.api.SkinButton(btn)

    btn.caption = btn:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    btn.caption:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.caption:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.caption:SetJustifyH("LEFT")
    btn.caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
    btn.caption:SetText(tabInfo.cleanTitle)

    local key = tabInfo.key
    btn:SetScript("OnClick", function()
      self:SelectTab(key)
    end)

    local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }
    local origLeave = btn:GetScript("OnLeave")
    btn:SetScript("OnLeave", function()
      if origLeave then origLeave() end
      if btn.selected then
        local border = btn.backdrop or btn
        if border.SetBackdropBorderColor then
          border:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        end
        if btn.caption then
          btn.caption:SetTextColor(a[1], a[2], a[3], 1)
        end
      end
    end)

    self.tabButtons[key] = btn
  end

  -- Build tab content panels
  local count = 1
  local rowHeight = 24
  local rowSpacing = 2
  local panelWidth = 430
  local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }

  for _, tabInfo in ipairs(tabOrder) do
    local panel = CreateFrame("Frame", nil, self.contentChild)
    panel:SetPoint("TOPLEFT", self.contentChild, "TOPLEFT", 0, 0)
    panel:SetWidth(panelWidth)
    panel:Hide()

    local header = panel:CreateFontString(nil, "LOW", "GameFontWhite")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    header:SetFont(pfUI.font_default, pfUI_config.global.font_size + 2, "OUTLINE")
    header:SetText(tabInfo.title)
    header:SetTextColor(a[1], a[2], a[3], 1)

    local div = panel:CreateTexture(nil, "BORDER")
    div:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -26)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -26)
    div:SetHeight(1)
    div:SetTexture(a[1], a[2], a[3], 0.35)

    local currentY = -34

    for _, data in ipairs(tabInfo.entries) do
      local frame = CreateFrame("Frame", "pfQuestConfig" .. count, panel)
      frame:SetWidth(panelWidth - 20)
      frame:SetHeight(rowHeight)
      frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, currentY)
      frame.data = data

      configframes[data.text] = frame
      if data.config then
        configframes[data.config] = frame
      end
      table.insert(self.entryFrames, frame)

      local indent = 5
      if data.parent then
        local p = self.configMap and self.configMap[data.parent]
        if p and p.parent then
          indent = 24
        else
          indent = 14
        end
      end

      frame.caption = frame:CreateFontString("Status", "LOW", "GameFontWhite")
      frame.caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      frame.caption:SetPoint("LEFT", indent, 0)
      frame.caption:SetPoint("RIGHT", -120, 0)
      frame.caption:SetJustifyH("LEFT")
      frame.caption:SetText(data.text)

      if data.type == "checkbox" then
        frame.input = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        frame.input:SetNormalTexture("")
        frame.input:SetPushedTexture("")
        frame.input:SetHighlightTexture("")
        pfUI.api.CreateBackdrop(frame.input, nil, true)
        frame.input:SetWidth(16)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -10, 0)
        frame.input.config = data.config
        if pfQuest_config[data.config] == "1" then
          frame.input:SetChecked()
        end
        frame.input:SetScript("OnClick", function()
          if frame.enabled == false then
            this:SetChecked(pfQuest_config[this.config] == "1")
            return
          end
          if this:GetChecked() then
            pfQuest_config[this.config] = "1"
          else
            pfQuest_config[this.config] = "0"
          end
          pfQuest:ResetAll()
          pfQuestConfig:UpdateDependencies()
        end)
      elseif data.type == "text" then
        frame.input = CreateFrame("EditBox", nil, frame)
        frame.input:SetTextColor(a[1], a[2], a[3], 1)
        frame.input:SetJustifyH("RIGHT")
        frame.input:SetTextInsets(5, 5, 5, 5)
        frame.input:SetWidth(36)
        frame.input:SetHeight(18)
        frame.input:SetPoint("RIGHT", -10, 0)
        frame.input:SetFontObject(GameFontNormal)
        frame.input:SetAutoFocus(false)
        frame.input:SetScript("OnEscapePressed", function()
          this:ClearFocus()
        end)
        frame.input.config = data.config
        frame.input:SetText(pfQuest_config[data.config] or data.default or "")
        frame.input:SetScript("OnTextChanged", function()
          if frame.enabled == false then return end
          pfQuest_config[this.config] = this:GetText()
        end)
        pfUI.api.CreateBackdrop(frame.input, nil, true)
      elseif data.type == "slider" then
        local minval = data.min
        local maxval = data.max
        local config = data.config
        local default = data.default
        local step = data.step or 0.1
        local fmt = data.format or "%.1fx"

        frame.input = CreateFrame("Slider", nil, frame)
        frame.input:SetOrientation("HORIZONTAL")
        frame.input:SetWidth(70)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -10, 0)
        frame.input:EnableMouse(true)
        frame.input:SetMinMaxValues(minval, maxval)
        frame.input:SetValueStep(step)
        frame.input:SetThumbTexture("Interface\\BUTTONS\\WHITE8X8")
        frame.input.thumb = frame.input:GetThumbTexture()
        frame.input.thumb:SetHeight(14)
        frame.input.thumb:SetWidth(8)
        frame.input.thumb:SetTexture(0.3, 1, 0.8, 0.5)
        pfUI.api.CreateBackdrop(frame.input, nil, true)

        frame.input.config = config

        frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.value:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
        frame.value:SetPoint("RIGHT", frame.input, "LEFT", -6, 0)
        frame.value:SetTextColor(a[1], a[2], a[3], 1)

        local val = tonumber(pfQuest_config[config]) or tonumber(default) or 1
        frame.input:SetValue(val)
        frame.value:SetText(string.format(fmt, val))

        frame.input.updating = false
        frame.input:SetScript("OnValueChanged", function()
          if frame.enabled == false then return end
          if this.updating then return end
          this.updating = true

          local val = this:GetValue()
          val = max(minval, min(maxval, val))
          val = floor(val / step + 0.5) * step

          this:SetValue(val)
          pfQuest_config[this.config] = tostring(val)
          frame.value:SetText(string.format(fmt, val))

          if pfQuest and pfQuest.route and pfQuest.route.arrow then
            pfQuest.route.arrow:ApplyScale()
          end
          if pfMap and pfMap.ResizeNodes then
            pfMap:ResizeNodes()
          end

          this.updating = false
        end)
      elseif data.type == "button" and data.func then
        frame.input = CreateFrame("Button", nil, frame)
        frame.input:SetWidth(44)
        frame.input:SetHeight(20)
        frame.input:SetPoint("RIGHT", -10, 0)
        frame.input:SetScript("OnClick", function()
          if frame.enabled == false then return end
          if data.func then data.func() end
        end)
        frame.input.text = frame.input:CreateFontString("Caption", "LOW", "GameFontWhite")
        frame.input.text:SetAllPoints(frame.input)
        frame.input.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
        frame.input.text:SetText("OK")
        pfUI.api.SkinButton(frame.input)
      end

      if frame.input and pfUI.api.emulated and data.type ~= "slider" then
        frame.input:SetWidth(frame.input:GetWidth() / 0.6)
        frame.input:SetHeight(frame.input:GetHeight() / 0.6)
        frame.input:SetScale(0.8)
        if frame.input.SetTextInsets then
          frame.input:SetTextInsets(8, 8, 8, 8)
        end
      end

      count = count + 1
      currentY = currentY - (rowHeight + rowSpacing)
    end

    panel.contentHeight = math.abs(currentY) + 15
    panel:SetHeight(panel.contentHeight)
    self.tabPanels[tabInfo.key] = panel
  end

  local defaultTab = (self.selectedTab and tabMap[self.selectedTab] and self.selectedTab) or (tabOrder[1] and tabOrder[1].key)
  if defaultTab then
    self:SelectTab(defaultTab)
  end

  self:UpdateDependencies()
end

function pfQuestConfig:IsEntryActive(data)
  if not data or not data.parent then
    return true
  end
  local parentKey = data.parent
  local parentData = self.configMap and self.configMap[parentKey]
  if parentData and not self:IsEntryActive(parentData) then
    return false
  end
  local val = pfQuest_config and pfQuest_config[parentKey]
  if val == nil and parentData then
    val = parentData.default
  end
  return val == "1"
end

function pfQuestConfig:SetEntryEnabled(frame, enabled)
  frame.enabled = enabled
  local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }

  if frame.caption then
    if enabled then
      frame.caption:SetTextColor(1, 1, 1, 1)
      if frame.caption.SetAlpha then frame.caption:SetAlpha(1.0) end
    else
      frame.caption:SetTextColor(0.5, 0.5, 0.5, 1)
      if frame.caption.SetAlpha then frame.caption:SetAlpha(0.6) end
    end
  end

  if frame.input then
    if enabled then
      if frame.input.Enable then frame.input:Enable() end
      if frame.input.EnableMouse then frame.input:EnableMouse(true) end
      if frame.input.SetAlpha then frame.input:SetAlpha(1.0) end
      if frame.data and frame.data.type == "text" and frame.input.SetTextColor then
        frame.input:SetTextColor(a[1], a[2], a[3], 1)
      end
    else
      if frame.input.Disable then frame.input:Disable() end
      if frame.input.EnableMouse then frame.input:EnableMouse(false) end
      if frame.input.ClearFocus then frame.input:ClearFocus() end
      if frame.input.SetAlpha then frame.input:SetAlpha(0.35) end
      if frame.data and frame.data.type == "text" and frame.input.SetTextColor then
        frame.input:SetTextColor(0.5, 0.5, 0.5, 1)
      end
    end
  end

  if frame.value then
    if enabled then
      frame.value:SetTextColor(a[1], a[2], a[3], 1)
    else
      frame.value:SetTextColor(0.5, 0.5, 0.5, 1)
    end
  end
end

function pfQuestConfig:UpdateDependencies()
  if not self.entryFrames then return end
  for _, frame in ipairs(self.entryFrames) do
    if frame.data then
      local active = self:IsEntryActive(frame.data)
      self:SetEntryEnabled(frame, active)
    end
  end
end

function pfQuestConfig:Rebuild()
  self:CreateConfigEntries(pfQuest_defconfig)
end

function pfQuestConfig:UpdateConfigEntries()
  for _, data in pairs(pfQuest_defconfig) do
    if data.type and (configframes[data.text] or (data.config and configframes[data.config])) then
      local frame = configframes[data.text] or configframes[data.config]
      if frame and frame.input then
        if data.type == "checkbox" then
          frame.input:SetChecked((pfQuest_config[data.config] == "1" and true or nil))
        elseif data.type == "text" then
          frame.input:SetText(pfQuest_config[data.config] or "")
        elseif data.type == "slider" then
          local newval = tonumber(pfQuest_config[data.config]) or tonumber(data.default) or 1
          local step = data.step or 0.1
          newval = floor(newval / step + 0.5) * step
          local oldval = frame.input:GetValue()
          if oldval ~= newval then
            frame.input:SetValue(newval)
          end
          if frame.value then
            local fmt = data.format or "%.1fx"
            frame.value:SetText(string.format(fmt, newval))
          end
        end
      end
    end
  end
  self:UpdateDependencies()
end

-- Register ADDON_LOADED event handler after all methods are defined
-- This ensures LoadConfig, MigrateHistory, CreateConfigEntries exist when called
pfQuestConfig:RegisterEvent("ADDON_LOADED")
pfQuestConfig:SetScript("OnEvent", function()
  -- Reforged: prefix-match the addon folder name. The old equality list
  -- (pfQuest/-tbc/-wotlk) silently skipped ALL of this init for any other
  -- install folder -- the canonical pfQuest-Reforged folder loaded with no
  -- config defaults, no settings entries and a nil pfQuest_track (QA: empty
  -- config window, dead arrow, menu.lua crash on fresh installs). The
  -- Match only the core addon's ADDON_LOADED event, not child database modules
  local mainAddon = pfQuestConfig.addonName or "pfQuest-Reborn"
  if not pfQuestConfig.initialized and (arg1 == mainAddon or not arg1) then
    pfQuestConfig.initialized = true

    -- Detect whether this is truly a fresh first-run before defaults are populated
    local isFresh = (not pfQuest_config) or (next(pfQuest_config) == nil)
    pfQuestConfig.isFirstRun = isFresh

    pfQuestConfig:LoadConfig()
    pfQuestConfig:MigrateHistory()
    pfQuestConfig:CreateConfigEntries(pfQuest_defconfig)

    -- If existing settings were present, mark welcome as done to prevent wizard popups on /reload
    if not isFresh and not pfQuest_config["welcome"] then
      pfQuest_config["welcome"] = "1"
    end

    pfQuest_questcache = pfQuest_questcache or {}
    pfQuest_history = pfQuest_history or {}
    pfQuest_colors = pfQuest_colors or {}
    pfQuest_config = pfQuest_config or {}
    pfQuest_track = pfQuest_track or {}
    pfBrowser_fav = pfBrowser_fav or { ["units"] = {}, ["objects"] = {}, ["items"] = {}, ["quests"] = {} }

    -- clear quest history on new characters
    if UnitXP("player") == 0 and UnitLevel("player") == 1 then
      pfQuest_history = {}
    end

    if pfBrowserIcon and pfQuest_config["minimapbutton"] == "0" then
      pfBrowserIcon:Hide()
    end

    if pfQuest and pfQuest.route and pfQuest.route.arrow then
      pfQuest.route.arrow:ApplyScale()
    end
  end
end)

do -- welcome/init popup dialog
  local config_stage = {
    arrow = 1,
    mode = 2,
    query = 1,
  }

  local desaturate = function(texture, state)
    if not texture then return end
    local supported = texture.SetDesaturated and texture:SetDesaturated(state)
    if not supported then
      if state then
        texture:SetVertexColor(0.5, 0.5, 0.5)
      else
        texture:SetVertexColor(1.0, 1.0, 1.0)
      end
    end
  end

  -- create welcome/init window
  pfQuestInit = CreateFrame("Frame", "pfQuestInit", UIParent)
  pfQuestInit:Hide()
  pfQuestInit:SetWidth(420)
  pfQuestInit:SetHeight(310)
  pfQuestInit:SetMovable(true)
  pfQuestInit:EnableMouse(true)
  pfQuestInit:SetPoint("CENTER", 0, 0)
  pfQuestInit:RegisterEvent("PLAYER_ENTERING_WORLD")
  table.insert(UISpecialFrames, "pfQuestInit")

  pfQuestInit:SetScript("OnMouseDown", function()
    this:StartMoving()
  end)

  pfQuestInit:SetScript("OnMouseUp", function()
    this:StopMovingOrSizing()
  end)

  pfQuestInit:SetScript("OnHide", function()
    if pfQuest_config then
      pfQuest_config["welcome"] = "1"
    end
  end)

  pfQuestInit:SetScript("OnEvent", function()
    -- Only show wizard on genuine first run, never on subsequent /reload or logins
    if pfQuest_config and pfQuest_config.welcome ~= "1" and pfQuestConfig.isFirstRun then
      -- parse current config
      if pfQuest_config["showspawn"] == "0" and pfQuest_config["showcluster"] == "1" then
        config_stage.mode = 1
      elseif pfQuest_config["showspawn"] == "1" and pfQuest_config["showcluster"] == "0" then
        config_stage.mode = 3
      end

      if pfQuest_config["arrow"] == "0" then
        config_stage.arrow = nil
      end

      pfQuestInit:Show()
    else
      if pfQuest_config then
        pfQuest_config["welcome"] = "1"
      end
    end
    this:UnregisterAllEvents()
  end)

  pfQuestInit:SetScript("OnShow", function()
    -- reload ui elements
    if pfQuestInit[1] and pfQuestInit[1].bg then desaturate(pfQuestInit[1].bg, true) end
    if pfQuestInit[2] and pfQuestInit[2].bg then desaturate(pfQuestInit[2].bg, true) end
    if pfQuestInit[3] and pfQuestInit[3].bg then desaturate(pfQuestInit[3].bg, true) end
    if pfQuestInit[config_stage.mode] and pfQuestInit[config_stage.mode].bg then
      desaturate(pfQuestInit[config_stage.mode].bg, false)
    end
    if pfQuestInit.checkbox then
      pfQuestInit.checkbox:SetChecked(config_stage.arrow)
    end
    if pfQuestInit.querybox then
      pfQuestInit.querybox:SetChecked(config_stage.query)
    end
  end)

  if pfQuestTheme and pfQuestTheme.SkinPanel then
    pfQuestTheme.SkinPanel(pfQuestInit)
    pfQuestTheme.HeaderStrip(pfQuestInit, 26)
  else
    pfUI.api.CreateBackdrop(pfQuestInit, nil, true, 0.85)
  end

  -- close button
  pfQuestInit.close = CreateFrame("Button", "pfQuestInitClose", pfQuestInit)
  pfQuestInit.close:SetPoint("TOPRIGHT", -5, -5)
  pfQuestInit.close:SetHeight(20)
  pfQuestInit.close:SetWidth(20)
  pfQuestInit.close.texture = pfQuestInit.close:CreateTexture("pfQuestInitCloseTex")
  pfQuestInit.close.texture:SetTexture(pfQuestConfig.path .. "\\compat\\close")
  pfQuestInit.close.texture:ClearAllPoints()
  pfQuestInit.close.texture:SetPoint("TOPLEFT", pfQuestInit.close, "TOPLEFT", 4, -4)
  pfQuestInit.close.texture:SetPoint("BOTTOMRIGHT", pfQuestInit.close, "BOTTOMRIGHT", -4, 4)
  pfQuestInit.close.texture:SetVertexColor(1, 0.25, 0.25, 1)
  pfUI.api.SkinButton(pfQuestInit.close, 1, 0.5, 0.5)
  pfQuestInit.close:SetScript("OnClick", function()
    if pfQuest_config then
      pfQuest_config["welcome"] = "1"
    end
    this:GetParent():Hide()
  end)

  -- welcome title
  pfQuestInit.title = pfQuestInit:CreateFontString("pfQuestInitTitle", "OVERLAY", "GameFontWhite")
  pfQuestInit.title:SetPoint("TOP", pfQuestInit, "TOP", 0, -8)
  pfQuestInit.title:SetJustifyH("CENTER")
  pfQuestInit.title:SetFont(pfUI.font_default, 12, "OUTLINE")
  pfQuestInit.title:SetText(L["Please select your preferred |cff33ffccpf|cffffffffQuest|r mode:"])

  -- questing mode
  local buttons = {
    {
      caption = L["Simple Markers"],
      texture = "\\img\\init\\simple",
      position = { "TOPLEFT", 15, -38 },
      tooltip = L["Only show cluster icons with summarized objective locations based on spawn points"],
    },
    {
      caption = L["Combined"],
      texture = "\\img\\init\\combined",
      position = { "TOP", 0, -38 },
      tooltip = L["Show cluster icons with summarized locations and also display all spawn points of each quest objective"],
    },
    {
      caption = L["Spawn Points"],
      texture = "\\img\\init\\spawns",
      position = { "TOPRIGHT", -15, -38 },
      tooltip = L["Display all spawn points of each quest objective and hide summarized cluster icons."],
    },
  }

  local buttonNames = { "pfQuestInitSimple", "pfQuestInitCombined", "pfQuestInitSpawns" }
  for i, button in ipairs(buttons) do
    pfQuestInit[i] = CreateFrame("Button", buttonNames[i], pfQuestInit)
    pfQuestInit[i]:SetWidth(120)
    pfQuestInit[i]:SetHeight(160)
    pfQuestInit[i]:SetPoint(unpack(button.position))
    pfQuestInit[i]:SetID(i)

    pfQuestInit[i].bg = pfQuestInit[i]:CreateTexture(nil, "ARTWORK")
    pfQuestInit[i].bg:SetWidth(120)
    pfQuestInit[i].bg:SetHeight(150)
    pfQuestInit[i].bg:SetPoint("CENTER", 0, 0)
    pfQuestInit[i].bg:SetTexture(pfQuestConfig.path .. button.texture)

    pfQuestInit[i].caption = pfQuestInit[i]:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    pfQuestInit[i].caption:SetPoint("TOP", pfQuestInit[i], "BOTTOM", 0, -6)
    pfQuestInit[i].caption:SetJustifyH("CENTER")
    pfQuestInit[i].caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
    pfQuestInit[i].caption:SetText(button.caption)

    pfUI.api.SkinButton(pfQuestInit[i])

    pfQuestInit[i]:SetScript("OnClick", function()
      desaturate(pfQuestInit[1].bg, true)
      desaturate(pfQuestInit[2].bg, true)
      desaturate(pfQuestInit[3].bg, true)
      desaturate(pfQuestInit[this:GetID()].bg, false)
      config_stage.mode = this:GetID()
    end)

    local OnEnter = pfQuestInit[i]:GetScript("OnEnter")
    pfQuestInit[i]:SetScript("OnEnter", function()
      if OnEnter then
        OnEnter()
      end
      GameTooltip_SetDefaultAnchor(GameTooltip, this)

      GameTooltip:SetText(this.caption:GetText())
      GameTooltip:AddLine(buttons[this:GetID()].tooltip, 1, 1, 1, true)
      GameTooltip:SetWidth(160)
      GameTooltip:Show()
    end)

    local OnLeave = pfQuestInit[i]:GetScript("OnLeave")
    pfQuestInit[i]:SetScript("OnLeave", function()
      if OnLeave then
        OnLeave()
      end
      GameTooltip:Hide()
    end)
  end

  -- show arrows
  pfQuestInit.checkbox = CreateFrame("CheckButton", "pfQuestInitArrowBox", pfQuestInit, "UICheckButtonTemplate")
  pfQuestInit.checkbox:SetPoint("BOTTOMLEFT", 15, 36)
  pfQuestInit.checkbox:SetNormalTexture("")
  pfQuestInit.checkbox:SetPushedTexture("")
  pfQuestInit.checkbox:SetHighlightTexture("")
  pfQuestInit.checkbox:SetWidth(20)
  pfQuestInit.checkbox:SetHeight(20)
  pfUI.api.CreateBackdrop(pfQuestInit.checkbox, nil, true)

  pfQuestInit.checkbox.caption = pfQuestInit.checkbox:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestInit.checkbox.caption:SetPoint("LEFT", pfQuestInit.checkbox, "RIGHT", 5, 0)
  pfQuestInit.checkbox.caption:SetJustifyH("LEFT")
  pfQuestInit.checkbox.caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
  pfQuestInit.checkbox.caption:SetText(L["Show Navigation Arrow"])
  pfQuestInit.checkbox:SetScript("OnClick", function()
    config_stage.arrow = this:GetChecked()
  end)

  pfQuestInit.checkbox:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    GameTooltip:SetText(L["Navigation Arrow"])
    GameTooltip:AddLine(L["Show navigation arrow that points you to the nearest quest location."], 1, 1, 1, true)
    GameTooltip:SetWidth(160)
    GameTooltip:Show()
  end)

  pfQuestInit.checkbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- query completed quests checkbox
  pfQuestInit.querybox = CreateFrame("CheckButton", "pfQuestInitQueryBox", pfQuestInit, "UICheckButtonTemplate")
  pfQuestInit.querybox:SetPoint("BOTTOMLEFT", 15, 10)
  pfQuestInit.querybox:SetNormalTexture("")
  pfQuestInit.querybox:SetPushedTexture("")
  pfQuestInit.querybox:SetHighlightTexture("")
  pfQuestInit.querybox:SetWidth(20)
  pfQuestInit.querybox:SetHeight(20)
  pfUI.api.CreateBackdrop(pfQuestInit.querybox, nil, true)

  pfQuestInit.querybox.caption = pfQuestInit.querybox:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestInit.querybox.caption:SetPoint("LEFT", pfQuestInit.querybox, "RIGHT", 5, 0)
  pfQuestInit.querybox.caption:SetJustifyH("LEFT")
  pfQuestInit.querybox.caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
  pfQuestInit.querybox.caption:SetText(L["Query Server for Completed Quests (/db query)"])
  pfQuestInit.querybox:SetScript("OnClick", function()
    config_stage.query = this:GetChecked()
  end)

  pfQuestInit.querybox:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    GameTooltip:SetText(L["Query Completed Quests"])
    GameTooltip:AddLine(L["Queries the server for quests your character has already completed (/db query). Highly recommended so finished quests are hidden from your map."], 1, 1, 1, true)
    GameTooltip:SetWidth(260)
    GameTooltip:Show()
  end)

  pfQuestInit.querybox:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- save button
  pfQuestInit.save = CreateFrame("Button", "pfQuestInitSave", pfQuestInit)
  pfQuestInit.save:SetWidth(100)
  pfQuestInit.save:SetHeight(24)
  pfQuestInit.save:SetPoint("BOTTOMRIGHT", -15, 10)
  pfQuestInit.save.text = pfQuestInit.save:CreateFontString("Caption", "LOW", "GameFontWhite")
  pfQuestInit.save.text:SetAllPoints(pfQuestInit.save)
  pfQuestInit.save.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
  pfQuestInit.save.text:SetText(L["Save & Close"])

  pfUI.api.SkinButton(pfQuestInit.save)

  pfQuestInit.save:SetScript("OnClick", function()
    -- write current config
    if config_stage.mode == 1 then
      pfQuest_config["showspawn"] = "0"
      pfQuest_config["showspawnmini"] = "0"
      pfQuest_config["showcluster"] = "1"
      pfQuest_config["showclustermini"] = "1"
    elseif config_stage.mode == 2 then
      pfQuest_config["showspawn"] = "1"
      pfQuest_config["showspawnmini"] = "1"
      pfQuest_config["showcluster"] = "1"
      pfQuest_config["showclustermini"] = "0"
    elseif config_stage.mode == 3 then
      pfQuest_config["showspawn"] = "1"
      pfQuest_config["showspawnmini"] = "1"
      pfQuest_config["showcluster"] = "0"
      pfQuest_config["showclustermini"] = "0"
    end

    if config_stage.arrow then
      pfQuest_config["arrow"] = "1"
    else
      pfQuest_config["arrow"] = "0"
    end

    -- save welcome flag
    pfQuest_config["welcome"] = "1"
    pfQuest:ResetAll()
    pfQuestInit:Hide()

    -- Run server query if requested
    if config_stage.query and pfDatabase and pfDatabase.QueryServer then
      pfDatabase:QueryServer()
    end
  end)
end
