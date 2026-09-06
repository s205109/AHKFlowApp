# 132 - Run E2E flow collections in parallel stacks

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project)
- **Difficulty**: complex
- **Stage**: 2-design

## Summary

The E2E flow collections run one after another against one stack. This item asks whether they
can run at the same time, each collection holding its own database, API host and browser, and
what that costs in reliability.

## User story

As a developer waiting on the E2E slice, I want independent flows to run at the same time, so
that the slice finishes in the time its slowest flow takes rather than the sum of all of them.

## Acceptance criteria

- [ ] A written decision exists on whether parallel stacks are worth it, backed by a measured
      median of five warm runs and by a soak. A decision not to do it is a real outcome, and it
      is recorded with its reason rather than left open.
- [ ] If it goes ahead: each parallel collection owns its own database, API host and browser,
      and no two collections share mutable state. Name in the item what each one owns.
- [ ] If it goes ahead: `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes and still reports 57
      tests. A different total means a collection lost its fixture and stopped running.
- [ ] If it goes ahead: `pwsh ./scripts/measure-test-modes.ps1 -Soak tests/AHKFlowApp.E2E.Tests
      -Runs 30 -NoBuild` passes 30 of 30. Five runs fix a median but say little about a race
      that fires one run in fifty, and this is the slice where this repository's flakes have
      historically come from.
- [ ] The measured median replaces the 321.65 s baseline in this item, with all five runs and
      the maximum beside it.

## Out of scope

- The incremental Blazor publish. That is backlog 131, and it is deliberately separate: bundled,
  the contained change would wait behind this risky one.
- The Fast and Integration Modes. Backlog 128 covered those.

## Notes / dependencies

- Filed out of backlog 128. E2E wall clock is 321.65 s and the test host holds 237 s, so this is
  the largest single piece of test time in the repository.
- This is a rewrite of `StackFixture`, not a configuration change. Backlog 128's design says so
  plainly, and that is why it is `complex` rather than `moderate`.
- Read backlog 126 first. It ran the PowerShell suites in parallel and found the whole run
  equalled its slowest single suite, because the suites competed for the disk. The same effect
  may cap the gain here, and measuring it is cheaper than assuming.
- Backlog 128 capped `maxParallelThreads` at 4 for the two SQL-sharing projects. Whatever this
  item does needs the same kind of bound, and the CI runner has 4 cores and 16 GB.
- Spec: none — the design is in
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`, under D7.
- Plan: none — not yet at Plan.
