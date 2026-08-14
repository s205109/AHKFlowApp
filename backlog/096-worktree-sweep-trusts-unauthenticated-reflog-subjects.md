# 096 - Worktree sweep trusts unauthenticated reflog subjects

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The merged-worktree sweep decides that a branch did its own work by reading reflog subjects. A
caller controls that text through `GIT_REFLOG_ACTION`, so an unstarted worktree can be made to look
finished. No commit is lost when that happens, but the worktree is removed.

## User story

As a contributor, I want the sweep to decide on facts nobody can rewrite, so that no worktree
disappears because of text a tool wrote into a ref log.

## Detail

`scripts/cleanup-merged-worktrees.ps1:118` documents three signals. Signal 1 reads reflog subjects
and signal 2 reads git history. Signal 3 asks whether any commit would be lost.

The reproduction, on git 2.55.0:

1. Create a worktree at `main^`, with no commits.
2. Run `git merge --ff-only <already-merged-branch>` with `GIT_REFLOG_ACTION=commit`.
3. The ref log reads `<merged-parent> commit: Fast-forward`.

Signal 1 accepts the subject. Signal 2 accepts the SHA, because that commit really is a non-first
parent of a merge commit on `main`. Signal 3 passes because the branch holds nothing. The probe
returns `True` and the worktree is eligible.

Nothing in git records which branch created a commit, so the current proof cannot separate this
from a genuine merged branch. That is why backlog 095 shipped the limit rather than a fix.

**What is actually at stake.** No commit is lost: signal 3 covers that, and
`tests/WorktreeMergedCleanup.Tests.ps1` pins it. The cost is an empty worktree removed under a
deliberately forged environment variable.

## Acceptance criteria

- [ ] The item states whether a stronger signal exists — for example a marker written by
      `new-worktree.ps1`, or reading the reflog of every other branch to see who created a SHA
- [ ] If a stronger signal exists, the sweep uses it and the forged fast-forward stops being
      eligible
- [ ] If no stronger signal exists, the limit is written where a reader meets it: the comment at
      `scripts/cleanup-merged-worktrees.ps1:118` and `.agents/worktrees/SKILL.md`
- [ ] A regression pins whichever answer wins

## Out of scope

- Signal 3, the no-loss check. It already holds and must keep holding
- Squash and patch-changing rebases. Backlog 095 records those as a separate limit

## Notes / dependencies

- Found in the second review round on backlog 095, pull request #310
- Backlog 094 and 095 both touch `Test-BranchOwnWorkWasMerged`. Read them first
- Spec: none — investigation first, no design yet
- Plan: none — investigation item, plan follows the answer
