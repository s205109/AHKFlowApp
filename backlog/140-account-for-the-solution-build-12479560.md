# 140 - Account for the solution build time inside an E2E run

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (measurement first)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

About 60 s of an E2E run is not accounted for by any record, and the solution build is the likely
owner. This item measures where that time goes before anybody proposes a fix for it.

## User story

As a developer running the E2E slice, I want to know which step owns the largest unexplained part
of the wall clock, so that the next speed item attacks the real cost instead of a small one.

## Acceptance criteria

- [ ] This item records where the roughly 60 s goes, measured, with each step named and timed.
- [ ] The measurement separates the solution build from the E2E publish, the SQL container start,
      and the test host.
- [ ] Every figure is the median of five runs, with all five runs and the maximum written down.
- [ ] The item states whether a fix is worth filing, and files it or says why not.

## Out of scope

- Fixing anything. This item measures. A fix is a separate item, filed from the result.
- The E2E publish step. Backlog 131 measured it at about 11 s and closed.
- Parallel E2E stacks. That is backlog 132, and it attacks the 237 s test host, not this.

## Notes / dependencies

- The 60 s is arithmetic, not a measurement, and that is the reason this item exists. Backlog 128
  measured the E2E wall clock at 321.65 s with 237 s inside the test host. Backlog 131 measured the
  publish at about 11 s. Backlog 128 put a SQL container start at 10 to 20 s. Subtracting those
  leaves roughly 60 s with no owner.
- Start by confirming the 321.65 s and 237 s figures still hold. They were measured on 2026-09-03
  and the tree has moved since.
- `scripts/measure-test-modes.ps1` builds once and then runs with `-NoBuild`, so its numbers
  exclude the build on every run after the first. A measurement of build cost needs a different
  shape, and designing that shape is part of this item.
- Difficulty is `to-be-determined` on purpose: nobody knows yet whether the answer is one slow
  project, cold MSBuild startup, or something else.
- Spec: none — not yet at Design.
- Plan: none — not yet at Plan.
