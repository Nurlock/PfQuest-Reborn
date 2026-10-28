-- pfQuest Reborn: Continent & Dungeon Map Markers
-- Projects zone quest nodes, flight paths, and utility NPCs onto the Continent Map view

local L = pfQuest_Loc or setmetatable({}, { __index = function(_, k) return k end })

local continentPins = {}
local maxContinentPins = 1500

-- WorldMapArea.dbc coordinates format: {width, height, left, top} in world coordinates
local mapData = {
  -- Eastern Kingdoms zones (instance 0)
  [1429] = {3470.84, 2314.62, 1535.42, -7939.58},     -- Elwynn Forest
  [1436] = {3500.00, 2333.30, 3016.67, -9400.00},     -- Westfall
  [1433] = {2170.84, 1447.90, -1570.83, -8575.00},    -- Redridge Mountains
  [1431] = {2700.00, 1800.03, 833.333, -9716.67},     -- Duskwood
  [1434] = {6381.25, 4254.10, 2220.83, -11168.80},    -- Stranglethorn Vale
  [1453] = {1737.50, 1158.34, 1722.92, -7995.83},     -- Stormwind City
  [1426] = {4925.00, 3283.34, 1802.08, -3877.08},     -- Dun Morogh
  [1455] = {790.63,  527.61,  -713.59, -4569.24},     -- Ironforge
  [1432] = {2758.33, 1839.58, -1993.75, -4487.50},    -- Loch Modan
  [1437] = {4135.42, 2756.25, -389.58, -2147.92},     -- Wetlands
  [1424] = {3200.00, 2133.33, 1066.67, 400.00},       -- Hillsbrad Foothills
  [1416] = {2800.00, 1866.67, 783.33,  1500.00},      -- Alterac Mountains
  [1417] = {3600.00, 2400.00, -866.67, -133.33},      -- Arathi Highlands
  [1425] = {3850.00, 2566.67, -1575.0, 1466.67},      -- The Hinterlands
  [1420] = {4518.75, 3012.50, 3033.33, 3837.50},      -- Tirisfal Glades
  [1421] = {4200.00, 2800.00, 3450.00, 1666.67},      -- Silverpine Forest
  [1458] = {959.38,  640.10,  873.19,  1877.94},      -- Undercity
  [1422] = {4300.00, 2866.67, 416.67,  3366.67},      -- Western Plaguelands
  [1423] = {4031.25, 2687.50, -2287.5, 3704.17},      -- Eastern Plaguelands
  [1418] = {2487.50, 1658.34, -2079.17, -5889.58},    -- Badlands
  [1427] = {2231.25, 1487.50, -322.92, -6100.00},     -- Searing Gorge
  [1428] = {2929.16, 1952.08, -266.67, -7031.25},     -- Burning Steppes
  [1435] = {2293.75, 1529.17, -2222.92, -9620.83},    -- Swamp of Sorrows
  [1419] = {3350.00, 2233.30, -1241.67, -10566.70},   -- Blasted Lands
  [1430] = {2500.00, 1666.63, -833.33, -9866.67},     -- Deadwind Pass

  -- Kalimdor zones (instance 1)
  [1438] = {5091.66, 3393.70, 3814.58, 11831.20},     -- Teldrassil (zone 141)
  [1457] = {1058.33, 705.71,  2938.36, 10238.30},     -- Darnassus (zone 1657)
  [1439] = {6550.00, 4366.66, 2941.67, 8333.33},      -- Darkshore (zone 148)
  [1440] = {5766.67, 3843.75, 1700.00, 4672.92},      -- Ashenvale (zone 331)
  [1442] = {4883.33, 3256.25, 3245.83, 2916.67},      -- Stonetalon Mountains (zone 406)
  [1413] = {10133.34, 6756.25, 2622.92, 1612.50},     -- The Barrens (zone 17)
  [1411] = {5287.50, 3525.00, -1962.50, 1808.33},     -- Durotar (zone 14)
  [1454] = {1402.61, 935.42,  -3680.60, 2273.88},     -- Orgrimmar (zone 1637)
  [1412] = {5137.50, 3425.00, 2047.92, -272.92},      -- Mulgore (zone 215)
  [1456] = {1043.75, 695.83,  516.67,  -850.00},      -- Thunder Bluff (zone 1638)
  [1443] = {4495.83, 2997.91, 4233.33, 452.08},       -- Desolace (zone 405)
  [1444] = {6950.00, 4633.33, 5441.67, -2366.67},     -- Feralas (zone 357)
  [1441] = {4400.00, 2933.33, -433.33, -3966.67},     -- Thousand Needles (zone 400)
  [1446] = {6900.00, 4600.00, -218.75, -5875.00},     -- Tanaris (zone 440)
  [1449] = {3700.00, 2466.66, 533.33,  -5966.67},     -- Un'Goro Crater (zone 490)
  [1451] = {3483.33, 2322.92, 2537.50, -5958.33},     -- Silithus (zone 1377)
  [1445] = {5250.00, 3500.00, -975.00, -2033.33},     -- Dustwallow Marsh (zone 15)
  [1452] = {7100.00, 4733.33, -316.67, 8533.33},      -- Winterspring (zone 618)
  [1447] = {5070.84, 3381.25, -3277.08, 5341.67},     -- Azshara (zone 16)
  [1448] = {5750.00, 3833.33, 1641.67, 7133.33},      -- Felwood (zone 361)
  [1450] = {2308.33, 1539.59, -1381.25, 8491.67},     -- Moonglade (zone 493)

  -- Continents
  [1415] = {40741.18, 27149.69, 18171.97, 11176.34}, -- Eastern Kingdoms continent
  [1414] = {36799.81, 24533.20, 17066.60, 12799.90}, -- Kalimdor continent
}

