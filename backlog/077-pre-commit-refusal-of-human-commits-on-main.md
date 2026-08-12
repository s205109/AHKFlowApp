# 077 - Pre-commit refusal of human commits on main

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (git hooks)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

An agent cannot commit on `main`; the guard denies it outright. A human still can, and a
small fix committed straight to `main` skips the pull request gate. Extend
`.githooks/pre-commit` to refuse a commit on `main` unless the human sets an environment
variable.

## User story

As a maintainer, I want the pre-commit hook to stop me committing on `main` by accident so
that every change reaches `main` through a pull request.

## Acceptance criteria

- [ ] `.githooks/pre-commit` refuses a commit when the current branch is `main`.
- [ ] The refusal message names the escape: set `AHKFLOW_ALLOW_MAIN=1` for a deliberate
      commit.
- [ ] The refusal message names the normal route: the housekeeping worktree.
- [ ] `AHKFLOW_ALLOW_MAIN=1` lets the commit through.
- [ ] The agent-side denial is unchanged. It stays a hard denial with no prompt.
- [ ] This item carries its own spec before implementation. That is why its Difficulty is
      `complex` and not `moderate`: only `complex` routes through Design.

## Out of scope

- Any change to the agent git guard — that is backlog 076.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P5)
  (private plans repo). Write a dedicated spec for this item before planning it.
- Dependency of backlog 072 (wave 2).
