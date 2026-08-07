# 058 - Native Edit refusal names a worktree copy that cannot exist

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — agent tooling only)

## Summary

Claude Code's own worktree isolation refuses an `Edit` or `Write` aimed at the main checkout. The
refusal reads:

> This session is isolated in the worktree ... Edit the worktree copy of this file instead of the
> shared-checkout path.

For `docs/superpowers/` there is no worktree copy to edit. `.gitignore:469` excludes
`docs/superpowers`, so `git worktree add` never checks it out.
`scripts/worktree-plans.common.ps1:59` links the main checkout's folder in with `mklink /D` instead.
The message names a file that cannot exist, and sends the next agent looking for it.

## Why this is its own item

Split out of `backlog/054-worktree-isolation-guard-misses-bash-file-writes.md`, which carried it as
a second, smaller defect.

054 closes a real hole this repository owns: a Bash write from a worktree reaching the main
checkout. This one is different in kind. The text belongs to the Claude Code harness, not to this
repository — the string `isolated in the worktree` appears nowhere in the checkout. Keeping both in
one item would have made 054 unclosable, because AGENTS.md requires every acceptance box ticked
before an item moves to `backlog/done/`.

This item is also Claude-only. Codex and Copilot have no equivalent isolation, so they never show
this message.

## First step: is it fixable here at all? Answered — no

Probed on 2026-08-07, against Claude Code 2.1.224. **The harness refusal takes precedence, so no
hook can replace its message.**

The probe measured which refusal reaches the agent, not the harness's internal execution order.
That is enough to close this item either way: whatever runs first inside the harness, a hook that
denies with its own message cannot get that message shown. Do not restate this as "the harness
check runs before the hook" in an upstream report without instrumenting it — `--debug-file` records
which hooks actually executed (https://code.claude.com/docs/en/hooks).

Full method and evidence:
`docs/superpowers/specs/2026-08-07-worktree-edit-isolation-precedence-design.md`.

Two runs settled it. Both asked a fresh session to make the same `Edit` on a main-checkout path,
with the same `PreToolUse` deny hook on `Edit|Write` supplied through `--settings`.

Control, without `-w`. The hook denied the edit, which proves the hook loaded and works:

> PreToolUse:Edit hook error: PROBE-C-HOOK-DENY: this refusal came from a repo PreToolUse hook, not
> the harness.

Test, with `-w`. The same hook produced nothing. The harness answered instead:

> This session is isolated in the worktree
> C:\Dev\segocom-github\AHKFlowApp\.claude\worktrees\probe058c. Edit the worktree copy of this file
> instead of the shared-checkout path.

A second finding came out of the same probes, and it is filed separately as
`backlog/065-native-edit-isolation-misses-worktree-sessions-without-w-flag.md`. The harness check is
driven by a session flag, not by the working directory. It fires for `-w`, `--worktree`, and
`EnterWorktree` sessions only. A session that merely has a worktree as its working directory gets no
check at all, and there a `PreToolUse` hook does win.

## Acceptance criteria

- [x] The hook-versus-harness precedence question above is answered, with the observed message
      recorded
- [x] If a hook can win: a refusal message that names the real reason and a real next step, and that
      never tells the agent to edit a worktree copy which cannot exist for `docs/superpowers`
      — **not applicable.** The probe showed a hook cannot win for the sessions this item covers.
      The case where a hook *can* win is backlog 065, not this item.
- [ ] If a hook cannot win: an upstream report filed with Anthropic, linked from this item, and the
      limitation recorded in `docs/agents/cross-agent-git-guardrails.md`

## Out of scope

- The Bash write hole. That is 054.
- Any change to where plans are written. `.claude/CLAUDE.md` deliberately keeps plan writes and plan
  commits in the main checkout. This item fixes wording, not policy.

## Notes / dependencies

- Depends on 054 only for context, not for code. They can land in either order.
- Design for 054: `docs/superpowers/specs/2026-08-06-worktree-guard-bash-writes-design.md`, section
  "Backlog scope"
- Probe method and evidence:
  `docs/superpowers/specs/2026-08-07-worktree-edit-isolation-precedence-design.md`
- The probe also exposed a gap that **is** fixable here. Filed as
  `backlog/065-native-edit-isolation-misses-worktree-sessions-without-w-flag.md`. Both items share
  the one probe, so nothing needs re-running.
