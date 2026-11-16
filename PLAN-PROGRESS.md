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
