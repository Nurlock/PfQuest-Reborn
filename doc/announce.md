# announce (`announce.lua`)

Chat announcements for your own progress: `pfQuestAnnounce`.

- Frame listens for `UI_INFO_MESSAGE` (objective updates).
- `AnnounceQuest`: on turn-in/accept prints quest state; objective
  pings resolve names via `GetQuestNameForObjective` and item ids
  via `GetItemIdForObjective`.
- Flags: `questannounce` master, `epochannounceFinished`,
  `epochannounceRemaining`, `epochannounceShowItem`.

Fire-and-forget chat output only — no state, no frames visible.
