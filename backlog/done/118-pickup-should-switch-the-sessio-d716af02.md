# 118 - Pickup should switch the session into the worktree

## Metadata

- **Epic**: Agent worktree lifecycle
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Picking up a backlog item creates a worktree, but the session stays in the main checkout and
reaches the worktree only through a per-command `cd`. Nothing durable records the switch, so
resuming the session puts the agent back on `main` with no memory of where the work lives.
Decide which of three fixes to take, and take it.

## The problem, observed

Session `5b7f17e2` did the whole of item 117 this way. It created
`.claude/worktrees/wt-worktree-removal-watcher-does-n-25bb8d24`, then ran every command with a
leading `cd`. At the end, `pwd` in that session still reported the main checkout and
`git rev-parse --abbrev-ref HEAD` still reported `main`. A resume would have started over on
`main`.

## Why the current route was chosen

`.claude/CLAUDE.md` tells an agent to prefer `scripts/new-worktree.ps1` over the native
`EnterWorktree` tool while a plan or spec is being written. The reason is real: entering a
worktree natively sets a session flag that turns on Claude Code's own `Edit` and `Write`
isolation, and that isolation refuses a write under `docs/superpowers/` while telling the agent
to edit "the worktree copy of this file". No such copy can exist - `.gitignore` excludes the
path and `scripts/worktree-plans.common.ps1` links it in instead.

Two things make this worth revisiting.

1. That behaviour was measured on Claude Code `2.1.224`, and is tracked in
   `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`. The local version
   is now `2.1.247`. Re-measure before assuming the workaround is still needed.
2. `EnterWorktree` is not a lesser route. It fires the `WorktreeCreate` hook, which runs
   `scripts/new-worktree.ps1` - the same manifest and the same no-auth setup. It also accepts a
   `path` to enter a worktree that already exists, so a script-created worktree can be adopted
   rather than recreated.

## The three candidate fixes

Research should pick one, or say why none works.

1. **Enter for real.** Pickup calls `EnterWorktree` so the harness records the switch. Blocked
   only by the `058` refusal, if that still fires on `2.1.247`.
2. **Restore on resume.** A resumed session returns to the worktree it was working in. Unknown
   whether the harness restores an `EnterWorktree` session across a resume. Measure it; we do
   not control it if it does not.
3. **Refuse work from main after a pickup.** The guard already refuses a worktree session from
   writing into main. The reverse is unguarded: a main session that just created a worktree can
   keep editing in main. Mark the session at pickup and refuse writes until it enters the
   worktree. This one needs no upstream cooperation.

## User story

As someone resuming an agent session, I want the session to come back to the worktree it was
working in, so that I do not have to notice it silently restarted on `main`.

## Acceptance criteria

- [x] A written measurement says whether the `058` `Edit`/`Write` refusal still fires under
      `docs/superpowers/` on the installed Claude Code version, with the version recorded.
      It still fires, word for word, on `2.1.251`.
- [x] A written measurement says whether a resumed session returns to a worktree entered with
      `EnterWorktree`. It does.
- [x] One of the three candidate fixes is chosen, with the reason the other two were not.
      Candidate 1. See `docs/adr/0012-pickup-enters-the-worktree.md`.
- [x] The chosen fix is implemented. Pickup enters the worktree with the native `EnterWorktree`
      tool, an entered session is refused every write into the main checkout, and the route is a
      rule in `.claude/CLAUDE.md`, `docs/development/workflow.md`, and `AGENTS.md` and an exit
      condition of Stage 1.
      **This box was revised.** It first asked that a session "can no longer" end a pickup in the
      main checkout. Candidate 1 does not force a session that never enters to move. Only
      candidate 3's session marker would have made the absolute wording true, and the human chose
      candidate 1 without it. The box now states the condition candidate 1 delivers.
- [x] `.claude/CLAUDE.md` and `docs/development/workflow.md` describe the route that is actually
      taken, and no longer describe one that was abandoned.

## Out of scope

- Unblocking `backlog/blocked/058`. That item's remaining step is a report to Anthropic. This
  item only needs to know whether the behaviour still happens.
- Changing what `scripts/new-worktree.ps1` sets up. The setup is not in question, only who calls
  it and what the session does afterwards.

## Notes / dependencies

- Reported by the human after session `5b7f17e2` finished item 117 entirely from `main`.
- Blocked sibling: `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`.
- Background on which refusal wins in which session:
  [`docs/agents/cross-agent-git-guardrails.md`](../docs/agents/cross-agent-git-guardrails.md).
- This file was renumbered from 117 by hand. `scripts/new-backlog-item.ps1` picked 117 because
  it reads the working tree, and the real 117 lives on an unmerged branch. Worth its own item.
- Pickup: branch `fix/wt-pickup-should-switch-the-sessio-d716af02`, based on `main` at
  `4f51230b`. Worktree `.claude/worktrees/wt-pickup-should-switch-the-sessio-d716af02`, created
  with `scripts/new-worktree.ps1` and then entered with the native `EnterWorktree` tool.
- Draft pull request: https://github.com/s205109/AHKFlowApp/pull/364.
- Spec: `docs/superpowers/specs/2026-08-29-pickup-enters-the-worktree-design-118.md`
- Plan: `docs/superpowers/plans/2026-08-29-pickup-enters-the-worktree-plan-118.md`
- Decision: candidate 1, "Enter for real". Recorded in `docs/adr/0012-pickup-enters-the-worktree.md`.
