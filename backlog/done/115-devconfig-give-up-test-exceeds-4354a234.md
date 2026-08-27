# 115 - DevConfig give-up test exceeds its five second completion budget

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

`DevConfigTests.AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns` fails under
load with `Expected task to complete within 5s`, then passes when run on its own. The test asserts
that a fetch which never completes is abandoned inside a five second budget, so the assertion and
the behaviour under test are measuring the same clock.

## User story

As a developer, I want the Blazor suite to fail only for a real defect, so that a red run always
means my change broke something.

## Detail

The failure, from `pwsh ./scripts/test-fast.ps1 -Mode Fast` on 2026-08-22:

```
Failed AHKFlowApp.UI.Blazor.Tests.Startup.DevConfigTests
       .AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns [5 s]
  Error Message:
   Expected task to complete within 5s.
  Stack Trace:
     at FluentAssertions.Specialized.NonGenericAsyncFunctionAssertions.CompleteWithinAsync(...)
     at ...DevConfigTests.AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns()
        in tests/AHKFlowApp.UI.Blazor.Tests/Startup/DevConfigTests.cs:line 42
```

The same run reported `Failed: 2, Passed: 952, Total: 954`. Re-running the two failures alone gave
`Passed: 2`, with no code change. The branch changed only Markdown, PowerShell, and the private
plans repository. No C#, no Razor, no `.csproj`.

### Why this is not backlog 114

Backlog 114 covers two bUnit `WaitForAssertion` timeouts that run on the framework's one-second
default. This one is different in every mechanical respect:

- The framework is FluentAssertions, not bUnit.
- The timeout is explicit â€” `CompleteWithinAsync(5s)` â€” not a silent default.
- The subject is a give-up path. The production code is supposed to abandon a hanging fetch, and
  the test measures how long that takes.

Same Epic, same symptom class, different root cause. They were found in the same run and split
deliberately.

### The question to answer first

Read (`tests/AHKFlowApp.UI.Blazor.Tests/Startup/DevConfigTests.cs:42`, "await act.Should().CompleteWithinAsync(TimeSpan.FromSeconds(5));") together with the give-up
timeout in the production code it exercises. If the code's own budget is at or near five seconds,
the assertion has no headroom at all, and any scheduling delay under load pushes it over. That
would make the test's budget wrong rather than the code slow.

Decide between three outcomes, with a measurement behind the choice:

1. The production give-up budget is close to five seconds. Raise the assertion's budget so it is
   comfortably above the code's, and say in a comment what it is measured against.
2. The production budget is much smaller and the gap is scheduling noise. Raise the assertion's
   budget and record the observed spread.
3. The give-up path is genuinely slow. That is a product defect, and this item becomes a fix rather
   than a test change.

## Evidence

All measurements from branch `fix/wt-devconfig-give-up-test-exceeds-4354a234` on 2026-08-27, on a
16-core Windows machine, built `-c Release`.

### The production give-up budget is 300 ms, not 5 s

The test overrides the production default with 150 ms per file, and `DevConfig` reads two files.
So the budget the test exercises is **300 ms**, against an assertion that allowed **5000 ms** —
about 16 times the budget. Outcome 1 in the list above is ruled out: there was plenty of headroom
on paper.

### Measured completion time

The test was temporarily changed to call the method directly and record `Stopwatch` elapsed time,
so a slow run reported its real number instead of stopping at five seconds.

| Condition | Elapsed (ms) |
|---|---|
| Test alone, five runs | 317, 324, 322, 339, 312 |
| Inside a full `-Mode Fast` run, three runs | 338, 374, 350 |
| With 24 busy CPU processes on 16 cores | 314 |
| With 16 blocked thread pool threads | 314 |
| With 32 blocked thread pool threads | 1537 |
| With 64 blocked thread pool threads | 2044 |

Whole-machine CPU load does **not** reproduce the failure. Blocked thread pool threads do.

