# locales (`locales.lua`, ~1.5k lines)

Single key table. `pfQuest_Loc` is a metatable falling back to the
`enUS` entry, so missing translations render English instead of nil.

Convention: new UI strings go here, never hardcoded at call sites.
Look keys up with `grep`, don't read the file end to end.
