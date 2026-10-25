# pfQuest Reborn

**A lightweight quest helper, navigation arrow, and database browser for WoW 3.3.5a with Questie party synchronization and dynamic Load-on-Demand databases.**

Accept a quest and the relevant NPCs, monsters, and objects are automatically pinned on your world map and minimap, with a smooth navigation arrow guiding you to the nearest objective. Open the database browser (`/db`) to look up any unit, item, object, or quest.

Built on [pfQuest](https://github.com/shagu/pfQuest) (Shagu, GPLv3) and modernized with Reforged UI enhancements, native party comms, and decoupled high-performance Load-on-Demand architecture.

---

## Key Features

- **Decoupled Load-on-Demand (LoD) Architecture**:
  - The core addon `pfQuest-Reborn` is ultra-lightweight (~500 KB) containing the UI, engine, map layer, and Questie comms.
  - Databases ship as standalone child modules marked `## LoadOnDemand: 1`:
    - `pfQuest-Reborn-vanilla` (Standard Vanilla 1.12 content)
    - `pfQuest-Reborn-epoch` (Project Epoch custom content and quests)
    - `pfQuest-Reborn-tbc` (The Burning Crusade content)
    - `pfQuest-Reborn-wotlk` (Wrath of the Lich King content)
  - **Dynamic Realm Auto-Detection**: The active realm is automatically detected (`GetRealmName()`), loading only the relevant database into memory.
  - **Zero RAM Overhead**: Inactive expansion databases consume **0 MB of Lua RAM** and **0 seconds of parse time**.
  - Manual override available in settings (`/pfquest` -> General -> Database Flavor).

- **High-Performance Lazy Metatables**:
  - Coordinates, drops, and quest relationships deserialized lazily on first access.
  - Sub-second addon load time (25x faster than legacy pfQuest).

- **Questie Group Quest Tracking & Sharing**:
  - Full bidirectional communication with party members running **Questie** (`questie` and `QuestieV1` comms protocols).
  - View party members' quest progress directly on monster, object, and item tooltips.
  - Synchronize quest objective states and visibility across your group in real-time.

- **Modernized Interface**:
  - Flat dark theme with teal accent.
  - Clean tabbed settings window with category navigation and scroll child panels.
  - Tracker progress bars and custom map/minimap node sliders.
  - Smoothly rotating navigation arrow with in-place rotation calculations.

---

## Installation

1. Download the latest release from the [Releases](../../releases) tab.
2. Extract `pfQuest-Reborn` and your desired database module(s) into your WoW directory:
   - `Interface\AddOns\pfQuest-Reborn` (Core engine - required)
   - `Interface\AddOns\pfQuest-Reborn-vanilla` (for Vanilla realms)
   - `Interface\AddOns\pfQuest-Reborn-epoch` (for Project Epoch)
   - `Interface\AddOns\pfQuest-Reborn-tbc` (for TBC realms)
   - `Interface\AddOns\pfQuest-Reborn-wotlk` (for WotLK / ChromieCraft realms)
3. Ensure folder names match exactly.
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
