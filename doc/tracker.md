# tracker (`tracker.lua`)

The on-screen watch list (`pfQuestMapTracker` frame).

- `OnUpdate`: throttled refresh of buttons, distances
  (`UpdateQuestDistances`, `RefreshNearestDistances`), alpha fade.
- Buttons: per-quest rows with icon/bg textures created once and
  reused; `ButtonEnter/Leave/Click`, hover tooltips, sort button
  toggling `trackerquestsort` level/distance.
- Click a non-log quest node marks it done in `pfQuest_history`
  (normalized key) with a `UIErrorsFrame` confirmation.
- Position/visibility persist via `trackerpos`, `showtracker`,
  `lock`, `trackerfontsize`.

Runs every frame — keep the tick to counter updates, never table
rebuilds or texture creation.
