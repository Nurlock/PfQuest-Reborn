# tooltips (`pfQuest-tooltip.lua` hooks, `database.lua`, `map.lua`)

Everything the player actually sees on hover. Three render sites,
one shared rule: build lines from cached tables, never scan the
quest log or raid per tooltip show.

## Unit tooltips (`HookGameTooltip`)

- Hooks `GameTooltip:OnTooltipSetUnit`. Skips players
  (`UnitIsPlayer`), empty units, and everything unless grouped with
  `showpartytooltips` on.
- Groups `partyQuestData[sender][unitName]` rows by quest, dedupes
  same player + objective, then appends: `[!]` quest header plus one
  line per member — class-colored name, objective text, `(cur/tot)`.
- Progress bar color is a red→yellow→green ramp on `current/total`
  (guarded by `IsValidProgress` at ingest, so no div-by-zero).
- Data shown is already sanitized at ingest (`SanitizePartyString`).

## Pin tooltips (`HookPfQuestTooltip` wrapping `pfMap:ShowTooltip`)

- Wraps the map pin tooltip: after the default node lines, appends
  your own log progress for that quest (objectives via
  `GetQuestLogLeaderBoards`) and any party rows for the same target.
- No-ops (`return false`) when `pfMap` or `pfQuestCompat` isn't
  loaded yet — pins still draw, just without extras.

## Extended DB tooltips (`pfDatabase:ShowExtendedTooltip`)

- Static info for browser/journal hover: quest description,
  requirements, rewards. Pure `pfDB` reads, capped line count.

Cost rule for all three: per-show work is proportional to lines
shown. Anything O(n) over the log or group belongs in the sync
layer (`tooltip-sync.md`), not here.
