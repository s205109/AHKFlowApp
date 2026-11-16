# 212 - Measure harness fails when runs round to zero

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (measurement script and its test suite)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

`tests/MeasureTestModes.Tests.ps1` fails on a fast machine when the stubbed counted runs take less
than 5 ms. The harness rounds each run to 0.00 s, and the spread line then refuses a median of
zero. Every case in the suite must pass however fast the stubbed runs are.

## User story

As a developer who runs the PowerShell suites on Linux or on a fast machine, I want
`MeasureTestModes.Tests.ps1` to pass every time at the same revision, so that a red result means a
real defect and not a timing accident.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] The test-fast stub in `tests/MeasureTestModes.Tests.ps1` sleeps at least 20 ms on every run,
      whatever value a case writes into `stub\sleeps.txt`.
- [ ] `tests/MeasureTestModes.Tests.ps1` passes three times in a row in the
      `mcr.microsoft.com/dotnet/sdk:10.0` container that GitHub issue 468 used.
- [ ] The case "A slow head is discarded and the median is the flat tail" still fails against a
      harness that counts the warm-up runs in the median.
- [ ] `Get-AhkFlowRelativeSpread` still throws for an empty set of values, and for a median of zero.

## Out of scope

- Running the Linux-capable entries of `tests/powershell-suites.json` on Linux in CI. Issue 468
  lists it as an open question. It is a separate concern. File an item for it only when a second
  Linux-only failure shows up.
- The rounding of real measured runs. A real Mode run takes seconds, never under 5 ms.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/468
- Found during backlog 201. Seen at `41f5be1e` and, for the second case, at `316389e7`, in a
  `mcr.microsoft.com/dotnet/sdk:10.0` container with PowerShell 7.6.6. On Windows CI the suite
  passes, because each stubbed run takes at least 0.01 s there.
- Root cause, with evidence from the issue and from `main` at `fcf2c959`:
  1. The harness rounds each run's time to two decimals: (`scripts/measure-test-modes.ps1:239`, "$elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)").
  2. The report computes the spread of the counted runs: (`scripts/measure-test-modes.ps1:731`, "(Get-AhkFlowRelativeSpread -Values $seconds))").
  3. The spread refuses a median of zero: (`scripts/test-results.common.ps1:167`, "throw 'Get-AhkFlowRelativeSpread needs a median above zero.'").
  4. The failing run logged "run 1 of 2: 0.00 s" and "run 2 of 2: 0.00 s". The harness exited 1,
     and the case failed on its first assertion.
- Two cases failed in the issue's runs: the slow-head case, which sets `stub\sleeps.txt` at
  `tests/MeasureTestModes.Tests.ps1` line 528, and "The discarded runs are printed, with how many
  there were", at line 549. More cases stub every run at 0 ms, so they can fail the same way:
  the Fast Mode cases at lines 373, 391 and 807, and every Gate Mode case that uses
  `New-GateFixture` at line 357.
- The Gate path has the same exposure: (`scripts/measure-test-modes.ps1:408`, "SpreadPercent = [Math]::Round((Get-AhkFlowRelativeSpread -Values $runSeconds), 1)").
- Two fixes were open. The harness could print the report without a spread when the median is
  zero, or the stub could give every run a small, non-zero time. The plan picks the stub: a real
  Mode run takes seconds, so only a stub can produce a zero median. The slow-head case allows
  0.30 s of margin, so a 20 ms floor keeps its point.
- `scripts/test-results.common.ps1` is on the coverage-tooling list in
  `.github/code-paths-filter.yml`. A branch that changes it makes the pre-push hook build the
  solution and run the fast test slice.
- Spec: none — moderate bug with a known root cause
- Plan: docs/superpowers/plans/2026-11-16-measure-harness-zero-runs-plan-212.md
