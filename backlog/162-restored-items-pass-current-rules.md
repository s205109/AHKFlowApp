# 162 - Restored items pass current rules

## Metadata

- **Epic**: History
- **Type**: Bug
- **Interfaces**: API (Restore and Revert responses), UI (Recycle Bin and history messages)
- **Difficulty**: complex
- **Stage**: 5-simplify

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
- [x] A legacy Script Snapshot and a legacy Hotkey Snapshot still restore, as ADR-0003 and
      ADR-0005 require. The existing legacy restore tests pass without edits.
- [x] The Recycle Bin names the failing rules after a Restore that came back applying to no
      profile, and the history dialog shows the 400 message after a refused Revert.

### The legacy criterion, and the cost accepted with it

The second sentence holds. `RestoreCommandTests.cs`, `RevertCommandTests.cs`,
`HotstringSnapshotCompatibilityTests.cs` and `HotkeySnapshotCompatibilityTests.cs` are all
unedited on this branch and all pass, which `git diff --name-only` against the merge base shows.

The first sentence holds for every legacy row. Restore always returns the Item, and
`LegacyHotkeySnapshotConverter` still runs on every legacy Hotkey row, which is what ADR-0003 and
ADR-0005 ask for. Neither ADR asks for the restored Item to be attached to a Profile.

Two families of legacy rows come back applying to no profile rather than attached. Both fail a
brace counter, and both counters are deliberately unaware of strings and comments, which is
decision D12 in the Raw work.

1. A legacy `Kind=Script` hotstring whose body sends a literal brace, such as `Send "{{}"`,
   composes into a Raw definition that `AddRawKindRules` reads as unbalanced.
2. A legacy hotkey whose `Action` is `Send` and whose `Parameters` hold `{{}` converts to a Raw
   hotkey, because `IsValidSendKeysContent` refuses a braced token that holds a second brace. Its
   body becomes `Send("{{}")`, which `BracesBalanced` reads as unbalanced.

AutoHotkey accepts both forms: `{{}` is how Send types a literal brace. Such a row used to restore
attached and emit an unchanged line. It now comes back applying to no profile, and
`UpdateHotstringCommandValidator` or `UpdateHotkeyCommandValidator` runs the same counter, so the
edit dialog refuses every save while the body stays as it is. A Revert to such a version is refused
outright.

**The cost, accepted on 2026-10-12.** An Owner who restores such a row gets the data back, and
must rewrite the body — or change the kind or action — before the row reaches a Profile script
again. Three facts make that cost acceptable. The same refusal already runs at Create on `main`,
so no new row can hold such a body. Only rows written before the Raw and registry work can hold
one, and their Owners already cannot save an edit to that value either way. The alternative, which
is dropping the brace rules inside the history path alone, produces the worse state ADR-0021
names: an Item that Restore accepts and the edit dialog then refuses forever.

Both behaviors are pinned, in `DefinitionRuleCheckTests`:
`Check_LegacyScriptBodyWithLiteralBrace_PinsTheNaiveBraceCounter` and
`Check_LegacyHotkeySendWithLiteralBrace_PinsTheNaiveBraceCounter`. The reasoning is consequence 5 of
[`docs/adr/0021-a-failed-restore-applies-to-no-profile.md`](../docs/adr/0021-a-failed-restore-applies-to-no-profile.md).
Keeping the behavior was chosen over dropping the brace rules from the Restore and Revert rule set,
because dropping them would let Restore accept a definition the edit dialog then refuses forever.

The counters are not this item's to change. They already refuse the same body at Create, so an
Owner cannot write one through the API today either. Making them aware of strings and comments
needs its own item, because it changes what Create and Update accept for every Raw row. That is
follow-up 1 below, and both pinning tests turn red when it lands.

### Evidence behind the ticked boxes

- Definition rule check, both entities: `tests/AHKFlowApp.Application.Tests/Validation/DefinitionRuleCheckTests.cs`
- Revert refusal and the no-history-staged ordering, one theory per entity, plus the four Restore
  cases: `tests/AHKFlowApp.Application.Tests/History/SnapshotRuleCheckTests.cs`
- The whole recovery sequence, both entities and both scope modes:
  `tests/AHKFlowApp.Application.Tests/History/InertRestoreRecoveryTests.cs`
- The definition validators refusing exactly what the Update validators refuse, 20 cases across
  both entities: `tests/AHKFlowApp.Application.Tests/Validation/DefinitionRuleParityTests.cs`.
  Criterion 1 names Create and Update, and these cases anchor on Update alone. That covers both,
  because each Create validator holds the same rule list as its Update twin.
- Revert 400 and Restore 200 over HTTP, one pair per entity:
  `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringHistoryEndpointsTests.cs` and
  `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeyHistoryEndpointsTests.cs`
- The Recycle Bin warning snackbar, both entities: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs`
- The same warning driven in a browser: `tests/AHKFlowApp.E2E.Tests/VersionHistoryFlowTests.cs`
- The history dialog showing the 400 message after a refused Revert, and staying open behind it,
  one test per entity: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringHistoryDialogTests.cs`
  and `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyHistoryDialogTests.cs`

One limit on the browser evidence. The browser test stops after the Recycle Bin warning and the
detached state. The repair itself — the Owner fixing the value, choosing profiles again, and the
item reaching the generated script — is proven at the Application level instead, through
`ValidatingUseCase` and the real script generator, because that is where the Update rules run.
Walking the same route through the edit dialog in a browser is follow-up work.

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

### Follow-up work this item leaves behind

A review round raised three things this item does not do. None is filed yet, because the backlog
numbering script picks the next number and a worktree session cannot run it.

1. **Make both brace counters aware of strings and comments.** This is the unticked criterion
   above. The counters live in `HotstringRules.AddRawKindRules` and `HotkeyRules.BracesBalanced`,
   and they already refuse a literal brace at Create, so the work changes what Create and Update
   accept for every Raw row. The two pinning tests in `DefinitionRuleCheckTests` turn red when it
   lands, which is how that item will know it is done.
2. **Walk the repair through the browser.** The browser test stops at the Recycle Bin warning. The
   repair route — open the item, fix the value, choose profiles, save, see it in the script — is
   proven at the Application level only.
3. **Show a detached item why it is detached.** `RestoreWarnings` arrives once, in the Restore
   response. Nothing persisted records which rules failed, so a page reload loses the list. The
   fix is to recompute the current failures when the Owner opens the item, rather than to store
   messages that can go stale. Consequence 3 of ADR-0021 is the same gap seen from the data side.
