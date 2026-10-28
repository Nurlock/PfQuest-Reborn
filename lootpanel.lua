-- pfQuest Reborn: Interactive Rare / Boss NPC Loot Panel
-- Displays drop probabilities and category filters on Alt-click of rare/boss pins

local GRID_COLUMNS = 6
local ICON_SIZE = 26
local ICON_PADDING = 6
local PANEL_MARGIN = 8
local MAX_ICONS = 18
local MIN_CONTENT_WIDTH = 120
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local L = pfQuest_Loc or setmetatable({}, { __index = function(_, k) return k end })
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

local RANK_INFO = {
  ["1"] = { text = "Elite",      r = 1, g = 0.5,  b = 0 },
  ["2"] = { text = "Rare Elite", r = 1, g = 0.42, b = 0.71 },
  ["3"] = { text = "Boss",       r = 1, g = 0,    b = 0 },
  ["4"] = { text = "Rare",       r = 1, g = 1,    b = 0 },
}

local unitDropsCache = {}

local function BuildDropsForUnit(unitid)
  local cached = unitDropsCache[unitid]
  if cached then return cached end

  local items = pfDB and pfDB["items"] and pfDB["items"]["data"]
  local refloot = pfDB and pfDB["refloot"] and pfDB["refloot"]["data"]
  local list = {}

  if items then
    for itemid, item in pairs(items) do
      if item["U"] and item["U"][unitid] then
        table.insert(list, { item = itemid, chance = item["U"][unitid] or 0, isRef = false })
      elseif item["R"] and refloot then
        for ref, chance in pairs(item["R"]) do
          local refdata = refloot[ref]
          if refdata and refdata["U"] and refdata["U"][unitid] then
            table.insert(list, { item = itemid, chance = chance or 0, isRef = true })
            break
          end
        end
      end
    end
  end

  table.sort(list, function(a, b) return a.chance > b.chance end)
  unitDropsCache[unitid] = list
  return list
end

local questStarterItems = {}
local questStarterIndexBuilt = false

local function BuildQuestStarterIndex()
  if questStarterIndexBuilt then return end
  questStarterIndexBuilt = true

  local quests = pfDB and pfDB["quests"] and pfDB["quests"]["data"]
  if quests then
    for _, quest in pairs(quests) do
      if quest["start"] and quest["start"]["I"] then
        for _, itemid in pairs(quest["start"]["I"]) do
          questStarterItems[itemid] = true
        end
      end
    end
  end
end

local function PassesCategoryFilters(itemid)
  BuildQuestStarterIndex()

  local showEquip = not pfQuest_config or pfQuest_config["epochLootPanelShowEquip"] ~= "0"
  local showQuestItems = not pfQuest_config or pfQuest_config["epochLootPanelShowQuestItems"] ~= "0"
  local showQuestStarters = not pfQuest_config or pfQuest_config["epochLootPanelShowQuestStarters"] ~= "0"
  local showRecipes = not pfQuest_config or pfQuest_config["epochLootPanelShowRecipes"] ~= "0"
  local showGrey = not pfQuest_config or pfQuest_config["epochLootPanelShowGrey"] ~= "0"
  local showWhite = not pfQuest_config or pfQuest_config["epochLootPanelShowWhite"] ~= "0"

  local _, _, quality, _, _, itemType = GetItemInfo(itemid)
  local isEquip = itemType == "Armor" or itemType == "Weapon"

  if isEquip then return showEquip end
  if questStarterItems[itemid] then return showQuestStarters end
  if itemType == "Quest" then return showQuestItems end
  if itemType == "Recipe" then return showRecipes end
  if quality == 0 then return showGrey end
  if quality == 1 then return showWhite end

  return true
end

local function GetVisibleDrops(unitid)
  local drops = BuildDropsForUnit(unitid)
  if not drops then return nil end

  local showReference = pfQuest_config and pfQuest_config["epochLootPanelShowReference"] == "1"
  local showUnknownChance = pfQuest_config and pfQuest_config["epochLootPanelShowUnknownChance"] == "1"

  local visible = {}
  for _, drop in ipairs(drops) do
    local passesRef = showReference or not drop.isRef
    local passesChance = showUnknownChance or (drop.chance and drop.chance > 0)
    if passesRef and passesChance and PassesCategoryFilters(drop.item) then
      table.insert(visible, drop)
    end
  end
  return visible
end

local panel = CreateFrame("Frame", "pfQuestLootPanel", UIParent)
panel:SetFrameStrata("TOOLTIP")
panel:SetFrameLevel(200)
if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
panel:Hide()

if panel.SetMovable then panel:SetMovable(true) end
if panel.EnableMouse then panel:EnableMouse(true) end
if panel.RegisterForDrag then
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
end

if pfQuestTheme and pfQuestTheme.SkinPanel then
  pfQuestTheme.SkinPanel(panel, 0.95)
elseif panel.SetBackdrop then
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  panel:SetBackdropColor(0, 0, 0, 0.9)
  panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

