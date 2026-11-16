# Plan progress — backlog 204

Plan: `docs/superpowers/plans/2026-11-16-run-the-net-test-projects-side-by-side-plan-204.md`

- Task 1: done at f6da5b3f. Tests: pass (SliceRunner.Tests.ps1). Deferrals: none.
- Task 2: done at d1b853eb. Tests: pass (SliceRunner.Tests.ps1, ProgressParallel.Tests.ps1). Deferrals: the Linux-only case is not run here (no pwsh in WSL).
- Task 3: done at 288a4579. Tests: pass (CoverageRunnerProgress, CoverageSliceSkip, PrePushQuickChecks, TestFastPowerShellMode); real coverage run complete on the fourth try. Deferrals: E2E reload tests failed in 3 of 4 full runs and could not be reproduced; the soaks will measure it.
- Task 4: done at 1558dcd4. Tests: pass (CoverageRunnerProgress, TestFastDotnetProgress, CoverageSliceSkip, TestFastPowerShellMode); real Integration run passed. Deferrals: none.
- Task 5: done at da20b1a5. Tests: pass (MeasureTestModes.Tests.ps1). Deferrals: none.
- Task 6: done at d8566fd3. Tests: pass (MeasureEvidence.Tests.ps1; PowerShell Mode 74 of 75, then CitationFreshness after the citation fix). Deferrals: none.
- Task 7: done at 7e72ce88. Tests: n/a (measurement; CitationFreshness passed on the record). Deferrals: none.
- Task 8: done at e63fb45c. Tests: n/a (measurement; CitationFreshness passed on the record). Deferrals: none.
- Task 9: done at f7ef6762. Tests: Gate passed (PowerShell 75/75, Coverage at Budget). Deferrals: Fast Mode item and 5.1 issue wait for the human.

## Failure edge to 4-execute (2026-11-16)

**Red evidence:**

```
CI run 43961612031 at d147df44 (also 43961133473, 43961260324):
SliceRunner.Tests.ps1: FAIL  Windows PowerShell 5.1 runs the Slice runner
  The 5.1 driver printed no JSON: Exception calling ReadAllText: Could not find file ...\start-A.txt (driver.ps1:28)
build-test E2E: FAIL AHKFlowApp.E2E.Tests.VersionHistoryFlowTests.RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload
  element(s) not found 'It breaks these rules: Value under Window context must not contain double quotes.'
```

**Recovery task:** R-CI-1: make the 5.1 driver report the runner's message when Slice A never starts, read it on CI, state the root cause, then fix it test-first. R-CI-2: find out whether the E2E VersionHistoryFlowTests failure also happens on main; the CI E2E step runs plain dotnet test, not the Slice runner.

