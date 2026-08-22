# 110 - Guard write decision allows on an ambiguous parse while the write-target reader denies

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Difficulty**: moderate
- **Stage**: 8-review

## Summary

Two parts of the Guard read the same condition and disagreed. When the tokenizer could not split a
command safely, `Get-AgentWorktreeWriteDecision` returned Allow, while `Get-AgentCommandWriteTarget`
reported the target list as incomplete so its callers fail closed. One of the two was wrong. This
item made both fail closed.

## User story

As a person who owns the main checkout, I want an unparseable command to get one answer from the
Guard, so that a command the Guard admits it cannot read is not simply allowed.

## Detail

`Get-AgentWorktreeWriteDecision` returned Allow on an ambiguous parse before this item shipped; it
now calls the shared refusal helper instead
(`scripts/agents/agent-worktree-guard.common.ps1:3323`, "    if ($parsed.Ambiguous) { return New-AgentGuardAmbiguousDecision }").

`Get-AgentCommandWriteTarget` sets `Unresolved` on the same condition
(`scripts/agents/agent-worktree-guard.common.ps1:2963`, "    if ($parsed.Ambiguous) {"),
and its own documentation says a caller must fail closed on that flag rather than read an empty
list as "writes nothing".

## Acceptance criteria

- [x] The repository states, in one place, what an ambiguous parse means for each policy layer
      — `docs/agents/cross-agent-git-guardrails.md`, the "A command the guard cannot read"
      subsection
- [x] The write decision and the write-target reader agree on that meaning — both fail closed
- [x] A command that no Reading can parse produces one documented outcome, and a test pins it
      — `tests/AgentWorktreeGuard.Tests.ps1`, the cross-layer section
- [x] The decision is recorded as an ADR when it changes the fail-open architecture note
      — `docs/adr/0009-an-unreadable-command-is-refused-by-every-policy-layer.md`

## Out of scope

- The combination rule for two Readings. Backlog 093 settled it, and it already keeps the worst
  action either Reading produced

  This bullet used to say an ambiguous Reading "contributes nothing, so it can never outrank
  the other Reading's Deny". The first half is wrong, and Design measured it: with
  `printf x > out`"` the bash Reading is ambiguous and refuses, the PowerShell Reading is clean
  and allows, and the combined answer is Deny. The ambiguous Reading contributed the whole
  answer. The true claim is narrower — Deny is the top of the severity table, so an ambiguous
  Reading can never be outranked and can never weaken the other Reading's answer

## Notes / dependencies

- Found while designing backlog 093, and deliberately scoped out of it. 093 fixes only the
  combination rule; the disagreement between these two functions predates it
- Both citations move when 093 lands. Re-read them before starting this item.
  Re-read on 2026-08-21 with 093 merged: both line numbers are unchanged
- Base: `origin/main` at f677f1bb, confirmed at Pickup
- Spec: `docs/superpowers/specs/2026-08-21-guard-ambiguous-parse-design-110.md`
- Plan: `docs/superpowers/plans/2026-08-21-guard-ambiguous-parse-plan-110.md`
