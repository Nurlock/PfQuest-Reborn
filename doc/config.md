# config (`config.lua`)

Owns `pfQuest_config` and its window (`pfQuestConfig` frame).

- `pfQuest_defconfig`: default for every option.
- `LoadConfig`: fill-missing-only merge — existing user values win,
  new keys get defaults. Never replaces the table.
- `MigrateHistory`: one-off repairs of `pfQuest_history` from older
  versions (e.g. `{0,0}` placeholder rows).
- `SelectTab` / `CreateConfigEntries`: builds checkbox/slider/text
  rows from the defconfig table; writes go straight to
  `pfQuest_config`, `save` calls `ReloadUI`.
- Wipes all SavedVars only on explicit reset.

Quest IDs in history are normalized with `tonumber(id) or id`
(number when numeric) — every reader/writer must use the same form.
