# 116 - Blazor tests use sleeps and wall clock instead of signals

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

Several Blazor tests wait on a fixed delay, a spin loop, or the real clock instead of a signal that
says the work finished. Each one can give a wrong result on a loaded machine, and two can fail on a
date boundary.

## User story

As a developer, I want the Blazor suite to fail only for a real defect, so that a red run always
means my change broke something.

## Where this came from

Review of pull request #349, which shipped backlog item 114. Item 114 raised bUnit's wait timeout
to 10 seconds, and that helps every `WaitForAssertion` call. It does not help the five patterns
below, because none of them waits on a render signal. They were out of scope for #349, which
touched no existing test.

## Detail

### 1. Fixed delays instead of a completion signal

- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`, lines 629,
  654, 678, 729, and 1075. Four are `await Task.Delay(150)` and one is `await Task.Delay(100)`.
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`, line 793,
  `await Task.Delay(150)`.

Under contention, the continuation can run after the delay ends. The test then reads the state from
before the work finished and reports a wrong result. Wait for the state, not for a duration.

### 2. Spin loop and an unsynchronised flag

`tests/AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs`, lines 84 to 101. A `bool
hotkeysStarted` is written on one thread and read by `SpinWait.SpinUntil` on another, with no
synchronisation, and the loop gives up after 250 ms.

Assert `_hotkeys.Received(1).ListDeletedAsync(...)` before releasing `hotstringsResult` instead. The
mock call count is the signal, and it needs no flag and no deadline.

### 3. Wall-clock polling loop

`tests/AHKFlowApp.UI.Blazor.Tests/Startup/StartupErrorRootTests.cs`, lines 55 to 59. The test polls
`nav.History` every 20 ms until a five-second deadline passes.

Use a `TaskCompletionSource` completed from `NavigationManager.LocationChanged`.

### 4. Tests that read the real clock

- `tests/AHKFlowApp.UI.Blazor.Tests/Validation/HotstringEditModelTests.cs`, lines 343 to 348.
  `SafePreview("d")` is compared with `DateTime.Now.ToString("%d")`. The two calls can land on
  different days.
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`, lines 288 to
  299. The rendered preview is compared with `DateTime.Now.Year`. The two can land in different
  years.

Both windows are small. Both are real, and a New Year failure is the worst possible time to debug a
test. Inject a fixed clock. `FakeTimeProvider` is already used elsewhere in this repository.

### 5. A wait that proves nothing

`WaitForAssertion(() => _api.DidNotReceive().DeleteAsync(...))` appears at:

- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/CategoriesPageTests.cs`, line 128
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`, line 591
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/ProfilesPageTests.cs`, line 162

`DidNotReceive` passes on the first check, so the wait returns at once and proves nothing about
whether the cancel path finished. Assert it plainly, and find a real signal for "the dialog
resolved" if the test needs one.

`ProfilesPageTests.Page_Delete_ConfirmCallsDeleteAsync` also carries a name that does not match what
it does. The name says confirm calls delete. The body asserts that delete was not called.

## Acceptance criteria

- [ ] No `Task.Delay` remains in `HotstringEditDialogTests.cs` or `HotkeyEditDialogTests.cs` as a
      way to wait for work to finish
- [ ] `RecycleBinPageTests.cs` proves the parallel start with a mock call count, and holds no
      cross-thread `bool` and no `SpinWait`
- [ ] `StartupErrorRootTests.cs` waits on a `NavigationManager.LocationChanged` signal, not on a
      deadline
- [ ] The two clock-reading tests pass with a fixed clock that is not the system clock
- [ ] The three `DidNotReceive` waits are plain assertions, and
      `ProfilesPageTests.Page_Delete_ConfirmCallsDeleteAsync` carries a name that matches its body
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode Fast` passes

## Out of scope

- The bUnit wait timeout. Backlog item 114 set it, and it is not what these five patterns depend on
- Any change to the pages and dialogs under test. Nothing here suggests a product defect

## Notes / dependencies

- Predecessor: `backlog/done/114-blazor-page-tests-time-out-on-b-fa112848.md`, and the review of
  pull request #349 that raised these five
- Precedent: `backlog/done/089-flaky-e2e-template-warning-test-times-out-in-ci.md` fixed the same
  class of problem in the E2E suite by finding the real signal
- Spec: none — `moderate` goes straight to Plan
- Plan: `docs/superpowers/plans/2026-08-27-blazor-tests-wait-on-signals-plan-116.md`
