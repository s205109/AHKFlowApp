# 076 - Guard exception - write to plans repo from worktree

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

The title still says "write to plans repo" rather than "commit" for the same reason. The
original title named the disproven mechanism.

## User story

As an agent working in a worktree, I want to edit a plan or spec in place so that a review
round does not force me out of the worktree for every artifact change.

## Acceptance criteria

- [ ] A worktree session whose writes this repository's guard adjudicates can create and
      edit files under `<main>/docs/superpowers/`. That is every agent's shell writes, and
      Claude `Edit`/`Write`/`NotebookEdit` **outside** a `-w` session. In a `-w` session
      Claude Code's own isolation refuses first and this change cannot affect it
      (`docs/agents/cross-agent-git-guardrails.md:338-352`).
- [ ] `<main>/docs/superpowers-decoy/` and any other sibling whose name merely starts the
      same way is still refused. `StartsWith($plansRoot + '\')` is what makes this pass,
      matching the existing convention at `agent-worktree-guard.common.ps1:1893`.
- [ ] Every other write into the main checkout is still refused, including a sibling
      worktree's own files. A sibling's `docs/superpowers` link resolves to the same private
      repository, so it is allowed; that grants no access this exception does not already
      give. Symlinks are resolved before the predicate runs
      (`agent-worktree-guard.common.ps1:1696`), so the session's link, a sibling's link, and
      the direct path are one and the same target.
- [ ] Create, edit, move and delete are allowed for files and directories **inside** the
      plans repo. The rule at `docs/agents/cross-agent-git-guardrails.md:134-137` governs
      shell writes, moves and deletes together, so the exception cannot cover only some.
- [ ] The plans root itself is **not** writable. The allow requires a path strictly under
      `<plansRoot>\`, never equal to it: deleting or renaming that directory would break
      every worktree's link.
- [ ] The git rules are unchanged. No new git allowance is added, because none is needed.
- [ ] `AHKFLOW_ALLOW_MAIN=1` remains the only escape for everything else, and the
      destructive-command tier it cannot downgrade is untouched.
- [ ] `docs/agents/cross-agent-git-guardrails.md` records the exception and its reason.
- [ ] `tests/AgentWorktreeGuard.Tests.ps1` covers the allow case, the decoy case, the
      plans-root case, and a sibling worktree's own files; `pwsh .\scripts\test-fast.ps1
      -Mode PowerShell` is green.
- [ ] This item carries its own spec before implementation. That is why its Difficulty is
      `complex` and not `moderate`: only `complex` routes through Design, and the guard is a
      safety boundary even though the change itself is small.

## Out of scope

- Any change to the refusal of human commits on `main` — that is backlog 077.
- Claude Code's native `-w` isolation. It is upstream behaviour and wins over repository
  hooks; see `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`.

## Notes / dependencies

- **Dedicated spec:** `docs/superpowers/specs/2026-08-11-plans-repo-guard-exception-design.md`.
- Origin: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P2).
- Dependency of backlog 072 (wave 2).
- The symlink layout is the reason the path is special: `docs/superpowers/` is a separate
  private repository linked into each worktree.
- **Prior art:** `docs/superpowers/specs/2026-08-04-private-plans-repo-guard-design.md`
  solved the **git** half, for Codex only, and states that Claude and Copilot payload
  handling stays unchanged. It never covered file writes. This item is the write half and
  reopens nothing there.
- **Where the change goes:** `scripts/agents/agent-worktree-guard.common.ps1`, in
  `Test-AgentWriteTargetAllowed` (line 1730 at the time of writing). The removal-log
  exception a few lines below it is the precedent for one named path inside `main` staying
  writable. The same `$plansRoot` compare already exists at lines 1892 and 1961, where it
  selects the denial message; reuse that shape. No other function needs to change.
- **Why it is safe:** the public repository git-ignores `docs/superpowers`, so nothing
  written there can enter a public commit or change a tracked file. The worktree can
  already read through the symlink; only writing changes.
- **Base:** this branch is on `main` and already carries the item (`232a241c`). It was
  removed from the backlog-071 branch in `a3ec9a2c`, so do not use that branch as a base.
- `scripts/new-worktree.ps1:106` refuses nested worktree creation, so Pickup for this item
  runs from a main-checkout session.
