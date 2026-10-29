# pfQuest Reborn

A small community fork of [pfQuest](https://github.com/shagu/pfQuest) for WoW 3.3.5a, borrowing UI work from [pfQuest-Reforged](https://github.com/stevemcqueenz/pfQuest-Reforged) and data/tooling from [pfQuest-epoch](https://github.com/Bennylavaa/pfQuest-epoch), plus Questie party sync. Far from perfect — standing on their work.

---

## Features

- **Standalone Package**:
  - Single addon folder with embedded databases (pre-bundled with Project Epoch data).
  - Database flavor can be swapped for Vanilla, TBC, or WotLK via `pfquest-db`.

- **Questie Party Synchronization**:
  - Shares quest progress with group members running **Questie** (`questie` and `QuestieV1` protocols).
  - Shows party members' objective counts and turn-in readiness on unit, object, and NPC tooltips.
  - Synchronizes objective updates and quest watch visibility across the party.
  - Optional party chat completion announcements.

- **Initial Setup & Completed Quest Sync**:
  - Brief setup popup on first login to select marker style and arrow preferences.
  - Optional **`/db query`** option to query the server for completed quests (`QueryQuestsCompleted`) to hide them from the map.

- **UI & Performance**:
  - Flat dark theme with tracker progress bars from pfQuest-Reforged.
  - Batched map updates and cached lookups to try to keep lag down during party play.
  - Basic theme adaptation when GW2 UI or pfUI is installed.

---

## Installation

1. Download the latest release from the [Releases](../../releases) tab.
2. Extract the `pfQuest-Reborn` folder into your WoW AddOns directory:
   - `World of Warcraft\Interface\AddOns\pfQuest-Reborn`
3. Ensure the folder name is exactly `pfQuest-Reborn`.
4. Log into World of Warcraft (Patch 3.3.5a, build 12340).

---

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/db` | Open the in-game Database Browser interface. |
| `/db [name]` | Search the database for an NPC, quest, item, vendor, or game object. |
| `/db query` | Query the server for completed quests (`QueryQuestsCompleted`) to populate quest history. |
| `/pfquest` or `/pfq` | Open the pfQuest-Reborn configuration and settings panel. |
| `/db show` | Toggle the database browser window. |
| `/db clean` | Clear all manual map pins and reset the active arrow. |
| `/db reset` | Reset and redraw all active map pins and route lines. |
| `/db tracker` | Toggle visibility of the quest tracker. |
| `/db lock` | Toggle map tracker position lock. |
| `/db journal` | Open the quest history journal. |
| `/db arrow` | Toggle or show the quest navigation arrow. |
| `/db scan` | Scan the server for custom items (where supported). |
| `/db locale` | Display active addon localization. |

---

## Changing Database Flavors

`pfQuest-Reborn` ships with Project Epoch database tables by default. To swap the active database flavor to standard Vanilla, TBC, or WotLK using the [`pfquest-db`](https://github.com/Nurlock/PfQuest-db) CLI tool:

```bash
# Export desired database flavor into your addon directory:
pfquest-db export-pfrb --db ref/epoch.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/vanilla.db --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/tbc.db     --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/wotlk.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
```

---

## Tests

`pfQuest-Reborn` includes a standalone test suite runnable under Lua 5.1 without requiring the WoW client:

```bash
cd /path/to/pfQuest-Reborn
lua5.1 tests/run_all_tests.lua
```

Tests cover questgiver lifecycle, objective parsing, metadata isolation, node cleanup, party synchronization, and setup popup states.

---

## Known Rough Edges

Party sync, quest history, and tooltips still have edge cases. Bug reports and fixes welcome.

## Credits & Citations

`pfQuest-Reborn` builds upon the work of the World of Warcraft addon development community:

- **[pfQuest](https://github.com/shagu/pfQuest)** by **Shagu** — The original quest helper and in-game database for legacy World of Warcraft clients (GPLv3).
- **[pfQuest-Reforged](https://github.com/stevemcqueenz/pfQuest-Reforged)** by **stevemcqueenz** — Modernized user experience, unified theme system (`theme.lua`), route calculation optimizations, tracker progress bars, and UX refinements.
- **[pfQuest-epoch](https://github.com/Bennylavaa/pfQuest-epoch)** by **Bennylavaa** — Project Epoch database adaptation, continent map pin scaling, and database export tooling.
- **[Questie](https://github.com/Questie/Questie)** by the Questie Team — Group communication protocols (`questie` and `QuestieV1`) enabling cross-addon party quest objective tracking.

---

## License

GPLv3. See [LICENSE](LICENSE) for details.
