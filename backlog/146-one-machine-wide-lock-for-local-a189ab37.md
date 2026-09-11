# 146 - One machine-wide lock for local test runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Feature
- **Interfaces**: none (test runner scripts)
- **Difficulty**: complex
- **Stage**: 0-intake

## Summary

Two local test runs can start at the same time and each take the full worker count. The
PowerShell mode takes no lock at all, and the .NET lock is one file per checkout, so two
worktrees never block each other. This item gives the machine one shared limit.

## User story

As a developer who runs tests in two terminals, I want the second run to share the machine
with the first, so that I do not have to remember to halve the worker count by hand.

## Acceptance criteria

- [ ] Two local test runs started from different checkouts of this repository share one limit.
      The lock file today sits in each checkout's own root
      (`scripts/test-fast.ps1:49`, "$repoRoot = Split-Path -Parent $PSScriptRoot"), so two
      worktrees hold two different locks and neither waits.
- [ ] `-Mode PowerShell` takes part. It returns today before the lock is taken: the mode block
      starts at (`scripts/test-fast.ps1:359`, "    if ($Mode -eq 'PowerShell') {") and the lock
      is taken after it at
      (`scripts/test-fast.ps1:394`, "    $testRunLock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode $Mode").
- [ ] The design records which of two shapes it chose, and why: refuse the second run, or let
      both run and divide one worker budget between them. The measurement below supports
      dividing, because two runs at 4 workers each both passed and neither waited.
- [ ] A run that is made to wait, or is given a smaller share, says so in one line, and names
      the other run's mode, process id, and checkout.
- [ ] A lock left behind by a killed run does not block or shrink the next run. The existing
      lock already promises this, and the machine-wide one keeps the promise.
- [ ] A CI job takes the lock on a fresh runner and never waits.
- [ ] A developer can opt out for a deliberate overlap, and the opt-out is documented in
      `docs/development/testing-workflow.md`.

## Out of scope

- The default worker count for one run. Backlog 145 owns it.
- The .NET modes' existing per-checkout lock behaviour, beyond making it machine-wide. The
  reason that lock exists does not change.
- Coordinating with any process outside this repository.

## Notes / dependencies

- **Why a lock exists at all.** Two overlapping .NET runs build into the same folders and
  instrument the same assemblies. Backlog 082 measured the result: coverlet writes no coverage
  file and `dotnet test` still exits zero. The PowerShell suites have a different problem. They
  do not share build output, but they do share the machine.
- **Measurement, one machine, 2026-09-07.** Intel Core i9-11900H, 8 physical cores, 16 logical
  processors. Windows Defender exclusions in place, BelowNormal priority, 56 suites.
  - One run, 6 workers: 160.7 s, all 56 passed.
  - One run, 8 workers: 163.1 s, all 56 passed.
  - Two runs at once, 4 workers each: 296.2 s and 296.1 s, all 56 passed in both.
- Two runs at 4 workers each put 8 lanes on the machine, which is what one run at the old
  default already did. Running them together took 300 seconds of wall clock. Running them one
  after another at 6 workers would take about 322 seconds. So dividing the budget is both
  lighter and slightly faster than waiting.
- Nothing failed in about 20 minutes of load across those runs. That does not close backlog
  137, which records the same suites failing now and then under load in CI.
- The trigger for this item was a laptop that stopped responding while the suites ran, most of
  all when two terminals ran them at once.
- Spec: none — filed at intake.
- Plan: none — filed at intake, not picked up yet.
