# 164 - Ship closes records with no progress file

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 0-intake

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

- [ ] A Ship transition on a branch with no `PLAN-PROGRESS.md` ends with the item in
      `backlog/done/`, its Stage line reading `9-ship`, and one commit holding both changes.
- [ ] A Ship transition on a branch that has a `PLAN-PROGRESS.md` still deletes that file, and
      the same commit records the deletion.
- [ ] A Ship run that cannot make the closure commit leaves the worktree with no uncommitted
      move: the item is back in `backlog/` and its Stage line is unchanged.
- [ ] `tests/StageTransition.Tests.ps1` holds a case that turns red when the closure stages
      `backlog` and `PLAN-PROGRESS.md` in one `git add` call.

## Out of scope

- The failure edge out of Ship. It calls `Restore-ProgressFile` first, which either finds the
  file or restores it from the commit that deleted it, so the same path always exists by the time
  that call runs.
- Every other `git add` in the script. Only the two closure calls name a path that can be absent.

## Notes / dependencies

- Found while shipping item 162 on 2026-10-12. The run printed
  `fatal: pathspec 'PLAN-PROGRESS.md' did not match any files`, then
  `REFUSED: The closure commit failed.` The item had already moved to `backlog/done/` and already
  read `Stage: 9-ship`, both uncommitted. I finished that closure by hand in commit `5b9dadcf`.
- The failing call: (`scripts/take-stage-transition.ps1:445`, "add -A -- backlog PLAN-PROGRESS.md").
- The same shape in the failure path, which is out of scope above:
  (`scripts/take-stage-transition.ps1:502`, "add -A -- backlog PLAN-PROGRESS.md").
- Item 081 built this script, and item 159 extracted its shared spine.
- Spec: none - a two-file script fix needs no design document.
- Plan: <path, or "none - reason">
