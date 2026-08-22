# 111 - Guard location Ask short-circuits a write-layer Deny

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The Guard runs three policy layers in order and returns the first one that does not say Allow. So
a weaker answer from an earlier layer hides a stronger answer from a later one. A command that the
write layer denies can reach the agent as an Ask, which a human can approve.

## User story

As a person who owns the main checkout, I want the Guard to return its strongest objection, so
that an approvable prompt never stands in for a refusal.

## Detail

`Invoke-AgentGuardPolicyForReading` returns the location decision whenever it is not Allow, and
never reaches the write layer
(`scripts/agents/agent-worktree-guard.common.ps1:3821`, "    if ($location.Action -ne 'Allow') { return $location }").

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
decisions (`scripts/agents/agent-worktree-guard.common.ps1:3769`, "function Get-AgentGuardActionSeverity {").
That helper ranks the two Readings against each other. The three layers inside one Reading are
still ordered by position, not by severity, which is the gap this item closes.

## Acceptance criteria

- [ ] One Reading returns the strongest action any of its three layers produced, not the first
      non-Allow one
- [ ] `git -C <main> add . ; Set-Content -Path <main>\probe.txt -Value x` reports Deny
- [ ] The message names the layer that produced the winning action
- [ ] A command whose only objection is an Ask still reports Ask
- [ ] The safety layer still fails closed and still wins outright when it denies
- [ ] A test pins the measured command above at Deny

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
- Spec: none — needs Design first
- Plan: none — not yet at Plan
