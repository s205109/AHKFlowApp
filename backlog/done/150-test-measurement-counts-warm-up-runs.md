# 150 - Test measurement counts warm-up runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (measurement script)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

`scripts/measure-test-modes.ps1` builds once and then times every run it is asked for. It
discards no warm-up run. The runs taken soon after a build are much slower for reasons that have
nothing to do with the tests, so a median of five runs started right after a build reads far
higher than the same tree reads twenty minutes later.

## User story

As a developer setting a speed target for a test Mode, I want the measurement to report a number
that does not depend on how recently I built the tree, so that two measurements of the same tree
agree with each other.

## The evidence

Measured 2026-09-10 on `main` at 27ff1147. The test count was 644 for every run, so the suite
did not change between them.

A five-run window started right after a Release build:

```
91.21 / 85.46 / 96.13 / 87.87 / 88.40      median 88.40 s
```

A second five-run window a few minutes later, which decayed inside itself:

```
91.33 / 62.30 / 57.27 / 59.05 / 52.84      median 59.05 s
```

Ten runs once the machine had settled:

```
55.64 / 51.10 / 53.68 / 51.15 / 51.53 / 54.45 / 56.79 / 57.92 / 68.64 / 62.83
median 55.05 s   max 68.64 s
```

So the same tree measured 88.40 s and 55.05 s about an hour apart, with no change to the code.
`AHKFlowApp.API.Tests` read 27 to 29 s in the first window and 11 to 13 s once settled.

The cause was not another test run competing. A sampler ran every three seconds through the
second window and never saw more than one `ahkflow-testsql` container, and a second local Claude
session confirmed it started no containers, no builds and no test runs. The most likely cause is
the file system cache plus the virus scanner reading the freshly written Release output.

## Why this matters beyond one script

Every speed number in the testing-infrastructure epic came through this script. Backlog 128
established the "median of five warm runs" rule and recorded all of its figures that way, and
backlog 131, 132, 133, 134 and 139 inherit the rule.

The error is large enough to change a decision. Backlog 134 records
`AHKFlowApp.API.Tests` at 20.97 s, split into a 5.84 s serial floor and 15.13 s that could run in
parallel. Settled measurement on 2026-09-10 put the same 239 tests at 11 to 13 s, split about
3 s and 10 s. That moved the item's predicted saving from about 12 s to about 5 to 7 s, below the
8 s threshold the item itself set for being worth doing.

## The stability figure, and why

**Relative spread**, printed as `(max - min) / median` in percent, beside the median. A `built`
line prints next to it and says how long the tree had been built when the counted runs started.

Spread answers the question a reader actually has: how much is this median worth? It does not say
whether the tree was cold, and no figure computed inside one measurement window can. In the record
above, the cold window spread 12.1 percent of its median and the settled ten-run window spread
31.9 percent, so the coldest measurement of the three looked like the tightest. A drift figure
fails the same way: the cold window is flat, and the settled window drifts upward by 12 percent.
The `built` line carries coldness instead.

The two measurements below show the figure doing its job. The first reads 21.3 percent and was
still moving. The second reads 5.9 percent and was steady.

## The two measurements

Measured 2026-09-12 on `fix/wt-test-measurement-counts-warm-up-runs` at 77da3180, Integration
Mode, five counted runs each. The tree was built once with `--no-incremental` before the first
measurement and was not touched again.

Right after the build:

```
Integration over 5 counted runs
  warm-up: 49.90 / 47.17 / 47.36 / 48.80 / 47.63 / 48.12 / 47.64 / 48.41 / 49.54 / 50.38 / 62.04 / 64.48 (discarded, 12)
  runs   : 57.76 / 52.44 / 49.12 / 47.28 / 47.85
  median : 49.12 s
  mean   : 50.89 s
  max    : 57.76 s
  spread : 21.3 % of the median
  built  : 638 s before the first counted run
```

About an hour later, with no rebuild:

```
Integration over 5 counted runs
  warm-up: 58.44 / 57.68 (discarded, 2)
  runs   : 58.09 / 57.36 / 57.06 / 57.28 / 60.44
  median : 57.36 s
  mean   : 58.05 s
  max    : 60.44 s
  spread : 5.9 % of the median
  built  : 4,181 s before the first counted run
```

**The two medians differ by 14.4 percent of the larger one. The fourth acceptance box stays
unticked.**

### What the two mechanisms did achieve

The settle clock worked. The first measurement's counted runs did not start until the tree had
been built for 638 s, and twelve warm-up runs filled that wait. The effect this item was filed for
is gone: the measurement taken right after the build is now the **faster** of the two.

The warm-up discard worked. The first measurement's twelve discarded runs show the machine flat
near 48 s for ten runs, then a jump to 62.04 s and 64.48 s. Without the discard those two runs
would have entered the median.

