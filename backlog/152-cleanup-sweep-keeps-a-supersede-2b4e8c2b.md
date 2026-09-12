# 152 - Cleanup sweep keeps a superseded reset without saying why

## Metadata

- **Epic**: Agent workflow
- **Type**: Fix
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The merged-worktree sweep kept `wt-backlog-housekeeping` after its branch merged, and wrote no
reason anywhere. Three defects caused or hid that: the merged check refuses a commit a `git reset`
dropped even when the same change later reached the base under a new SHA, the skip that refusal
takes writes no outcome line, and the removal script says `Kept:` when it kept nothing.

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
dropped (`scripts/worktree-git.common.ps1:526`, "rev-list $before --not $after"). That returns
`53e298f8`, which is in the stranded set, so the function returns false
(`scripts/worktree-git.common.ps1:400`, "if ($strandedSet.ContainsKey"). <!-- citation-check:ignore the fix replaced this line -->

`53e298f8` was not lost. It came back as `dcee707a`, which is on `main`. `git diff 53e298f8 dcee707a`
shows only the other commit on the branch, and that commit is on `main` too. The check compares by
SHA reachability, so it cannot see that the change returned under a new SHA.

Reachability is a deliberate choice, not an oversight. `git cherry` was used here before and was
removed because it normalizes whitespace, skips merge commits, and ignores author, message,
signature, and empty-commit intent
(`scripts/worktree-git.common.ps1:340`, "normalizes whitespace, it skips merge commits entirely").
A regression test holds that line
(`tests/WorktreeMergedCleanup.Tests.ps1:445`, "Content that differs only in whitespace must still count as discarded work.").
So whatever answers this item must not reintroduce patch-text comparison. Finding the safe rule is
the pickup's job; this item states the outcome only.

The sweep then takes the silent skip
(`scripts/cleanup-merged-worktrees.ps1:287`, "if (-not (Test-BranchOwnWorkWasMerged"). Three of the
four other refusal paths write a `Kept:` line through `Write-SweepOutcome`. The locked path runs
before the merged check
(`scripts/cleanup-merged-worktrees.ps1:126`, "Write-SweepOutcome -RepoRoot $RepoRoot").
The plan guard and the dirty check run after it. The merged-check skip writes nothing, so
`worktree-removal.log` held no record of the decision.

A second refusal path is silent in the same way. When `git status` itself fails, the sweep keeps the
worktree and writes only to stderr
(`scripts/cleanup-merged-worktrees.ps1:185`, "git -C $wtFull status --porcelain"). No outcome line
reaches the log there either.

The third defect showed up while clearing this up by hand. `remove-worktree-local-dev.ps1` run on a
folder that is already gone writes
(`scripts/remove-worktree-local-dev.ps1:815`, "Kept: the worktree folder does not exist."). <!-- citation-check:ignore the fix changed this string --> Nothing
was kept. `Kept:` is the prefix the sweep uses when it deliberately preserves a worktree, so a reader
of the log cannot tell a real refusal from "there was nothing here".

## Acceptance criteria

- [ ] The sweep removes a merged worktree whose branch reflog holds a `reset:` that dropped a commit
      the base later received, in the shape `chore/wt-backlog-housekeeping` had
      (`scripts/worktree-git.common.ps1:504`, "function Test-StrandedWorkWasSuperseded {")
- [ ] The sweep keeps a merged worktree whose branch reflog holds a `reset:` that dropped a commit
      the base never received
- [ ] The sweep keeps a merged worktree whose dropped commit differs from what the base holds only in
      whitespace, in being a merge commit, or in author, message, signature, or empty-commit intent
      (`tests/WorktreeMergedCleanup.Tests.ps1:445`, "Content that differs only in whitespace must still count as discarded work.")
- [ ] Every worktree the sweep declines to remove has exactly one line in `worktree-removal.log`
      saying why, including a merged-check refusal
      (`scripts/cleanup-merged-worktrees.ps1:146`, "$mergedVerdict = Get-BranchMergedVerdict")
- [ ] A worktree the sweep keeps because `git status` failed has a line in `worktree-removal.log`
      saying so (`scripts/cleanup-merged-worktrees.ps1:185`, "git -C $wtFull status --porcelain")
- [ ] The log line for a merged-check refusal names which of the five signals refused
      (`scripts/worktree-git.common.ps1:1060`, "function Get-BranchMergedVerdict {")
- [ ] `remove-worktree-local-dev.ps1` run on a folder that no longer exists writes an outcome line
      that does not start with `Kept:`, because it kept nothing
      (`scripts/remove-worktree-local-dev.ps1:817`, "Nothing to remove: the worktree folder does not exist.")

## Out of scope

- Reintroducing `git cherry` or any other patch-text comparison. It was removed on purpose and a
  regression test guards its removal.
- The other four signals in `Test-BranchOwnWorkWasMerged`. Only the dropped-commit signal changes.
- Removing `wt-backlog-housekeeping` itself. That is a one-time manual step, not this item's work.

## Notes / dependencies

- Found while asking why `wt-backlog-housekeeping` survived the sweep after pull request #405 merged.
- Verification artifact: `tests/WorktreeMergedCleanup.Tests.ps1`. Every criterion above is a scenario
  that file can build and assert, so no new suite is needed.
- The reporting gap made the diagnosis much slower than the fix. Ship the reporting criteria even if
  a safe rule for the dropped-commit signal turns out to be hard to find.
- Spec: none — the defects and the wanted behavior are named above.
- Plan: `docs/superpowers/plans/2026-09-12-cleanup-sweep-superseded-reset-plan-152.md`
