# 140 - Account for the unexplained E2E harness overhead

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (measurement first)
- **Difficulty**: complex
- **Stage**: 4-execute

## Summary

Roughly 33 to 46 seconds of an E2E run is not accounted for by any named step. This item measures
where that time goes before anybody proposes a fix for it.

**That range is an estimated remainder, not measured time.** It is what is left after subtracting
three figures from two whole-run times, and the three figures come from different places. One of
them, the 237 s test host, does not record which measurement round produced it. So the remainder
could move once somebody measures the run directly, and that is the work here. Treat the range as
"tens of seconds, owner unknown" rather than as a quantity anybody has observed.

**Do not assume the solution build owns it.** Backlog 128 measured one `dotnet build` of an
up-to-date tree at 10 s, and the runs this arithmetic uses passed `-NoBuild`, so they contain no
solution build at all. The honest name for the remainder is E2E harness overhead, and naming it
anything more specific is the thing this item exists to stop.

## User story

As a developer running the E2E slice, I want to know which step owns the largest unexplained part
of the wall clock, so that the next speed item attacks the real cost instead of a small one.

## Acceptance criteria

- [x] This item records where the unexplained time goes, measured, with each step named and timed.
- [x] The measurement separates the SQL container start, the Blazor publish, Playwright browser
      install and launch, the API and SPA host start, and any time the test host reports outside
      the tests themselves.
- [x] The solution build is timed separately, and this item states whether it belongs in the E2E
      figure at all. A `-NoBuild` run excludes it; a plain `dotnet test` does not.
- [x] Every figure is the median of five runs, with all five runs and the maximum written down.
- [x] The item states whether a fix is worth filing, and files it or says why not.

## Measurement

Taken on 2026-09-12 on one machine, in one sitting, with the machine otherwise idle. Both warm
sessions ran back to back, because backlog 150 measured 15 to 20 percent drift across an hour.
Every warm figure below is the median of five counted runs. Each session discarded its own
warm-up runs and waited out the 600 s settle clock before counting.

### The headline: the command a developer types

`pwsh .\scripts\measure-test-modes.ps1 -Mode E2E -Runs 5 -KeepBuildInRun`. Each counted run
builds, so this is the whole command.

| Figure | Five runs | Median | Max |
|---|---|---|---|
| Wall clock, seconds | 77.46 / 78.06 / 82.38 / 78.09 / 77.03 | **78.06** | 82.38 |
| TRX run interval, seconds | 67.60 / 68.58 / 72.47 / 68.43 / 67.48 | 68.43 | 72.47 |
| Harness overhead, seconds | 1.338 / 1.393 / 1.310 / 1.369 / 1.291 | **1.338** | 1.393 |
| Outside the TRX run interval, seconds | 9.86 / 9.48 / 9.91 / 9.66 / 9.55 | 9.66 | 9.91 |

Spread across the five runs was 6.9 percent of the median.

### The `-NoBuild` comparison, for backlog 132

`pwsh .\scripts\measure-test-modes.ps1 -Mode E2E -Runs 5`. This builds once up front and passes
`-NoBuild` to every run, so it is the figure that compares with backlog 132's 110.60 s.

| Figure | Five runs | Median | Max |
|---|---|---|---|
| Wall clock, seconds | 71.45 / 72.55 / 73.37 / 72.25 / 71.69 | **72.25** | 73.37 |
| TRX run interval, seconds | 67.21 / 68.49 / 69.22 / 68.11 / 67.53 | 68.11 | 69.22 |
| Harness overhead, seconds | 1.280 / 1.225 / 1.326 / 1.256 / 1.227 | **1.256** | 1.326 |
| Outside the TRX run interval, seconds | 4.24 / 4.06 / 4.15 / 4.14 / 4.16 | 4.15 | 4.24 |

Spread was 2.7 percent of the median. The slice is now 72.25 s, not 110.60 s. The tree got
faster between backlog 132 and today.

### One cold run

`pwsh .\scripts\test-fast.ps1 -Mode E2E -FreshSql`, taken once. **This is one run. It has no
median and it must never be averaged with the warm runs.**

- Wall clock: 105.26 s
- TRX run interval: 83.95 s
- Harness overhead: 1.29 s
- Outside the TRX run interval: 21.31 s, of which the fresh SQL container start was 11.74 s
- Stack setup, summed across four stacks: 24.13 s, against 8.01 s warm

### The named steps

