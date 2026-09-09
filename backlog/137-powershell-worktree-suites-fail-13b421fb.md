# 137 - PowerShell worktree suites fail intermittently in CI

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (CI and test harness)
- **Difficulty**: moderate
- **Stage**: 6-verify

## Summary

The `powershell-suites` CI job fails now and then, and a different worktree suite fails each
time. One commit passed on its first run and failed on the two runs after it. This item asks
what makes those suites unreliable under the parallel runner, and for a fix or a recorded limit.

## User story

As a developer reading a red pull request, I want a failure to mean my own change broke
something, so that I do not learn to re-run the job until it turns green.

## Evidence

Every run below is the branch `chore/wt-improve-net-test-speed-and-reliability`, on 2026-09-05.
The two failures sit on one commit and name different suites.

| Run | Commit | Result | Failing suite |
|---|---|---|---|
| 33988519704 | `05b490db` | pass | none |
| 33989354260 | `77b8654d` | fail | `WorktreeSweepRemoteBase.Tests.ps1` |
| 33989354260 re-run | `77b8654d` | fail | `WorktreeRemoveHook.Tests.ps1` |
| 33990116818 | `f2de1830` | pass | none |

The two failures read differently:

- `WorktreeSweepRemoteBase.Tests.ps1` ended with `You cannot call a method on a null-valued
  expression.` It named no failing case, so it died outside one.
- `WorktreeRemoveHook.Tests.ps1` ended after git refused a branch delete: `error: the branch
  'feat-forced' is not fully merged`, then `Branch was not deleted: feat-forced`.

Neither suite reads anything the commit between the pass and the failures changed. That commit
touched `scripts/test-results.common.ps1`, `scripts/measure-test-modes.ps1`,
`tests/MeasureTestModes.Tests.ps1`, one ADR, and `PLAN-PROGRESS.md`.

Both suites passed on Windows locally three times the same afternoon, once at 98.6 s and once
at 158.6 s.

## What is already suspected

Backlog 126 made the PowerShell suites run in parallel, and measured that the whole run took as
long as its slowest single suite, because the suites competed for the disk. Both failing suites
create and delete git worktrees under the temporary folder, which is the most disk-heavy work
the set does. The runner allows up to 8 workers. Both failed attempts used 4 workers.

One thing this item must not assume: that the branch under test was innocent. The same commit
added test cases that made `MeasureTestModes.Tests.ps1` slower, 22.3 s to 25 s, and gave it more
temporary-directory work. That could shift the parallel schedule enough to expose a race that
was always there. Nobody has evidence either way yet.

## Root cause

The parallel runner exposes two readiness races inside the suites. It does not make their
temporary paths overlap.

`WorktreeSweepRemoteBase.Tests.ps1` used to wait only until a process marker path existed. The
fixture now makes that race deterministic. It creates the empty marker
(`tests/WorktreeSweepRemoteBase.Tests.ps1:485`, "New-Item -ItemType File -Path"), then waits for
the parent-observation signal (`tests/WorktreeSweepRemoteBase.Tests.ps1:487`, "Test-Path -LiteralPath '$parentMarkerObserved'") before writing the PID
(`tests/WorktreeSweepRemoteBase.Tests.ps1:491`, "Set-Content -LiteralPath '$parentMarker'"). The
old path-only wait could read `$null` and call `.Trim()`, which produced the exact CI error. The
fixed wait reads the content (`tests/WorktreeSweepRemoteBase.Tests.ps1:498`, "$markerValue = Get-Content -Raw -LiteralPath $parentMarker -ErrorAction SilentlyContinue") and accepts only a
positive parsed PID (`tests/WorktreeSweepRemoteBase.Tests.ps1:500`, "[int]::TryParse([string] $markerValue, [ref] $candidateChildId)"). It signals that the empty marker was observed before
the child can continue (`tests/WorktreeSweepRemoteBase.Tests.ps1:505`, "Set-Content -LiteralPath $parentMarkerObserved -Value 'observed'").

The failure cleanup also stops both known process IDs
(`tests/WorktreeSweepRemoteBase.Tests.ps1:519`, "foreach ($id in @($parent.Id, $childId))"). An
early assertion can no longer leave the fixture child running until its own timeout.

