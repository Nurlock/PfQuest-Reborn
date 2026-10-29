# browser (`browser.lua`)

In-game database search window (`pfBrowser`).

- File-top dereferences `pfDB` tables into locals — load order must
  keep `database.lua` first.
- `BrowserSearch` (in database) feeds `RefreshView`/`SelectView`
  tabs (Units/Objects/Items/Quests); result buttons are pooled
  (`ResultButtonCreate`) with hover/click/fav handlers.
- Favorites persist in `pfBrowser_fav` (per character), merged
  fill-missing-only per tab; `favonlogin` restores them on
  `PLAYER_ENTERING_WORLD`.
- `search_limit` (512) and `tooltip_limit` (5) cap cost; shared
  `tooltip_maps` table is cleared and reused to avoid GC churn.

Clicking a result hands the id to map/tracker to show nodes.
