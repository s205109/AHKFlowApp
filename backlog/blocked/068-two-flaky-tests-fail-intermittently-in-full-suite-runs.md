# 068 - Two flaky tests fail intermittently in full-suite runs

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Status**: Fixed by backlog 216. It closes when pull request #495 ships.
- **Stage**: 4-execute

## Fixed by backlog 216

Flake A failed again in CI run 43973543752 on 2026-11-16. The diagnostic fired, and it named
line 680 of `tests/WorktreeRemoveHook.Tests.ps1`. The cause and the fix are in
`backlog/216-suite-flake-worktreeremovehook-ae08ca07.md`. In short: the watcher still writes the
diagnostics log after the folder is gone, and `Get-Content -Raw` can return an array while another
process appends to the file. Backlog 216 reads every diagnostics log with one `ReadToEnd()` call
instead.

The failure on 2026-08-08 came before the diagnostic existed, so its line is still not known. The
same mechanism fits it, but no evidence names its line.

Flake B is fixed and merged.

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

## Findings

### Flake B - reproduced, cause named, fixed

The whole `AHKFlowApp.UI.Blazor.Tests` project was run in Release with `--no-build`, twice in a
row: 25 runs, then 40 runs. One run in each batch failed, always the same test and the same line.

```
KnownShortcutsPageTests.IgnoredUse_OffersRestore_AndCallsIt [FAIL]
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive exactly 1 call matching:
	RestoreAsync("windows.file-explorer", "Windows", any CancellationToken)
Actually received no matching calls.
   at ...KnownShortcutsPageTests.cs:line 143
```

Two things follow from that text. The restore button was found and clicked, because lines 140 and
141 ran without error. And the substitute had recorded **no** call at all, not a call with other
arguments.

One theory was ruled out by probe. A test stubbed `RestoreAsync` with a genuinely asynchronous
result (`await Task.Delay(50)`), clicked, and asserted `Received(1)` straight away on an idle
machine. It passed. `KnownShortcuts.razor:337` returns `RunMutationAsync(...)`, and
`RunMutationAsync` at `KnownShortcuts.razor:342-357` runs `await call()`, so the delegate is
invoked before the first suspension point. Slowness inside the API task cannot cause this failure.

What is left is the dispatch. In bUnit 2.7.2 the synchronous `Click()` discards the task its async
counterpart returns, and the event travels through the renderer's dispatcher. So the handler can
still be pending when `Click()` returns. `WaitForAssertion` runs the assertion immediately, then
again after each render, until it passes or the timeout expires.

The fix wraps that assertion, and every other assertion in the file that reads a **positive**
result after a click. The three assertions that read a **negative** after a click were left alone
on purpose and moved to `backlog/done/069-...`. `WaitForAssertion` passes on its first try, which is
exactly the moment a queued handler has not run, so it would make those tests look careful while
proving nothing.

Version pinned at `Directory.Packages.props:13`. bUnit documentation for the behavior:
https://bunit.dev/docs/verification/async-assertion.html

**Confidence runs.** After the last test change, and against a Release assembly rebuilt from it,
the whole `AHKFlowApp.UI.Blazor.Tests` project ran 50 times. All 50 passed, 950 of 950 tests each
time.

An earlier batch of 50 also passed, but review then changed the same file again, so that batch
described an older assembly. It is not counted. Only runs made after the final change count.

Read that honestly. At the observed rate of about 1 failure in 32 runs, 50 clean runs would happen
by luck roughly 20% of the time if nothing had been fixed. So the runs support the named mechanism.
They do not prove it on their own. The argument is the mechanism plus the runs, not the runs.

The 65 runs made **before** the fix are not counted here. They found the bug; they say nothing about
whether it is gone.

### Flake A - not reproduced, every lead ruled out

The suite ran 40 times standalone and passed every time. The full runner
(`scripts/run-powershell-suites.ps1`, 18 suites) ran 12 times with the diagnostic in place. All 12
passed and the diagnostic never fired.

Those numbers close nothing. A check that never triggers says nothing about a fault seen once.

The backlog's original lead is **wrong**. A probe ran `Wait-ForCondition` in isolation and printed
the returned type. It returns `System.Boolean` on the success path **and** on the timeout path. It
cannot return an array.

`Test-Path -LiteralPath` returns `System.Object[]` only when its path argument is already an array.
No path variable in this suite can become one:

