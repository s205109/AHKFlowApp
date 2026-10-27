# Plan progress: backlog 195

Plan: `docs/superpowers/plans/2026-10-27-apply-the-deferred-test-audit-speed-ups-plan-195.md`

- Task 1 (WatchTask): done at d9394970. Tests: `WatchTask.Tests.ps1` passes alone; Suite median 42.0 s before, 31.2 s after. Deferrals: none.
- Task 2 (CiPowerShellSuiteRunner): done at def4d881. Tests: `CiPowerShellSuiteRunner.Tests.ps1` and `SuiteWorkerCount.Tests.ps1` pass alone; Suite median 113.4 s before, 82.0 s after. Deferrals: none.
- Task 3 (StageTransition): done at f6627379. Tests: `StageTransition.Tests.ps1` passes alone; Suite median 92.8 s before, 65.5 s after. Deferrals: none; row 67 applied in part (P10).
- Task 4 (AgentWorktreeGuard): done at 2c3461c6. Tests: `AgentWorktreeGuard.Tests.ps1` passes alone; Suite median 42.6 s before, 38.6 s after (one back-to-back pair). Deferrals: none; row 22 rejected.

## Failure edge to 4-execute (2026-10-27)

**Red evidence:**

```
Gate step 3 at da0ed8e4, with AHKFLOW_GATE_REUSE=off: pwsh .\scripts\test-fast.ps1 -Mode PowerShell
FAILED: CitationFreshness.Tests.ps1 (exit code 1)
**1 of 73 suite(s) failed:** CitationFreshness.Tests.ps1
"This repository must hold no stale citation, found 2":
- tests/AgentWorktreeGuard.Tests.ps1 line 1157 cites line 2302 for "    $heredocAmbiguousCases = @(". The text is now on line 2327.
- tests/AgentWorktreeGuard.Tests.ps1 line 1158 cites line 2391 for "    $hereStringAmbiguousCases = @(". The text is now on line 2416.
The lines moved in Task 4 (first at 3acda874) and again in Simplify. Both citations point into their
own file, so the quoted text also matches the citation line. That makes the move an error, not a warning.
The four changed Suites passed: AgentWorktreeGuard 75.5 s, StageTransition 105.7 s,
CiPowerShellSuiteRunner 114.9 s, WatchTask 40.2 s.
```

**Recovery task:** Task 5 recovery: point the two citations at lines 1157 and 1158 of tests/AgentWorktreeGuard.Tests.ps1 at lines 2327 and 2416, run CitationFreshness.Tests.ps1 alone, then pass Execute and Simplify again and rerun the Gate at Verify.

- Task 5 recovery: done at d7c02d19. Tests: `CitationFreshness.Tests.ps1` passes alone, and the citation check reports no problem. Next: Simplify, then the Gate at Verify again.