### What that means

Outcome 2: the production budget is much smaller and the gap is scheduling delay. The give-up path
is not slow, so there is no product defect and no code fix to the behaviour.

But raising the assertion's budget, which outcome 2 proposed, is not the repair. The elapsed time
is set by how many pool threads are free, which no test controls. Blocking 64 threads drove the
same 300 ms budget to 2044 ms with no code change at all, and the recorded CI failure went past
5000 ms. Any number chosen for that assertion is a bet on the scheduler. This follows the rule
already set by `backlog/done/089-flaky-e2e-template-warning-test-times-out-in-ci.md`: "Fix the
cause. A longer timeout or a retry is not a fix."

### The fix

`DevConfig.AddCacheBustedDevConfigAsync` takes an optional `TimeProvider`, defaulting to
`TimeProvider.System`. Shipped behaviour is unchanged; the parameter is a seam so a test can drive
the give-up with `FakeTimeProvider`. The fake message handler moves that clock as each request
arrives, so the token is cancelled while `SendAsync` is still running and no real waiting happens.

After the change, under the same 64 blocked threads:

| Test | 0 blockers | 64 blockers |
|---|---|---|
| Fake clock (`WhenFetchNeverCompletes_GivesUpAndReturns`) | 1, 1, 1 ms | 0, 0, 0 ms |
| System clock (`WithNoClockGiven_StillGivesUpOnTheSystemClock`) | 309, 311, 312 ms | 1516, 1525, 1531 ms |

A first attempt advanced the clock from the test body, waiting for each request in a loop. Every
`await` in that loop needs a pool thread, and it measured 31.6 to 33.7 seconds under 64 blockers —
worse than the assertion it replaced. The probe caught it before commit.

### Verification runs

- `pwsh ./scripts/test-fast.ps1 -Mode Fast` — passed, nothing failed
- `pwsh ./scripts/test-fast.ps1 -Mode Coverage` — passed, nothing failed
- Twenty consecutive runs of `DevConfigTests` — 20 of 20 passed
- `dotnet format AHKFlowApp.slnx --verify-no-changes` — exit 0

## Acceptance criteria

- [x] This item records the production give-up budget and the measured completion time under load,
      so the chosen assertion budget is derived from both. Budget 300 ms; measured 312 ms alone,
      2044 ms with 64 blocked pool threads. The conclusion the numbers support is that no assertion
      budget is sound, so the wall clock was removed rather than raised
- [x] The test passes in a full `pwsh ./scripts/test-fast.ps1 -Mode Fast` run and under
      `-Mode Coverage`. Both run green. The cited line no longer exists: the
      `CompleteWithinAsync(5s)` assertion is gone, replaced by a fake clock
- [x] Satisfied by removing the thing it asks for, which needs saying plainly. There is no longer
      an assertion timeout measured against the production budget, because the give-up no longer
      waits on real time. What remains is a 30 second `HangGuard`, and its comment states that it
      is a guard against a hang and not a budget, so no reader can mistake it for one
- [x] The give-up path is not too slow. It completed in 312 to 339 ms against a 300 ms budget on an
      idle machine. No behaviour was changed; the only production edit is an optional `TimeProvider`
      parameter that defaults to `TimeProvider.System`

## Out of scope

- Retrying a failed test, and adding sleeps. Neither is a fix
- The two bUnit timeouts in backlog 114
- Changing what the give-up path does, unless outcome 3 above is what the measurement shows

## Notes / dependencies

- Precedent: `backlog/done/089-flaky-e2e-template-warning-test-times-out-in-ci.md` solved the same
  class of problem in the E2E suite
- Found during backlog 112, in the same run as backlog 114. Backlog 112 could not file either one:
  an agent cannot create a worktree from inside a worktree
- Spec: none â€” `moderate` goes straight to Plan
- Plan: `docs/superpowers/plans/2026-08-27-devconfig-give-up-test-budget-plan-115.md`