Every figure below is the median across the five `-NoBuild` runs. `Sum` adds the four stacks
together, which is what the machine paid. `Per stack` is the median of one stack's own figure,
which is what one stack costs. The two differ because four stacks run at the same time.

| Component | Operation | Count | Sum, ms | Per stack, ms |
|---|---|---|---|---|
| StackFixture | InitializeAsync | 4 | 8009.78 | 2002.44 |
| HostStartGate | QueueWait | 24 | 4665.45 | 45.97 |
| StackFixture | ResetDataAsync | 60 | 3245.77 | 48.98 |
| HostStartGate | GatedWork | 23 | 2456.06 | 52.62 |
| StackFixture | BrowserLaunch | 4 | 2382.17 | 595.47 |
| StackFixture | BrowserInstall | 4 | 661.55 | 167.35 |
| StackFixture | SpaHostStart | 4 | 51.56 | 8.32 |

`InitializeAsync` is the parent of every other `StackFixture` row and of the two gate rows, so
its 2002.44 ms per stack is the whole cost of bringing one stack up. All four stacks are up
inside about 2.0 s.

Two notes a later reader needs:

- The gate counts are 24 and 23, not 4 and 4. `HostStartGateTests` starts hosts of its own
  through the same gate, and those records carry the same operation names. The current record
  has no field that tells a stack start apart from a test's own start. Taking only the four
  largest `GatedWork` entries gives 1.50 s summed, and the four largest `QueueWait` entries give
  3.72 s summed, but that ordering is an assumption, not a label.
- `GatedWork` is written after the work finishes, so a host start that throws writes no record.
  That is why there are 24 waits and 23 works.

### The SQL container and the Blazor publish

`scripts/test-fast.ps1` already prints the container step, so this item reads it rather than
instrumenting it again:

- Warm, reused: 0.251 / 0.250 / 0.256 / 0.242 / 0.256 s. Median 0.251 s, max 0.256 s.
- Cold, fresh start: 11.74 s, from the one cold run.

The Blazor publish is out of scope for this item, and backlog 131 closed it. Backlog 139
measured it at 4.51 s median with compression off. This item does not re-measure it. What this
item can say is the window it lives in: on a warm `-NoBuild` run the whole time outside the TRX
run interval is 4.15 s, and the container takes 0.251 s of that, so the publish, process start
and script overhead share at most about 3.9 s between them. The publish is therefore incremental
and near-free on a warm tree, which is what backlog 131 built it to be.

### Does the solution build belong in the E2E figure?

Yes, when the question is "how long does the command take". No, when the question is "how long do
the tests take". The two medians say what it costs: 78.06 s with the build inside every run,
72.25 s with one build up front. The build adds **5.81 s** to a run of an already-built tree.

Both numbers are worth keeping. `AGENTS.md` names `pwsh .\scripts\test-fast.ps1 -Mode E2E` as the
verification command, and a developer running it on a tree they just edited pays the build. A
developer running it twice in a row does not.

## The premise is retired

**There is no unexplained time. The residual is 1.256 s, which is 1.8 percent of the TRX run
interval.** The item's estimate of 33 to 46 seconds was arithmetic over four figures, and all
four described a tree that no longer exists. The spec's "The premise this design retires" section
has the detail; here is what each input got wrong.

1. **The whole-run times were pre-split.** The item subtracted from 293.38 s and 306.22 s.
   Backlog 132 split the suite into four parallel groups on 2026-09-09. The same slice now
   measures 72.25 s. The starting number was wrong by a factor of about four.
2. **The test-host figure was pre-split.** The item subtracted 237 s, from backlog 128, before
   the split, and the item itself recorded that nobody knew which round produced it.
3. **The publish figure was about 8 s too high.** The item subtracted 12.37 s. Backlog 139 then
   measured 4.51 s, and on a warm tree today the whole outside-the-run window is 4.15 s.
4. **The container figure described a start a warm run does not perform.** The item subtracted
   about 11 s. A warm run reuses the container in 0.251 s. Only a `-FreshSql` run pays 11.74 s,
   and this item measured that separately rather than folding it in.

**Why subtraction produced a number at all, and why it could not have been right.** Summed test
durations across the five `-NoBuild` runs were 217.95 / 221.81 / 221.45 / 219.04 / 219.45 s, for
a run interval of 68.11 s. Subtracting summed durations from wall clock gives about minus 151
seconds. Four groups run at once, so the same seconds are counted up to four times, and a parent
step is counted again for every child inside it. `Get-AhkFlowIntervalUnionMilliseconds` merges
ranges instead of adding them: the union of the test intervals is 64.68 s, and tests plus fixture
steps cover 66.86 s of the 68.11 s run.

