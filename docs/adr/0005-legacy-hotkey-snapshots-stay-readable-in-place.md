# Legacy hotkey snapshots stay readable in place

`LegacyHotkeySnapshotConverter` stays as permanent runtime code. No migration rewrites hotkey history snapshots. Hotkey history rows written before the Wave 1 typed-action work hold a legacy pair — an `Action` enum and a free `Parameters` string — instead of typed columns. The converter turns that pair into typed columns when a user restores or reverts such a row, and it keeps doing so.

## Why the rows are still there

Since `EntityHistories` was created, no later migration has rewritten hotkey `SnapshotJson` payloads. The `20260722105522_HotkeyTypedActions` migration rewrites the hotkey table only. So the legacy pair is still present in every database that has pre-W1 history.

Keeping the converter freezes six things: the backend `LegacyHotkeyDefinitionConverter.HotkeyAction` enum, the frontend `AHKFlowApp.UI.Blazor.DTOs.HotkeyAction` mirror of it, the `Action` and `Parameters` members on `HotkeySnapshot`, the same pair mirrored on `HotkeyHistoryVersionDto`, the converter and its tests, and two display arms in `HotkeyActionDisplay`. The alternative is a third migration that rewrites those JSON payloads in place and lets all six go.

## Consequences

Four reasons, in order of weight:

1. **History is an audit record.** ADR 0003 frames history as point-in-time snapshots. Rewriting an old snapshot changes what the record says was stored. Reading a legacy row through a converter leaves the record alone.
2. **A migration contradicts a decision already made.** Commit `6972f90` deliberately displays a legacy row as "Legacy" rather than as the kind a revert would produce. Normalizing the same rows in storage contradicts that more strongly than normalizing them on the wire, which was already ruled out.
3. **It would duplicate the hardest code in the repository a second time.** The existing T-SQL classifier needed a Testcontainers parity test and a large golden fixture set to pin traps that appear only in SQL: `LEN()` ignoring trailing spaces, `IN` pad-comparison, `UNICODE()` accepting C1 control characters, and `nvarchar(4000)` truncation. A second hand-written copy inherits every one of them.
4. **The cost of keeping it does not grow.** The six frozen items are fixed by data already written. No future feature adds to that list.

The honest cost: six pieces of code stay that a migration would delete. That is accepted.

## Revisit if

A future change needs to alter the shape of `HotkeySnapshot` in a way the optional legacy members block, or an operator confirms no database in any environment holds a pre-W1 hotkey history row. The second case allows deleting the shim with no migration at all.