local zoneToUiMapID = {
  -- Eastern Kingdoms
  [12] = 1429, [40] = 1436, [44] = 1433, [10] = 1431, [33] = 1434,
  [1519] = 1453, [1] = 1426, [1537] = 1455, [38] = 1432, [11] = 1437,
  [267] = 1424, [36] = 1416, [45] = 1417, [47] = 1425, [85] = 1420,
  [130] = 1421, [1497] = 1458, [28] = 1422, [139] = 1423, [3] = 1418,
  [51] = 1427, [46] = 1428, [8] = 1435, [4] = 1419, [41] = 1430,

  -- Kalimdor
  [141] = 1438, [1657] = 1457, [148] = 1439, [331] = 1440, [406] = 1442,
  [17] = 1413, [14] = 1411, [1637] = 1454, [215] = 1412, [1638] = 1456,
  [405] = 1443, [357] = 1444, [400] = 1441, [440] = 1446, [490] = 1449,
  [1377] = 1451, [15] = 1445, [618] = 1452, [16] = 1447, [361] = 1448,
  [493] = 1450,
}

local zoneContinent = {
  -- Eastern Kingdoms = 2 (in WoW API continent 2 is Eastern Kingdoms)
  [1] = 2, [3] = 2, [4] = 2, [8] = 2, [10] = 2, [11] = 2, [12] = 2,
  [28] = 2, [33] = 2, [36] = 2, [38] = 2, [40] = 2, [41] = 2, [44] = 2,
  [45] = 2, [46] = 2, [47] = 2, [51] = 2, [85] = 2, [130] = 2, [139] = 2,
  [267] = 2, [1497] = 2, [1519] = 2, [1537] = 2,

  -- Kalimdor = 1
  [14] = 1, [15] = 1, [16] = 1, [17] = 1, [141] = 1, [148] = 1, [215] = 1,
  [331] = 1, [357] = 1, [361] = 1, [400] = 1, [405] = 1, [406] = 1, [440] = 1,
  [490] = 1, [493] = 1, [618] = 1, [1377] = 1, [1637] = 1, [1638] = 1, [1657] = 1,
}

local function ZoneToWorld(x, y, zoneID)
  local uiMapID = zoneToUiMapID[zoneID]
  if not uiMapID then return nil, nil end
  local data = mapData[uiMapID]
  if not data then return nil, nil end

  local worldX = data[3] - data[1] * (x / 100)
  local worldY = data[4] - data[2] * (y / 100)
  return worldX, worldY
end

local function WorldToContinent(worldX, worldY, continent)
  local contData = mapData[continent == 1 and 1414 or 1415]
  if not contData then return nil, nil end

  local x = (contData[3] - worldX) / contData[1]
  local y = (contData[4] - worldY) / contData[2]
  return x, y
end

pfQuestContinent = {
  ZoneToWorld = ZoneToWorld,
  WorldToContinent = WorldToContinent,
  mapData = mapData,
  zoneToUiMapID = zoneToUiMapID,
  zoneContinent = zoneContinent,
}

local function ResizeContinentNode(frame)
  local invScale = pfMap and pfMap.mainmap_inversescale or 1.0
  if not frame.icon then
    frame.defsize = tonumber(pfQuest_config["continentNodeSize"]) or 12
    frame.defsize = frame.defsize * invScale
  else
    frame.defsize = tonumber(pfQuest_config["continentUtilityNodeSize"]) or 14
    frame.defsize = (frame.defsize - 2) * invScale + 2
  end
  frame:SetWidth(frame.defsize)
  frame:SetHeight(frame.defsize)
  if frame.hl then
    frame.hl:SetWidth(frame.defsize)
    frame.hl:SetHeight(frame.defsize)
  end
end

