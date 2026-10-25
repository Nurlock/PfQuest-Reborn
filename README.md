# pfQuest Reborn

**A lightweight quest helper, navigation arrow, and database browser for WoW 3.3.5a with Questie party synchronization and high-performance lazy metatables.**

Accept a quest and the relevant NPCs, monsters, and objects are automatically pinned on your world map and minimap, with a smooth navigation arrow guiding you to the nearest objective. Open the database browser (`/db`) to look up any unit, item, object, or quest.

Built on [pfQuest](https://github.com/shagu/pfQuest) (Shagu, GPLv3) and modernized with Reforged UI enhancements, native party comms, and standalone high-performance lazy-loading architecture.

---

## Key Features

- **Standalone All-in-One Addon**:
  - `pfQuest-Reborn` runs as a single, self-contained addon without requiring external dependencies or secondary addons.
  - Ships with high-performance embedded database tables in `db/`.
  - Simple internal flavor swapping for different game expansions (Vanilla 1.12, Project Epoch, TBC 2.4.3, WotLK 3.3.5a).

- **High-Performance Lazy Metatables**:
  - Coordinates, drops, and quest relationships deserialized lazily on first access.
  - Sub-second addon load time (~0.2s, 25x faster than legacy pfQuest) and low memory footprint (~24 MB).

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
2. Extract the `pfQuest-Reborn` folder into your WoW AddOns directory:
   - `World of Warcraft\Interface\AddOns\pfQuest-Reborn`
3. Ensure the folder name is exactly `pfQuest-Reborn`.
4. Log into World of Warcraft (Patch 3.3.5a, build 12340).

---

## Changing Database Flavors

To swap the active database flavor (e.g. between Project Epoch, Vanilla, TBC, or WotLK):

```bash
# Using pfquest-db exporter tool:
pfquest-db export-pfrb --db ref/epoch.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/wotlk.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/vanilla.db --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/tbc.db     --dest /path/to/Interface/AddOns/pfQuest-Reborn
```

---

## Slash Commands

- `/db` — Open the in-game Database Browser.
- `/db [name]` — Search for an NPC, quest, item, or object.
- `/pfquest` or `/pfq` — Open the settings and configuration panel.
- `/db clean` — Clear all manual map pins and reset the active arrow.

---

## License

GPLv3. See [LICENSE](LICENSE) for details.
