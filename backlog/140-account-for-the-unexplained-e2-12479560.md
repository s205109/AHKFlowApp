# 140 - Account for the unexplained E2E harness overhead

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (measurement first)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

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

- [ ] This item records where the unexplained time goes, measured, with each step named and timed.
- [ ] The measurement separates the SQL container start, the Blazor publish, Playwright browser
      install and launch, the API and SPA host start, and any time the test host reports outside
      the tests themselves.
- [ ] The solution build is timed separately, and this item states whether it belongs in the E2E
      figure at all. A `-NoBuild` run excludes it; a plain `dotnet test` does not.
- [ ] Every figure is the median of five runs, with all five runs and the maximum written down.
- [ ] The item states whether a fix is worth filing, and files it or says why not.

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
- Difficulty is `to-be-determined` on purpose: nobody knows yet whether the answer is the browser
  install, the host start, container teardown, or something else.
- Filed out of backlog 131. The arithmetic and its sources are in
  `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`.
- Spec: none — not yet at Design.
- Plan: none — not yet at Plan.
