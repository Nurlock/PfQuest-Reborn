# menu (`menu.lua`)

Minimap button (`pfQuestIcon`) + dropdown (`pfQuestMenu`).

- Button: draggable, hides when `minimapbutton == "0"`; hover shows
  status tooltip; click toggles the menu.
- Menu rows (`MenuButtonEnter/Leave/Click`): tracker, browser,
  journal, config, arrow, and tracking-list switches — thin calls
  into those modules' `Show/Hide` or config flags.
- Rebuilds on `CURSOR_UPDATE` and `OnShow`; no state of its own.

If a new window needs opening from the UI, add one row here.
