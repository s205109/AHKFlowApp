# 178 - Ship failure edge handles a never-tracked progress file

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

The failure edge out of Ship leaves a half-done state on a branch whose `PLAN-PROGRESS.md` git
never tracked. It flips the pull request to draft and moves the item out of `backlog/done/`, and
only then does `Restore-ProgressFile` refuse, because no commit on the branch deleted the file.

## User story

As a maintainer, I want the failure edge out of Ship to work on every branch Ship can close, so
that sending shipped work back never leaves the pull request and the item half reopened.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] On a shipped branch whose `PLAN-PROGRESS.md` git never tracked, the failure edge out of Ship
      reopens the item at its target stage, with a progress file that holds the failure record.
- [ ] When the failure edge out of Ship refuses for any reason about the progress file, the pull
      request is still ready and the item is still in `backlog/done/` at `9-ship`.
- [ ] A test in the PowerShell suites covers a never-tracked progress file on the failure edge out
      of Ship, and fails when the edge refuses or leaves a half-done state.
- [ ] The failure edge out of Ship on a branch whose progress file git did track still restores
      the file's last committed content, and an existing test proves it.

## Out of scope

- The success edge into Ship. Item 164 fixed how Ship closes the records on a branch with no
  progress file.
- Every other `git add` in `scripts/take-stage-transition.ps1`.

## Notes / dependencies

- Found by plan review round 3 of item 164 on 2026-10-13, finding 3: "Confirmed, not fixed here".
  Item 164's `## Out of scope` section names the state and says "It needs its own item".
- Before item 164, a branch with a never-tracked progress file could not Ship at all, so this state
  could not be reached. Item 164 made it reachable.
- The order is the defect. `Invoke-ShipFailureTransition` runs `gh pr ready --undo` and moves the
  item out of `backlog/done/` before it calls `Restore-ProgressFile`. That function throws "no
  commit on this branch deleted it" when `git log --diff-filter=D` finds nothing.
- Depends on item 164's code. This worktree was created from `0f76c1e8`, before item 164 merged, so
  the branch must take `main` before Execute starts.
- Spec: none — moderate, goes straight to Plan at pickup.
- Plan: none — moderate work, goes straight to Plan at pickup.
