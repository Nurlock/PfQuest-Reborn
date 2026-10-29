# nameplates (`nameplates.lua`)

Draws slay/loot icons on 3D nameplates (`pfQuestNameplates`).

- `ScanQuestObjectives` maps active quest targets → unit names.
- `ScanWorldFrameChildren` walks `WorldFrame` kids, `IsNameplate`
  filters real plates; `OnNameplateShow/Hide` attach/detach a
  cached icon frame (`GetIconFrame`/`RemoveIconFrame`).
- `StartNameplateWatcher`: a ticker frame with throttled `OnUpdate`
  re-scans; `StopNameplateWatcher` nils the script when disabled.
- Settings cached to locals (`UpdateCachedSettings`: scale, x/y) so
  the scan never reads config per plate.
- Refresh triggers: `QUEST_LOG_UPDATE`, zone changes,
  `PLAYER_ENTERING_WORLD`; gated by `epochnameplatesEnabled`.

Mock gap: `GetChildren()` returns nil under tests, so plate logic
is only partly covered — verify in game.
