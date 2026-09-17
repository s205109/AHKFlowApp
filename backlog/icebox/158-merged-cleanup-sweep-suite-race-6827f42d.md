# 158 - Merged cleanup sweep suite races under two concurrent runners

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (test harness)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

> **Iceboxed.** The failure is rare and nobody is blocked by it. It would become worth doing if
> this suite starts failing in CI, or if a second person loses time to it. Backlog 137 shows the
> cost of leaving this class alone: a red pull request teaches people to re-run the job.

## Summary

`tests/WorktreeMergedCleanupSweep.Tests.ps1` failed once under load from two concurrent suite
runners. The merge gate answered `False` for a branch that was merged, so the cleanup hook kept
a worktree the test expected it to remove. The root cause is not known.

## User story

As a developer reading a red suite run, I want a failure to mean my own change broke something,
so that I do not learn to re-run the runner until it turns green.

## Evidence

Observed 2026-09-17 on branch `feature/wt-one-machine-wide-lock-for-local-a189ab37` at commit
`977a706c`, while manually testing the backlog 146 Lane pool. Two checkouts of the same commit
each ran `run-powershell-suites.ps1 -Suite 'Worktree*'` at the same time, sharing one Lane pool
of capacity six.

The run that started second failed:

```
FAILED: WorktreeMergedCleanupSweep.Tests.ps1 (exit code 1)
  - The second worktree must be removed.
```

The assertion is (`tests/WorktreeMergedCleanupSweep.Tests.ps1:370`, "The second worktree must be removed. Stderr:").
It creates two merged worktrees, runs one sweep, and expects both to be removed. The hook
diagnostics show the two branches judged differently:

```
Hook merge gate: branch 'feat-outcome-one' merged into 'main' = True     -> removed
Hook merge gate: branch 'feat-outcome-two' merged into 'main' = False    -> kept
```

Both branches are created merged by the fixture, so both must report `True`. The hook then
refused to delete an apparently unmerged branch, which is correct behaviour given a wrong answer.

The same run also logged `cleanup: GitHub lookup unavailable (gh-failed); deciding on local
history only.` That fallback is by design, so it may be unrelated.

## What is already known

- **The same suite passed at the same moment in the other checkout.** Same commit, same code,
  running concurrently. One instance failed and one passed.
- It passed in two full five-step Gate runs on this commit, and in CI run `35227805333`.
- It passed when run alone, and passed again when two copies ran at the same time with nothing
  else on the machine. It does not reproduce without the full nineteen-suite load on both sides.
- This is the same class as `backlog/done/137-powershell-worktree-suites-fail-13b421fb.md`,
  "PowerShell worktree suites fail intermittently in CI". That item's root cause reads: the
  parallel runner "exposes each suite's incomplete wait". It fixed two suites,
  `WorktreeSweepRemoteBase.Tests.ps1` and `WorktreeRemoveHook.Tests.ps1`. This suite was not one
  of them, so this looks like a third instance in a suite 137 never touched.
- Backlog 146 predicted it. Its notes say: "Nothing failed in about 20 minutes of load across
  those runs. That does not close backlog 137."

## What is suspected, and not proven

The test runs two detached watchers against one fixture repository on purpose. A watcher prunes
git and deletes a branch in that repository while the other worktree's hook runs its merge gate
against the same repository. A git command that fails under that contention could be read as a
definite "not merged" rather than "cannot tell".

(`scripts/worktree-git.common.ps1:527`, "if ($LASTEXITCODE -ne 0) { return $false }") has that
shape. Nobody has shown that this line is the path taken. Treat it as a starting point for
instrumentation, not as the answer.

The backlog 146 Lane pool does not cause this. It lowers total load, because two runners share
six Lanes instead of taking six each. It does change when suites start: the second runner's
Workers queue for a Lane rather than starting at once, and the failure hit the run that was
queuing. Backlog 137 warns about exactly that, saying a schedule shift "could shift the parallel
schedule enough to expose a race that was always there".

## Acceptance criteria

- [ ] The merge gate tells "not merged" apart from "could not decide", and a git failure never
      reads as a definite "not merged".
- [ ] `tests/WorktreeMergedCleanupSweep.Tests.ps1` passes twenty consecutive times under the load
      that produced the failure: two checkouts of one commit running the full `Worktree*` set at
      the same time.
- [ ] The root cause is written down with `file:line` evidence, or the item records why it could
      not be found and what was ruled out.

## Out of scope

- The other worktree suites, unless the same root cause covers them.
- The backlog 146 Lane pool. It is not the cause.
- Making the worktree suites run one at a time. Backlog 137 kept them `parallel` at zero measured
  cost, and this item must not undo that without evidence.

## Notes / dependencies

- Related: `backlog/done/137-powershell-worktree-suites-fail-13b421fb.md` — same class, two other
  suites, already fixed.
- Reproducing it needs real load. A solo run and two concurrent solo runs both pass.
- Spec: none — a bug with an unknown cause. Investigate before designing anything.
- Plan: none — iceboxed at intake.
