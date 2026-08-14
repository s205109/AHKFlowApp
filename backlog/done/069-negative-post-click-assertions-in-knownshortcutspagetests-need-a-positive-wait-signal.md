# 069 - Negative post-click assertions in KnownShortcutsPageTests need a positive wait signal

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Stage**: 9-ship

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

## Findings

### The fix is the awaited click, not a rendered signal

The item asked for a rendered state to wait on. There is a better answer, and it needs no guessing
per test.

bUnit ships an async twin of every event helper. `Bunit.EventHandlerDispatchExtensions.ClickAsync`
is documented as returning "A task that completes when the event handler is done"
(`~/.nuget/packages/bunit/2.7.2/lib/net10.0/bunit.xml:2614-2622`). The synchronous `Click()` at
`:2606-2613` has no `<returns>` at all — that is the whole difference, and it is the bug backlog 068
named.

So each negative assertion now awaits the click. When the await returns, the page handler has run to
the end, so anything it was going to call it has already called. That is a stronger signal than any
rendered state, and it is what the cancelled-delete path needs: that path renders nothing at all, so
no rendered signal exists to wait for.

The two negative tests became `async Task`. `PerformMutation` became `PerformMutationAsync` and
returns the click task, so both mutation theories await it.

One wart is recorded in a comment at the call site. `DidNotReceive().DeleteAsync(...)` returns a
null task, and inside an `async` method that raises CS4014, which this repository builds as an
error. The result is discarded with `_ =`.

`OpenAddForm` keeps its existing `WaitForElement` and stays synchronous. `StartAdd` is a plain
synchronous handler at `KnownShortcuts.razor:279-284`, so the form appearing already proves the
click was handled.

### The premise was slightly too strong

The item says the negative assertions "cannot fail". On an idle machine they can, and they did. With
the delete confirmation guard removed on purpose, the old synchronous form failed. So these
assertions were timing-dependent, not dead.

A probe pinned the real hole down. The failing API call was stubbed with a genuinely asynchronous
task (`await Task.Delay(50)`), which is the condition a loaded machine produces: the handler
suspends, so `Click()` returns while the rest of the handler is still to come. Two tests then ran
against the same page, broken so that a server-answered failure invalidates the dialog cache:

```
ProbeNegativeAssertionsTests.NewForm_AwaitedClick_CatchesTheBrokenPage [FAIL]
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive no calls matching:
	Invalidate()
Actually received 1 matching call:
	Invalidate()
Failed!  - Failed: 1, Passed: 1, Skipped: 0, Total: 2
```

The one that passed is `OldForm_SyncClick_MissesTheBrokenPage`. Same broken page, same assertion,
blind. That is the hole this item closes. The probe was temporary and is not in the branch.

### Mutation experiments

Each assertion was shown to fail against a page broken on purpose. All against Release builds of
`tests/AHKFlowApp.UI.Blazor.Tests`.

**1. `Delete_WhenTheConfirmationIsCancelled_RemovesNothing`.** Removed `if (confirmed != true)
return;` from `DeleteAsync`, so a cancelled dialog deletes anyway.

```
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive no calls matching:
	DeleteAsync(any Guid, any CancellationToken)
Actually received 1 matching call:
	DeleteAsync(7b718890-63d7-4327-b0ee-ecf19903bc16, System.Threading.CancellationToken)
   at ...KnownShortcutsPageTests.Delete_WhenTheConfirmationIsCancelled_RemovesNothing() ... line 411
Failed!  - Failed: 1, Passed: 0, Skipped: 0, Total: 1
```

**2. `AFailedMutation_DoesNotInvalidateTheDialogCache`, the ignore, restore and delete cases.** Moved
`Catalog.Invalidate()` in `AfterMutationAsync` outside the `ApiResultStatus.NetworkError` check, so
a server-answered failure throws the cache away.

```
AFailedMutation_DoesNotInvalidateTheDialogCache(mutation: "restore") [FAIL]
AFailedMutation_DoesNotInvalidateTheDialogCache(mutation: "delete") [FAIL]
AFailedMutation_DoesNotInvalidateTheDialogCache(mutation: "ignore") [FAIL]
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive no calls matching:
	Invalidate()
Actually received 1 matching call:
	Invalidate()
Failed!  - Failed: 3, Passed: 1, Skipped: 0, Total: 4
```

The create case passed, and that is correct. Create never reaches `AfterMutationAsync`; it has its
own failure branch in `CommitAddAsync`. So it needed its own mutation.

**3. Same theory, the create case.** Added `Catalog.Invalidate()` to the failure branch of
`CommitAddAsync`.

```
AFailedMutation_DoesNotInvalidateTheDialogCache(mutation: "create") [FAIL]
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive no calls matching:
	Invalidate()
Actually received 1 matching call:
	Invalidate()
Failed!  - Failed: 1, Passed: 3, Skipped: 0, Total: 4
```

**4. `SignedOut_SaysSo_AndReadsNothing`.** Removed the `if (_isAuthenticated)` check in
`OnInitializedAsync`, so the page reads while signed out.

```
SignedOut_SaysSo_AndReadsNothing [FAIL]
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive no calls matching:
	ListManagedAsync(any CancellationToken)
Actually received 1 matching call:
	ListManagedAsync(System.Threading.CancellationToken)
Failed!  - Failed: 1, Passed: 0, Skipped: 0, Total: 1
```

### `SignedOut_SaysSo_AndReadsNothing` is ruled out, and here is why

It is left unchanged, and a comment on the test now says so.

There is no click, and nothing is ever queued. The page reads inside `if (_isAuthenticated)` at
`KnownShortcuts.razor:215-216`, and the state cascaded into this test is anonymous, so that branch
is never taken on any timeline. On top of that, `AnonymousState` is an already-completed
`Task.FromResult`, so `OnInitializedAsync` runs straight through and finishes before `Render`
returns.

Mutation experiment 4 above is what proves the assertion still has teeth. Nothing to wait for, and
nothing to fix.

### Verification

Whole `AHKFlowApp.UI.Blazor.Tests` project, Release:

```
Passed!  - Failed: 0, Passed: 950, Skipped: 0, Total: 950
```

`dotnet format AHKFlowApp.slnx --verify-no-changes` reports no changes.

**Confidence runs.** Against the Release assembly built from the final test file, the project ran 50
times. All 50 passed, 950 of 950 tests each time. An earlier batch was stopped part-way and thrown
away, because the test file changed again afterwards. Only runs made against the final build count.

Read those runs the way backlog 068 asks. These tests were never seen failing in the wild, so clean
runs say little on their own. The argument here is the mutation experiments plus the probe: the old
form was shown blind to a real regression, and the new form was shown to catch it.

## Acceptance criteria

- [x] Each named test waits for a positive signal before it asserts the negative — the awaited click
      is the signal, and it is exact rather than a proxy for the handler finishing
- [x] Each chosen signal is written down in a comment, saying what it proves the page has finished
- [x] Each changed test is shown to fail when the behavior it guards is broken on purpose, and the
      failure output is recorded
- [x] `SignedOut_SaysSo_AndReadsNothing` is either changed or explicitly ruled out, with the reason

## Out of scope

- The positive assertions in the same file. Backlog 068 already changed those.
- Any change to `KnownShortcuts.razor` itself. The page is not at fault.

## Notes / dependencies

- Split out of `backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md` on
  2026-08-08, during review of the fix for that item. Item 068 moved to `blocked/` on 2026-08-10
- bUnit `WaitForAssertion` behavior: https://bunit.dev/docs/verification/async-assertion.html
- bUnit version is pinned at `Directory.Packages.props:13`
