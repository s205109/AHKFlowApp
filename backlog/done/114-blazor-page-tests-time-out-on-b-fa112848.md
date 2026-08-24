# 114 - Blazor page tests time out on bUnit's one-second default

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Two bUnit page tests fail with `WaitForFailedException` on branches that cannot have caused it,
then pass on a plain re-run of the same commit. Nothing in this repository raises bUnit's default
`WaitForAssertion` timeout of one second, and neither test passes an explicit `TimeSpan`.

## User story

As a developer, I want the Blazor suite to fail only for a real defect, so that a red run always
means my change broke something.

## Detail

### The two tests

**`HotkeysPageTests.Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible`**, at
(`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs:465`, "public void Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible()").

```
Bunit.Extensions.WaitForHelpers.WaitForFailedException :
The assertion did not pass within the timeout period.
```

- CI run 32519664768 on commit 158ac0da — failed.
- CI run 32526741613 on commit 6d52f6f1 — failed.
- Re-run of the failed job only, same commit, no code change — passed.
- Locally: passes in 1 second, Release, `--no-build`.
- The branch it failed on touched six files: two PowerShell scripts, three Markdown files, one
  backlog rename. No C#, no Razor, no `.csproj`.

**`HotstringsPageTests.Page_WhileReloadIsInFlight_RendersLoadingIndicator`**, at
(`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs:85`, "cut.WaitForAssertion(() =>").

Same exception, same bUnit hint text, found on 2026-08-22 during backlog 112. That run reported:

```
Component render count: 491.
```

### Why the second test changes the diagnosis

The `HotkeysPageTests` failures were all in the `build-test` job's "Test with coverage" step, which
made coverage instrumentation the obvious suspect. The `HotstringsPageTests` failure was **local,
in `scripts/test-fast.ps1 -Mode Fast`, with no coverage at all**, on a branch that changed only
Markdown, PowerShell, and the private plans repository.

So coverage is an aggravating factor, not the cause. A one-second budget is thin enough to lose on
an ordinary loaded machine. 491 renders inside that budget is the number to weigh.

### Why these tests and not their neighbours

Worth checking rather than assuming. The hotkeys test does more between render and assertion than
most of the file:

```csharp
IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);   // renders, clicks, waits once already

cut.Find("input[data-test=\"ctrl-checkbox\"]").Change(false);
cut.Find("input[data-test=\"shift-checkbox\"]").Change(true);
cut.Find("input[data-test=\"win-checkbox\"]").Change(true);
cut.Find("button.commit-edit").Click();

cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(...));
```

Three `Change` calls, each triggering a re-render, then a click, then a wait on an NSubstitute call
count. `StartInlineEdit` at `HotkeysPageTests.cs:170` has already spent one wait getting the row
into edit mode. That is more renders before the assertion than most tests in the file, which fits a
timing margin rather than a logic error.

### There is no configured timeout anywhere

No `DefaultWaitTimeout` exists under `tests/`. All 54 waits in `HotkeysPageTests.cs` run on the
bUnit default. The failure text is bUnit's own wording for exactly this situation:

> If this test does not fail consistently, the reason may be that the wait timeout is too short,
> and the runtime did not have enough time to complete the necessary number of renders.

## Measurement

Taken on 2026-08-24 on this branch, on a 16-core Windows machine. Every run used `-c Release` with
`--collect:"XPlat Code Coverage" --settings coverlet.runsettings`, the same collection the
`build-test` job uses. A temporary probe wrapped each wait in a `Stopwatch`. The probe was removed
before the commit.

Under coverage, with no extra load, the whole-test durations that already cross one second:

```
HotkeysPageTests.Grid_GlobalHotkey_ShowsNoContextIcon                              1.211 s
HotkeysPageTests.Page_ClearFilters_ResetsSearchActionAndCategoryAndReloads         1.152 s
HotkeysPageTests.Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible  1.110 s
HotkeysPageTests.Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeUpdate  1.091 s
```

The waits inside those tests, however, are short. Left column is with no extra load. Right column
is the same run with 24 busy processes on 16 cores, where the suite still passed 954 of 954:

```
wait                                       idle ms   loaded ms
Hotstrings.ReloadInFlight.spinnerClears      297.0       937.0
Hotkeys.StartInlineEdit.editModeWait          78.0       224.9
Hotstrings.ReloadInFlight.initialLoad         52.5       180.4
Hotstrings.ReloadInFlight.spinnerAppears      21.1       178.1
Hotkeys.EditRow_WithModifiers.commitWait      36.5         8.7
```

