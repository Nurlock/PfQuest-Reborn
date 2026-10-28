# updatenotify (`updatenotify.lua`)

Tells players a newer version exists. Local `strsplit` parses
`major.minor.fix` into one comparable number
(`major*10000 + minor*100 + fix`).

- On `ADDON_LOADED` reads own version from the `.toc`.
- On `PLAYER_ENTERING_WORLD`, `PARTY_MEMBERS_CHANGED`,
  `RAID_ROSTER_UPDATE`: broadcasts `VERSION:<n>` on the group
  channel (`RAID` preferred, else `PARTY`), at most every 10s.
- On `CHAT_MSG_ADDON` (`pfQReborn`): accepts only from real group
  members (nil sender counts as trusted only in unit tests) and
  pins `pfQuest_config.latest = max(latest, remote)`.
- Prints the "New version available!" chat line once when
  `latest > version`.

Anyone off-group is ignored, so strangers can't trigger fake
update notices.
