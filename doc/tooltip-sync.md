# party sync (`party.lua`) + tooltips (`partytooltip.lua`)

Two jobs: share live quest progress with the party, and show
party progress in tooltips.

## Outbound

- `QUEST_LOG_UPDATE` only sets `questLogSyncPending`; `OnUpdate`
  flush (`PumpSyncTimers`) rebuilds + broadcasts at most every 2s.
- `RebuildQuestMappings`: scans own log into `myQuestMappings`
  (target → quest → objective + progress).
- `ShareQuestData`: sends `V1|<payload>` deltas on the group
  channel (tracks sent keys, no-change = no send);
  `BroadcastQuestRemove(questId, title)` sends `REMOVEQ:<id>:<title>`.
- Group join (`PARTY_MEMBERS_CHANGED`, `RAID_ROSTER_UPDATE`,
- `PLAYER_ENTERING_WORLD`): cleanup + full share. No answering
  handshake: inbound requests are ignored; both sides push
  proactively, and a slow periodic full share (every 5 min while
  grouped) heals reloads. One outbound request per login pulls
  full state from peers that never push unprompted (Epoch).

## Inbound (`pfqe` prefix)

- `IsTrustedSender`: non-empty string, not self, channel is
  `PARTY`/`RAID`, and actually in the group.
- `HandlePfqeMessage`: `V1|` batches go through 1s-per-sender
  throttle (`InboundAllowed`, overflow parks in
  `pendingInboundBySender`); `REMOVEQ:` applies immediately.
- `ProcessQuestData`: colon-safe parsers (`ParseColonTail`,
  `ParseQuestSpec` — names may contain colons); progress validated
  by `IsValidProgress`; everything display-bound passes
  `SanitizePartyString` (strips `|cHhTtRr` markup, length caps)
  before landing in `partyQuestData[sender][target]`.
- `REMOVEQ` title is sanitized before compare (matches stored
  form); old `REMOVE:<target>:<quest>` format still handled.
- `CleanupPartyData` drops leavers' rows on roster change.

## Display

- `HookGameTooltip` / `HookPfQuestTooltip`: append party lines
  (class-colored names). Per-show cost only — no scans here.
- `UpdatePartyMapNodes` / `DeletePartyQuestNodes` (via `pfMap`):
  `PARTY` pins titled `"<quest> (<sender>)"`; removal matches own
  sender's nodes only.

Test hooks: `pfQuest.epochComms` exposes handlers + tables.
