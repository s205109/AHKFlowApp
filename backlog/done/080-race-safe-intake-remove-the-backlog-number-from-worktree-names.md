# 080 - Race-safe Intake - remove the backlog number from worktree names

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Filing a new tracked backlog item needed its number before the worktree existed, but the
script that assigns the number only does so when it writes the file. Today that is resolved
by hand: the human files and commits the backlog item on `main` first, then creates the
worktree. An agent cannot do that step, because it cannot commit on `main`.

The number had to be known early for one reason only: the worktree directory and the branch
carried it. Nothing in `scripts/` or `.github/workflows/` parses it. So the fix is to take
the number out of those names, name the worktree from the title, and file the backlog item
inside the worktree, where `scripts/new-backlog-item.ps1` assigns the number as it writes the
file — exactly as it works today.

## The circular dependency, and where it is cut

- `scripts/new-worktree.ps1` throws without a name, so the worktree name must be known before
  the worktree exists.
- The old branch convention was `feature/wt-NNN-<topic>`, and the pre-PR discovery rule found
  work by its number-prefixed worktree. Both needed the number.
- `scripts/new-backlog-item.ps1` works out the next free number only as it writes the file,
  and it writes into the repository it runs in.
- The cut: the worktree name and the branch name no longer carry the number, so nothing needs
  it before the worktree exists.

## User story

As an agent picking up new work, I want to create the worktree and file the backlog item
inside it, so that there is no human step in the middle and no commit on `main`.

## Acceptance criteria

- [ ] An agent can file a new tracked backlog item and create its worktree without any human
      commit on `main`.
- [ ] No backlog number appears in a worktree directory name or a branch name.
- [ ] The worktree name and the backlog item file name are derived from one title through one
      slug rule, so they agree by construction.
- [ ] Two sessions filing at the same moment may take the same number. `Get-BacklogProblem`
      and the `powershell-suites` CI job catch it once the first branch merges and the second
      refreshes, and the repair renames one file, not a branch or a worktree.
- [ ] `docs/development/workflow.md` replaces its documented main-checkout route with the new
      one, and the "Where Intake writes the file" note shrinks accordingly.
- [ ] `scripts/new-worktree.ps1` keeps its PowerShell 5.1 floor.

## Out of scope

- Letting agents commit on `main`. That stays refused; see backlog 077.
- Reserving a number before the worktree exists. Tried, planned in full, and dropped as too
  large for what it buys. See the superseded plan for the three holes it carried.
- Preventing duplicate numbers outright. Two unmerged branches cannot see each other, so the
  duplicate check plus CI stays the net, exactly as it is today.
- Filing a backlog item from inside an unrelated worktree without mixing it into that
  worktree's pull request. Still open; see unresolved question 2.

## Notes / dependencies

- Found by the second-round review of PR #288 (backlog 071 wave 1).
- `docs/development/workflow.md` documents the route under **Where Intake writes the file**
  and points here. Keep the two in step.
- This worktree and its branch both carry `080` and keep it. The convention applies to new
  names; nothing parses the number, so an old name keeps working.
- Plan: `docs/superpowers/plans/2026-08-13-number-free-worktree-names-plan.md`
- Superseded plan: `docs/superpowers/plans/2026-08-13-race-safe-intake-plan.md`