local closeButton = CreateFrame("Button", nil, panel)
closeButton:SetWidth(14)
closeButton:SetHeight(14)
closeButton:SetPoint("TOPRIGHT", -4, -4)
closeButton:SetFrameLevel(panel:GetFrameLevel() + 10)
closeButton.text = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
closeButton.text:SetPoint("CENTER")
closeButton.text:SetText("x")
closeButton.text:SetTextColor(0.8, 0.3, 0.3)
closeButton:SetScript("OnEnter", function() closeButton.text:SetTextColor(1, 1, 1) end)
closeButton:SetScript("OnLeave", function() closeButton.text:SetTextColor(0.8, 0.3, 0.3) end)
closeButton:SetScript("OnClick", function() pfQuestLoot.Hide() end)

panel.header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_MARGIN, -PANEL_MARGIN)
panel.header:SetJustifyH("LEFT")
panel.header:Hide()

panel.noItems = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.noItems:SetJustifyH("LEFT")
panel.noItems:SetText(L["No items linked to this NPC"] or "No items linked to this NPC")
panel.noItems:Hide()

local function FormatChance(chance)
  if chance <= 0 or chance >= 1 then
    return string.format("%.0f%%", chance)
  end

  local oneDecimal = string.format("%.1f%%", chance)
  if oneDecimal == "0.0%" then
    return string.format("%.2f%%", chance)
  end

  return oneDecimal
end

local buttonPool = {}

local function GetButton(index)
  local button = buttonPool[index]
  if button then return button end

  button = CreateFrame("Button", nil, panel)
  button:SetWidth(ICON_SIZE)
  button:SetHeight(ICON_SIZE)

  button.border = button:CreateTexture(nil, "BACKGROUND")
  button.border:SetPoint("TOPLEFT", -1, 1)
  button.border:SetPoint("BOTTOMRIGHT", 1, -1)
  button.border:SetTexture(1, 1, 1, 1)

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints(button)

  button.chanceText = button:CreateFontString(nil, "OVERLAY")
  button.chanceText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
  button.chanceText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
  button.chanceText:SetTextColor(1, 1, 0)

  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  button:SetScript("OnEnter", function()
    if not button.itemid then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    local name = GetItemInfo(button.itemid)
    local linkOk = name and pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. button.itemid .. (pfQuestCompat and pfQuestCompat.itemsuffix or ""))

    if not linkOk then
      local itemLoc = pfDB and pfDB["items"] and (pfDB["items"]["loc"] or pfDB["items"]["enUS"])
      local localName = itemLoc and itemLoc[button.itemid]
      GameTooltip:SetText(name or ((localName and localName ~= "") and localName or ("Item #" .. button.itemid)), 1, 1, 1)
      if not name then
        GameTooltip:AddLine("Item data unavailable", 0.6, 0.6, 0.6)
      end
    end

    if button.chance and button.chance > 0 then
      GameTooltip:AddLine("Drop chance: " .. FormatChance(button.chance), 0.6, 0.9, 1)
    end

    GameTooltip:SetFrameLevel(panel:GetFrameLevel() + 10)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  buttonPool[index] = button
  return button
end

local function LayoutButton(button, index, topOffset)
  local col = (index - 1) - floor((index - 1) / GRID_COLUMNS) * GRID_COLUMNS
  local row = floor((index - 1) / GRID_COLUMNS)
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", panel, "TOPLEFT",
    PANEL_MARGIN + col * (ICON_SIZE + ICON_PADDING),
    -topOffset - row * (ICON_SIZE + ICON_PADDING))
  button:SetFrameLevel(panel:GetFrameLevel() + 1)
end

local function RankText(unitData)
  local info = unitData and unitData["rnk"] and RANK_INFO[tostring(unitData["rnk"])]
  if not info then return nil end
  return string.format("Rank: |cff%02x%02x%02x%s|r", info.r * 255, info.g * 255, info.b * 255, info.text)
end

pfQuestLoot = {}
pfQuestEpochLoot = pfQuestLoot

local pinned = false
local pinnedUnitId = nil

function pfQuestLoot.Hide()
  pinned = false
  pinnedUnitId = nil
  panel:Hide()
end

local function ApplyItemVisuals(button, itemid)
  local _, _, quality = GetItemInfo(itemid)
  button.icon:SetTexture(GetItemIcon(itemid) or FALLBACK_ICON)

  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local c = ITEM_QUALITY_COLORS[quality]
    button.border:SetVertexColor(c.r, c.g, c.b, 1)
    return true
  end

  button.border:SetVertexColor(0.4, 0.4, 0.4, 1)
  return false
end

