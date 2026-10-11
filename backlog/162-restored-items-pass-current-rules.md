# 162 - Restored items pass current rules

## Metadata

- **Epic**: History
- **Type**: Bug
- **Interfaces**: API (Restore and Revert responses), UI (Recycle Bin and history messages)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

Restore and Revert apply a stored Snapshot straight to the Item. They do not run the validators
that Create and Update run. A Snapshot passed only the rules that existed when it was saved. When a
rule became stricter later, Restore or Revert brings back a value the current rules refuse. The
Emitters then write that value into the Profile script unchanged, because they trust the
validators to have run. The likely effect is a Profile script that does not load.

## User story

As an Owner who restores or reverts a Hotstring or Hotkey, I want the result to pass the same rules
as a new save, so that one old Snapshot cannot stop my whole Profile script from loading.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] Restore and Revert of a Hotstring check the definition they are about to apply against the
      same rules as Create and Update. A Snapshot that fails returns `Result.Invalid(errors)` and
      leaves the Item unchanged.
- [ ] Restore and Revert of a Hotkey do the same.
- [ ] An integration test in `tests/AHKFlowApp.API.Tests` seeds a Snapshot that a current rule
      refuses, and shows that Restore and Revert both return 400 with the rule's message.
- [ ] A legacy Script Snapshot and a legacy Hotkey Snapshot still restore, as ADR-0003 and
      ADR-0005 require. The existing legacy restore tests pass without edits.
- [ ] The Recycle Bin and the history dialog show the 400 message to the Owner.

## Out of scope

- Making the Emitters check their own input. The Emitters keep trusting validated input; this item
  makes sure every write path validates.
- Import. It runs its own checks, produces Text hotstrings only, and the Emitter escapes those
  fully.
- Rewriting stored Snapshots.

## Notes / dependencies

- **Where this came from.** Architecture review in session
  https://claude.ai/code/session_01EPTqaHBB9hCJgYiHcDySQe, candidate 4.
- Evidence at filing time:
  - Hotstring Restore applies the Snapshot: (`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RestoreHotstringCommand.cs:63`, "ScriptToRawComposer.ToDefinition(snapshot),").
  - Hotstring Revert applies the Snapshot: (`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RevertHotstringCommand.cs:63`, "entity.Update(ScriptToRawComposer.ToDefinition(snapshot), clock);").
  - Hotkey Restore applies the Snapshot: (`src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RestoreHotkeyCommand.cs:61`, "LegacyHotkeySnapshotConverter.ToDefinition(snapshot),").
  - Hotkey Revert applies the Snapshot: (`src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RevertHotkeyCommand.cs:61`, "entity.Update(LegacyHotkeySnapshotConverter.ToDefinition(snapshot), clock);").
  - The Window context is written unescaped: (`src/Backend/AHKFlowApp.Application/Services/DefinitionWrapping.cs:75`, "ContextValue has already passed validation").
  - The date format is written unescaped: (`src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs:77`, "validation lives elsewhere").
  - The Macro emitter trusts its input: (`src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs:85`, "enforced elsewhere (Task 3)").
  - A Remap with no destination throws during generation: (`src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs:66`, "Remap requires a RemapDest").
- Open question for Pickup: should a failing Snapshot be refused, or restored with a warning and
  left for the Owner to fix? Refusing is simpler, but it can make a deleted Item impossible to get
  back. Settle this before Difficulty.
- Only the Owner writes their own Snapshots, so this is a reliability risk, not an attack path.
- Spec: none — not picked up yet.
- Plan: none — not picked up yet.
