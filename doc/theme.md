# theme (`theme.lua`)

One table, `pfQuestTheme` (`T`), with skinning helpers shared by all
windows: `SkinPanel`, `HeaderStrip`, `CreateProgressBar`,
`HoverIcon` (plus `OnEnter`/`OnLeave` wiring).

Reads only `pfQuest_config` font size. Holds no state, registers no
events. Visual changes go here so panels stay consistent.
