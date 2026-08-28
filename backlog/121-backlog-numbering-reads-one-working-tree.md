# 121 - Backlog numbering reads one working tree, so numbers collide

## Metadata

- **Epic**: Developer workflow
- **Type**: Fix
- **Interfaces**: none - repository tooling
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

`Get-NextBacklogNumber` picks the next number from the files in the current working tree. It cannot
see numbers claimed on other branches or worktrees. Two worktrees started close together pick the
same number, and nothing notices until both branches meet in `main`. CI then fails on a duplicate,
days after the number was chosen.

## User story

As a developer running several worktrees at once, I want a new backlog item to get a number nobody
else holds, so that CI does not fail on a duplicate long after I filed the item.

## Acceptance criteria

### Numbering reads every ref

- [ ] `Get-NextBacklogNumber` considers every backlog number reachable from any local or remote ref, not only the files in the working tree.
- [ ] Running `new-backlog-item.ps1` in two worktrees of the same repository, without either branch being pushed, produces two different numbers.
- [ ] Running the scaffold twice in one worktree, without committing in between, produces two different numbers.
- [ ] A test builds two refs that each claim the same next number, and asserts the function skips it.
- [ ] The function still returns a number in a repository that has no remote.
- [ ] The function still returns a number when a ref cannot be read, and says so, rather than failing the run.

### CI fails fast on repository invariants

- [ ] `ci.yml` runs the cheap repository-invariant checks in one job.
- [ ] Every other job in `ci.yml` names that job in `needs:`, so nothing expensive starts until the invariants pass.
- [ ] That job finishes in under two minutes on a normal pull request.
- [ ] A duplicate backlog number fails the run before the .NET build starts.
- [ ] The invariant job covers at least: backlog numbering, backlog plan pointers, stale open backlog items, citation freshness, and skill parity.

## Out of scope

- Renumbering items that already collided. Each one is repaired on its own branch.
- Changing how `run-powershell-suites.ps1` reports. It runs every suite after a failure on purpose, so one run lists every broken suite.
- Reserving a number at worktree creation time instead of at item creation time. That is a larger design change and belongs in its own item.

## Notes / dependencies

- The numbering function is (`scripts/backlog.common.ps1:274`, "function Get-NextBacklogNumber {").
- `ci.yml` has no `needs:` key at all today, so every job starts at once. A duplicate number is found
  only after the slowest job has been running for minutes.
- The suite runner discovers suites in name order and deliberately keeps going after a failure. That
  is correct for reporting, and this item does not change it.
- Measured on 2026-08-27: `BacklogNumbering.Tests.ps1` failed about 90 seconds into a
  `powershell-suites` job that then ran for a further 12 minutes, while `build-test` spent 8 minutes
  in parallel.
- One item was renumbered three times for this reason: filed as 117, changed to 118, then to 120.
  117 belongs to `fix/wt-removal-watcher-powershell-5`, 118 merged first from
  `feature/wt-pickup-enters-worktree`, and 119 belongs to
  `fix/wt-gate-runs-the-coverage-slice-on-b9c0664d`.
- Filing this very item hit the same defect twice: the scaffold ran three times in one worktree and
  handed out 119, 120 and 121, two of which were already taken elsewhere.
- Spec: none - the cause and both fixes are stated here.
- Plan: none - not yet planned.