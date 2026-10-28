# data (`db/`)

Static content, loaded as Lua tables into `pfDB`. Never read whole
files — `grep` one id or name.

- `quests.lua` (~6k lines): objectives, rewards, chains (`close`
  lists mutually-exclusive quests), level/min, race/class bits.
- `units.lua` (~11k): mobs/NPCs, spawn maps, quest relations.
- `items.lua` (~8k): loot tables, vendors, quest-item links.
- `objects.lua` (~7k): game objects, spawns, quest relations.
- `meta.lua`, `zones.lua`, `minimap.lua`, `areatrigger.lua`,
  `quests-itemreq.lua`: lookup helpers, zone/map tables, triggers.
- `enUS/`: localized names (units/items/objects/quests).
- `init.lua`: assembles/merges the tables into `pfDB`.

`database.lua` builds runtime indexes (`nameIndex`) on top at
login; the files themselves are inert data.
