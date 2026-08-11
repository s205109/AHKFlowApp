# 076 - Guard exception - commit to plans repo from worktree

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (agent git guard)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

A session running in a managed worktree cannot commit to the private plans repo at
`docs/superpowers/`. The guard refuses the write. So a review round that changes a plan
forces the session back to the main checkout. Add a narrow exception for that one path.

## User story

As an agent working in a worktree, I want to commit a plan change to the private plans
repo so that a review round does not force me out of the worktree.

## Acceptance criteria

- [ ] The guard allows `git -C <worktree>/docs/superpowers commit` from a managed worktree.
- [ ] The guard still refuses every write to the main checkout's working tree, index, and
      HEAD.
- [ ] The exception is scoped to the plans repo path. No other path gains a new right.
- [ ] `docs/agents/cross-agent-git-guardrails.md` records the exception and its reason.
- [ ] This item carries its own spec before implementation. It is `complex` enough to need
      one even though the change itself is small: the guard is a safety boundary.

## Out of scope

- Any change to the refusal of human commits on `main` — that is backlog 077.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P2)
  (private plans repo). Write a dedicated spec for this item before planning it.
- Dependency of backlog 072 (wave 2).
- The symlink layout is the reason the path is special: `docs/superpowers/` is a separate
  private repository linked into each worktree.