- `New-TempGitRepo` and `Add-TestWorktree` send every command's output to `Out-Null`, and both end
  with `(Resolve-Path -LiteralPath ...).Path`, which is one string.
- All four `$log` reads use `Get-Content -Raw`, which returns one string for one file. So
  `$log -match ...` returns a `System.Boolean`, not an array of matches.
  Backlog 216 showed this is false while another process appends to the file.

So reading the code says the failure is impossible, and it still happened once. The call site is
**not identified**. Rather than guess, the fix removes the reason the call site stayed hidden. The
`Assert-True` parameter was typed `[bool]`, so an array argument failed during parameter binding,
and a binding failure reports no line number. The parameter is untyped now, with an explicit type
check that throws a message carrying the runtime type, the values, and the caller's line. The suite
still fails on a recurrence. It now says where.

A test covers that check, because a passing suite never reaches it. Putting the `[bool]` type back
makes the new test fail, and the failure quotes the original error word for word:

```
Expected the caller's line number in the message. Got: Cannot process argument transformation on
parameter 'Condition'. Cannot convert value "System.Object[]" to type "System.Boolean".
```

**`Wait-ForCondition` was left unchanged, on purpose.** A first draft made it return a scalar
boolean. That was speculative hardening for a function already ruled out, and it was also wrong:
the loop's `if (& $Condition)` treats any non-empty array as true, so normalizing only the timeout
path made one function answer the same script block two different ways. It was reverted.

## Acceptance criteria

- [x] Each flake has a named root cause with `file:line` evidence, or a written record of what was
      ruled out and why it could not be reproduced
- [x] `KnownShortcutsPageTests.IgnoredUse_OffersRestore_AndCallsIt` no longer races - the fix makes
      the assertion wait for the click handler rather than assuming it finished
- [x] `WorktreeRemoveHook.Tests.ps1` cannot pass an array to `Assert-True`, and the fix names which
      call site did it
      - The 2026-11-16 failure named line 680, the `Watcher spawned` check of the locked-helper
        case. Backlog 216 switched every diagnostics read that feeds a `-match` to `Read-LogText`,
        which returns one string. The 2026-08-08 line is still not known.
- [ ] Both are exercised repeatedly enough to give confidence - run each in its normal full-suite
      context several times in a row and record the results
      - Not met yet for flake A. Backlog 216 needs three counted full runs in a row, and it does
        not have them yet.
      - Backlog 216's new case failed first against `Get-Content -Raw`, which returned an array
        in 27 of 200 reads.
      - After the fix, the full `suites` job ran 8 times on revision d2adff12 (runs 11 to 18).
        All 75 suites passed each time, and the job exit code was 0.
      - Only runs 11, 14, 16 and 18 count. Runs 12, 13, 15 and 17 printed a "Sharing the test
        Lane pool" line, and the plan refuses any run with that line. A later check found the
        named records stale, but that check cannot show the lock was free during the run.
      - Flake B: see the 50 confidence runs in the Findings section.

Backlog 216 meets criterion 3 for the 2026-11-16 recurrence, and names line 680. The 2026-08-08
line stays unknown. Criterion 4 is met for flake B by the 50 runs above. It is not met yet for
flake A, because backlog 216 has no three counted full runs in a row.

## Out of scope

- A general retry or rerun-on-failure setting for the test runners. Hiding a flake is not fixing it.
- Any other test that has not actually failed. This item covers the two named above. The one
  exception is the rest of `KnownShortcutsPageTests.cs`: the assertions that read a positive result
  after a click share the proven mechanism, so they were fixed in the same pass.
- Negative assertions after a click. Moved to
  `backlog/done/069-negative-post-click-assertions-in-knownshortcutspagetests-need-a-positive-wait-signal.md`,
  and finished there.
- The other 15 PowerShell suites that define their own `Assert-True`. If the diagnostic proves
  useful, spreading it is separate work.

## Notes / dependencies

- Both flakes were seen on 2026-08-08 while finishing backlog item 067
  (`backlog/done/067-make-the-powershell-suites-ci-check-required-and-runnable-from-test-fast.md`)
- `powershell-suites` became a required status check on `main` the same day, so flake A can now block
  a merge
- Flake A is Windows-only in practice: the suite runs in the `powershell-suites` job on
  `windows-latest` (`.github/workflows/ci.yml:102-103`)
- Plan: `docs/superpowers/plans/2026-08-08-backlog-068-flaky-tests-plan.md`
