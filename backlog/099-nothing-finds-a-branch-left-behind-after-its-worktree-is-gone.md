# 099 - Nothing finds a branch left behind after its worktree is gone

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

The removal watcher prunes the worktree before it deletes the branch, and it has a documented
outcome that stops between the two. No script finds what that leaves behind: a merged branch with
no worktree. Only a hand-written git check does.

## User story

As a contributor, I want one command to report every leftover from a removal, so that a partly
finished cleanup does not need a check I have to remember.

## Detail

The merged-worktree sweep enumerates `git worktree list`
(`scripts/cleanup-merged-worktrees.ps1:292`, "worktree list --porcelain"). A branch whose worktree
is already pruned appears nowhere in that list, so the sweep cannot see it.

The watcher prunes the worktree
(`scripts/remove-worktree-local-dev.ps1:916`, "'worktree', 'prune', '-v'") first and deletes the
branch (`scripts/remove-worktree-local-dev.ps1:922`, "'branch', '-d', '--', $branchName") second,
and logs (`scripts/remove-worktree-local-dev.ps1:997`, "worktree removed; branch preserved") when
it stops in between. That is the exact partial failure the deferred cleanup route exists for, and
the sweep is blind to it.

Stage 10 — Cleanup therefore hands the reader a hand-written check
(`docs/development/workflow.md:607`, "Branch still present, worktree already gone."): a local
branch other than `main`, merged into `main`, with no registered worktree, whose tip differs from
`main`'s tip. The tip comparison is what keeps it usable, because `git branch --merged main` alone
also lists every branch freshly cut from `main`.

## Acceptance criteria

- [ ] One command reports both leftovers: a worktree still present, and a branch present with its
      worktree already gone
- [ ] The branch check does not report a branch that was freshly cut from the base and has no
      commits of its own
- [ ] The branch check decides against the same base the sweep uses, so a merge that is only on
      the remote still counts (backlog 094)
- [ ] A fixture proves both leftovers and proves a clean repository reports nothing
- [ ] The Cleanup leftover check
      (`docs/development/workflow.md:607`, "Branch still present, worktree already gone.")
      names the command instead of the hand-written check

## Out of scope

- Deleting the leftover branch automatically. Reporting first; removal is a separate decision
- The removal watcher's own ordering. Prune-then-delete stays as it is

## Notes / dependencies

- Found while implementing backlog 094, which re-pointed the claim
  (`docs/development/workflow.md:615`, "Until backlog 099 scripts this")
- Backlog 073 covers cleanup experience
  (`backlog/073-process-wave-3-cleanup-ux.md:25`, "Worktree removal runs without opening a terminal window.")
  and does not cover this
- Spec: none — one report, no design yet
- Plan: `docs/superpowers/plans/2026-08-19-leftover-branch-after-worktree-gone-plan-099.md`