local function CreateContinentPin(index)
  if not continentPins[index] then
    local pin = CreateFrame("Button", "pfQuestContinentPin" .. index, WorldMapButton)
    pin.isContinentPin = true
    pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 10)
    if pin.SetFrameStrata then pin:SetFrameStrata("DIALOG") end

    pin.tex = pin:CreateTexture(nil, "BACKGROUND")
    pin.tex:SetAllPoints(pin)

    pin.pic = pin:CreateTexture(nil, "BORDER")
    pin.pic:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    pin.pic:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)

    pin.hl = pin:CreateTexture(nil, "OVERLAY")
    pin.hl:SetTexture((pfQuestConfig and pfQuestConfig.path or "Interface\\AddOns\\pfQuest-Reborn") .. "\\img\\track")
    pin.hl:SetPoint("TOPLEFT", pin, "TOPLEFT", -5, 5)
    pin.hl:Hide()

    pin.defalpha = 1
    pin.dt = 0

    pin:EnableMouse(true)
    if pin.RegisterForClicks then pin:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    pin:SetScript("OnEnter", function(self)
      if self.node and pfMap and pfMap.NodeEnter then
        pfMap.NodeEnter(self)
      end
    end)

    pin:SetScript("OnLeave", function(self)
      if pfMap and pfMap.NodeLeave then
        pfMap.NodeLeave(self)
      end
    end)

    pin:SetScript("OnClick", function(self, button)
      if self.node and pfMap and pfMap.NodeClick then
        pfMap.NodeClick(self, button)
      end
    end)

    continentPins[index] = pin
  end
  return continentPins[index]
end

-- Observe (never replace) map's update pipeline through the sanctioned seam.
-- The continent body below runs unchanged after every map update.
local function UpdateContinentPins()
    if not GetCurrentMapContinent or not GetCurrentMapZone then
      return
    end

    local continent = GetCurrentMapContinent()
    local zone = GetCurrentMapZone()

    for i = 1, maxContinentPins do
      if continentPins[i] then
        continentPins[i]:Hide()
        continentPins[i].node = nil
      end
    end

    if pfQuest_config and pfQuest_config["epochContinentPins"] == "0" then
      return
    end

    if zone > 0 then
      return
    end

    if IsInInstance and IsInInstance() then
      return
    end

    local pinCount = 0
    local targetContinents = (continent == 0) and { 1, 2 } or { continent }

    for _, targetContinent in ipairs(targetContinents) do
      for addon, addonData in pairs(pfMap.nodes or {}) do
        for zID, zoneNodes in pairs(addonData) do
          local zoneCont = zoneContinent[zID]
          if zoneCont == targetContinent then
            local uiMapID = zoneToUiMapID[zID]
            if uiMapID and mapData[uiMapID] then
              for coords, node in pairs(zoneNodes) do
                local _, _, strx, stry = string.find(coords, "(.*)|(.*)")
                local zoneX = tonumber(strx)
                local zoneY = tonumber(stry)

                if zoneX and zoneY then
                  local worldX, worldY = ZoneToWorld(zoneX, zoneY, zID)
                  if worldX and worldY then
                    local contX, contY = WorldToContinent(worldX, worldY, targetContinent)
                    if contX and contY and contX >= 0 and contX <= 1 and contY >= 0 and contY <= 1 then
                      local mapX, mapY = contX, contY
                      if continent == 0 then
                        if targetContinent == 1 then
                          mapX = contX * 0.90 - 0.22
                          mapY = contY * 0.85 + 0.05
                        else
                          mapX = 0.33 + (contX * 0.90)
                          mapY = contY * 0.90 - 0.04
                        end
                      end

                      if mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
                        pinCount = pinCount + 1
                        if pinCount > maxContinentPins then break end

                        local pin = CreateContinentPin(pinCount)
                        pin.node = node
                        pfMap:UpdateNode(pin, node, nil, nil, nil)
                        ResizeContinentNode(pin)

                        pin:ClearAllPoints()
                        local wmWidth = WorldMapButton:GetWidth()
                        local wmHeight = WorldMapButton:GetHeight()
                        pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", mapX * wmWidth, -mapY * wmHeight)
                        pin:Show()
                      end
                    end
                  end
                end
              end
            end
          end
          if pinCount >= maxContinentPins then break end
        end
        if pinCount >= maxContinentPins then break end
      end
      if pinCount >= maxContinentPins then break end
    end
  end

if pfMap and pfMap.AddUpdateHook then
  pfMap:AddUpdateHook(function(kind, frame, node, color, obj)
    if kind == "node" then
      if obj ~= "minimap" and frame and frame.isContinentPin then
        ResizeContinentNode(frame)
      end
    elseif kind == "nodes" then
      UpdateContinentPins()
    end
  end)
end
