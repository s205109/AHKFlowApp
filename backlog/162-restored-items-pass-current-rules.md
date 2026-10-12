# 162 - Restored items pass current rules

## Metadata

- **Epic**: History
- **Type**: Bug
- **Interfaces**: API (Restore and Revert responses), UI (Recycle Bin and history messages)
- **Difficulty**: complex
- **Stage**: 3-plan

## Summary

Restore and Revert apply a stored Snapshot straight to the Item. They do not run the validators
that Create and Update run. A Snapshot passed only the rules that existed when it was saved. When a
rule became stricter later, Restore or Revert brings back a value the current rules refuse. The
Emitters then write that value into the Profile script unchanged, because they trust the
validators to have run. The likely effect is a Profile script that does not load.

## User story

As an Owner who restores or reverts a Hotstring or Hotkey, I want the result to pass the same rules
as a new save, so that one old Snapshot cannot stop my whole Profile script from loading.

Design settled the open question below. A failing Revert is refused; a failing Restore brings the
item back **Applies to no profile**, so the data returns and no Profile script can break. The
reasons are in [`docs/adr/0021-a-failed-restore-applies-to-no-profile.md`](../docs/adr/0021-a-failed-restore-applies-to-no-profile.md).

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [x] Restore and Revert of a Hotstring, and Restore and Revert of a Hotkey, check the definition
      they are about to apply against the same rules Create and Update apply. For a Hotkey the
      check reads the definition `LegacyHotkeySnapshotConverter.ToDefinition` produced, not the
      stored Snapshot shape.
- [x] A Revert whose definition fails returns `Result.Invalid(errors)` and leaves the Hotstring or
      Hotkey unchanged. The errors name the failing rules.
- [x] A Restore whose definition fails still creates the Item, with no Profile link and
      `AppliesToAllProfiles` false, and its response carries a `RestoreWarnings` collection naming
      every failing rule.
- [x] A test walks the whole recovery sequence: a Restore that fails the rules, the generated
      Profile script with the Item absent, a repair that assigns a Profile, then the generated
      script with the Item present. It runs for a Snapshot that applied to all Profiles and for one
      that named Profiles explicitly.
- [x] A Restore whose definition passes keeps the Snapshot's own Profile scope, filtered to live
      Profiles as it is today.
- [x] The rules checked are the definition's own rules only. The Profile and Category association
      rules are not among them, so a Restore whose Profiles were all deleted still succeeds.
- [x] An integration test in `tests/AHKFlowApp.API.Tests` seeds a Snapshot that a current rule
      refuses, and shows Revert returning 400 with the rule's message and Restore returning 200
      with the Item attached to no Profile.
- [ ] A legacy Script Snapshot and a legacy Hotkey Snapshot still restore, as ADR-0003 and
      ADR-0005 require. The existing legacy restore tests pass without edits.
- [x] The Recycle Bin names the failing rules after a Restore that came back applying to no
      profile, and the history dialog shows the 400 message after a refused Revert.

### Why the legacy criterion is not ticked

The second sentence holds. `RestoreCommandTests.cs`, `RevertCommandTests.cs`,
`HotstringSnapshotCompatibilityTests.cs` and `HotkeySnapshotCompatibilityTests.cs` are all
unedited on this branch and all pass, which `git diff --name-only` against the merge base shows.

The first sentence does not hold for one family of legacy rows. A legacy `Kind=Script` hotstring
whose body sends a literal brace, such as `Send "{{}"`, composes into a Raw definition that the
brace counter in `AddRawKindRules` reads as unbalanced. That counter is deliberately unaware of
strings and comments, which is decision D12 in the Raw work. Such a row used to restore attached
and emit an unchanged line. It now comes back applying to no profile, and
`UpdateHotstringCommandValidator` runs the same rule, so the edit dialog refuses every save while
the body stays as it is. A Revert to such a version is refused outright.

This is a behavior change the design stage did not weigh, so it is a decision for the human rather
than a tick. The behavior is pinned by
`DefinitionRuleCheckTests.Check_LegacyScriptBodyWithLiteralBrace_PinsTheNaiveBraceCounter` and
recorded as consequence 5 of
[`docs/adr/0021-a-failed-restore-applies-to-no-profile.md`](../docs/adr/0021-a-failed-restore-applies-to-no-profile.md).
Keeping the behavior was chosen over dropping the brace rule from the Restore and Revert rule set,
because dropping it would let Restore accept a definition the edit dialog then refuses forever.

### Evidence behind the ticked boxes

- Definition rule check, both entities: `tests/AHKFlowApp.Application.Tests/Validation/DefinitionRuleCheckTests.cs`
- Revert refusal and the no-history-staged ordering, one theory per entity, plus the four Restore
  cases: `tests/AHKFlowApp.Application.Tests/History/SnapshotRuleCheckTests.cs`
- The whole recovery sequence, both scope modes: `tests/AHKFlowApp.Application.Tests/History/InertRestoreRecoveryTests.cs`
- Revert 400 and Restore 200 over HTTP, one pair per entity:
  `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringHistoryEndpointsTests.cs` and
  `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeyHistoryEndpointsTests.cs`
- The Recycle Bin warning snackbar, both entities: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs`
- The same warning driven in a browser: `tests/AHKFlowApp.E2E.Tests/VersionHistoryFlowTests.cs`

One limit on the last ticked box. Its first half is covered by the two files above. Its second half,
the history dialog showing the 400 message after a refused Revert, was verified by reading the code
rather than by a new test: both dialogs route a failed Revert through `ApiErrorMessageFactory.Build`
into an error snackbar, at `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringHistoryDialog.razor:127`
and `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyHistoryDialog.razor:120`. That
plumbing predates this item, and the spec says so under "The UI needs no new error plumbing".

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
- Open question for Pickup — **settled in Design.** A failing Revert is refused. A failing Restore
  brings the Item back applying to no profile. ADR-0021 holds the reasoning.
- Only the Owner writes their own Snapshots, so this is a reliability risk, not an attack path.
- Design found that no `IsEnabled` flag exists on a Hotstring, a Hotkey, or a Profile. Detaching
  from every Profile is therefore the only lever that makes an Item inert without changing an
  Emitter.
- Design also found the rules are already reusable: `HotstringRules` and `WindowContextRules` are
  generic over the validated type, and `AddHotkeyActionRules` validates through `IHotkeyDraft`,
  whose members match `HotkeyDefinition` field for field.
- Spec: `docs/superpowers/specs/2026-10-11-restored-items-pass-current-rules-design-162.md`
- Plan: `docs/superpowers/plans/2026-10-11-restored-items-pass-current-rules-plan-162.md`