## What actually costs time, and the verdict

Nothing is missing from the account, so the next speed item cannot be about harness overhead. The
measurement did find one real cost, and it is the balance of the four groups.

Counting how many of the four groups were running a test at each moment, across the same five
runs, gives these medians for a 68.11 s run interval:

| Groups running a test | Median time |
|---|---|
| 4 | 48.37 s |
| 3 | 5.63 s |
| 2 | 2.04 s |
| 1 | 8.68 s |
| 0 | 3.31 s |

For **19.66 s of a 68.11 s run, 29 percent, fewer than four groups are executing a test.** The
8.68 s at one group is the long tail: three groups have finished and one is still working. The
3.31 s at zero groups is stack setup at the start and teardown at the end, and the named steps
above already account for it.

**Verdict: no fix is worth doing now. The finding is filed as backlog 155, in
`backlog/icebox/`.** The number that decides it is 3.4 s.

An earlier draft of this record estimated the saving at 13 s. That figure compared balanced test
time with the whole run interval and left out the 5.9 s of stack setup and teardown that no group
covers. It was wrong.

The real ceiling comes from one class. `ShortcutWarningFlowTests` holds 12 tests that take 58.78 s,
26 percent of all E2E test time, and xUnit runs the tests inside one collection one after another.
Moving whole classes between groups can therefore bring the run from 68.1 s to about 64.7 s, and
no further. That saves 3.4 s of a 72.25 s slice.

The saving would also decay. The group figures in `tests/AHKFlowApp.E2E.Tests/E2ETestCollection.cs`
were recorded on 2026-09-09. Three days later group B measured 48.4 s against a recorded 61.36 s.
Nothing enforces the balance, so a one-off rebalance starts drifting the day it merges.

Backlog 155 holds the per-group table and the conditions that would make the work worth doing.

Two smaller findings, recorded but not worth an item on their own:

- Stack setup costs about 2.0 s per stack warm and about 5.9 s cold. Serialising the four API
  host starts behind one semaphore is not the cost the spec suspected it might be.
- The gate's records cannot be told apart from `HostStartGateTests`' own host starts. Anybody
  extending this instrumentation should add a field that names the caller.

## Out of scope

- Fixing anything. This item measures. A fix is a separate item, filed from the result.
- The E2E publish step. Backlog 131 measured it at about 11 s and closed.
- Parallel E2E stacks. That is backlog 132, and it attacks the 237 s test host, not this.

## Notes / dependencies

- The remainder is arithmetic, not a measurement, and that is the reason this item exists.
- Backlog 128 measured E2E two ways. Letting every project build itself gave one run of 321.65 s.
  Building the solution once and then passing `-NoBuild` gave 293.38 s and 306.22 s. The
  `-NoBuild` pair is the repeatable measurement, so the arithmetic uses it.
- Subtract 237 s in the test host, 12.37 s for the Blazor publish target from backlog 131, and
  about 11 s of SQL container start from backlog 128. That leaves about 33 s and about 46 s.
- The publish figure is the target's whole cost, because the target deletes and then publishes.
  An earlier draft used 11 s, which was the cost of publishing without the delete, and got
  34.38 s to 47.22 s. The 1.4 s difference is far inside the uncertainty of the estimate, which
  is why this item rounds and does not quote decimals.
- The 237 s test-host figure does not record which of the two measurement rounds produced it. That
  uncertainty is real and it is one more reason to measure rather than to reason from the table.
- `scripts/measure-test-modes.ps1` builds once and then runs with `-NoBuild`, so its numbers
  exclude the build on every run. Timing the build needs a different shape, and designing that
  shape is part of this item.
- Difficulty was `to-be-determined` on purpose at intake, and Design settled it as `complex` on
  2026-09-12. Seven surfaces change across C# and PowerShell, and one is a new algorithm with its
  own suite. The first suspect is the four API host starts, which a semaphore runs one at a time.
  That is a place to look, not an answer; the item still measures rather than assumes.
- Filed out of backlog 131. The arithmetic and its sources are in
  `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`.
- Spec: `docs/superpowers/specs/2026-09-12-e2e-harness-overhead-design-140.md`
- Plan: `docs/superpowers/plans/2026-09-12-e2e-harness-overhead-plan-140.md`
