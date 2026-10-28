# automation (`automation.lua`)

Auto-questing: `pfQuestAutomation.OnEvent` on `questLogFrame`
(`QUEST_DETAIL`, `GOSSIP_SHOW`, `QUEST_COMPLETE`, `QUEST_GREETING`,
`QUEST_PROGRESS`).

- Accepts available quests and completes finished ones
  (`CompleteQuestWithRewards`, picks the best-value reward).
- Guards: master switch `epochAutoQuests`; `SkipLowLevelQuest` for
  trivial quests (`epochAutoQuestsSkipLowLevel`); commission quests
  (`epochSkipCommissionQuests`); single-option runecloth donations
  (`epochAutomateRuneclothDonations`).
- Never automates when the player must choose (multiple rewards,
  unhandled gossip) — it leaves the window open.

No frames of its own, no SavedVars beyond config flags.
