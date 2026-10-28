# Plan: party rows in the tracker (own on top, party at bottom)

Status: implemented once (luac-clean, suite green), reverted on request
to keep the tree bug-fix-only. Re-apply when ready.

## Goal

Shared quests appear in the quest tracker: the player's own quests on
top (unchanged), party members' quests in a section pinned at the
bottom, with live per-objective progress from sync data.

## Prerequisites (already in tree)

- `pfQuest.epochComms.partyQuestData[sender][target] = {{quest, questId,
  objective, current, total}}` (tooltip-sync).
- Party nodes carry `partyMember`, `quest`, `questid`, `title`
  ("Quest (Player)").
- `board_cache` reuse pattern in `tracker.ButtonEvent`.

## Changes (`tracker.lua` only)

1. **Mode filter** (`tracker.ButtonAdd`, QUEST_TRACKING branch):
   accept `PARTY` alongside `PFQUEST`:
   `if node.addon ~= "PFQUEST" and node.addon ~= "PARTY" then return end`.
   Leave GIVER/DATABASE branches untouched.

2. **Sort** (`trackersort`, first criterion after the empty check):
   own quests before party rows, then existing order within each group:
   ```lua
   local aparty = (a.node and a.node.addon == "PARTY") and 1 or -1
   local bparty = (b.node and b.node.addon == "PARTY") and 1 or -1
   if aparty ~= bparty then
     return aparty < bparty
   end
   ```

3. **Render** (`tracker.ButtonEvent`, QUEST_TRACKING branch): branch on
   `local isParty = node.addon == "PARTY" and node.partyMember`.
   - Party path: iterate `epochComms.partyQuestData[player]` rows
     matching `node.quest`; fill `board_cache` with
     `{objective..": "..cur.."/"..tot, "monster", done}` entries;
     `cur`/`max` from the same pass; `complete = n > 0 and cur >= max`;
     `level = node.qlvl or UnitLevel("player")`.
     Guard the whole block with `pfQuest.epochComms` existing
     (tooltip loads after tracker).
   - Skip the log-based rebuild loop for party
     (`if not isParty and objectives and objectives > 0 then`).
   - Everything below (expand/collapse, progress bar, percent text)
     works unchanged.
   - Override the tooltip for party rows (no quest-log entry to open):
     Unfold / Ctrl-Click / Shift-Click only.

4. **Clicks** (`tracker.ButtonClick`, Shift branch): keep node deletion,
   but skip the `pfQuest_history` write for `addon == "PARTY"`
   (it would mark *your* history for a quest you don't have).

## Tests

- Extend `tests/test_party_sync_and_tooltips.lua`: feed V1 batches from
  a fake sender, assert a tracker row appears below own rows with the
  sender's counts. Note: no suite loads `tracker.lua` today (mock has
  no button frames) — a harness must stub `tracker.buttons` pooling
  or drive `ButtonAdd` with a fake button table. In-game check is
  mandatory regardless: group up, confirm party rows render under
  yours with live counts, Shift-click only hides the pin.

## Known limits (accepted)

- 25-button pool is shared; in huge groups extras drop. Own-first
  ordering is by add order, not reserved. Revisit only if observed.
- No data for a sender yet (or sync off) renders the row at 0% —
  correct, updates live on the next batch.
