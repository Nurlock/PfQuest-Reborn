# route (`route.lua`)

Ordering + guidance for active nodes.

- `OnUpdate` on `pfQuest.route`: re-sorts tracked quests (cached
  comparator `sortfuncCached`; mode from `trackerquestsort`:
  `distance` or `level`) and redraws.
- `GetNearest` (greedy nearest-neighbor TSP) chains objective
  coordinates into a walking order.
- `DrawLine(path, …)`: draws segment textures between nodes. Frames
  are hidden, never released — don't add per-tick creation here.
- Arrow (`pfQuest.route.arrow`): target selection, drag position
  saved to `pfQuest_config.arrowpos`, scale via mouse wheel
  (`arrowscale`), text panel + fader. Hidden on taxi, wrong map, or
  `arrow == "0"`.

Gated by `routes` / `routeminimap` config. Skipped entirely when no
coords exist.
