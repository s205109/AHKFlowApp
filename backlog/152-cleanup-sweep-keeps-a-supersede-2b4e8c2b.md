# 152 - Cleanup sweep keeps a superseded reset without saying why

## Metadata

- **Epic**: Agent workflow
- **Type**: Fix
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The merged-worktree sweep kept `wt-backlog-housekeeping` after its branch merged, and wrote no
reason anywhere. Two separate defects caused that: the merged check refuses a commit a `git reset`
dropped even when the same change later reached the base under a new SHA, and the skip that refusal
takes writes no outcome line.

## User story

As a developer running `scripts/cleanup-merged-worktrees.ps1`, I want a merged worktree to be
removed when its work really is in the base, and I want every worktree the sweep keeps to say why,
so that I never have to read the script to find out what happened.

## Background

`chore/wt-backlog-housekeeping` merged as pull request #405, and the sweep still skipped it. The
branch ref log holds this sequence:

```
@{2} 7f139861 commit: chore: run the pre-push record checks before build and tests
@{3} 04e27a22 reset: moving to 04e27a22
@{4} 53e298f8 commit: chore: close 134 declined, file 150 for warm-up runs
```

`Test-StrandedWorkWasSuperseded` walks each `reset:` entry and asks git which commits the reset
dropped (`scripts/worktree-git.common.ps1:396`, "rev-list $before --not $after"). That returns
`53e298f8`, which is in the stranded set, so the function returns false
(`scripts/worktree-git.common.ps1:400`, "if ($strandedSet.ContainsKey").

`53e298f8` was not lost. It came back as `dcee707a`, which is on `main`. `git diff 53e298f8 dcee707a`
shows only the other commit on the branch, and that commit is on `main` too. The check compares by
SHA reachability, so it cannot see that the change returned under a new SHA.

The sweep then takes the silent skip
(`scripts/cleanup-merged-worktrees.ps1:143`, "if (-not (Test-BranchOwnWorkWasMerged"). The three
later skip paths each write a `Kept:` line through `Write-SweepOutcome`
(`scripts/cleanup-merged-worktrees.ps1:203`, "Write-SweepOutcome -RepoRoot $RepoRoot"). This one
writes nothing, so `worktree-removal.log` held no record of the decision.

## Acceptance criteria

- [ ] `Test-StrandedWorkWasSuperseded` accepts a dropped commit whose patch-id is already reachable
      from the base ref, and still refuses a dropped commit whose change reached no ref
      (`scripts/worktree-git.common.ps1:378`, "function Test-StrandedWorkWasSuperseded {")
- [ ] A Pester test builds a branch with a `reset:` that drops a commit later replayed onto the base
      under a new SHA, and asserts `Test-BranchOwnWorkWasMerged` returns `$true`
- [ ] A Pester test builds a branch with a `reset:` that drops a commit no ref holds, and asserts
      `Test-BranchOwnWorkWasMerged` returns `$false`
- [ ] The merged-check skip in `Invoke-MergedWorktreeCleanup` writes a `Kept:` line to
      `worktree-removal.log` naming the signal that refused
      (`scripts/cleanup-merged-worktrees.ps1:143`, "if (-not (Test-BranchOwnWorkWasMerged")
- [ ] `Test-BranchOwnWorkWasMerged` reports which signal refused, rather than a bare `$false`, so the
      sweep can name it
      (`scripts/worktree-git.common.ps1:944`, "return (Test-StrandedWorkWasSuperseded -RepoRoot")
- [ ] A Pester test asserts the sweep writes exactly one outcome line for a worktree the merged check
      refuses

## Out of scope

- The `git cherry` / patch-id comparison is for the dropped-commit path only. The other four signals
  in `Test-BranchOwnWorkWasMerged` keep their current rules.
- Removing `wt-backlog-housekeeping` itself. That is a one-time manual step, not this item's work.

## Notes / dependencies

- Found while asking why `wt-backlog-housekeeping` survived the sweep after pull request #405 merged.
- The reporting gap made the diagnosis much slower than the fix. Fix the reporting even if the
  patch-id change turns out to be harder than it looks.
- Spec: none — the defect and both fixes are named above.
- Plan: none — not started.
