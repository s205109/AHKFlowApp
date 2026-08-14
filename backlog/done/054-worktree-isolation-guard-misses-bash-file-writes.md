# 054 - Worktree isolation guard stops git and Edit, but not Bash file writes

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — agent tooling only)
- **Stage**: 9-ship

## Summary

A worktree-isolated agent session is meant to stay inside its own worktree. The guard enforces that
for git commands and for the Edit and Write tools. A plain shell redirect from the Bash tool walks
straight through and writes into the human-owned main checkout.

Tested on 2026-08-05 from `.claude/worktrees/feature-wt-profiles-page-download`:

| Operation | Result |
|---|---|
| Bash `printf 'probe' > docs/superpowers/.guard-probe.tmp` | **Succeeded**, exit 0. File landed in the main checkout. |
| Bash `printf 'probe' > C:/Dev/segocom-github/AHKFlowApp/.guard-probe2.tmp` | **Succeeded**, exit 0. Main checkout root, no symlink involved. |
| Bash `rm` on both | Succeeded. |
| Edit or Write tool, same resolved path | Refused. |
| `git -C docs/superpowers status` (relative) | Refused. |
| `git -C C:/Dev/.../docs/superpowers status` (absolute) | Refused. |
| `cd <worktree>/docs/superpowers && git status` | Refused. |

Both probe files were removed straight after the test.

The second row is the important one. The first probe went through the `docs/superpowers` symlink, so
it could have been a symlink-resolution gap. The second wrote to the main checkout root directly, so
the hole is general: **any path in the main checkout is writable from a worktree session through
Bash.**

Nothing is corrupted by this today. The risk is quiet drift — an agent that believes it is isolated
can edit, overwrite, or delete the human's working tree, and the session reports success.

## Second, smaller defect

The Edit tool's refusal message reads:

> This session is isolated in the worktree ... Edit the worktree copy of this file instead of the
> shared-checkout path.

For `docs/superpowers/` there is no worktree copy to fall back to. `.gitignore:469` excludes
`docs/superpowers`, so `git worktree add` never checks it out.
`scripts/worktree-plans.common.ps1:59` links the main checkout's folder in with `mklink /D` instead.
The message therefore names a file that cannot exist, and sends the next agent looking for it.

## Acceptance criteria

- [x] A Bash command that writes, moves, or deletes a file under the main checkout is refused from a
      worktree-isolated session, the same way Edit and Write already are
- [x] Reads stay allowed. AGENTS.md says agents may inspect, build, test, and format in main, and
      building writes to `obj/` and `bin/` — so the rule must target source paths, not every write
- [x] The **Bash** refusal this repo owns names the real reason and a real next step. When no
      worktree copy of the path can exist, it must not tell the agent to edit one
- [x] A test covers both probes above — the symlinked path and a plain main-checkout path

The Edit tool's refusal message is Claude Code's own text, not this repo's. It moved to
`backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`, so this item stays
closable.

## Out of scope

- The git side of the guard. All three redirect forms are already refused, and that half works
- Relaxing the rule so agents may write plans from a worktree. CLAUDE.md deliberately keeps plan
  writes and plan commits in the main checkout. This item closes a hole; it does not reopen the
  question

## Notes / dependencies

- Same theme as `backlog/done/039-agent-git-guard-wrapper-bypass.md` — the guard being routed around
  rather than failing
- Guard behaviour is documented in `docs/agents/cross-agent-git-guardrails.md`
- Found while revising `docs/superpowers/specs/2026-08-05-profiles-page-download-design.md`. I twice
  told the user a worktree session could not write to `docs/superpowers/`, built a copy-and-commit
  handoff on that, and was wrong. Only the commit half is blocked
- One nuance for whoever picks this up: two separate guards exist. The main-checkout git guard
  classifies `docs/superpowers` as outside the protected repo, so committing there **from the main
  checkout** is allowed and should stay allowed. The worktree guard is the one with the hole
- Line numbers were read on `feature/wt-profiles-page-download` at `599b0ca0`
