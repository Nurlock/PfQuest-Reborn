# map (`map.lua`, ~2.2k lines)

Owns all pins: `pfMap` frame on `WorldFrame`, node store
`pfMap.nodes[addon][map][coord][title]`, plus `titleIndex`.

- `AddNode(meta)` / `DeleteNode(addon, title)` / `GetNodes`: the only
  writers are quest, party sync, and user clicks.
- `ShowTooltip(meta, tooltip)`: per-pin tooltip; checks
  `showtooltips` config.
- Map math: `GetMapID`, `SetMapByID`, `ParentZone`,
  `ToSubmap`/`FromSubmap`, `ShowMapID`.
- Shift-click a pin marks the quest done (`pfQuest_history`, key
  normalized) and flags `pfQuest.updateQuestGivers`.
- `queue_update` timestamp: producers bump it, the draw pass
  consumes it — never redraw synchronously from event handlers.
- Minimap: indoor detection (`indoorwatch` on zone events) and
  square-minimap probing.

Hot path: runs on throttled `OnUpdate`. No per-frame allocations,
no texture creation per tick.
