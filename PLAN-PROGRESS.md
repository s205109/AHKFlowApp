# Plan progress: backlog 195

Plan: `docs/superpowers/plans/2026-10-27-apply-the-deferred-test-audit-speed-ups-plan-195.md`

- Task 1 (WatchTask): done at d9394970. Tests: `WatchTask.Tests.ps1` passes alone; Suite median 42.0 s before, 31.2 s after. Deferrals: none.
- Task 2 (CiPowerShellSuiteRunner): done at def4d881. Tests: `CiPowerShellSuiteRunner.Tests.ps1` and `SuiteWorkerCount.Tests.ps1` pass alone; Suite median 113.4 s before, 82.0 s after. Deferrals: none.
- Task 3 (StageTransition): done at f6627379. Tests: `StageTransition.Tests.ps1` passes alone; Suite median 92.8 s before, 65.5 s after. Deferrals: none; row 67 applied in part (P10).
- Task 4 (AgentWorktreeGuard): done at 2c3461c6. Tests: `AgentWorktreeGuard.Tests.ps1` passes alone; Suite median 42.6 s before, 38.6 s after (one back-to-back pair). Deferrals: none; row 22 rejected.
