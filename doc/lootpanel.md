# lootpanel (`lootpanel.lua`)

"What's on this mob" panel (`pfQuestLoot`, alias `pfQuestEpochLoot`).

- `BuildDropsForUnit(unitid)` joins `refloot` data into per-unit
  drop rows; `BuildQuestStarterIndex` maps starter items → quests.
- `GetVisibleDrops` applies the `epochLootPanelShow*` category
  filters (equip, quest items, starters, recipes, grey/white,
  reference data, unknown chance).
- Buttons pooled (`GetButton`), laid out by `LayoutButton`, chance
  formatted by `FormatChance`; row hover shows extended tooltips.
- Draggable panel, close button hides it.

Read-only over `pfDB`; no SavedVars of its own.
