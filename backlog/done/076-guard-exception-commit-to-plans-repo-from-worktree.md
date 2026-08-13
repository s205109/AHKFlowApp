# 076 - Guard exception - write to plans repo from worktree

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (agent git guard)
- **Difficulty**: complex
- **Stage**: 9-ship

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
the spec's P2 description and never checked.

Correcting that does **not** narrow the work to a single predicate. The write-target
grammar reports only the destination of a move, so a destination-only exception would open
a way to delete a tracked file in main. See the move criterion below. The change is two
predicates: the subtree exception, and move-source classification.

The heading still says "write to plans repo" rather than "commit" for the same reason: the
original heading named the disproven mechanism. The filename keeps "commit" as well, and
for the same reason — renaming the file would break every link to this item and would erase
the record that the mechanism was disproven. The spec's filename keeps it too
(`docs/superpowers/specs/2026-08-11-plans-repo-guard-exception-design.md:8-9`).

## User story

As an agent working in a worktree, I want to edit a plan or spec in place so that a review
round does not force me out of the worktree for every artifact change.

## Acceptance criteria

- [x] A worktree session whose writes this repository's guard adjudicates can create and
      edit files under `<main>/docs/superpowers/`. That is the supported shell write commands
      from every agent, and Claude `Edit`/`Write`/`NotebookEdit` **outside** a `-w` session.
      The guard reads a denylist of write commands, so a writer outside that list — `del`,
      `python -c`, a compiled tool — was never adjudicated and still is not
      (`docs/agents/cross-agent-git-guardrails.md:333-335`). In a `-w` session Claude Code's
      own isolation refuses first and this change cannot affect it
      (`docs/agents/cross-agent-git-guardrails.md:338-352`).
- [x] `<main>/docs/superpowers-decoy/` and any other sibling whose name merely starts the
      same way is still refused. `StartsWith($plansRoot + '\')` is what makes this pass,
      matching the existing convention at `agent-worktree-guard.common.ps1:1893`.
- [x] Every other write into the main checkout is still refused, including a sibling
      worktree's own files. A sibling's `docs/superpowers` link resolves to the same private
      repository, so it is allowed; that grants no access this exception does not already
      give. Symlinks are resolved before the predicate runs
      (`agent-worktree-guard.common.ps1:1696`), so the session's link, a sibling's link, and
      the direct path are one and the same target. The two exceptions that already exist stay
      exactly as they are: the removal log by exact path, and the build-output path components
      (`agent-worktree-guard.common.ps1:1748-1757`).
- [x] Create, edit, move and delete are allowed for files and directories whose every
      endpoint is **inside** the plans repo. The rule at
      `docs/agents/cross-agent-git-guardrails.md:134-137` governs shell writes, moves and
      deletes together, so the exception cannot cover only some.
- [x] Delete inside the plans repo is allowed only as an ordinary classified delete. The
      destructive-command rules run before any location logic and no location rule can relax
      them (`agent-worktree-guard.common.ps1:221,246-254`), so `rm -rf` stays denied inside
      the plans repo just as it is everywhere else.
- [x] A move whose **source** is a main-checkout path outside the plans repo is still
      refused, even when its destination is inside the plans repo. Today the guard reports
      only a move's destination — `agent-worktree-guard.common.ps1:1430-1436` for `mv`,
      `:1457-1460` for `Move-Item` and `Rename-Item` — so a destination-only exception would
      allow `mv <main>\README.md <main>\docs\superpowers\README.md`, which deletes a tracked
      file in main. Probed on 2026-08-11: both commands report the destination and nothing
      else. `Get-AgentSegmentWriteTarget` must therefore report a move's source as a write
      target as well. `cp`, `install` and `ln` are unchanged, because they do not remove the
      source.
- [x] The wider denial that move-source classification creates is accepted and stated: a
      move out of the main checkout to any destination, a worktree included, becomes a
      denial. That is correct — the move deletes a path in main — and it matches the write
      grammar's own rule that a target list must be a superset
      (`agent-worktree-guard.common.ps1:1268-1271`).
- [x] The plans root itself is **not** writable. The allow requires a path strictly under
      `<plansRoot>\`, never equal to it: deleting or renaming that directory would break
      every worktree's link.
- [x] The git rules are unchanged. No new git allowance is added, because none is needed.
- [x] `AHKFLOW_ALLOW_MAIN=1` remains the only escape for everything else, and the
      destructive-command tier it cannot downgrade is untouched.
- [x] `docs/agents/cross-agent-git-guardrails.md` records the exception and its reason.
- [x] `tests/AgentWorktreeGuard.Tests.ps1` covers the allow case, the decoy case, the
      plans-root case, a sibling worktree's own files, a move inside the plans repo, a move
      from main into the plans repo, and `rm -rf` inside the plans repo; `pwsh
      .\scripts\test-fast.ps1 -Mode PowerShell` is green.
- [x] This item carries its own spec before implementation. That is why its Difficulty is
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
- **Prior art:** `docs/superpowers/specs/2026-08-04-private-plans-repo-guard-design.md` is an
  **approved but unimplemented** design for the **git** half, for Codex only. It states that
  Claude and Copilot payload handling stays unchanged, and it never covered file writes. Its
  plan is untouched — all 21 boxes in
  `docs/superpowers/plans/2026-08-04-private-plans-repo-guard-plan.md` are unticked — and
  neither `ToolWorkdir` nor `Resolve-AgentGuardExecutionCwd` exists in
  `scripts/agents/agent-worktree-guard.common.ps1`. So nothing from it can be reused here.
  This item is the write half and reopens nothing there.
- **Where the change goes:** `scripts/agents/agent-worktree-guard.common.ps1`, in two
  functions.
  1. `Test-AgentWriteTargetAllowed` (line 1730 at the time of writing) gains the subtree
     exception. The removal-log exception a few lines below it is the precedent for one
     named path inside `main` staying writable. The same `$plansRoot` compare already exists
     at lines 1892 and 1961; reuse that shape. Note what that compare does and does not do:
     it selects which refusal text to print. It does not prove the path is a Git repository,
     and this exception does not start proving that either.
  2. `Get-AgentSegmentWriteTarget` (line 1382) gains move-source classification, so a move
     out of main cannot enter the plans repo through the new exception.
- **Why it is safe:** the public repository git-ignores `docs/superpowers`, so nothing
  written there can enter a public commit or change a tracked file. The worktree can
  already read through the symlink; only writing changes.
- **Base:** this branch is on `main` and already carries the item (`232a241c`). It was
  removed from the backlog-071 branch in `a3ec9a2c`, so do not use that branch as a base.
- `scripts/new-worktree.ps1:106` refuses nested worktree creation, so Pickup for this item
  runs from a main-checkout session.
