# 220 - Show a test host crash next to a failing test in a Slice

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test scripts)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

In the Integration and Coverage Modes, the evidence reader of `scripts/measure-evidence.common.ps1`
reports a Slice failure only when no test of that Slice failed. So when a test fails and the test
host crashes in the same Slice, the verdict shows only the test failure. A Soak can then clear that
test failure as existing, and the crash is never reported. This item makes the crash show as its
own failure.

## User story

As the developer of this repository, I want every test host crash in a measured run to show in the
verdict, so that a setting that crashes the test host is never kept.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] In the Integration and Coverage Modes, a Slice whose TRX has a `RunInfo` with
      `outcome="Error"` gives one failure for that crash, also when a test of the same Slice failed.
- [ ] That failure blocks the setting, and a Soak never clears it as existing.
- [ ] `tests/MeasureEvidence.Tests.ps1` has a case for a crash next to a failing test in one Slice,
      for each of the two Modes.

## Out of scope

- The Fast Mode. Backlog 219 dropped its side-by-side change, so its evidence path did not change.
- The E2E Mode, which the measurement scripts do not time.

## Notes / dependencies

- Filed by backlog 219, Task 6 Step 4, from the gap its plan names in decision D9. The record is in
  `docs/development/cycle-time-record.md`, section "Run the Fast Mode test assemblies side by side
  (backlog 219)".
- The rule that hides the crash:
  (`scripts/measure-evidence.common.ps1:145`, "if ($exitCode -ne 0 -and $testFailures -eq 0) {"). <!-- citation-check:ignore: backlog 220 changed this line; the citation records the tree before the fix. -->
- Backlog 219 wrote and then reverted a reader for these `RunInfo` lines, for the Fast Mode only:
  `Get-AhkFlowTrxRunError` in commit `ddfc810f`, reverted in `c2d4a699`. Its test fixture writes a
  `RunInfos` block into a TRX. Both may be reused here.
- Spec: none — the item is `moderate`, so it skips Design.
- Plan: `docs/superpowers/plans/2026-11-25-show-a-test-host-crash-next-to-a-failing-test-plan-220.md`
