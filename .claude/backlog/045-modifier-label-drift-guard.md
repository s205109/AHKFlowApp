# 045 - Modifier label map can drift from the key registry

## Metadata

- **Epic**: Hotkeys
- **Type**: Tech debt
- **Interfaces**: UI

## Summary

`KnownShortcutWarning.s_modifierLabels` in the Blazor project hard-codes the modifier key names. The real list of modifier keys lives in `HotkeyKeys.cs` in the backend. Nothing checks that the two agree. So adding a modifier to the registry quietly stops the remap destination notice from warning about it.

## User story

As an owner, I want the remap destination notice to warn about every modifier key the app supports, so that adding a new modifier does not create a silent gap.

## Background

Item 044 added `KnownShortcutWarning.DestinationTextFor`. It reads a hard-coded map of 11 modifier names. Today that map matches `s_modifierKeys` in `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs` exactly.

The frontend cannot reference that constant. `tests/AHKFlowApp.UI.Blazor.Tests` references only the Blazor project and `AHKFlowApp.TestUtilities`, so a plain unit test cannot compare the two lists.

The frontend does receive the registry at runtime, through the key catalog endpoint. So the check has to run where both sides are reachable. That means an integration test or an E2E test, not a unit test.

## Acceptance criteria

- [ ] A test fails when the key registry gains a modifier the frontend label map does not cover
- [ ] The failure message names the missing key, so the fix is obvious
- [ ] The test lives where both the registry and the frontend map are reachable

## Out of scope

- Moving the label map to the backend, or serving the labels from the API. That is a larger design change, and this item only asks for a guard
- The wording of the labels themselves

## Notes / dependencies

- Map: `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/KnownShortcutWarning.cs`
- Registry: `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`
- Raised by the local review of item 044
