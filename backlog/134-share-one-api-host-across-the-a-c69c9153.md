# 134 - Share one API host across the API test classes

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test infrastructure)
- **Difficulty**: complex
- **Stage**: 2-design

## Summary

`AHKFlowApp.API.Tests` holds 33 test classes. Twenty-nine of them carry `[Collection("WebApi")]`
and therefore run one after another, and the assembly holds 20.97 s of the Integration Mode. This
item asks whether one API host, held for the test process and reached through a gate, lets most of
those classes run at the same time.

Backlog 128 designed this change in full and then did not do it. The design is written; this item
is the decision to run it, and the measurement that says whether it was worth it.

## Why it was declined, and why it is still filed

Backlog 128 met its Integration target of 65 seconds without this change, reaching a median of
49.59 s. This was predicted to be worth about 12 s more, taking Integration to roughly 38 s.

The human declined it at that checkpoint. The price had not changed: a shared mutable
`WebApplicationFactory` behind a semaphore, a second fixture type, an exclusive Collection, an
audit of all 33 classes and edits to up to 29 of them, in a suite where thirteen runs had found
no flaky test. Scaling the work down was their call.

So the design is sound and unused. Picking this up means accepting that price for 12 seconds on
a Mode that is not the inner loop.

## What the design already settles

- `AHKFlowApp.API.Tests` holds 33 test classes. Twenty-nine carry `[Collection("WebApi")]`, of
  which **eight** build a second host with `WithWebHostBuilder`. Four belong to no Collection.
- The eight second-host classes hold 24 tests and **5.84 s**. That is a serial floor no
  parallelism removes, so only the remaining 15.13 s can go wide.
- Three separate races have to be closed, not one: `WebApplicationFactory` tracks its clients and
  its derived factories in plain `List<T>` fields with no lock; a second host started while the
  shared one is serving tests replaces Serilog's process-global `Log.Logger`; and the eight
  second-host classes need to run alone.
- Every client in the assembly comes from exactly two calls, `CreateClient` and
  `CreateAuthenticatedClient`, so the gate has two methods and no third.
- `ApiTestFixture` must lose its public `Factory` property. A grep is not a guard: leave the
  property and a class written next year still compiles while racing on the shared factory.

## Before this item starts

Both steps come before any design work, and neither is optional.

1. **Update the branch from the merged backlog 128 result.** That branch renamed and rewrote
   `docs/adr/0013`, reshaped `AHKFlowApp.Infrastructure.Tests`, and changed the measurement
   harness this item's numbers depend on. Measuring against a stale base gives a wrong answer.
2. **Write a design and a plan for this item.** Difficulty is `complex`, so the workflow sends it
   to Design. Backlog 128's spec D3 and plan Task 6 are frozen records of the tree as it was in
   September 2026, not instructions for the tree as it is. Read them, re-verify every line they
   cite, and write this item's own spec and plan.

## Acceptance criteria

- [ ] An audit of all 33 classes is written into this item, recording for each whether it can run
      beside another class. All 33, not only the 29 in the Collection: the four outside it are
      not exempt from proving it.
- [ ] Every class that builds its own host with `WithWebHostBuilder` joins the non-parallel
      Collection. The audit names them, and the count is at least the eight already known.
- [ ] If more than five classes beyond the known eight must be exclusive — that is, if 14 or more
      of the 33 end up exclusive — the item is abandoned and the reason recorded. Fourteen leaves
      too little running wide to pay for the machinery, and that is a real outcome rather than a
      failure.
- [ ] `AHKFlowApp.API.Tests` carries an explicit `maxParallelThreads` of **4** in its own
      `xunit.runner.json`, matching the CI runner's core count and the cap
      `AHKFlowApp.Infrastructure.Tests` already uses.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode Integration` passes, and reports the same test count as
      a run of the updated base branch taken immediately before the work starts. Record both
      numbers here. A different total means a class lost its fixture and silently stopped running.
- [ ] A direct `dotnet test tests/AHKFlowApp.API.Tests` with `AHKFLOW_TEST_SQL_CONNECTION_STRING`
      cleared, polled while the run is in flight, peaks at **1** SQL container. Twenty-one would
      mean the fixture is still building its own.
- [ ] `pwsh ./scripts/measure-test-modes.ps1 -Soak tests/AHKFlowApp.API.Tests -Runs 30 -NoBuild`
      passes 30 of 30. Any failure means this introduced a race; revert rather than patch around
      it, and record why.
- [ ] The Integration median is measured over five warm runs and written into this item, with all
      five runs and the maximum, beside a fresh baseline median taken from the updated base branch
      on the same machine.
- [ ] That median is at least **8 seconds** faster than the fresh baseline. The design predicted
      about 12 s; 8 s is two thirds of it. Anything less does not pay for a shared mutable host, a
      serialisation gate, an exclusive Collection and a standing audit duty, and the item is
      reverted and closed as not worth it.

## Out of scope

- The Fast Mode. Backlog 128 finished it at a 15.68 s median.
- The E2E slice. Backlog 131 and 132 own that.
- Disposing the shared host. Backlog 128 withdrew that requirement with its reasons; the host
  lives as long as the test process, the same way `SharedSqlContainer` holds its container.

## Notes / dependencies

- Filed out of backlog 128 as its declined D3.
- The full design, including the code for `SharedApiHost`, `ExclusiveApiTestFixture` and the
  rewritten `ApiTestFixture`, is in
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md` under D3, and
  the steps are in
  `docs/superpowers/plans/2026-09-04-net-test-speed-and-reliability-plan-128.md` as Task 6. Both
  are frozen records of the tree as it was in September 2026, so re-verify every line they cite
  before trusting it.
- `docs/adr/0013-sql-backed-tests-isolate-by-database.md` lands with backlog 128. Its section on
  what a shared host would additionally require is the design summary for this item, and its
  Consequences section records what `API.Tests` looks like today.
- Backlog 128 did the same reshape for `AHKFlowApp.Infrastructure.Tests` and it soaked 30 of 30.
  That is the closest evidence that this shape works, but the API assembly is the harder case:
  the Infrastructure classes share only a SQL Server, and these share a host as well.
- Spec: none yet — see "Before this item starts". Backlog 128's D3 section is input, not a
  substitute.
- Plan: none yet — see the line above.
