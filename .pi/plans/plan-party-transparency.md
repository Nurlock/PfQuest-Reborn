# Plan: dim quest pins that are not the player's own

Status: plan only. Re-apply hunk by hunk; verify in game (mock cannot
render frames).

## Goal

Party-shared objective pins render more transparent than the player's
own pins on both maps, so ownership is visible at a glance. Hovered
pins stay full-alpha (existing hover-to-inspect behavior).

## Mechanism (already in tree)

- Pins animate toward a target alpha in the world-map `OnUpdate`
  highlight pass (`map.lua`, `pfMap:Animate`): textured nodes → 1.0,
  plain dots → `frame.defalpha` (`worldmaptransp` /
  `minimaptransp`), hovered → 1.0, others-while-hovering → `nodefade`.
- Minimap pins have no alpha animation; they render at frame alpha 1.
- Node tables already carry `partyMember` (copied from meta in
  `AddNode`: `for key, val in pairs(meta)`), but `UpdateNode`'s
  flatten loop (`map.lua`, after `frame.layer = tab.layer`) does
  **not** copy it onto the frame — so the render pass cannot tell
  party pins apart today.

## Changes (`map.lua` only, plus one config row)

1. **Expose ownership on the frame.** In `UpdateNode`'s flatten block
   (where `frame.title`, `frame.quest` etc. are set), add
   `frame.partyMember = tab.partyMember`, and reset it to nil where
   the block starts (`frame.layer = 0` area) so pooled pin frames
   never leak a stale sender.
2. **World map dimming.** In the `OnUpdate` highlight pass, multiply
   the animation target by the party factor for frames with
   `frame.partyMember` set — textured-default and plain-default
   branches only. Leave the hovered (1.0) and hover-fade (`nodefade`)
   branches untouched.
3. **Minimap dimming.** In the minimap loop's show branch
   (after `mpins[i]:Show()`), set
   `mpins[i]:SetAlpha(party and dim or 1)` unconditionally so reused
   pins reset.
4. **Config.** Add `partytransp` (slider 0.2–1.0, default 0.6) next to
   the other transparency entries in `config.lua`; the options window
   builds rows from the defconfig table, so no UI code is needed
   (confirm on load). Factor used: `targetAlpha * partytransp`.

## Tests

- Render-only change: not unit-testable in the mock (no frames).
  In-game check: group up, confirm party pins render dimmer than own
  pins on both maps, hover restores full alpha, own pins unchanged,
  and the factor follows the new slider.
- `luac5.1 -p` must stay clean (balanced `if`/`end` in the
  flatten block is the fragile spot).

## Edge cases (decided)

- Mixed own+party entries on one pin: the winning tab decides, same
  as title/texture today — dim follows displayed content.
- Senders that left: `CleanupPartyData` already deletes their nodes,
  so no stale dimmed pins.
- Cost: one field copy per `UpdateNode`, one branch per pin per
  animation tick; the highlight pass only runs with the world map
  open. Negligible next to a pin redraw.
- Tracker party rows (separate plan) should dim their text the same
  way when that lands; out of scope here.
