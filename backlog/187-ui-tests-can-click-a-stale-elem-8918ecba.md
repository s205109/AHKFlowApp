# 187 - UI tests can click a stale element after a background render

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Difficulty**: to-be-determined
- **Stage**: 2-design

## Summary

Some bUnit tests take an element from `FindAll(...)` on the test thread and then fire an event on
it. `FindAll` returns a snapshot of the markup. When the component renders again between those two
steps, the snapshot still carries a handler ID that the renderer has removed, and the test fails
now and then. `Find(...)` is not exposed, because bUnit runs its selector again after every render.
Move every event on a `FindAll` element onto the renderer, in every UI test file.

## User story

As a developer pushing a branch, I want the UI tests to fire events only on the renderer, so
that a render I did not cause never fails an unrelated push.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] This item lists every UI component under test that can render without a test action, such
      as a debounced preview, a timer, or an async continuation. Each entry cites the source line
      that causes the render.
- [ ] In every UI test file, each event fired on an element taken from `FindAll(...)` runs inside
      `InvokeAsync`, together with that `FindAll` call. An event is `Click`, `Change`, `Input`, or
      any other bUnit event method, including its `Async` form.
- [ ] This item records a throwaway probe in `HotkeyEditDialogTests.cs`. After a background render,
      a 600 ms pause between the find and the click fails a `FindAll` element, and passes both a
      `Find` element and the `InvokeAsync` form.

## Out of scope

- `Find(...)` followed by an event. bUnit 2.7.2 wraps that element and runs the selector again
  after every render, and it reads the handler ID inside the renderer. The probe below shows that
  this form passes. Wrapping its roughly 240 calls would be churn, not a fix.
- `HotstringEditDialogTests.cs`. Commit `f07926c2` on `main` already wraps all of its events, for
  GitHub issue #446.
- `PreviewScheduler` waits with a real `Task.Delay`, not with the injected `TimeProvider`. That is
  why the race depends on wall-clock time. Changing it is production code, and a separate item.

## Evidence

- GitHub issue #446: `HotstringEditDialogTests.KindToggle_LeavingRaw_KeepsTheDefinitionsOptions`
  failed once in the pre-push fast slice with `UnknownEventHandlerIdException`.
- The cause in that file: a Raw item schedules a preview 400 ms after each render. When the preview
  returns, the dialog renders again on the renderer's synchronization context. A toggle taken from
  `FindAll` before that render carries the old handler ID.
- A throwaway mutation proved it. With a 600 ms pause between find and click, the bare form failed
  two of six theory cases on every run. The same pause inside `InvokeAsync` passed all six.
- bUnit 2.7.2 treats the two find methods differently. `Find` returns a wrapper, and the wrapper
  runs its CSS selector again after every render. That is `CssSelectorElementFactory` in the bUnit
  source at tag `v2.7.2`. `FindAll` returns a plain array of nodes that are never refreshed. bUnit
  reads the handler ID inside the renderer's dispatcher, so only a node that is out of date can
  carry a removed ID.
- A throwaway probe in `HotkeyEditDialogTests.cs` proved this on 2026-10-26. The probe typed into
  the description field, waited 600 ms, checked that the dialog had rendered again, and then
  clicked the `SendText` action toggle. Over three runs, the `FindAll` form failed every time with
  `UnknownEventHandlerIdException : There is no event handler with ID '66' associated with the
  'onclick' event in the current render tree.` The `Find` form and the `InvokeAsync` form passed
  every time.
- The hotkey edit dialog renders on its own through the MudBlazor text-field debounce, at
  (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor:81`, "DebounceInterval=")
  and on four more fields. Its `PreviewScheduler` adds no delay, at
  (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor:329`, "Debounce is TimeSpan.Zero here").
  All 52 bare events in its test file use `Find`. None use `FindAll`.
- On `main` at `eefd8142`, 10 bare events fire on a `FindAll` element, in 5 files:
  `HotkeyMobileListTests.cs` (2), `HotstringMobileListTests.cs` (2), `CliQuickstartCardTests.cs`
  (1), `ProfilesPageTests.cs` (4), and `KnownShortcutsPageTests.cs` (1). About 240 other bare events
  use `Find`, directly or through a helper.

## Notes / dependencies

- Design question: should a check keep new bare events out of exposed test files, or is a
  convention in the UI test docs enough?
- Spec: none — Design decides whether one is needed.
- Plan: none — not planned yet; Design comes first because Difficulty is to-be-determined.
