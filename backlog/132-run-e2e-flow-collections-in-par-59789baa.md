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
- [ ] If it goes ahead: each parallel collection owns its own database, API host, SPA host and
      browser. The one thing the collections share is a single SQL Server container, and each
      collection names its own database on it. No two collections share mutable state.
- [ ] If it goes ahead: `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes and still reports 62
      tests. A different total means a collection lost its fixture and stopped running.
      The number was 57 when this item was filed. A warm run on 2026-09-09 reported
      "Failed: 0, Passed: 62, Skipped: 0, Total: 62", so 62 is the count this item holds to.
- [ ] If it goes ahead: `pwsh ./scripts/measure-test-modes.ps1 -Soak tests/AHKFlowApp.E2E.Tests
      -Runs 30 -NoBuild` passes 30 of 30. Five runs fix a median but say little about a race
      that fires one run in fifty, and this is the slice where this repository's flakes have
      historically come from.
- [ ] The measured median replaces the 321.65 s baseline in this item, with all five runs and
      the maximum beside it.

## Out of scope

- The incremental Blazor publish. That was backlog 131, and it closed on 2026-09-06 without a code
  change: the publish step costs about 11 s warm, not the 85 s the framing implied, and the saving
  never reaches CI. Do not expect that item to reduce the wall clock this item measures against.
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
- Spec: `docs/superpowers/specs/2026-09-09-parallel-e2e-stacks-design-132.md`. The framing that
  led to it is in `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`,
  under D7.
- Plan: none — not yet at Plan.
- **Measured baseline, one warm run, this machine, 2026-09-09.** Wall clock 306.96 s, not the
  321.65 s this item was filed with. The test host reported 270 s, the 62 test durations sum to
  260.22 s, `StackFixture.InitializeAsync` costs 6.24 s once, and all 57 `ResetDataAsync` calls
  together cost 3.08 s. So the database reset is 1% of the run: it is a lock, not a bill.
- **The floor is `ShortcutWarningFlowTests`, at 60.07 s of the 260.22 s.** A collection holds
  whole test classes, so no four-way split finishes faster than that one class. Splitting it is
  filed separately and is out of scope here.
- **The design records a tension with ADR 0013**, which rejected hand-picked collection groups as
  arbitrary. `docs/adr/0014-an-e2e-group-owns-a-whole-stack.md` says why that rejection does not
  reach this suite, where the group is the only thing that can own a browser.
