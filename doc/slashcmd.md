# slashcmd (`slashcmd.lua`)

One handler: `SlashCmdList["PFDB"]` for `/db`, `/shagu`,
`/pfquest`, `/pfdb`. Splits input into params and dispatches:

- bare `/db`: prints help via `DEFAULT_CHAT_FRAME`.
- toggles: `lock`, `tracker`, `journal`, `arrow`, `show`, `config`,
  `locale`, `debug`.
- searches: `track <list>`, `unit`, `object`, `item`, `vendor`,
  `quest <name>` — these call into `database.lua` search and print
  results to chat.

No state. Thin dispatch over config flags, frames, and DB search.
