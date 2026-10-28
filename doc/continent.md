# continent (`continent.lua`)

Pins for the continent (multi-zone) view (`pfQuestContinent`).

- `ZoneToWorld` / `WorldToContinent`: coordinate conversion between
  zone space and continent space; `ParentZone`/`GetSubmap` resolve
  which sub-map a node belongs to.
- `CreateContinentPin`: pooled pins sized by
  `continentNodeSize` / `continentUtilityNodeSize`
  (`ResizeContinentNode`); hover shows quest info, click drills
  into the zone map.
- Gated by `epochContinentPins`. In tests the map
  continent/zone constants make this module early-return — covered
  by mock only, verify in game.
