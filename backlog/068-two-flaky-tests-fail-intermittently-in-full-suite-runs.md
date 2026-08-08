# 068 - Two flaky tests fail intermittently in full-suite runs

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)

## Summary

Two tests failed once each on 2026-08-08, and both passed on a rerun with no code change between
the runs. A flaky test teaches everyone to rerun and move on, which is how a real failure gets
ignored. Both are now required-check territory: `powershell-suites` blocks merges on `main`, and
the pre-push hook already blocked a Markdown-only push over the second one.

## Evidence

### Flake A - `WorktreeRemoveHook.Tests.ps1`

Failed inside a full `scripts/run-powershell-suites.ps1` run. Exact message:

```
WorktreeRemoveHook.Tests.ps1: Cannot process argument transformation on parameter 'Condition'.
Cannot convert value "System.Object[]" to type "System.Boolean". Boolean parameters accept only
Boolean values and numbers, such as $True, $False, 1 or 0.
FAILED: WorktreeRemoveHook.Tests.ps1 (exit code 1)
```

`Condition` is the parameter of `Assert-True` at `tests/WorktreeRemoveHook.Tests.ps1:13-16`, typed
`[bool]`. Something passed it an array. Which call site did that is not pinned down yet, so the
first job is to reproduce and find it, not to guess.

The two calls that take a computed value rather than a direct `Test-Path` are
`tests/WorktreeRemoveHook.Tests.ps1:174` and `:237`. Both read `$removed`, which comes from
`Wait-ForCondition` at `:154-163`. That function returns `& $Condition`, so a script block that
writes more than one value to the pipeline would return an array. That is a lead, not a diagnosis.

Same-day evidence that it is not deterministic: the suite passed standalone in the worktree, passed
standalone in the main checkout, passed in a full main-checkout runner pass (17 suites), and passed
in two later full worktree runs (18 suites).

### Flake B - `KnownShortcutsPageTests.IgnoredUse_OffersRestore_AndCallsIt`

Failed during `pwsh .\scripts\test-fast.ps1 -Mode Fast`, run by the pre-push hook:

```
[xUnit.net 00:00:04.58]     AHKFlowApp.UI.Blazor.Tests.Pages.KnownShortcutsPageTests.IgnoredUse_OffersRestore_AndCallsIt [FAIL]
Failed!  - Failed: 1, Passed: 949, Skipped: 0, Total: 950
```

The test is at `tests/AHKFlowApp.UI.Blazor.Tests/Pages/KnownShortcutsPageTests.cs:131-143`. It
clicks a button, then asserts on the NSubstitute call straight away:

```csharp
Button(page, "restore-use", "windows.file-explorer", "Windows").Click();

_api.Received(1).RestoreAsync("windows.file-explorer", "Windows", Arg.Any<CancellationToken>());
```

The neighbouring test at `:146-159` does the same kind of check inside `page.WaitForAssertion(...)`.
That difference is the lead: an async click handler that has not finished when the assertion runs
would fail exactly this way, and only sometimes.

It passed alone with a filtered `dotnet test` run, and passed on a full rerun of the fast slice
(950 of 950).

## Acceptance criteria

- [ ] Each flake has a named root cause with `file:line` evidence, or a written record of what was
      ruled out and why it could not be reproduced
- [ ] `KnownShortcutsPageTests.IgnoredUse_OffersRestore_AndCallsIt` no longer races - the fix makes
      the assertion wait for the click handler rather than assuming it finished
- [ ] `WorktreeRemoveHook.Tests.ps1` cannot pass an array to `Assert-True`, and the fix names which
      call site did it
- [ ] Both are exercised repeatedly enough to give confidence - run each in its normal full-suite
      context several times in a row and record the results

## Out of scope

- A general retry or rerun-on-failure setting for the test runners. Hiding a flake is not fixing it.
- Any other test that has not actually failed. This item covers the two named above.

## Notes / dependencies

- Both flakes were seen on 2026-08-08 while finishing backlog item 067
  (`backlog/done/067-make-the-powershell-suites-ci-check-required-and-runnable-from-test-fast.md`)
- `powershell-suites` became a required status check on `main` the same day, so flake A can now block
  a merge
- Flake A is Windows-only in practice: the suite runs in the `powershell-suites` job on
  `windows-latest` (`.github/workflows/ci.yml:102-103`)
