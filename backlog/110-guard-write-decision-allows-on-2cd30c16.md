# 110 - Guard write decision allows on an ambiguous parse while the write-target reader denies

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

Two parts of the Guard read the same condition and disagree. When the tokenizer cannot split a
command safely, `Get-AgentWorktreeWriteDecision` returns Allow, and `Get-AgentCommandWriteTarget`
reports the target list as incomplete so its callers fail closed. One of the two is wrong.

## User story

As a person who owns the main checkout, I want an unparseable command to get one answer from the
Guard, so that a command the Guard admits it cannot read is not simply allowed.

## Detail

`Get-AgentWorktreeWriteDecision` returns Allow on an ambiguous parse
(`scripts/agents/agent-worktree-guard.common.ps1:3267`, "    if ($parsed.Ambiguous) { return New-AgentGuardDecision -Action Allow }").

`Get-AgentCommandWriteTarget` sets `Unresolved` on the same condition
(`scripts/agents/agent-worktree-guard.common.ps1:2912`, "    if ($parsed.Ambiguous) {"),
and its own documentation says a caller must fail closed on that flag rather than read an empty
list as "writes nothing".

The file's architecture note says safety rules fail closed and location rules fail open, so the
Allow may be deliberate. That has to be settled before either side changes, which is why the
Difficulty is `to-be-determined` rather than a guess.

## Acceptance criteria

- [ ] The repository states, in one place, what an ambiguous parse means for each policy layer
- [ ] The write decision and the write-target reader agree on that meaning
- [ ] A command that no Reading can parse produces one documented outcome, and a test pins it
- [ ] The decision is recorded as an ADR when it changes the fail-open architecture note

## Out of scope

- The combination rule for two Readings. Backlog 093 already settled that an ambiguous Reading
  contributes nothing, so it can never outrank the other Reading's Deny

## Notes / dependencies

- Found while designing backlog 093, and deliberately scoped out of it. 093 fixes only the
  combination rule; the disagreement between these two functions predates it
- Both citations move when 093 lands. Re-read them before starting this item
- Spec: none — needs Design first
- Plan: none — not yet at Plan
