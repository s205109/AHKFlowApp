# 137 - PowerShell worktree suites fail intermittently in CI

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (CI and test harness)
- **Difficulty**: moderate
- **Stage**: 5-simplify

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

`WorktreeSweepRemoteBase.Tests.ps1` waits only until a process marker path exists at
`tests/WorktreeSweepRemoteBase.Tests.ps1:491`. It then reads the marker and calls `.Trim()` at
`tests/WorktreeSweepRemoteBase.Tests.ps1:493`. The path can become visible before `Set-Content`
at `tests/WorktreeSweepRemoteBase.Tests.ps1:486` has made content readable. `Get-Content -Raw`
then returns `$null`, which produces the exact CI error.

`WorktreeRemoveHook.Tests.ps1` waits only until the worktree folder is gone at
`tests/WorktreeRemoveHook.Tests.ps1:545`. It reads the diagnostic file at
`tests/WorktreeRemoveHook.Tests.ps1:550` before it waits for the watcher outcome. The watcher
deletes the folder at `scripts/remove-worktree-local-dev.ps1:1292`, then keeps writing while it
prunes Git and deletes the branch. It does not finish diagnostics and write the outcome until
`scripts/remove-worktree-local-dev.ps1:1395-1401`. A concurrent raw read can return multiple
objects. PowerShell applies `-match` to each object, so line 551 passes `System.Object[]` to
`Assert-True`. That is the exact type and line reported by CI attempt 2.

The `feat-forced` branch error is expected. The fixture creates an unmerged branch at
`tests/WorktreeRemoveHook.Tests.ps1:540`. The watcher deliberately uses safe `git branch -d` at
`scripts/remove-worktree-local-dev.ps1:1320`, so Git preserves that branch. The branch refusal
was text captured during the premature diagnostic read. It did not cause the test failure.

The failed suites have unique GUID-based fixture paths and run in separate PowerShell processes.
Parallel disk and process contention changes timing. It exposes each suite's incomplete wait.

## Acceptance criteria

- [ ] A written statement of what makes a worktree suite fail under the parallel runner, with
      the `file:line` that shows it. "It is flaky" is not an answer.
- [ ] `WorktreeSweepRemoteBase.Tests.ps1` and `WorktreeRemoveHook.Tests.ps1` each pass 20 times
      in a row, on CI or on a machine that reproduces the failure, with the run numbers written
      into this item.
- [ ] Either the cause is fixed, or both suites carry a recorded limit the runner honours, such
      as `execution` set to `exclusive` in `tests/powershell-suites.json`, with the measured cost
      of that choice written here.
- [ ] The whole `powershell-suites` job passes 5 times in a row on one commit.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode PowerShell` still passes locally, and its run time is
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
