# 133 - Reuse the SQL test container between runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test infrastructure)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

Every Integration and E2E run starts a fresh SQL Server container and removes it afterwards,
which costs 10 to 20 seconds a run. This item asks whether one container can serve several runs.
It cannot today, and the blocker is named below.

## User story

As a developer running the Integration slice several times in a row, I want the second run to
reuse the SQL Server the first one started, so that I do not pay a container start every time.

## What has to change first

**The migration tests must drop their own databases.** They migrate fixed database names from
scratch, and no test in the repository drops its database afterwards. On a reused container the
second run would find those databases already migrated and fail for a reason the code under test
did not cause. Backlog 128 hit exactly this, which is why its soak harness starts one container
per repetition instead of reusing one.

That is real work with a real risk: a test that drops and recreates its own database is a test
whose isolation now depends on its own cleanup running. Weakening the migration tests to save
15 seconds a run would be a bad trade, so this item has to show it did not.

## Acceptance criteria

- [ ] Every test that migrates a fixed database name drops that database when it finishes, and
      the item names each one.
- [ ] Running the Integration slice twice in a row against one container passes both times. The
      second run is the one that proves it: today it would fail on an already-migrated schema.
- [ ] `pwsh ./scripts/measure-test-modes.ps1 -Soak tests/AHKFlowApp.Infrastructure.Tests -Runs 30`
      passes 30 of 30 against a reused container, not a fresh one per repetition.
- [ ] The saving is measured as a median of five warm runs for the Integration Mode, written
      into this item beside the 49.59 s that backlog 128 left it at, with all five runs and the
      maximum.
- [ ] The migration tests still fail when a migration is broken. Prove it by breaking one on
      purpose and showing the red run, then putting it back. A cleanup change that quietly made
      these tests pass on anything is the failure this box exists to catch.

## Out of scope

- The E2E slice's own container. Handle it only if the same change covers it for free.
- Sharing a container across two developers or across CI jobs. This is about runs in one place,
  one after another.

## Notes / dependencies

- Filed out of backlog 128, which measured the cost: the SQL container start took 20.42 s,
  11.17 s and 10.65 s across three Integration runs, and that alone explained most of the spread
  between 107.50 s and 81.51 s.
- Every container gets a fresh name today, in `scripts/test-sql-container.common.ps1`, and is
  removed afterwards. `scripts/test-fast.ps1` owns that life for Integration and E2E.
- `SharedSqlContainer` already holds one container for the life of a test process. This item is
  about holding one across processes, which is a different problem.
- Backlog 128's design records this as blocked rather than merely deferred, and the block is the
  migration tests, not the container plumbing.
- Spec: none — the design is in
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`, under D7.
- Plan: none — not yet at Plan.
