# 204 - Run the .NET test projects side by side

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (`scripts/run-coverage.ps1`, `scripts/test-fast.ps1`)
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

## Summary

The Gate's coverage step runs the eight .NET test projects one after another
(`scripts/run-coverage.ps1:98`, "foreach ($project in $coverageProject) {"). The Fast Mode and
the Integration Mode also run their projects in sequence. This item tries running them side by
side, and keeps the change only when it saves time and the tests stay stable.

## User story

As the developer of this repository, I want the .NET test steps to use the machine's idle cores,
so that a code change reaches a green Gate sooner.

## Acceptance criteria

- [ ] A record states the coverage step time with the projects in sequence and side by side, each
      the median of five counted runs.
- [ ] A record states the soak runs and their failures for the side-by-side runs, for UI.Blazor
      and E2E at least.
- [ ] The runner runs the projects side by side only when the record shows a saving and no new
      failure. Otherwise the record says why the change was dropped.
- [ ] The coverage report still holds the results of every coverage project.

## Out of scope

- Changing which tests CI runs.
- The test audits, which backlogs 194 and 203 carry.

## Notes / dependencies

- Filed by backlog 194 at its Design (decision D4 of its spec), from section 4.6 of the
  2026-10-17 triage:
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/dotnet-tests.md`.
- The triage measured 88.2 s for the seven non-E2E projects and 135.4 s for E2E, run one after
  another. It did not try any switch for parallel runs.
- Two risks to test first: CPU contention, which made backlog 114 raise the bUnit wait timeout,
  and file locks on the coverage output, which the test-run lock exists to prevent.
- Spec: none — Design writes it.
- Plan: none — Plan comes after Design.
