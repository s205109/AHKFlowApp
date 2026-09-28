# 161 - Leaving Raw keeps hotstring Options

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

In the hotstring edit dialog, a switch from Raw to Text, Date & time, or Macro loses the
`*`, `?`, `C`, and `O` Options of the Raw definition without a warning. Reproduced at Pickup.

The defect is wider than the first reading suggested. The dialog does not only drop Options.
It also turns **Trigger inside words** on for every Raw definition that does not carry `?`,
including a definition that carries no Options at all. That adds behavior the user never asked
for, so the hotstring starts firing in the middle of words after the switch.

## User story

As a user who switches a Raw hotstring to Text, I want its Options to carry over, or a warning
before they are lost, so that the hotstring still fires the way it did.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] After a switch from Raw `:*C:btw::by the way` to Text, the dialog shows ending character
      not required and case sensitive, or it asks for confirmation before it discards them.
- [ ] After a switch from Raw `::btw::by the way` (no `?`) to Text, the dialog does not turn
      triggering inside words on without a confirmation.
- [ ] A bUnit test in `tests/AHKFlowApp.UI.Blazor.Tests` covers a Raw definition that carries
      each of `*`, `?`, `C`, and `O`.

## Out of scope

- Options that no structured field can hold, such as `K1000` or `SE`. The dialog already warns
  about those.
- Moving the syntax rules out of the dialog (candidate 1 of the same review).

## Notes / dependencies

- **Where this came from.** Architecture review in session
  https://claude.ai/code/session_01EPTqaHBB9hCJgYiHcDySQe, candidate 5.
- Suspected cause at filing time:
  - `RawDefinition.Decompose` counts `* ? C O` as expressible, so no discard warning shows: (`src/Frontend/AHKFlowApp.UI.Blazor/Helpers/RawDefinition.cs:36`, "private static readonly HashSet<string> ExpressibleOptions =").
  - `RawDecomposition` carries no values for those Options.
  - The dialog then sets them back to defaults: (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor:476`, "Item.IsCaseSensitive = false;").
- The only dialog test for this switch, `KindToggle_RawToText_DecomposesDefinitionIntoFields`,
  uses a definition with no Options. It asserts Kind, Trigger, and Replacement only, so it
  never reads the four Option fields and cannot see this defect.

### Root cause, confirmed at Pickup

The suspected cause is correct, and it has two halves.

1. `Decompose` drops the four Options on the floor. It splits the Option tokens into
   expressible and unexpressible, and then keeps only the unexpressible ones:
   (`src/Frontend/AHKFlowApp.UI.Blazor/Helpers/RawDefinition.cs:142`, "List<string> unexpressible = ").
   `RawDecomposition` has no field that could carry the values of `*`, `?`, `C`, and `O`.
2. The dialog writes the four fields back to the new-item defaults of `HotstringEditModel`,
   whatever the Raw definition said:
   (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor:479`, "Item.IsTriggerInsideWord = true;").

The correct mapping is already written down, in the other direction, in `Compose`:
(`src/Frontend/AHKFlowApp.UI.Blazor/Helpers/RawDefinition.cs:52`, "if (!isEndingCharacterRequired) options += ").
`Decompose` has to invert it.

### Reproduction at Pickup

Two bUnit tests were added to `HotstringEditDialogTests`, run, and then removed again, so the
Pickup commit carries no red test. Execute writes them back with the fix. Both failed:

```
KindToggle_RawToTextWithStarAndCaseOptions_KeepsThoseOptions
  Raw ":*C:btw::by the way" switched to Text
  Expected item.IsEndingCharacterRequired to be False because the Raw definition carried '*', but found True.

KindToggle_RawToTextWithoutInsideWordOption_LeavesTriggerInsideWordOff
  Raw "::btw::by the way" switched to Text
  Expected item.IsTriggerInsideWord to be False because the Raw definition carried no '?', but found True.
```

Command: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~KindToggle_RawToText"`
Result: `Failed! - Failed: 2, Passed: 1, Skipped: 0, Total: 3`

### Difficulty verdict at Pickup: moderate

- One production caller of `Decompose`, in the edit dialog. Nothing on the server reads it.
- Three source files change: the helper record, the `Decompose` method, and the dialog block.
- No API contract change, no database change, no new glossary term, no ADR.
- The correct mapping already exists in `Compose`, so no design work is needed to find it.
- One judgement call is left for the plan: what `Decompose` should do when a definition carries
  both `*` and `O`, which `Compose` never writes together.

- Spec: none — `moderate`, so the item goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-09-28-leaving-raw-keeps-hotstring-options-plan-161.md`
