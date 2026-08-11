# 076 - Guard exception - commit to plans repo from worktree

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (agent git guard)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

A session running in a managed worktree cannot **edit** files in the private plans repo at
`docs/superpowers/`. So a review round that changes a plan forces the session back to the
main checkout. Add a narrow write exception for that one subtree.

**The commit is not the problem — measured, not assumed.** Probed on 2026-08-11 from the
`071-development-process` worktree:

| Operation | Result |
|---|---|
| `Edit` / `Write` into `docs/superpowers/...` | Denied, rule `agent-worktree-main-write` |
| `pwsh Set-Content` into the same path | Denied, same rule |
| `git -C <worktree>/docs/superpowers commit --dry-run --allow-empty` | **Allowed** |
| `git -C <main>/docs/superpowers commit --dry-run --allow-empty` | **Allowed** |

The git side already works because the guard gates commands that could change the
*protected checkout's* HEAD, index, or working tree, and the plans repo is a different
repository. This item's first draft claimed the commit was refused; that was written from
the spec's P2 description and never checked. Correcting it narrows the work to one
write-target predicate.

## User story

As an agent working in a worktree, I want to edit a plan or spec in place so that a review
round does not force me out of the worktree for every artifact change.

## Acceptance criteria

- [ ] A managed-worktree session can create and edit files anywhere under
      `<main>/docs/superpowers/`, through the worktree's symlink or the main path.
- [ ] `<main>/docs/superpowers-decoy/` and any other sibling whose name merely starts the
      same way is still refused. The prefix test must compare against the path plus a
      separator.
- [ ] Every other write into the main checkout is still refused, including a sibling
      worktree and that sibling's own `docs/superpowers` link.
- [ ] The git rules are unchanged. No new git allowance is added, because none is needed.
- [ ] `AHKFLOW_ALLOW_MAIN=1` remains the only escape for everything else, and the
      destructive-command tier it cannot downgrade is untouched.
- [ ] `docs/agents/cross-agent-git-guardrails.md` records the exception and its reason.
- [ ] `tests/powershell/AgentWorktreeGuard.Tests.ps1` covers the allow case, the decoy case,
      and the sibling case; `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` is green.
- [ ] This item carries its own spec before implementation. That is why its Difficulty is
      `complex` and not `moderate`: only `complex` routes through Design, and the guard is a
      safety boundary even though the change itself is small.

## Out of scope

- Any change to the refusal of human commits on `main` — that is backlog 077.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P2)
  (private plans repo). Write a dedicated spec for this item before planning it.
- Dependency of backlog 072 (wave 2).
- The symlink layout is the reason the path is special: `docs/superpowers/` is a separate
  private repository linked into each worktree.
- **Where the change goes:** `scripts/agents/agent-worktree-guard.common.ps1`, in
  `Test-AgentWriteTargetAllowed` (line 1730 at the time of writing). The removal-log
  exception a few lines below it is the precedent for one named path inside `main` staying
  writable. No other function needs to change.
- **Why it is safe:** the public repository git-ignores `docs/superpowers`, so nothing
  written there can enter a public commit or change a tracked file. The worktree can
  already read through the symlink; only writing changes.
- **Before pickup:** this item does not exist on `main` — it was filed on the backlog-071
  branch. A worktree based on `main` will not contain it until backlog 071 merges. Base the
  work on `main` anyway and let the item arrive with 071, or pass
  `-BaseRef feature/wt-071-development-process` to stack it.
- `scripts/new-worktree.ps1:106` refuses nested worktree creation, so Pickup for this item
  runs from a main-checkout session.
