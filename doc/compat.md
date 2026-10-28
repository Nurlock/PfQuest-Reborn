# compat (`compat/pfUI.lua`, `compat/client.lua`)

API shim loaded first so every other file can assume one API.

- `pfUI.lua`: re-exports/bridges the bits borrowed from the pfUI
  addon (split helpers, UI utilities).
- `client.lua`: normalizes client differences — quest-log accessors
  (`GetQuestLogTitle` wrapper), difficulty colors
  (`GetDifficultyColor`), and other 3.3.5a API surface used by later
  files.

No frames, no events, no SavedVars. Pure functions + `pfQuestCompat`
table. If a Blizzard API behaves differently than expected, fix it
here, not at call sites.
