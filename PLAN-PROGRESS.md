# Plan progress: backlog 214

Task 1: done at 4233e9b7. Tests: probe P1 on 5.1 and 7.6. Deferrals: none.
Task 2: done at 981ddf44. Tests: Step 3 gave 3 FAIL lines, all from the new 5.1 reuse case. Step 5 gave no FAIL line and `passed. 39 cases.` Deferrals: none.
Task 3: done at 01364c74. Tests: Step 3 gave 12 FAIL lines (7 behaviour, 5 source rule). Step 5 gave no FAIL line and `passed. 41 cases.` Step 6 gave 3 FAIL lines with the Wait line removed, then the line was restored and the count was 5. Step 7: guarded removal printed `removed=True skipped=False error=`, then `powershell.exe -NoProfile -File scripts\run-coverage.ps1` printed `Shared SQL test container ready in 10131.745 ms.`, `All per-assembly coverage thresholds met.` and `Coverage run complete.`, exit 0, and the container exists again. Deferrals: none.
