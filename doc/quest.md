# quest (`quest.lua`)

The log-scan loop. `pfQuest` frame listens for `QUEST_LOG_UPDATE`,
`QUEST_WATCH_UPDATE`, `QUEST_FINISHED`, `PLAYER_LEVEL_UP`,
`SKILL_LINES_CHANGED`, `PLAYER_ENTERING_WORLD`, `ADDON_LOADED`.

- Rebuilds `pfQuest.questlog` from the client log (respects
  collapsed headers via `CollapseQuestHeader`/`ExpandQuestHeader`;
  collapse state lives in `pfQuest_config.collapsedQuestIDs` so it
  survives reloads).
- `REMOVE` entries write `pfQuest_history` (`tonumber(entry[2]) or
  entry[2]`) and fire `pfQuestAnnounce`; abandon entries clear it.
- Sets flags for others: `updateQuestGivers`, `updateQuestLog`,
  `pfMap.queue_update`.
- `SortedPairs` helper is shared by journal and tracker.

`QUEST_LOG_UPDATE` fires per kill/loot tick — keep this handler to
flag-setting and let throttled `OnUpdate` passes do the work.
