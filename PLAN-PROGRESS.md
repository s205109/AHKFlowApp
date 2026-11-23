# Plan progress: backlog 216

Plan: `docs/superpowers/plans/2026-11-22-worktree-remove-hook-growing-log-plan-216.md`

- Task 1 (Read-LogText): in progress at d2adff12. Step 10 is not met yet. Tests: the new case failed first against `Get-Content -Raw`, in 27 of 200 reads. `WorktreeRemoveHook.Tests.ps1` passed alone 3 times under pwsh and once under Windows PowerShell 5.1. The full `suites` job passed 8 times on d2adff12, runs 11 to 18: all 75 suites each time, with job exit code 0. Only runs 11, 14, 16 and 18 count, because runs 12, 13, 15 and 17 printed a Lane pool sharing line. So no three counted runs are in a row yet. Deferrals: none. Notes: `backlog/done/137-...` got an ignore-file header, because this change moved the lines it cites.
