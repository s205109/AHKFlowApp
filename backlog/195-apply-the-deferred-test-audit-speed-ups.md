# 195 - Apply the deferred test-audit speed-ups

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (test suites)
- **Difficulty**: complex
- **Stage**: 6-verify

## Summary

Backlog 188 audited ten PowerShell Suites and applied only the cheapest changes, within a limit
of about five hours of runs. It deferred 101 proposals worth about 172 seconds of Suite time,
listed in `docs/development/test-audit-deferred.md`. This item applies or rejects the 79 rows of
four Suites, about 106 seconds. Backlog 201 carries the other 22 rows.

## User story

As a developer, I want the slowest PowerShell Suites to run faster without losing any check, so
that the Gate and CI finish sooner.

## Acceptance criteria

The four Suites are `StageTransition`, `WatchTask`, `CiPowerShellSuiteRunner` and
`AgentWorktreeGuard`.

- [x] Every row of the four Suites in `docs/development/test-audit-deferred.md` is marked applied
      or rejected, with a one-line reason for each rejection.
- [x] `docs/development/cycle-time-record.md` holds the before and after median of each of the
      four Suites, each Suite run alone, one warm-up plus three counted runs.
- [x] Every row timed on its own under D2 of the spec has its two medians recorded, and no kept
      change saved less than 1 s.
- [x] Every applied MERGE or REMOVE, and every reworked case removed under D5 of the spec, names in
      its commit body the test that still catches the defect, or the behaviour that is gone.
- [x] Every Suite this item changes passes in the Gate.
- [x] `baselineSeconds` in `tests/powershell-suites.json` of every changed Suite comes from a
      Gate run at Verify with evidence reuse off.

## Out of scope

- The six Suites that build git fixtures. Backlog 201 carries their rows.
- Auditing Suites that backlog 188 did not audit. Run the `test-audit` workflow for those, as
  `docs/development/test-audit-workflow.md` describes.
- `tests/WorktreeRemoveHook.Tests.ps1`, which backlog 068 owns.

## Notes / dependencies

- Backlog 188 has merged, with `docs/development/test-audit-deferred.md`,
  `docs/development/test-audit-workflow.md` and the audit record.
- The four Suites hold 75 SPEED UP rows and 4 REWORK rows. Two rows need a change to a script under
  `scripts/`: the StageTransition 15-edge loop and the in-process GitHub Actions worker count.
- Batch 1 showed that an auditor's estimate can be far off: a seed cache saved 1.7 of an
  estimated 17 seconds. Decision D2 of the spec says which rows are timed on their own.
- Split at Design into this item and backlog 201, decision D8 of the spec. Backlog 201 is stacked
  on this branch.
- Spec: `docs/superpowers/specs/2026-10-27-apply-the-deferred-test-audit-speed-ups-design-195.md`
- Plan: `docs/superpowers/plans/2026-10-27-apply-the-deferred-test-audit-speed-ups-plan-195.md`.
