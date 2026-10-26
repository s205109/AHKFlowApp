# 187 - UI tests can click a stale element after a background render

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Difficulty**: to-be-determined
- **Stage**: 2-design

## Summary

Some bUnit tests find an element on the test thread and then fire an event on it. When the
component renders again between those two steps, the event carries a handler ID that no longer
exists, and the test fails now and then. Find which UI tests are exposed to such a render, and
move their event calls onto the renderer.

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
- [ ] In the test file of every listed component, each `Find(...)` or `FindAll(...)` that is
      followed by `Click`, `Change`, or `Input` runs inside `InvokeAsync`, together with its event.
- [ ] This item records a throwaway mutation for `HotkeyEditDialogTests.cs`: a pause between the
      find and the event fails the old form and passes the new form.

## Out of scope

- Test files for components that never render without a test action. A bare event there cannot
  race, so changing it is churn, not a fix.
- `HotstringEditDialogTests.cs`. The housekeeping round on `chore/wt-backlog-housekeeping` already
  wraps all of its events, in the commit that fixes GitHub issue #446.
- `PreviewScheduler` waits with a real `Task.Delay`, not with the injected `TimeProvider`. That is
  why the race depends on wall-clock time. Changing it is production code, and a separate item.

## Evidence

- GitHub issue #446: `HotstringEditDialogTests.KindToggle_LeavingRaw_KeepsTheDefinitionsOptions`
  failed once in the pre-push fast slice with `UnknownEventHandlerIdException`.
- The cause in that file: a Raw item schedules a preview 400 ms after each render. When the preview
  returns, the dialog renders again on the renderer's synchronization context. A click found
  before that render carries the old handler ID.
- A throwaway mutation proved it. With a 600 ms pause between find and click, the bare form failed
  two of six theory cases on every run. The same pause inside `InvokeAsync` passed all six.
- On `main` at `b7a1953b`, 206 bare `Click`, `Change`, or `Input` calls remain in 18 UI test files.
  Bare calls alone do not prove a race. Only components that render in the background are exposed.
- The hotkey edit dialog uses the same `PreviewScheduler` as the hotstring dialog, at
  (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor:334`, "_preview = new PreviewScheduler"). Its test file holds 46 bare
  event calls, so it is the first candidate.

## Notes / dependencies

- Design question: should a check keep new bare events out of exposed test files, or is a
  convention in the UI test docs enough?
- Spec: none — Design decides whether one is needed.
- Plan: none — not planned yet; Design comes first because Difficulty is to-be-determined.