local function PopulateGrid(unitid, topOffset)
  local drops = GetVisibleDrops(unitid)
  local count = drops and min(table.getn(drops), MAX_ICONS) or 0

  for i = 1, count do
    local drop = drops[i]
    local button = GetButton(i)

    button.itemid = drop.item
    button.chance = drop.chance

    if drop.chance and drop.chance > 0 then
      local text = FormatChance(drop.chance)
      button.chanceText:SetText(text)
      button.chanceText:SetFont("Fonts\\FRIZQT__.TTF", string.len(text) >= 5 and 7 or 9, "OUTLINE")
      button.chanceText:Show()
    else
      button.chanceText:Hide()
    end

    if ApplyItemVisuals(button, drop.item) then
      button.pendingQualityItem = nil
    else
      button.pendingQualityItem = drop.item
    end

    LayoutButton(button, i, topOffset)
    button:Show()
  end

  for i = count + 1, table.getn(buttonPool) do
    buttonPool[i]:Hide()
  end

  if count == 0 then
    return false, 0, 0
  end

  local columns = min(count, GRID_COLUMNS)
  local rows = ceil(count / GRID_COLUMNS)
  local width = PANEL_MARGIN * 2 + columns * ICON_SIZE + (columns - 1) * ICON_PADDING
  local gridHeight = rows * ICON_SIZE + (rows - 1) * ICON_PADDING
  return true, width, gridHeight
end

function pfQuestLoot.HasDrops(unitid)
  local drops = unitid and GetVisibleDrops(unitid)
  return drops ~= nil and table.getn(drops) > 0
end

function pfQuestLoot.ShowPinned(nodeFrame)
  local unitid = nodeFrame and (nodeFrame.spawnid or nodeFrame.id)
  if not unitid then return end

  if pinned and pinnedUnitId == unitid then
    pfQuestLoot.Hide()
    return
  end

  local unitData = pfDB and pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitid]
  if not unitData or not unitData["rnk"] then return end

  local unitLoc = pfDB and pfDB["units"] and (pfDB["units"]["loc"] or pfDB["units"]["enUS"])
  local mobName = (nodeFrame.spawn or (unitLoc and unitLoc[unitid]) or UNKNOWN)

  local headerLines = {
    "|cff4dffcc" .. mobName .. "|r",
    (pfQuest_Loc["Level"] or "Level") .. ": " .. (nodeFrame.level or unitData.lvl or UNKNOWN),
    (pfQuest_Loc["Type"] or "Type") .. ": " .. (nodeFrame.spawntype or pfQuest_Loc["Monster"] or "Monster"),
  }

  local rankText = RankText(unitData)
  if rankText then table.insert(headerLines, rankText) end

  if nodeFrame.respawn then
    table.insert(headerLines, (pfQuest_Loc["Respawn"] or "Respawn") .. ": " .. nodeFrame.respawn)
  end

  local drops = GetVisibleDrops(unitid)
  local dropCount = drops and min(table.getn(drops), MAX_ICONS) or 0
  local columns = min(dropCount, GRID_COLUMNS)
  local gridContentWidth = columns > 0 and (columns * ICON_SIZE + (columns - 1) * ICON_PADDING) or 0
  local contentWidth = max(gridContentWidth, MIN_CONTENT_WIDTH)

  panel.header:SetWidth(contentWidth)
  panel.header:SetText(table.concat(headerLines, "\n"))
  panel.header:Show()

  local headerHeight = panel.header:GetHeight() + 10
  local ok, _, gridHeight = PopulateGrid(unitid, headerHeight)

  local noItemsHeight = 0
  if ok then
    panel.noItems:Hide()
  else
    panel.noItems:ClearAllPoints()
    panel.noItems:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_MARGIN, -headerHeight)
    panel.noItems:SetWidth(contentWidth)
    panel.noItems:Show()
    noItemsHeight = panel.noItems:GetHeight()
  end

  pinned = true
  pinnedUnitId = unitid

  panel:SetWidth(contentWidth + PANEL_MARGIN * 2)
  panel:SetHeight(headerHeight + PANEL_MARGIN + (ok and gridHeight or noItemsHeight))

  panel:ClearAllPoints()
  if nodeFrame.GetLeft and nodeFrame:GetLeft() then
    panel:SetPoint("TOPLEFT", nodeFrame, "BOTTOMLEFT", 0, -6)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end

  panel:Show()
end

local pendingQualityElapsed = 0
panel:SetScript("OnUpdate", function(self, elapsed)
  pendingQualityElapsed = pendingQualityElapsed + (elapsed or 0)
  if pendingQualityElapsed < 0.5 then return end
  pendingQualityElapsed = 0

  for i = 1, table.getn(buttonPool) do
    local button = buttonPool[i]
    if button and button:IsShown() and button.pendingQualityItem then
      if ApplyItemVisuals(button, button.pendingQualityItem) then
        button.pendingQualityItem = nil
      end
    end
  end
end)

local mapWatcher = CreateFrame("Frame")
mapWatcher:RegisterEvent("WORLD_MAP_UPDATE")
mapWatcher:SetScript("OnEvent", pfQuestLoot.Hide)

if WorldMapFrame and WorldMapFrame.HookScript then
  WorldMapFrame:HookScript("OnHide", pfQuestLoot.Hide)
  WorldMapFrame:HookScript("OnHide", function() unitDropsCache = {} end)
end
