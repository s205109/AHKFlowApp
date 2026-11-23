# Plan progress: backlog 216

Plan: `docs/superpowers/plans/2026-11-22-worktree-remove-hook-growing-log-plan-216.md`

- Task 1 (Read-LogText): done at d2adff12. Tests: the new case failed first against `Get-Content -Raw`, in 27 of 200 reads. `WorktreeRemoveHook.Tests.ps1` passed alone 3 times under pwsh and once under Windows PowerShell 5.1. The full `suites` job counted 8 times in a row on d2adff12, runs 11 to 18: all 75 suites passed each time, with job exit code 0. Deferrals: none. Notes: runs 1 to 17 printed a Lane pool sharing line in 10 runs. Every line named only stale run records from 2026-09-17 to 2026-11-16, whose locks were not held. So those lines did not show another run, and runs 11 to 18 were judged again with that rule. `backlog/done/137-...` got an ignore-file header, because this change moved the lines it cites.
