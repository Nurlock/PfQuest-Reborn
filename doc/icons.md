# icons (`icons.lua`)

Data-only file: `pfDatabase:AddCustomIcon(id, path)` calls assigning
custom minimap/node textures. Negative ids = game objects, positive =
units (mostly mining veins in the current list).

Must load after `database.lua` (uses `pfDatabase`). To add an icon,
one line, one id per name to avoid duplicates.
