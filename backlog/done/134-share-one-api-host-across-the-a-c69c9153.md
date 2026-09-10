# 134 - Share one API host across the API test classes

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test infrastructure)
- **Difficulty**: complex
- **Stage**: 9-ship

## Outcome: declined on 2026-09-10, against this item's own threshold

This item set itself a bar: the change had to make the Integration median **at least 8 seconds**
faster, and below that the item said to revert and close it as not worth it. Settled measurement
on 2026-09-10 put the realistic saving at **5 to 7 seconds**, so the bar is not met and the work
was never started.

The bar was written as a test to run after the work. Running it before the work reaches the same
answer and costs nothing, so that is what happened.

Every figure this item was built on came from `scripts/measure-test-modes.ps1`, which discards no
warm-up run. Its numbers were therefore about 1.7 times too high. That defect is now backlog 150.

## What was measured on 2026-09-10

`main` at 27ff1147, Release, ten runs after the machine settled. The test count was 644 for every
run, the same 644 backlog 128 recorded, so the suite did not change in between.

Integration Mode, ten runs:

```
55.64 / 51.10 / 53.68 / 51.15 / 51.53 / 54.45 / 56.79 / 57.92 / 68.64 / 62.83
median 55.05 s   max 68.64 s
```

That sits close to the 49.59 s backlog 128 recorded. **There is no regression.** An earlier
reading of 88.40 s in this same session was taken before the machine settled and is wrong.

`AHKFlowApp.API.Tests` on its own, two passes against one shared container, second pass:

| Slice | Tests | Reported | Wall |
|---|---|---|---|
| All 33 classes | 239 | 11 s | 12.54 s |
| The 8 that build their own host | 24 | 3 s | 4.56 s |
| The other 25 classes | 215 | 10 s | 11.58 s |

Set beside what this item recorded before:

| Figure | This item said | Settled measurement |
|---|---|---|
| Whole assembly | 20.97 s | 11 to 13 s |
| Serial floor, 8 classes | 5.84 s | about 3 s |
| Parallelizable, 25 classes | 15.13 s | about 10 s |

## Why 5 to 7 seconds

The parallelizable part is 10 s. `AHKFlowApp.Infrastructure.Tests` achieved 3.25x with the same
reshape, which would turn 10 s into about 3 s. Adding the 3 s serial floor gives an assembly of
about 6 s, against 12 s today.

The ceiling is hard. Deleting all 25 parallelizable classes outright would save only 10 s,
because the serial floor and the fixture start remain. So no version of this work clears 8 s with
room to spare.

Where Integration's 55.05 s goes now:

| Part | Seconds | Owner |
|---|---|---|
| SQL container start | about 11 | backlog 133 |
| four `dotnet test` startups | about 9 | none |
| `AHKFlowApp.API.Tests` | about 13 | this item |
| `AHKFlowApp.Infrastructure.Tests` | about 9 | backlog 128, done |
| `AHKFlowApp.CLI.Tests` integration slice | about 8 | none |
| `AHKFlowApp.Application.Tests` integration slice | about 5 | none |

The container start is now the largest single cost, and backlog 133 already owns it.

## The audit, as far as it was taken

The audit was not finished, because the item was declined before Design. What was checked reads
better than this item assumed, and it is written down so the next reader does not repeat it.

- Exactly **8** classes build a second host with `WithWebHostBuilder`:
  `TestAuthProviderToggleTests`, `CorsTests`, `DevSeedEndpointTests`, `HealthControllerTests`,
  `SerilogRequestLoggingTests`, `GlobalExceptionMiddlewareTests`, `ValidationProblemDetailsTests`
  and `ProgramTests`.
- `CustomWebApplicationFactory.WithTestAuth` is a ninth route to a derived host, because it calls
  `WithWebHostBuilder` itself. No test in `AHKFlowApp.API.Tests` calls it today. A future test
  that does would join the exclusive set without looking like it.
- No test in the assembly touches `AppDbContext` directly. Every one goes through HTTP with an
  owner-scoped identity, which is a stronger starting point than a grep for collection attributes
  suggests.
- `reset=true` on the dev seed endpoints filters by `OwnerOid`, so `DevSeedEndpointTests` and
  `DevSeederEndpointTests` do not remove another class's rows.
- 17 of the 20 classes that authenticate pass a fresh `Guid.NewGuid()` per client. The three that
  use the fixed default oid — `HotkeyKeysEndpointTests`, `KnownShortcutsEndpointTests` and
  `HeaderPresetsEndpointTests` — only issue GET requests.
- So the audit would likely have landed near 8 exclusive and 25 parallel, well under the 14 that
  this item set as its abandon point. Isolation was not the reason this was declined.

