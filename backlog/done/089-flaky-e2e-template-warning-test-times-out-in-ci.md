# 089 - Flaky E2E template warning test times out in CI

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI

## Summary

`ShortcutWarningFlowTests.AHotkeyOnAKeyTheProfileHeaderUses_IsWarnedAbout` fails in CI without a
related code change, then passes on a plain re-run of the same commit. The test waits 30 seconds
for the template warning to appear in the hotkey dialog, and times out.

## User story

As a developer, I want the E2E suite to fail only for a real defect, so that a red CI run always
means my change broke something.

## Evidence

- Test: `tests/AHKFlowApp.E2E.Tests/ShortcutWarningFlowTests.cs:321`
- Failure: `System.TimeoutException : Timeout 30000ms exceeded.`
  Call log: `waiting for Locator(".hotkey-edit-dialog [data-test=\"template-warning\"]") to be visible`
- Run: <https://github.com/s205109/AHKFlowApp/actions/runs/31696017304> on commit `b7398e25`
  (PR #293). That PR changed only the guard script, the guard tests, the guard docs, and one
  backlog file. A re-run of the same commit passed with no code change.
- The test first saves a profile header, then opens the create dialog and binds `CapsLock`. The
  warning needs the saved header to reach the dialog. So the first places to look are the wait
  after the `Profile updated.` message, and any profile state shared between tests in the class.

## Root cause

A race in the UI, not in the test.

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor:356-366` — `OnInitializedAsync` sets
  `_profiles` only after four fetches return. The grid loads its rows from its own request, so a
  page whose rows arrive first re-renders with the Add button enabled and `_profiles` still empty.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor:698` and `:730` — both dialog openers copy
  `_profiles` into `DialogParameters`. A dialog keeps the copy it was given, so a dialog opened in
  that window holds an empty list for the rest of its life.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/ShortcutWarning.razor:250-266` — the
  template notice reads that list. No Profiles, no notice.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/ShortcutWarning.razor:104-127` — the
  component re-evaluates only when its `EvaluationKey` changes, and the key did not hold the
  Profile list. The grid's inline row hands over a live list, so that path went silent the same way.

CI evidence, run 31696017304 attempt 1, commit `b7398e25`: `GET /api/v1/hotkeys` returned at
`11:37:31.697`, `GET /api/v1/profiles` at `11:37:31.925`, and the test failed at `11:38:02.748`
after its 30 second wait. The click landed inside that 228 ms window.

## Acceptance criteria

- [x] Name the root cause with `file:line` evidence, not a guess. Say whether the cause is a race
      in the test, a race in the UI, or state shared between tests.
- [x] Fix the cause. A longer timeout or a retry is not a fix.
- [x] Show the test passing on 10 runs in a row of `ShortcutWarningFlowTests`. Ten local runs of
      `dotnet test tests/AHKFlowApp.E2E.Tests -c Release --filter FullyQualifiedName~ShortcutWarningFlowTests`
      passed, 12 tests each. PR #299 and its CI run 31702215783 carry the merged result.
- [x] Check the other tests in the class for the same pattern, and fix them in the same change.

## Out of scope

- A general CI retry policy for the E2E suite.
- Any change to the shortcut warning feature itself.

## Fix

- `Pages/Hotkeys.razor` holds the reference-data fetch in a field, and both dialog openers wait for
  it before they read `_profiles`. The click still works; the dialog opens once the list is there.
- `Components/Hotkeys/ShortcutWarning.razor` puts the templates it reads into its `EvaluationKey`,
  so a Profile list that arrives later re-evaluates instead of leaving a row that can never warn.

## Verification

- `tests/AHKFlowApp.E2E.Tests/ShortcutWarningFlowTests.cs` — new test
  `WhileTheProfileListIsStillLoading_TheCreateDialogStillWarns` holds the Profile list open and
  clicks Add at the first moment the page allows. It fails before the fix and passes after it.
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/ShortcutWarningTests.cs` — new tests for the
  list that arrives late and for an edit to a template the component already read.

## Notes / dependencies

- Verification artifact: the existing `*FlowTests.cs` E2E test, run with
  `pwsh .\scripts\test-fast.ps1 -Mode E2E`.
- Hotstrings page snapshots its Profile list the same way. No warning reads that list there, so it
  needs no change now.
