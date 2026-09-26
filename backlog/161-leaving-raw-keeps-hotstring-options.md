# 161 - Leaving Raw keeps hotstring Options

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

In the hotstring edit dialog, a switch from Raw to Text, Date & time, or Macro probably loses the
`*`, `?`, `C`, and `O` Options of the Raw definition without a warning. Found by reading the code,
not yet reproduced.

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
  uses a definition with no Options.
- First step at Pickup: reproduce it with a failing bUnit test, then set Difficulty.
- Spec: none — not picked up yet.
- Plan: none — not picked up yet.
