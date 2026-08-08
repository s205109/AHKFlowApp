# 069 - Negative post-click assertions in KnownShortcutsPageTests need a positive wait signal

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)

## Summary

Three tests click a button and then assert that something did **not** happen. If the click has not
been handled yet, the assertion passes for the wrong reason. It cannot fail, so it proves nothing.

This came out of backlog 068. That item fixed the assertions that read a **positive** result after a
click, by wrapping them in `page.WaitForAssertion(...)`. The negative ones were left alone on
purpose, because `WaitForAssertion` does not help them.

## Why WaitForAssertion is the wrong tool here

In bUnit 2.7.2 `WaitForAssertion` runs the assertion straight away, then again after each render,
and stops as soon as it passes. A negative assertion passes on the very first try. That first try
is exactly the moment when a queued click handler has not run yet. So wrapping it changes nothing
and hides the problem behind a call that looks careful.

Each test needs a **positive** signal to wait for first. That signal is some rendered state which
only appears once the click has been handled. Picking the right one differs per test, which is why
this is its own item rather than a line in backlog 068.

## The three tests

All in `tests/AHKFlowApp.UI.Blazor.Tests/Pages/KnownShortcutsPageTests.cs`:

- `Delete_WhenTheConfirmationIsCancelled_RemovesNothing` — asserts
  `_api.DidNotReceive().DeleteAsync(...)` after clicking delete.
- `AFailedMutation_DoesNotInvalidateTheDialogCache` — asserts `_catalog.DidNotReceive().Invalidate()`
  after each of four mutations.
- `SignedOut_SaysSo_AndReadsNothing` — asserts `_api.DidNotReceive().ListManagedAsync(...)`. This one
  has no click at all, so check whether it belongs here before changing it.

None of these has ever failed. This is a correctness problem in the tests, not a known flake.

## Acceptance criteria

- [ ] Each named test waits for a positive signal before it asserts the negative
- [ ] Each chosen signal is written down in a comment, saying what it proves the page has finished
- [ ] Each changed test is shown to fail when the behavior it guards is broken on purpose, and the
      failure output is recorded
- [ ] `SignedOut_SaysSo_AndReadsNothing` is either changed or explicitly ruled out, with the reason

## Out of scope

- The positive assertions in the same file. Backlog 068 already changed those.
- Any change to `KnownShortcuts.razor` itself. The page is not at fault.

## Notes / dependencies

- Split out of `backlog/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md` on
  2026-08-08, during review of the fix for that item
- bUnit `WaitForAssertion` behavior: https://bunit.dev/docs/verification/async-assertion.html
- bUnit version is pinned at `Directory.Packages.props:13`