## One more reason, recorded for the next reader

CI never runs Integration Mode. `.github/workflows/ci.yml` runs one `dotnet test` over the whole
solution with coverage collection on `ubuntu-latest`. Every acceptance criterion below measures
`scripts/test-fast.ps1 -Mode Integration` on a developer machine, so the saving this item chased
was local only, by its own design. The repository is public, so that runner does have the four
cores the `maxParallelThreads` criterion assumed.

## Summary

`AHKFlowApp.API.Tests` holds 33 test classes. Twenty-nine of them carry `[Collection("WebApi")]`
and therefore run one after another, and the assembly holds 20.97 s of the Integration Mode. This
item asks whether one API host, held for the test process and reached through a gate, lets most of
those classes run at the same time.

Backlog 128 designed this change in full and then did not do it. The design is written; this item
is the decision to run it, and the measurement that says whether it was worth it.

The measurement is now taken, and the answer is no.

## Why it was declined, and why it is still filed

Backlog 128 met its Integration target of 65 seconds without this change, reaching a median of
49.59 s. This was predicted to be worth about 12 s more, taking Integration to roughly 38 s.

The human declined it at that checkpoint. The price had not changed: a shared mutable
`WebApplicationFactory` behind a semaphore, a second fixture type, an exclusive Collection, an
audit of all 33 classes and edits to up to 29 of them, in a suite where thirteen runs had found
no flaky test. Scaling the work down was their call.

So the design is sound and unused. Picking this up means accepting that price for 12 seconds on
a Mode that is not the inner loop.

On 2026-09-10 the twelve seconds turned out to be five to seven, and the item closed.

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

The two timing figures in this section are the contaminated ones. The settled values are 3 s and
10 s, in the table above. The rest of the section still holds.

## Before this item starts

Both steps come before any design work, and neither is optional.

1. **Update the branch from the merged backlog 128 result.** That branch renamed and rewrote
   `docs/adr/0013`, reshaped `AHKFlowApp.Infrastructure.Tests`, and changed the measurement
   harness this item's numbers depend on. Measuring against a stale base gives a wrong answer.
2. **Write a design and a plan for this item.** Difficulty is `complex`, so the workflow sends it
   to Design. Backlog 128's spec D3 and plan Task 6 are frozen records of the tree as it was in
   September 2026, not instructions for the tree as it is. Read them, re-verify every line they
   cite, and write this item's own spec and plan.

Step 1 was done on 2026-09-10 and is what closed the item. Step 2 never ran.

## Acceptance criteria

These are left unticked on purpose. The work was never done, so no box is true. The last box is
the one that decided the item, and it is answered below rather than ticked.

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

**Answered, not ticked.** The fresh baseline is 55.05 s. The realistic saving is 5 to 7 s and the
absolute ceiling is 10 s. Less than 8 s, so by the rule this box states, the item is closed as not
worth it.

## Out of scope

- The Fast Mode. Backlog 128 finished it at a 15.68 s median.
- The E2E slice. Backlog 131 and 132 own that.
- Disposing the shared host. Backlog 128 withdrew that requirement with its reasons; the host
  lives as long as the test process, the same way `SharedSqlContainer` holds its container.

## Notes / dependencies

- Filed out of backlog 128 as its declined D3. Closed on 2026-09-10 as declined a second time,
  this time against its own numeric threshold rather than by judgement.
- The full design, including the code for `SharedApiHost`, `ExclusiveApiTestFixture` and the
  rewritten `ApiTestFixture`, is in
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md` under D3, and
  the steps are in
  `docs/superpowers/plans/2026-09-04-net-test-speed-and-reliability-plan-128.md` as Task 6. Both
  are frozen records of the tree as it was in September 2026, so re-verify every line they cite
  before trusting it. The design was never the problem; the arithmetic on top of it was.
- `docs/adr/0013-sql-backed-tests-isolate-by-database.md` describes what a shared host would
  additionally require, and its closing line says the Infrastructure rules would apply here if
  this item ran. It does not run, so that section stays a description of a road not taken.
- Backlog 150 covers the measurement defect this item uncovered: `measure-test-modes.ps1`
  discards no warm-up run, which is why this item's recorded figures were about 1.7x too high.
- Backlog 133 owns the SQL container start, which is now the largest single cost in the
  Integration Mode at about 11 s of 55 s.
- Backlog 128 did the same reshape for `AHKFlowApp.Infrastructure.Tests` and it soaked 30 of 30.
  That is the closest evidence that this shape works, and it is also where the 3.25x used in the
  estimate above comes from.
- Spec: none — the item closed before Design. Backlog 128's D3 section was input, not a
  substitute, and it was never turned into this item's own spec.
- Plan: none — the item closed before Plan.
