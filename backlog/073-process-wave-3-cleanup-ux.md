# 073 - Process wave 3 - cleanup UX

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts)
- **Difficulty**: complex
- **Stage**: 1-pickup
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
- The sweep deletes the worktree folder directly today
  (`scripts/remove-worktree-local-dev.ps1`), so a git-level lock alone protects nothing.
  The lock must be read by the sweep itself.
- Target: cleanup popups and blocked runs drop to zero. That is a direction, not a
  percentage: backlog 072 has no established baseline yet.