### Why the criterion still fails, and why the build is not the cause

The later measurement is the slower one, by about 17 percent. A build cannot explain that. The
tree was older at the second measurement, not fresher.

Every part of the run got slower by about the same share:

| Step | Right after the build | An hour later |
|---|---|---|
| SQL container start | 7.2 s, on 14 of 17 runs | 9.4 to 9.7 s, on every run |
| `Application.Tests` | 4 s, on 12 of 17 runs | 6 s, on every run |
| `CLI.Tests` | 6 s, on 10 of 17 runs | 7 s, on every run |
| `API.Tests` | 11 s, on 9 of 17 runs | 12 to 13 s |
| `Infrastructure.Tests` | 8 s, on 8 of 17 runs | 11 to 12 s |

A slowdown spread evenly across the container start and all four test projects is a change in the
machine, not a change in the tests. The first measurement also caught a transient: warm-up runs 11
and 12 read 62.04 s and 64.48 s, their container starts read 8.5 s, 10.5 s and 9.6 s, and the
counted runs then decayed from 57.76 s back to 47.28 s.

So this machine moves by 15 to 20 percent over an hour, for a reason this item did not set out to
find and has not removed. Naming that reason would go beyond the evidence: thermal state, a
background process, and a power-plan change would all look exactly like this.

## Acceptance criteria

- [x] `scripts/measure-test-modes.ps1` discards warm-up runs before it computes the median, and
      the number it discards is visible in the output rather than hidden in the code.
- [x] The script prints the discarded runs as well as the counted ones. A reader can see the
      decay and judge whether the run settled.
- [x] The script reports a stability figure beside the median, so a reader can tell a settled
      measurement from one that is still moving. The item names the figure it chose and why.
- [ ] Running the same Mode twice on one unchanged tree, once right after a build and once an
      hour later, produces medians within 10 percent of each other. Record both, with every run.
      **Not met. Both measurements are recorded above, with every run.** The medians differ by
      14.4 percent. The build is not the cause: the measurement taken right after the build is the
      faster one, and the whole machine ran 15 to 20 percent slower an hour later, container start
      included. The two mechanisms this item built both work; a second source of variance, which
      this item did not set out to find, is what keeps the box unticked.
- [x] `docs/development/testing-workflow.md` states the warm-up rule where it states the
      measurement rule, so the next person setting a target does not have to find this item.
- [x] `tests/MeasureTestModes.Tests.ps1` covers the discard: a stubbed run list with a slow head
      and a flat tail reports the tail's median, not the whole list's.
- [x] Every open item that carries a numeric speed threshold measured with this script is listed
      here, with a note saying whether its threshold survives re-measurement. Backlog 133 is one;
      the list names the rest.

## Open items with a threshold from this script

Searched on 2026-09-10 across `backlog/` and `backlog/blocked/` for `measure-test-modes` and
`median of`. Three items matched, and one of them is this one.

- **133 — Reuse the SQL test container between runs.** Carries 49.59 s as the Integration baseline
  and asks for a median of five warm runs. That 49.59 s came from backlog 128 and inherits the
  warm-up error, so it is probably high. The item sits at `Stage: 2-design` with pull request #402
  open, so it can adopt the new defaults before it measures anything. **Its threshold does not
  survive. Backlog 133 re-measures the 49.59 s baseline with the new script before it states a
  saving.**
- **140 — Account for the unexplained E2E harness overhead.** Asks for medians of five runs. It has
  taken no measurements of its own yet, and it already calls its numbers an estimated remainder
  rather than observed time. **Nothing to re-measure. It inherits the new defaults when it starts.**
- **146 — One machine-wide lock for local test runs.** Did not match the search, and it is listed
  here because it carries numbers. They were timed by hand around `-Mode PowerShell` runs rather
  than produced by this script, and they compare two lock shapes rather than setting a speed
  threshold. **Not affected.**

The three items in `backlog/blocked/` carry no speed threshold from this script.

## Out of scope

- Re-deriving the numbers in items that are already shipped and frozen. Backlog 128's record
  stays as it was written; this item does not rewrite history.
- Making the tests themselves faster. This item is about measuring them honestly.
- The virus scanner and the file system cache. Naming the cause is enough; this item does not
  try to remove it.

## Notes / dependencies

- Filed 2026-09-10 out of the decision on backlog 134, which was declined because settled
  measurement moved its prize below its own threshold. See `backlog/done/134-*.md`.
- The script's own documentation says the numbers "measure test execution and not compilation"
  because it builds once and passes `-NoBuild`. That is true about compilation and is the reason
  the warm-up effect went unnoticed: it is not compilation.
- Backlog 133's acceptance criteria are written as five-run medians and would inherit the same
  error. It is open with pull request #402.
- Spec: none — Difficulty is `moderate`, so the item goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-09-10-test-measurement-warm-up-plan-150.md`
