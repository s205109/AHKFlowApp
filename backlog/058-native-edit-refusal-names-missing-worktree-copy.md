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

## First step: is it fixable here at all?

This is a real question, not a foregone conclusion. Answer it before designing anything.

A `PreToolUse` hook matching `Edit|Write` can return a deny decision with its own message. If that
hook fires **before** the harness's own isolation check, this repository can emit a correct message
and the item is fixable locally. If the harness checks first, its message wins and no hook can
replace it.

Probe: register a temporary `PreToolUse` hook on `Edit|Write` that denies with a recognizable
string, then attempt an `Edit` on a main-checkout path from a worktree session. Whichever message
appears answers the question.

## Acceptance criteria

- [ ] The hook-versus-harness precedence question above is answered, with the observed message
      recorded
- [ ] If a hook can win: a refusal message that names the real reason and a real next step, and that
      never tells the agent to edit a worktree copy which cannot exist for `docs/superpowers`
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
