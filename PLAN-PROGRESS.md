# Plan progress: backlog 220

Plan: `docs/superpowers/plans/2026-11-25-show-a-test-host-crash-next-to-a-failing-test-plan-220.md` (frozen in plans commit `7512bb9`)

- Task 1 (a test host crash is a run failure of its Slice): done at fe793bb0. Tests: `MeasureEvidence.Tests.ps1` passes alone, 17 cases. Case A, Case B and the edited blocked-line case failed first; Case A failed on the count (1 in place of 2). Mutation 1 (accept every outcome) failed Case A with 3 failures in place of 2. Mutation 2 (run errors only on a non-zero exit) failed Case A on its exit-0 example. Ruling: the plan expected "no failure in place of one" there; the run's own fallback failure `run|x` came instead, because nothing else explained the failed run. The mutation is still caught. Probes (Step 9): `Done: exit code 1, 1 run error(s): The active test run was aborted. Reason: Test host process crashed` for Integration and for Coverage. Reader (Step 10): `Done: 1 failure(s) in PowerShell 7.6.10.` and `Done: 1 failure(s) in PowerShell 5.1.26100.9818.` for Integration; `Done: 2 failure(s) in PowerShell 7.6.10.` and `Done: 2 failure(s) in PowerShell 5.1.26100.9818.` for Coverage, the second being the expected `no coverage file`. Each gave exactly one `run | UI.Blazor | <crash>` line. Deferrals: none.
- Simplify: four reviewers (reuse, simplification, efficiency, altitude). Fixed in a2ca47d2: `Read-AhkFlowTrxXml` shares the TRX loader of `Get-AhkFlowTrxFailure` and `Get-AhkFlowTrxRunError`; Case A reuses the shared crash Slice. Ruling: that Slice now carries the Warning RunInfo, so Case B has it too; a Warning gives no failure, so Case B's output is unchanged. Skipped: a third parse per Slice (tens of ms, the helpers are shared with test-fast.ps1), one helper for the Mode summary, merging the two counters, and a new Kind `crash` (D1 chose against it).
- Verify: the verification artifact is the suite plus the probes. `MeasureEvidence.Tests.ps1` 17 cases pass after the simplify pass, and Step 10 gives the same four `Done:` lines again under pwsh 7.6.10 and Windows PowerShell 5.1.26100.9818.
- Document: boxes 1, 2 and 3 ticked. Nothing else to document: no document describes the failure kinds, and the functions' comments carry the rule.
- Gate green at 2caca04a. Build 0 errors, 0 warnings; format clean; PowerShell 75 of 75 suites passed; Coverage skipped (every changed file is excluded); `git diff --check main...HEAD` clean.

## Failure edge to 4-execute (2026-11-25)

**Red evidence:**

```
Outside review round 1, finding 1 (required, correctness): two RunInfo errors with the same cause in one Slice of one run give two failures with one key, so the Soak table counts that run twice. Scratch repro dup-220.ps1 on the real Integration crash TRX with its RunInfo duplicated printed: 'run | UI.Blazor | The active test run was aborted. Reason: Test host process crashed | 2 | 2 | not cleared' and 'Done: 2 failure(s) from one run.'
```

**Recovery task:** Task 2: a Slice gives one run failure per distinct cause (Outside review finding 1), with a regression case for two matching run errors in one run; also comment the log-only crash case (Claude review finding 1, optional)


- Task 2 (one run failure per distinct cause in a Slice): done at 49830ab4. Tests: `MeasureEvidence.Tests.ps1` passes alone, 18 cases; the new case `Two matching run errors in one Slice are one run failure, so a Soak counts that run once` failed first with two failures. The scratch repro now prints `| 1 | 1 | not cleared`, and the duplicated TRX gives `Done: 1 failure(s) in PowerShell 5.1.26100.9818.` Ruling: the fix removes duplicate causes in the reader, not in the Soak inputs as the reviewer suggested; two errors with one key in one run are one failure, and identical rows in the timing table carry nothing more. Also folded in: the comment on the log-only crash case (Claude review finding 1, optional). Deferrals: none.
- Simplify: nothing to simplify. The pass changes five lines of code, one comment and one case.
- Verify: the suite (18 cases) plus Step 10 again: the same four `Done:` lines under pwsh 7.6.10 and Windows PowerShell 5.1.26100.9818.
- Document: boxes 1, 2 and 3 still true. Nothing else to document.
