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
- Task 5 (Gate and baselines): done at 880ea480. Tests: the Gate at a2a9d9e4 passed with AHKFLOW_GATE_REUSE=off, all 73 Suites, 6 Workers; baselines refreshed from it. Deferrals: none.

## Failure edge to 4-execute (2026-10-28)

**Red evidence:**

```
Local review of 0112b0b0: jq-disabled shim probes forward as Auto, contradicting parser-dependent assertions; removing the existing-progress guard breaks the skipped Ship-failure state but not its named replacement.
```

**Recovery task:** Review recovery 1: control jq-present and jq-absent shim environments. Review recovery 2: restore existing-progress Ship-failure coverage and prove progress survives without closure lookup.


- Review recovery 1: implemented explicit jq responses and deterministic absent-jq forwarding checks for both payloads. Full guard Suite and focused mutation checks passed.
- Review recovery 2: restored the existing-progress Ship-failure edge with success and preservation assertions. Full transition Suite passed; removing the existing-file guard fails the focused case.
- Review recovery verification: fixes committed as 148fa7cc and 38f36a3e. Build, format, all 73 PowerShell Suites (reuse off), and full coverage passed. Coverage: 94.8% line, 83.2% branch. The transition commit's EOF blank line is removed by these recovery entries; recheck the final commit range.
- Recovery Simplify: reviewed the two test corrections at 4cdcb0d9 using code-simplifier guidance. Nothing to simplify: explicit jq modes preserve the dependency boundary, and the restored Ship edge remains distinct from post-closure recovery. Refresh S-A timing for the three-edge skip at Verify.

## Failure edge to 4-execute (2026-10-28)

**Red evidence:**

```
D2 corrected S-A: full-loop runs 24.307, 23.813, 23.423 s; three-edge-skip runs 19.414, 22.814, 24.483 s. Medians 23.813 and 22.814 s; saving 0.999 s is below the required 1 s.
```

**Recovery task:** Reject S-A row 53 and restore all legal loop edges while retaining existing-progress recovery assertions. Run StageTransition, then Simplify and the Verify Gate.

- D2 recovery: row 53 rejected at 0.999 s saving (23.813 before, 22.814 after). Removed the skip table and condition; kept existing-progress recovery assertions.
- D2 recovery verification: the complete StageTransition Suite passed in 68.6 s with every legal edge restored. Simplify scope is only removal of the skip table and condition; no further simplification needed.
