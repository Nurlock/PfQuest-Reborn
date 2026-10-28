# pfQuest-Reborn — component docs

WoW 3.3.5a quest-helper addon. Pure Lua 5.1, no build step.

## Load order (`init/addon.xml`, top to bottom)

`compat` → `theme` → `locales` → `config` → `slashcmd` → `database` →
`icons` → `map` → `quest` → `route` → `tracker` → `browser` →
`lootpanel` → `nameplates` → `continent` → `automation` → `announce` →
`journal` → `menu` → `updatenotify` → `party` → `tooltip`.

Order matters: `browser.lua` dereferences `pfDB` at file top, so
`database.lua` must load first.

## Data flow (the three loops)

1. **Log scan** — `QUEST_LOG_UPDATE` → `quest.lua` rebuilds
   `pfQuest.questlog`, writes completions to `pfQuest_history`.
2. **Pins** — `questlog` changes set `pfMap.queue_update`; `map.lua`
   resolves objectives through `database.lua` into nodes; `route.lua`
   orders them and draws lines + arrow.
3. **Party sync** — `QUEST_LOG_UPDATE` (debounced) broadcasts `pfqe`
   messages; inbound updates land in `partyQuestData` and become
   `PARTY` map nodes + tooltip lines.

## SavedVariables (`.toc`)

- Global: `pfQuest_questcache`
- Per-character: `pfQuest_config`, `pfBrowser_fav`, `pfQuest_history`,
  `pfQuest_colors`, `pfQuest_server`, `pfQuest_track`

Rule: merge fill-missing-only (`x = x or {}`), never assign a fresh
table at load. Never alias a SavedVar table into transient state.

## Files

| Doc | Component |
| --- | --------- |
| `compat.md` | API shims (`compat/`) |
| `theme.md` | Frame skinning |
| `locales.md` | Localization table |
| `config.md` | Defaults + options window |
| `slashcmd.md` | `/db` commands |
| `database.md` | DB search + quest matching |
| `icons.md` | Custom node icons |
| `map.md` | Pins + map utils |
| `quest.md` | Quest-log scan loop |
| `route.md` | Ordering + lines + arrow |
| `tracker.md` | Watch-frame tracker |
| `browser.md` | DB search window |
| `lootpanel.md` | Drop preview panel |
| `nameplates.md` | Objective icons on nameplates |
| `continent.md` | Continent-view pins |
| `automation.md` | Auto accept / turn-in |
| `announce.md` | Progress chat messages |
| `journal.md` | Completion history window |
| `menu.md` | Minimap button + menu |
| `updatenotify.md` | Version broadcast |
| `tooltip-sync.md` | Party sync protocol |
| `tooltip.md` | Tooltip rendering (unit, pin, extended) |
| `data.md` | `db/` data tables |
