# pfQuest Reborn

**A lightweight quest helper and database browser for WoW 3.3.5a — tailored for Vanilla content with Questie party quest synchronization.**

Accept a quest and the relevant NPCs, monsters, and objects are automatically pinned on your world map and minimap, with a smooth navigation arrow guiding you to the nearest objective. Open the database browser (`/db`) to look up any unit, item, object, or quest in Vanilla World of Warcraft.

Built on [pfQuest](https://github.com/shagu/pfQuest) (Shagu, GPLv3) and modernized with Reforged UI enhancements and native party comms.

---

## Key Features

- **Pure Vanilla Database**: Stripped of all Outland (TBC) and Northrend (WotLK) database bloat. Loads instantly with a minimal memory footprint (~12MB).
  - 4,433 Vanilla quests
  - 10,385 Units (NPCs and monsters)
  - 8,985 GameObjects
  - 17,712 Items
  - 71,098 unit spawn points and 53,596 object spawn points with accurate coordinates and respawn timers.
- **Questie Group Quest Tracking & Sharing**:
  - Full bidirectional communication with party members running **Questie** (`questie` and `QuestieV1` comms protocols).
  - View party members' quest progress directly on monster, object, and item tooltips.
  - Synchronize quest objective states and visibility across your group in real-time.
- **Modernized Interface**:
  - Flat dark theme with teal accent.
  - Clean tabbed settings window with category navigation and scroll child panels.
  - Tracker progress bars and custom map/minimap node sliders.
  - Smoothly rotating navigation arrow.
- **Zero Startup Lag**:
  - Eliminated runtime multi-expansion `patchtable()` deep-merges on `ADDON_LOADED`.
  - Lean TOC file with only core vanilla data tables.

---

## Installation

1. Download the latest release from the [Releases](../../releases) tab.
2. Extract the archive into your WoW directory: `Interface\AddOns\pfQuest-Reborn`.
3. Ensure the folder is named exactly `pfQuest-Reborn`.
4. Log into World of Warcraft (Patch 3.3.5a, build 12340).

---

## Slash Commands

- `/db` — Open the in-game Database Browser.
- `/db [name]` — Search for an NPC, quest, item, or object.
- `/pfquest` or `/pfq` — Open the settings and configuration panel.
- `/db clean` — Clear all manual map pins and reset the active arrow.

---

## License

GPLv3. See [LICENSE](LICENSE) for details.
