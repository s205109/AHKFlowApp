# 060 - Merged-worktree cleanup deletes brand-new worktrees that have no commits

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — agent tooling only)

## Summary

You cannot hold two fresh worktrees at once. Creating the second one deletes the first.

`scripts/new-worktree.ps1:252` runs `scripts/cleanup-merged-worktrees.ps1` before it creates the
worktree. That sweep decides which worktrees are finished from
`git branch --merged main` (`scripts/cleanup-merged-worktrees.ps1:76`) and a lookup in the
resulting set (`:115`).

A worktree that was just created has no commits of its own. Its branch still points at the same
commit as `main`, so `git branch --merged main` lists it. The sweep reads it as finished work and
removes it.

`-ExcludePath` (`:105`) protects only the worktree this run is creating. It does not protect any
other empty worktree. So each new create deletes the previous unstarted one.

## How it was seen

Two worktrees were wanted at the same time, one for backlog 057 and one for backlog 053. Creating
057 was fine. Creating 053 printed:

> cleanup: removing merged worktree: ...\.claude\worktrees\downloads-save-failure [fix/wt-downloads-save-failure]

Recreating 057 then deleted 053 the same way. Only ever one of the two survived.

`git config --local ahkflow.worktreeCleanup` is `true` in this checkout, so the sweep runs without
asking.

## What it is not

This is not Claude Code's worktree integration. The string `cleanup: eligible merged worktree` comes
from `scripts/cleanup-merged-worktrees.ps1:283`, and the removal is spawned by that same script at
`:247`. The worktrees above were created by calling `scripts/new-worktree.ps1` directly from a
shell, with no Claude Code worktree tool involved.

## Acceptance criteria

- [x] A worktree whose branch has no commits of its own is never swept, whatever the cleanup
      setting says
- [x] Two freshly created worktrees can exist at the same time
- [x] A worktree whose branch really was merged into `main` is still swept, so the feature keeps
      working
- [x] A test in `tests/WorktreeMergedCleanup.Tests.ps1` covers the empty-branch case

## Out of scope

- The dirty-working-tree check at `scripts/cleanup-merged-worktrees.ps1:117`. It is correct and this
  item does not touch it
- The opt-in setting and its ask-once flow. The bug is in which worktrees are picked, not in whether
  the sweep is allowed to run
- Changing the default of `ahkflow.worktreeCleanup`

## Notes / dependencies

- Found while creating worktrees for backlog 057 and backlog 053

### Rejected approaches

- `git rev-list --count main..<branch>` returning 0, proposed here as the likely fix. That count is
  0 for a merged branch too, so it would have switched the sweep off completely
- Counting ref-log entries. An untouched worktree that ran `git merge --ff-only main` has two
  entries, exactly like finished work
- Matching ref-log subjects on their own. `GIT_REFLOG_ACTION` and `git update-ref -m` let a caller
  write a `commit:` subject for an operation that created no commit

### How it was fixed

- Removal now needs two independent signals: a `commit`-prefixed ref-log entry AND some commit the
  branch has pointed at being a non-first parent of a merge commit in `main`. Each covers the
  other's blind spot, and anything unproven keeps the worktree
- The second signal reads the branch's whole ref-log history. Checking only the current tip broke
  the third acceptance criterion: a finished worktree that ran `git merge --ff-only main` moved its
  tip onto the merge commit and stopped being swept
- Sweeping only branches with a merged pull request, the second option listed above, was not
  needed. The merge-commit shape gives the same evidence locally, with no network access
