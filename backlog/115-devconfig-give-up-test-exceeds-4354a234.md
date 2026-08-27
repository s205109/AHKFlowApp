# 115 - DevConfig give-up test exceeds its five second completion budget

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

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
- The timeout is explicit — `CompleteWithinAsync(5s)` — not a silent default.
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

## Acceptance criteria

- [ ] This item records the production give-up budget and the measured completion time under load,
      so the chosen assertion budget is derived from both
- [ ] (`tests/AHKFlowApp.UI.Blazor.Tests/Startup/DevConfigTests.cs:42`, "await act.Should().CompleteWithinAsync(TimeSpan.FromSeconds(5));") passes in a full
      `pwsh ./scripts/test-fast.ps1 -Mode Fast` run and under `-Mode Coverage`
- [ ] The assertion's timeout is stated next to the production budget it is measured against, so a
      reader can see the headroom rather than infer it
- [ ] If the give-up path itself is too slow, the item says so and fixes the code, not the test

## Out of scope

- Retrying a failed test, and adding sleeps. Neither is a fix
- The two bUnit timeouts in backlog 114
- Changing what the give-up path does, unless outcome 3 above is what the measurement shows

## Notes / dependencies

- Precedent: `backlog/done/089-flaky-e2e-template-warning-test-times-out-in-ci.md` solved the same
  class of problem in the E2E suite
- Found during backlog 112, in the same run as backlog 114. Backlog 112 could not file either one:
  an agent cannot create a worktree from inside a worktree
- Spec: none — `moderate` goes straight to Plan
- Plan: `docs/superpowers/plans/2026-08-27-devconfig-give-up-test-budget-plan-115.md`
