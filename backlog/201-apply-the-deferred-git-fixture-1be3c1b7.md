# 201 - Apply the deferred git-fixture test speed-ups

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (test suites)
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

Backlog 195 split its work in two at Design. This item applies or rejects the 22 deferred audit
rows of the six Suites that build git fixtures, about 66 seconds of Suite time. The rows are in
`docs/development/test-audit-deferred.md`.

## User story

As a developer, I want the slowest PowerShell Suites to run faster without losing any check, so
that the Gate and CI finish sooner.

## Acceptance criteria

The six Suites are `WorktreeMergedCleanupEligibility`, `WorktreeMergedCleanup`,
`WorktreeMergedCleanupSweep`, `WorktreeSweepRemoteBase`, `BacklogStaleOpen` and
`MeasureTestModes`.

- [ ] Every row of the six Suites in `docs/development/test-audit-deferred.md` is marked applied
      or rejected, with a one-line reason for each rejection.
- [ ] `docs/development/cycle-time-record.md` holds the before and after median of every Suite
      this item changes, each Suite run alone, one warm-up plus three counted runs.
- [ ] Every row timed on its own under D2 of spec 195 has its two medians recorded, and no kept
      change saved less than 1 s.
- [ ] Every applied MERGE or REMOVE, and every reworked case removed under D5 of spec 195, names in
      its commit body the test that still catches the defect, or the behaviour that is gone.
- [ ] Every Suite this item changes passes in the Gate.
- [ ] `baselineSeconds` in `tests/powershell-suites.json` of every changed Suite comes from a
      Gate run at Verify with evidence reuse off.

## Out of scope

- The four Suites that backlog 195 keeps: `StageTransition`, `WatchTask`,
  `CiPowerShellSuiteRunner` and `AgentWorktreeGuard`.
- Suites that backlog 188 did not audit.
- `tests/WorktreeRemoveHook.Tests.ps1`, which backlog 068 owns. It has its own copy of
  `New-TempGitRepo`, so a template in `tests/WorktreeMergedCleanup.Common.ps1` does not reach it.

## Notes / dependencies

- Split from backlog 195 at its Design, decision D8 of the spec. Decisions D1 to D6 and D9 of that
  spec apply here too, narrowed to these six Suites.
- Based on `main`. Backlog 195 merged as pull request 463, so this item no longer stacks on its
  branch. Both items edit the deferred list, the cycle-time record and
  `tests/powershell-suites.json`, so this item starts from the state 195 left them in.
- Most rows need new fixture code, so D2 times almost every row on its own. Backlog 188's seed
  cache saved 1.7 of an estimated 17 seconds.
- `tests/WorktreeMergedCleanup.Common.ps1` is shared by `WorktreeMergedCleanup`,
  `WorktreeMergedCleanupSweep` and `WorktreeMergedCleanupEligibility`. A template repository there
  changes all three Suites, so time all three before and after it.
- The two MERGE rows in `MeasureTestModes` were never tested by a refuter. Prove each with a
  mutation before you apply it (D5).
- Spec: `docs/superpowers/specs/2026-10-27-apply-the-deferred-test-audit-speed-ups-design-195.md`
- Plan: `docs/superpowers/plans/2026-10-29-apply-the-deferred-git-fixture-test-speed-ups-plan-201.md`.
