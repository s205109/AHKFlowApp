# 164 - Ship closes records with no progress file

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 6-verify

## Summary

The Ship transition stages the closure with one `git add` call that names two paths. A branch
that never wrote `PLAN-PROGRESS.md` has only one of them, and git treats a path that matches
nothing as fatal. So the add stages nothing, the commit fails, and the run stops after it has
already moved the backlog item and written the Stage. The worktree is left half closed.

## User story

As an Owner shipping an item, I want the Ship transition to close the records on any branch, so
that a branch without a progress file does not need a repair by hand.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [x] A Ship transition on a branch with no `PLAN-PROGRESS.md` ends with the item in
      `backlog/done/`, its Stage line reading `9-ship`, and one commit holding both changes.
- [x] A Ship transition on a branch that has a `PLAN-PROGRESS.md` still deletes that file, and
      the same commit records the deletion.
- [x] A Ship run that cannot make the closure commit leaves the worktree with no uncommitted
      move: the item is back in `backlog/` and its Stage line is unchanged.
- [x] `tests/StageTransition.Tests.ps1` holds a case that turns red when the closure stages
      `backlog` and `PLAN-PROGRESS.md` in one `git add` call.

## Out of scope

- The failure edge out of Ship, with one case named below that this item leaves open. The edge
  keeps its own wide `git add`, because `Restore-ProgressFile` puts the file back before that
  line runs.
- A branch whose `PLAN-PROGRESS.md` git never tracked, once it has shipped. Ship deletes that
  file and records no deletion, because there is nothing for git to record. The failure edge then
  finds no commit to restore from and refuses, after it has already flipped the pull request to
  draft and moved the item out of `backlog/done/`. That is a half-done state. Before this item's
  fix such a branch could not Ship at all, so the state could not be reached. It needs its own
  item. Found in review round 3 on 2026-10-13.
- Every other `git add` in the script. Only the two closure calls name a path that can be absent.

## Notes / dependencies

- Found while shipping item 162 on 2026-10-12. The run printed
  `fatal: pathspec 'PLAN-PROGRESS.md' did not match any files`, then
  `REFUSED: The closure commit failed.` The item had already moved to `backlog/done/` and already
  read `Stage: 9-ship`, both uncommitted. I finished that closure by hand in commit `5b9dadcf`.
- The failing call, as it stood before this item's fix: (`scripts/take-stage-transition.ps1:445`, "add -A -- backlog PLAN-PROGRESS.md"). That line is gone now, so this records the tree as it was (citation-check:ignore)
- The same shape in the failure path, which is out of scope above:
  (`scripts/take-stage-transition.ps1:645`, "add -A -- backlog PLAN-PROGRESS.md").
- Item 081 built this script, and item 159 extracted its shared spine.
- Spec: none - a two-file script fix needs no design document.
- Plan: `docs/superpowers/plans/2026-10-12-ship-closes-records-with-no-progress-file-plan-164.md`
