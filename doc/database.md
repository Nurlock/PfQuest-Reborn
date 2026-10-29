# database (`database.lua`, ~3k lines)

Read/query layer over the static `pfDB` tables. Two globals:
`pfDB` (data) and `pfDatabase` (methods).

- Indexes: `BuildNameIndex` (title → ids), `BuildStaticRejectSet`;
  `pfDatabase.tracking` frame refreshes them on
  `PLAYER_ENTERING_WORLD`.
- Quest matching: log title + level + objective text are fuzzy-matched
  with bounded Levenshtein (`lev`) against `pfDB.quests.loc`;
  results cached in `pfQuest_questcache` keyed by
  `title:level:objective:text`. Empty-table entries are valid
  negative cache (hit check is key existence, not `[1]`).
- Search: `BrowserSearch(query, type)` for items/quests/objects/units
  (numeric query → ID lookup, else name); `GetIDByName`,
  `GetIDByIDPart`, `SearchMobID`, `SearchAreaTriggerID`.
- Helpers: `ShowExtendedTooltip`, difficulty colors, race/class bit
  masks, `GetQuestsCompleted` reconciliation (writes completions to
  `pfQuest_history` with normalized keys).
- `itemlist` frame scans bags on `BAG_UPDATE` via throttled
  `OnUpdate`.

Never read `db/*.lua` fully — `grep` one key instead.
