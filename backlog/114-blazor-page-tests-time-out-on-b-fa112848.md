# 114 - Blazor page tests time out on bUnit's one-second default

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

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

## Acceptance criteria

- [ ] The repository states a wait timeout for bUnit assertions rather than relying on the
      framework default, and a reader can find both the number and the reason for it
- [ ] (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs:465`, "public void Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible()") and
      (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs:85`, "cut.WaitForAssertion(() =>") pass under
      `pwsh ./scripts/test-fast.ps1 -Mode Coverage`
- [ ] This item records how long those two tests' waits actually take under coverage, so the chosen
      number is measured rather than guessed
- [ ] If the fix raises a default for the whole suite, this item names which other tests were near
      the edge, measured, not assumed

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