Ten further loaded runs of both page classes passed, 92 tests each. Across those ten, the worst
`spinnerClears` was 509.4 ms and the worst `EditRow_WithModifiers.commitWait` was 52.2 ms.

What this says:

- `Page_WhileReloadIsInFlight_RendersLoadingIndicator` is the one test near the edge. Its third
  wait reached 937 ms, which is 63 ms short of the one-second default. No other wait passed 225 ms.
- `Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible` is not near the edge. Its wait
  finished in 8.7 ms to 52.2 ms in every observation. A slow wait does not explain its CI failure.
- That same test still reached 3.248 s in total under load, while its own wait took milliseconds.
  So the process stalls for seconds under contention, and a stall inside the one-second window
  fails a wait however cheap the wait is.

The hotkeys failure was not reproduced locally. If it returns after this change, the next step is
instrumentation inside that test, not a larger number.

## Acceptance criteria

- [x] The repository states a wait timeout for bUnit assertions rather than relying on the
      framework default, and a reader can find both the number and the reason for it
- [x] (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs:465`, "public void Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible()") and
      (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs:85`, "cut.WaitForAssertion(() =>") pass under
      `pwsh ./scripts/test-fast.ps1 -Mode Coverage`
- [x] This item records how long those two tests' waits actually take under coverage, so the chosen
      number is measured rather than guessed
- [x] If the fix raises a default for the whole suite, this item names which other tests were near
      the edge, measured, not assumed

## Fix

`tests/AHKFlowApp.UI.Blazor.Tests/BunitWaitTimeout.cs` sets `BunitContext.DefaultWaitTimeout` to 10
seconds from a `[ModuleInitializer]` method. The initializer runs once, before the first test, so no
test class has to opt in. The file's comment carries the measured numbers and the reason for 10
seconds.

The suite-wide default won over a stated timeout on each failing wait. A per-wait number claims
"this wait is slow". For the hotkeys test that claim is false, as the measurement above shows. The
real cause is a stall of the whole process, which can catch any wait in the suite.

`AHKFlowApp.UI.Blazor.Tests` is the only project that references bunit, so one file covers every
bUnit wait in the repository.

## Verification

- `tests/AHKFlowApp.UI.Blazor.Tests/BunitWaitTimeoutTests.cs` asserts that the timeout is set. It is
  the durable artifact. Without it, a module initializer that stops running would put the suite back
  on one second with no other signal.
- `pwsh ./scripts/test-fast.ps1 -Mode Fast` — 955 Blazor tests passed, and the whole slice passed.
- `pwsh ./scripts/test-fast.ps1 -Mode Coverage` — passed, all per-assembly coverage thresholds met.
- Ten runs of both page classes with 24 busy processes on 16 cores — 92 tests passed each time.

## Out of scope

- Retrying a failed test, and adding sleeps. Neither is a fix
- The `DevConfigTests` timeout in backlog 115. That one is FluentAssertions
  `CompleteWithinAsync(5s)`, not bUnit, and its subject is a fetch that never completes
- The behaviour of the pages under test. Nothing here suggests a product defect

## Notes / dependencies

- Precedent: `backlog/done/089-flaky-e2e-template-warning-test-times-out-in-ci.md` solved the same
  class of problem in the E2E suite. Read its fix before choosing an approach here
- Two routes, and the first is preferred. **One**: give each failing `WaitForAssertion` a stated
  timeout with a comment saying why. A named number a reader can judge beats a silent default.
  **Two**: raise the default once for the whole suite. Cleaner if other tests are near the edge as
  well, but a suite-wide raise hides the next slow test instead of surfacing it. Measure first
- Check whether other tests in either file have failed in CI recently. Several would mean a
  suite-wide default problem rather than two slow tests
- Check whether the `build-test` job's coverage settings changed recently, which would explain why
  this started when it did
- Not caused by a stale branch. The three recent Blazor flake-repair commits on `main` — d9594ea9,
  78bf453f, c5d6a60a — were already in the failing branch, and they touched
  `ShortcutWarningFlowTests`, `ShortcutWarning.razor`, and `KnownShortcutsPageTests`. None touched
  either file named here
- Not caused by pull request #334, which changed no compiled code
- Found during backlog 112, which could not file it: an agent cannot create a worktree from inside
  a worktree
- Spec: none — `moderate` goes straight to Plan
- Plan: `docs/superpowers/plans/2026-08-24-blazor-bunit-wait-timeout-plan-114.md`
