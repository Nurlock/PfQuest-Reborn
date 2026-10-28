# journal (`journal.lua`)

Completion-history window (`pfJournal`, opens on `dirty` flag via
throttled `OnUpdate`).

- `ReloadJournal`: groups `pfQuest_history` rows by day column
  (`date("%A, %B %d (%Y)")`, `UNKNOWN` for `{0,0}` placeholders);
  skips rows that aren't `{number timestamp, ...}` so one corrupt
  entry can't kill the window.
- `UpdateEntry`: per-row render — column header vs quest row (name
  from `pfDB.quests.loc`, time, level); hides rows with no history.
- `OnEnter`: extended tooltip + "Completed Level" line (history key
  normalized with `tonumber(id) or id` everywhere).
- `RemoveOnClick`: deletes the history row and reloads the view.
- Scroll/offset: mouse wheel + click-to-reload; max 24 columns.

Reads `pfQuest_history` only; writes only on explicit remove.
