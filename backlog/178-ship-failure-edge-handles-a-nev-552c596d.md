# 178 - Ship failure edge handles a never-tracked progress file

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 7-document

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

- [x] On a shipped branch whose `PLAN-PROGRESS.md` git never tracked, the failure edge out of Ship
      reopens the item at its target stage, with a progress file that holds the failure record.
- [x] When the failure edge out of Ship refuses for any reason about the progress file, the pull
      request is still ready and the item is still in `backlog/done/` at `9-ship`.
- [x] A test in the PowerShell suites covers a never-tracked progress file on the failure edge out
      of Ship, and fails when the edge refuses or leaves a half-done state.
- [x] The failure edge out of Ship on a branch whose progress file git did track still restores
      the file's last committed content, and an existing test proves it.
- [x] On a branch whose history holds another item's deleted `PLAN-PROGRESS.md`, the failure edge
      out of Ship writes none of that item's lines into this item's progress file.
- [x] When the failure edge out of Ship cannot push the branch's unpushed commits before it starts,
      the pull request is still ready and the item is still in `backlog/done/` at `9-ship`.

How each box was checked, at Document on 2026-10-14:

- Box 2 covers every refusal. `Get-ShippedProgressSource` makes all of them, and the edge calls it
  before the undo. The `$rf` case proves one of them. The `git restore` after the undo can still
  fail, but that is a failed write and not a refusal. The plan's `## Known limits` lists it.
- Box 4 holds byte for byte. Review round 1 found that the old read lost non-ASCII text and CRLF
  endings, so the edge now restores the file with `git restore`. The `$f5` case and a new
  byte-exact case prove it. A mutation that always starts a new file turns `$f5` red.

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
- Measured at Plan on 2026-10-14: in this repository the search never comes back empty. Every
  branch inherits other items' closure commits from `main`, and on this branch it found
  `a075257d chore: 151 close the records`. So on a real never-tracked branch the edge does not
  refuse. It restores another item's progress file, commits it, and exits 0. A fresh test fixture
  has no such history, which is why only the refusal was seen. The fifth criterion covers this.
- Found in plan grilling on 2026-10-14: the pre-flight push also runs after the undo. When that
  push is refused, the pull request is already a draft, and the refusal still says "Nothing was
  changed." The sixth criterion covers this.
- Depends on item 164's code. This worktree was created from `0f76c1e8`, before item 164 merged, so
  the branch must take `main` before Execute starts. Done in `24786c7b`.
- Spec: none — moderate, goes straight to Plan at pickup.
- Plan: `docs/superpowers/plans/2026-10-14-ship-failure-edge-never-tracked-progress-plan-178.md`