`WorktreeRemoveHook.Tests.ps1` used to wait only until the worktree folder was gone
(`tests/WorktreeRemoveHook.Tests.ps1:545`, "$removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }"). It then read the diagnostic file without waiting for the watcher. The
fixed ordering waits for the outcome (`tests/WorktreeRemoveHook.Tests.ps1:549`, "$outcomeLines = @(Wait-ForOutcomeLine -RepoDir $repo)") before the raw diagnostic read
(`tests/WorktreeRemoveHook.Tests.ps1:556`, "$diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)"). The watcher deletes the folder
(`scripts/remove-worktree-local-dev.ps1:1292`, "Remove-Item -LiteralPath $tempName -Recurse -Force -ErrorAction Stop"), then prunes Git and deletes the branch
(`scripts/remove-worktree-local-dev.ps1:1320`, "$branchDelete = Invoke-GitCapture @('-C', $mainCheckout, 'branch', '-d', '--', $branchName)"). It writes its final diagnostic
(`scripts/remove-worktree-local-dev.ps1:1395`, "Write-DiagnosticLog 'Watcher done (worktree removed; branch preserved).'") before the outcome
(`scripts/remove-worktree-local-dev.ps1:1401`, "Write-Outcome 'Removed.'"). The premature read
produced the `System.Object[]` passed to `Assert-True` in CI attempt 2.

The `feat-forced` branch error is expected. The fixture creates an unmerged branch
(`tests/WorktreeRemoveHook.Tests.ps1:540`, "$wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-forced' -Unmerged"). The watcher deliberately uses safe `git branch -d`
(`scripts/remove-worktree-local-dev.ps1:1320`, "$branchDelete = Invoke-GitCapture @('-C', $mainCheckout, 'branch', '-d', '--', $branchName)"), so Git preserves that branch. The branch
refusal was text captured during the premature diagnostic read. It did not cause the failure.

The failed suites have unique GUID-based fixture paths and run in separate PowerShell processes.
Parallel disk and process contention changes timing. It exposes each suite's incomplete wait.

## Verification evidence

Both targeted suites passed under `pwsh` and Windows PowerShell 5.1 after the fix. Their
consecutive `pwsh` repetition runs were:

| Suite | Passing run numbers |
|---|---|
| `WorktreeSweepRemoteBase.Tests.ps1` | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 |
| `WorktreeRemoveHook.Tests.ps1` | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 |

The full local PowerShell slice passed all 56 suites in 206.865 seconds with six workers. The
starting observations were 98.6 seconds and 158.6 seconds. The change keeps both suites marked
`execution: "parallel"` in `tests/powershell-suites.json`. No serialization was introduced, so
its measured cost is zero.

The five-step local Gate passed. Build and format reported no errors. The coverage slice skipped
all five changed files under its test-only exclusions. `git diff --check main...HEAD` passed.

GitHub Actions run `34269850009` passed five consecutive attempts on verification commit
`774930b1d2aeabf1feddb437c226e28a6be037dd`:

| Attempt | `powershell-suites` job | Result |
|---|---|---|
| 1 | `102208987508` | pass |
| 2 | `102349931778` | pass |
| 3 | `102351861390` | pass |
| 4 | `102353998330` | pass |
| 5 | `102356110090` | pass |

Nothing else needs documentation. The change affects only the two test readiness conditions.

## Acceptance criteria

- [x] A written statement of what makes a worktree suite fail under the parallel runner, with
      the `file:line` that shows it. "It is flaky" is not an answer.
- [x] `WorktreeSweepRemoteBase.Tests.ps1` and `WorktreeRemoveHook.Tests.ps1` each pass 20 times
      in a row, on CI or on a machine that reproduces the failure, with the run numbers written
      into this item.
- [x] Either the cause is fixed, or both suites carry a recorded limit the runner honours, such
      as `execution` set to `exclusive` in `tests/powershell-suites.json`, with the measured cost
      of that choice written here.
- [x] The whole `powershell-suites` job passes 5 times in a row on one commit.
- [x] `pwsh ./scripts/test-fast.ps1 -Mode PowerShell` still passes locally, and its run time is
      written here beside the number this item started from.

## Out of scope

- Making the PowerShell suites faster. Backlog 126 owns that.
- The .NET test suites. Backlog 128 measured and improved those.
- Re-running a red job until it passes. That is the habit this item exists to remove.

## Notes / dependencies

- Found while addressing a review round on backlog 128, pull request #369. That branch is green
  now, and this failure is not its subject, so it was not fixed there.
- Related: backlog 126, which added the parallel suite runner and recorded the disk contention.
- Start by reading `scripts/run-powershell-suites.ps1` and `tests/powershell-suites.json`, then
  the two named suites.
- Spec: none — the root cause is bounded to two test readiness races.
- Plan: `docs/superpowers/plans/2026-09-08-powershell-worktree-suite-readiness-plan-137.md`
