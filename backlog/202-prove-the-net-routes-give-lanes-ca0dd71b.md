# 202 - Prove the .NET routes give Lanes back on failure

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (test Suites only)
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

`scripts/test-fast.ps1` and `scripts/run-coverage.ps1` must give their Lanes and the checkout
lock back when a `dotnet` step fails. Today no test proves it. This item adds one failure case
for each script.

## User story

As a developer who runs the test slices, I want a failed run to free its Lanes, so that the next
run on the machine does not wait for Lanes that nobody holds.

## Acceptance criteria

- [ ] `tests/TestFastDotnetProgress.Tests.ps1` has a case `Fast Lane route: failure`. It runs
      `test-fast.ps1` with a `dotnet` stub that fails, and it checks that the checkout lock is
      free after the script returns.
- [ ] `tests/CoverageRunnerProgress.Tests.ps1` has a case `Coverage Lane route: direct failure`.
      It does the same for `run-coverage.ps1`.
- [ ] Each failure case checks the checkout lock before it checks the error message. A throw in
      the `finally` block replaces the child's error, so the order matters.
- [ ] Both cases fail when the run end (`Exit-AhkFlowLaneRun`) moves from the `finally` block to
      the end of the `try` block in its script. The pull request shows that failure.
- [ ] All PowerShell Suites pass.

## Out of scope

- The Lane run interface that backlog 193 tried and reverted.
- Changes to the scripts themselves. This item adds tests only.

## Notes / dependencies

- Backlog 193 found this gap. A failure throws inside the `try` block, so a run end moved out of
  the `finally` block still passed every existing case. See
  `docs/development/architecture-pilot-record.md`.
- Commit `53fe6ab8` on the branch `feature/wt-architecture-pilot-on-one-tested-module` holds
  working code for both cases. It adds a `-Fail` switch to `Test-DotnetLaneRoute` in
  `tests/DotnetLane.Common.ps1`. The 193 revert removed it because the pilot verdict was negative,
  not because the cases were wrong. In 193, a mutation that moved the run end failed both cases
  with the checkout-lock message, and the owner case still passed.
- Spec: none — a small test-only change; this item is the spec.
- Plan: none — the commit named above is the reference implementation.
