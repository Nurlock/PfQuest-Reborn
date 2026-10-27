# pfQuest Reborn

**A lightweight quest helper, navigation arrow, and database browser for WoW 3.3.5a with Questie party synchronization, high-performance lazy metatables, and standalone all-in-one architecture.**

Accept a quest and the relevant NPCs, monsters, and objects are automatically pinned on your world map and minimap, with a smooth navigation arrow guiding you to the nearest objective. Open the database browser (`/db`) to look up any unit, item, object, or quest.

Built on [pfQuest](https://github.com/shagu/pfQuest) (Shagu, GPLv3) and modernized with Reforged UI enhancements, native Questie party comms, server completed-quest sync, and a high-performance lazy-loading architecture.

---

## Key Features

- **Standalone All-in-One Addon**:
  - `pfQuest-Reborn` runs as a single, self-contained addon without requiring external dependencies or secondary addons.
  - Ships with high-performance embedded database tables in `db/` (pre-bundled with Project Epoch content).
  - Simple flavor swapping for different game expansions (Project Epoch, Vanilla 1.12, TBC 2.4.3, WotLK 3.3.5a).

- **First-Run Setup Wizard & Completed Quest Sync**:
  - Streamlined setup wizard on first launch to configure preferred marker style (*Simple Markers*, *Combined*, or *Spawn Points*) and navigation arrow.
  - Integrated **`/db query`** checkbox to instantly query the server for your character's already completed quests (`QueryQuestsCompleted`), hiding finished quests from your map.
  - Clean dismissal and automatic state preservation: once configured or dismissed, the wizard never pops up again on `/reload` or re-logins.

- **Questie Group Quest Tracking & Comms**:
  - Full bidirectional communication with party members running **Questie** (`questie` and `QuestieV1` comms protocols).
  - Displays party members' quest objectives and progress directly on monster, object, and item tooltips.
  - Synchronizes quest objective states and visibility across your group in real-time.
  - Optional party quest completion announcements.

- **Hierarchical Configuration & Dynamic Gray-Out**:
  - Clean tabbed settings window with category navigation and scroll panels (`/pfquest` or `/pfq`).
  - True parent-child dependency system: disabling a master switch (such as *Experimental Features* or *Show Route Between Objects*) visually grays out and locks all child options.
  - Visual indentations reflecting settings hierarchy.

- **High-Performance Lazy Metatables**:
  - Coordinates, drops, and quest relationships deserialized lazily on first access.
  - Sub-second addon load time (~0.2s, 25x faster than legacy pfQuest) and low memory footprint (~24 MB).
  - Pre-indexed quest lookups and cached route math eliminate frame stutter.

- **Modernized Interface & Theme Engine**:
  - Flat dark theme with signature teal accent.
  - Automatic theme detection: seamlessly adopts parchment gold and dark styling when GW2 UI is installed, and integrates natively with pfUI.
  - Tracker progress bars and custom map/minimap node sliders.
  - Smoothly rotating navigation arrow with in-place angle and distance calculations.

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

`pfQuest-Reborn` ships with Project Epoch database tables by default. To swap the active database flavor to standard Vanilla, TBC, or WotLK using the `pfquest-db` CLI tool:

```bash
# Export desired database flavor into your addon directory:
pfquest-db export-pfrb --db ref/epoch.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/vanilla.db --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/tbc.db     --dest /path/to/Interface/AddOns/pfQuest-Reborn
pfquest-db export-pfrb --db ref/wotlk.db   --dest /path/to/Interface/AddOns/pfQuest-Reborn
```

---

## Testing & Quality Assurance

`pfQuest-Reborn` includes an automated standalone regression test suite running under standard Lua 5.1 without requiring the WoW client:

```bash
cd /path/to/pfQuest-Reborn
lua5.1 tests/run_all_tests.lua
```

The suite validates:
- **Questgiver lifecycle**: Quest acceptance, node deletion, ender spawning, and duplicate suppression.
- **Objective parsing**: Kill count, multi-word objective names, non-slain verbs (*healed*, *collected*, *dispelled*), and turn-in checks.
- **Metadata isolation**: Preventing shared table mutations during recursive quest searches.
- **Node cache & fallback deletion**: Unified coordinate pruning on quest completion.
- **Performance & memory guards**: Safe Levenshtein cache ring buffers, frame level clamping ($\le 128$), and broadcast echo guards.
- **Config UI dependencies**: Hierarchical disabling, graying-out, and interaction locking.
- **Setup wizard lifecycle**: First-run detection, `/reload` suppression, and server query execution.

---

## License

GPLv3. See [LICENSE](LICENSE) for details.
