# AGENTS.md — pfQuest-Reborn

WoW 3.3.5a (interface 30300) quest-helper addon. Pure Lua 5.1, runs
in-game; no build step. CI (`release.yml`) gates on `luac5.1 -p` + the
Lua test suite. Keep every change small: this code runs on the game
frame, and every extra line costs runtime + review tokens later.

## Map (read only what you need)

- Load order is `init/addon.xml` top-to-bottom: compat → theme →
  locales → config → slashcmd → database → icons → map → quest →
  route → tracker → browser → lootpanel → nameplates → continent →
  automation → announce → journal → menu → updatenotify → tooltip.
  Order matters: `browser.lua:30-35` derefs `pfDB` at file top, so
  anything moving load order must keep `database.lua` first.
- `db/*.lua` are DATA (units 11k lines, items 8k, objects 7k, quests
  6k). Never read them fully. `grep` for an ID or name instead.
- Logic lives in root `*.lua`: `quest.lua` (log scan loop),
  `tracker.lua` (watch frame), `route.lua` (TSP + line drawing),
  `map.lua` (pins, 2.2k lines), `database.lua` (search/cache, 3k),
  `party.lua` (party sync protocol) + `partytooltip.lua` (tooltip hooks).
- Tests: `lua5.1 tests/run_all_tests.lua` (9 suites). Mocks live in
  `tests/mock_wow_api.lua`.

## Token rules (how to work cheap and stay accurate)

1. `grep` first, `read` slices after. Never open a file over ~500
   lines without a line target.
2. One `grep` beats five reads. Batch independent calls in one block.
3. Never re-read a range you already saw. Quote `file:line` refs.
4. Don't `read` `db/units|items|objects|quests.lua` — `grep` one key.
5. `locales.lua` (1.5k lines) is a key table: `grep` the key, don't
   read the file.
6. Run the test suite after logic changes; paste only failures back.
7. Verify every bug claim against the real file before reporting —
   two candidate "bugs" in the last audit died on re-read (guarded
   lines). No case, no finding.

## Conventions that bite

- Lua 5.1 + WoW 3.3.5a API. Event handlers use implicit global `this`
  and `arg1..argN` — the mock passes varargs as params only, so code
  reading bare `arg1` gets nil under tests. Test event paths through
  the mock's `FireScript`, not by calling internals directly.
- Mock fidelity gaps (don't trust green tests here): `GetChildren()`
  returns nil, no `WorldFrame`, no `GetItemInfo`, map continent/zone
  constants mean `continent.lua` early-returns always.
- SavedVariables: `pfQuest_questcache` (global), per-character
  `pfQuest_config, pfBrowser_fav, pfQuest_history, pfQuest_colors,
  pfQuest_server, pfQuest_track`. Never assign a fresh table to one
  at load (`browser.lua:16` pattern wipes saves on reload) — always
  `x = x or {}` and fill-missing-only.
- Never alias a SavedVar table into transient state
  (`quest.lua:243-244` pattern persists accidents across reloads).
- Quest IDs are mixed number/string keys. Any code doing
  `tonumber(id)` vs raw title must handle both, or history/cache
  rows get poisoned (`tracker.lua:438`, `journal.lua:122`).
- Tooltip text: sanitize markup/length (`SanitizePartyString`
  pattern), use `%s` in formats, guard `cur/tot` division.

## Hot paths — touch with care

- `quest.lua` OnUpdate polls the full quest log every 1s; `tracker`,
  `route`, `map`, `lootpanel`, `nameplates` all run throttled
  OnUpdate loops. Don't add work to these without a throttle, and
  don't create textures/frames per tick (`route.lua DrawLine` already
  leaks this way — hides, never releases).
- `QUEST_LOG_UPDATE` → full quest-DB rescan + party broadcast
  (`party.lua` event frame). Any new consumer of this event
  must debounce or it spams addon chat N-to-N in raids.
- Tooltip hooks (`HookGameTooltip`, `HookPfQuestTooltip`) run per
  tooltip show: no full-log scans, no per-line raid scans — cache or
  hoist.
- Inbound addon comms: validate sender (party/raid membership, not
  self), validate channel, validate schema/length before processing.
  `pfqe` handler today trusts all three — see audit findings 4–6.

## Change checklist

- [ ] `luac5.1 -p` parses; `lua5.1 tests/run_all_tests.lua` green.
- [ ] No new globals (grep `^name =`); no new per-frame allocation.
- [ ] New locale strings added to `locales.lua`, not hardcoded.
- [ ] New SavedVar key merged fill-missing-only, per-char unless
      global is justified.
- [ ] Event-path test added if the logic touches comms, tooltips,
      history, or cache (direct-call tests miss wiring bugs —
      finding 1 proved it).

## Known bugs (from 2026-10 audit, unfixed)

Inbound `REMOVEQ` dropped (see `party.lua` receive path); journal
nil-index crash (`journal.lua:122-123`); nil cached into
`pfQuest_questcache` (`database.lua:2815`); self-echo stored in party
data; no sender/channel check on `pfqe`; update notices skip PARTY
(`updatenotify.lua`). Details in audit findings 1–6.
