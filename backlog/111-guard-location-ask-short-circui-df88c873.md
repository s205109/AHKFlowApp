# 111 - Guard location Ask short-circuits a write-layer Deny

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

The Guard runs three policy layers in order and returns the first one that does not say Allow. So
a weaker answer from an earlier layer hides a stronger answer from a later one. A command that the
write layer denies can reach the agent as an Ask, which a human can approve.

## User story

As a person who owns the main checkout, I want the Guard to return its strongest objection, so
that an approvable prompt never stands in for a refusal.

## Detail

`Invoke-AgentGuardPolicyForReading` used to return the location decision whenever it was not
Allow, and never reached the write layer. Fixed on this branch: the orchestrator now hands all
three layer answers to `Resolve-AgentGuardLayerDecision`
(`scripts/agents/agent-worktree-guard.common.ps1:3818`, "function Resolve-AgentGuardLayerDecision {"),
which returns the strongest one.

Measured from a managed worktree, with the protected root set to the main checkout:

```
git -C <main> add . ; Set-Content -Path <main>\probe.txt -Value x
    combined = Ask      location = Ask      write = Deny
```

The write layer denies. The combined answer is Ask, because the location layer answered first.
Approving that prompt runs both halves, including the write into the main checkout.

The same shape with `git -C <main> commit` returns Deny, because that command makes the location
layer deny rather than ask. Only the Ask tier is affected.

Backlog 093 added a severity order — `Deny > Ask > Warn > Allow` — and a helper that ranks two
decisions (`scripts/agents/agent-worktree-guard.common.ps1:3775`, "function Get-AgentGuardActionSeverity {").
That helper ranks the two Readings against each other. The three layers inside one Reading are
still ordered by position, not by severity, which is the gap this item closes.

## Acceptance criteria

- [x] One Reading returns the strongest action any of its three layers produced, not the first
      non-Allow one
- [x] `git -C <main> add . ; Set-Content -Path <main>\probe.txt -Value x` reports Deny
- [x] The message names the layer that produced the winning action
- [x] A command whose only objection is an Ask still reports Ask
- [x] The safety layer still fails closed and still wins outright when it denies
- [x] A test pins the measured command above at Deny

## Out of scope

- The combination rule across Readings. Backlog 093 settled that, and it already keeps the worst
  action
- What an ambiguous parse means per layer. Backlog 110 owns that

## Notes / dependencies

- Predates backlog 093. Confirmed with `git show main:scripts/agents/agent-worktree-guard.common.ps1`,
  which carries the same short-circuit
- Found by a reviewer of the pull request for backlog 093, who correctly scoped it out of that PR
- Running the later layers changes cost: the write layer spawns git probes. Measure before
  assuming every layer must always run
- Spec: none — Difficulty is `moderate`, so Pickup jumps straight to Plan and no spec is written
- Plan: `docs/superpowers/plans/2026-08-22-guard-layer-severity-plan-111.md`
