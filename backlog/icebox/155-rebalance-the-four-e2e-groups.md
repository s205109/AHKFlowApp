# 155 - Rebalance the four E2E groups

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

**Iceboxed. Do not pick this up as written.** Backlog 140 measured it, and a plain rebalance is
worth about 3.4 s of a 72.25 s E2E slice. It also decays: the balance figures in
`tests/AHKFlowApp.E2E.Tests/E2ETestCollection.cs` were three days old and already 13 s wrong.

It is kept so the finding is not lost. Read "What would make it worth doing" before reopening it.

## User story

As a developer running the E2E slice, I want the four parallel groups to stay balanced, so that
the slice is not held back by one slow group while the other three sit idle.

## Acceptance criteria

- [ ] The slowest group's busy time is within an agreed margin of the fastest group's, measured
      as the median of five warm runs.
- [ ] A check fails when the groups drift outside that margin, so balance does not depend on a
      doc comment somebody has to keep current.
- [ ] `ShortcutWarningFlowTests` no longer sets the floor for the whole slice on its own.

## What would make it worth doing

Reopen this item only if one of these becomes true:

- The E2E slice grows until the long tail costs more than about 10 s.
- Somebody splits `ShortcutWarningFlowTests`, which removes the floor that caps every rebalance.
- A self-correcting balance check becomes cheap, so the result stops decaying.

## The measurement behind the verdict

From backlog 140's five `-NoBuild` runs on 2026-09-12. Busy time per group is the union of that
group's test intervals, so concurrent tests are not counted twice.

| Group | Recorded 2026-09-09 | Measured 2026-09-12 |
|---|---|---|
| A | 64.03 s | 62.2 s |
| B | 61.36 s | 48.4 s |
| C | 64.28 s | 53.8 s |
| D | 70.51 s | 56.1 s |

The run interval is 68.1 s. Group A is the critical path, so 5.9 s of the run is stack setup and
teardown that no group covers.

One class decides the ceiling. `ShortcutWarningFlowTests` holds 12 tests that take 58.78 s, which
is 26 percent of all E2E test time. xUnit runs the tests inside one collection one after another,
so no reshuffle of whole classes can bring group A below that figure.

- Move whole classes, leave that class alone: the run falls to about 64.7 s. That saves 3.4 s.
- Also split that class across two collections: the run falls to about 61.7 s. That saves 6.4 s.

Backlog 140 first estimated the saving at 13 s. That figure compared the balanced test time with
the whole run interval and left out the 5.9 s of setup and teardown. It was wrong.

## Why it drifts

Nothing enforces the balance. A test class joins a group through one attribute, such as
`[Collection(E2ECollectionB.Name)]`. The only guidance is a comment in `E2ETestCollection.cs`
and a line in `docs/development/testing-workflow.md`, and both quote seconds that go stale as soon
as a test changes. A one-off rebalance starts decaying the day it merges.

## Out of scope

- Adding a fifth group. That adds a whole stack, and backlog 140 measured about 2.0 s of setup per
  stack warm and about 5.9 s cold.
- Making the tests inside `ShortcutWarningFlowTests` faster. That is a separate question from
  where they run.

## Notes / dependencies

- Filed from backlog 140, whose record holds the full measurement.
- Spec: none — iceboxed at intake, no design started
- Plan: none — iceboxed at intake, no plan started
