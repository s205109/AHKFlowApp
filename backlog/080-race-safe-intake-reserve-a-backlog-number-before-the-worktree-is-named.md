# 080 - Race-safe Intake - reserve a backlog number before the worktree is named

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Filing a new tracked item needs its number before the worktree exists, but the script that
assigns the number only does so when it writes the file. Today that is resolved by hand:
the human files and commits the item on `main` first, then creates the worktree. An agent
cannot do that step, because it cannot commit on `main`.

## The circular dependency

- `scripts/new-worktree.ps1:221` throws without `-Name`, so the worktree name must be known
  before the worktree exists.
- The branch convention is `feature/wt-NNN-<topic>`, and the pre-PR discovery rule finds
  work by its number-prefixed worktree. Both need the number.
- `scripts/new-backlog-item.ps1:33` works out the next free number only as it writes the
  file, and it writes into the repository it runs in.
- So filing inside an already-named worktree needs a number nobody has assigned yet, and
  filing on `main` first needs a commit an agent may not make.

## User story

As an agent picking up new work, I want to reserve the next backlog number without
committing on `main`, so that I can name the worktree and file the item without a human
step in the middle.

## Acceptance criteria

- [ ] An agent can file a new tracked item and create its correctly named worktree without
      any human commit on `main`.
- [ ] The number is reserved atomically. Two sessions filing at the same moment never
      receive the same number.
- [ ] The reservation survives a session that dies before it files, or it expires cleanly.
      A reservation must never permanently consume a number.
- [ ] The branch name, the worktree directory name, and the item file all carry the same
      number.
- [ ] `docs/development/workflow.md` replaces its documented main-checkout route with the
      new one, and the "Where Intake writes the file" note shrinks accordingly.
- [ ] A test proves the concurrent case, not just the happy path.

## Out of scope

- Letting agents commit on `main`. That stays refused; see backlog 077.
- The plans-repo guard exception; that is backlog 076.

## Notes / dependencies

- Found by the second-round review of PR #288 (backlog 071 wave 1).
- `docs/development/workflow.md` documents the manual route under
  **Where Intake writes the file** and points here. Keep the two in step.
- A reservation scheme is not the only answer. Naming the worktree provisionally and
  renaming it after filing would also work, if the rename is safe for an open worktree.
