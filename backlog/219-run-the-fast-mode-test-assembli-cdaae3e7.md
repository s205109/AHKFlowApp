# 219 - Run the Fast Mode test assemblies side by side

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test scripts)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The Fast Mode of `scripts/test-fast.ps1` runs its five unit test assemblies in one `dotnet test`
call. Backlog 204 made the coverage step and the Integration Mode run their test projects side by
side. This item tries the same for the Fast Mode, and keeps it only when it saves time and the
tests stay stable.

## User story

As the developer of this repository, I want the Fast Mode to use the machine's idle cores, so
that the pre-push check and a local test run finish sooner.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [x] A record states the Fast Mode time in sequence and side by side, each the median of five
      counted runs.
- [ ] A record states the Soak runs and their failures for the side-by-side runs, for UI.Blazor
      at least.
      Not true: no Soak ran. Neither `2` nor `Budget` saved time by D7 of the plan, so no setting
      was a candidate, and the plan soaks only a candidate. The record says so in its section
      "Soaks". So the record has no Soak runs and no UI.Blazor result to state.
- [x] The Fast Mode runs its assemblies side by side only when the record shows a saving and no
      new failure. Otherwise the record says why the change was dropped.

## Out of scope

- The coverage step and the Integration Mode, which backlog 204 changed.
- The E2E Mode, which has one project.
- Changing which tests CI runs.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/489
- Filed by backlog 204 under decision D13 of its spec: the coverage Soak at `Budget` showed no
  UI.Blazor failure in 20 runs. The record is in `docs/development/cycle-time-record.md`, section
  "Run the .NET test projects side by side (backlog 204)".
- Backlog 204's spec (D1) puts the possible saving at about 5 s, because the five assemblies
  already run in one call. The item may end as a record that drops the change.
- The Slice runner is `scripts/slice-runner.common.ps1`. Its `-SlicesAtOnce` takes a whole
  number or `Budget`.
- Measure on mains power. Backlog 204's first sessions ran partly on battery and were discarded.
- Spec: none — moderate item, planned directly. The timing and Soak rules come from backlog 204's spec.
- Plan: `docs/superpowers/plans/2026-11-24-run-the-fast-mode-test-assemblies-side-by-side-plan-219.md`
