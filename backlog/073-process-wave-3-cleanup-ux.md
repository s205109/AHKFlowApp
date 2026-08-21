# 073 - Process wave 3 - cleanup UX

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts)
- **Difficulty**: complex
- **Stage**: 2-design
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

Wave 3 of the development process. Cleanup is the stage that interrupts the human most
often: a terminal window opens, the log is hard to read, and a removal fails without
saying which process holds the folder. This wave fixes the cleanup experience.

## User story

As a contributor, I want worktree cleanup to run quietly and explain its own failures so
that a merged branch never leaves me a popup to dismiss.

## Acceptance criteria

- [ ] Worktree removal runs without opening a terminal window.
- [ ] The removal log is readable: one line per attempt, the outcome named in plain words.
- [ ] When a removal fails because a process holds the folder, the log names that process.
- [ ] A guard refuses to remove a worktree whose plan was never implemented, and says so.
- [ ] The merged-cleanup sweep honors `git worktree lock` and skips a locked worktree.

## Out of scope

- Parity check and drift guard — wave 2 (backlog 072).
- CI routing — wave 4 (backlog 074).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §13
  (private plans repo).
- Design: `docs/superpowers/specs/2026-08-21-cleanup-ux-design-073.md` (private plans repo).
- The sweep deletes the worktree folder directly today
  (`scripts/remove-worktree-local-dev.ps1`), so a git-level lock alone protects nothing.
  The lock must be read by the sweep itself. Proved on 2026-08-21 in a scratch repository:
  `git worktree remove` exits 128 on a locked worktree, and `[System.IO.Directory]::Move`
  on the same folder succeeds.
- Target: cleanup popups and blocked runs drop to zero. That is a direction, not a
  percentage: backlog 072 has no established baseline yet.

### Criterion 1 is already met

Backlog 088 shipped it. `New-HiddenProcessStartup` passes `ShowWindow = 0` to
`Win32_Process.Create`, and `tests/WorktreeWatcherWindow.Tests.ps1` covers it. This item
adds no code for that criterion; it runs that test and ticks the box with the output.

### Scope this design widens, deliberately

- The acceptance criterion names only the merged-cleanup sweep for `git worktree lock`. The
  detached watcher deletes folders the same way, so it honors the lock too. Fixing one of
  two identical holes would leave the hole open.
- The diagnostics file the log split creates is capped at 5 MB, keeping one old generation.
  No criterion asks for that. Replacing one file that grows forever with another one is not
  an improvement.
- `AHKFLOW_WORKTREE_FORCE_REMOVE=1` clears the new plan guard and does **not** clear a lock.
  A lock is aimed at one worktree by a human on purpose, and git itself demands
  `remove -f -f` for one.
