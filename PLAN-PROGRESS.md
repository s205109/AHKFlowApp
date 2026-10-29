# Plan progress: backlog 201

Plan: `docs/superpowers/plans/2026-10-29-apply-the-deferred-git-fixture-test-speed-ups-plan-201.md`

- Task 1 (template in WorktreeMergedCleanup.Common.ps1): done at 9fc18691. Tests: the three cleanup Suites pass alone, and on Linux for `WorktreeMergedCleanup`; T-A summed 16.8 s before, 6.8 s after. Deferrals: none.
- Task 2 (WorktreeMergedCleanup rows 120, 121): done at ebacc677. Both rows rejected on a bound below 1 s (0.48 s, 0.16 s); no code change. Suite median 34.6 s before, 25.3 s after (T-A). Deferrals: none.
- Task 3 (WorktreeMergedCleanupSweep rows 123, 124): done at 63e3d388. Tests: Sweep Suite passes alone; both past-date mutations fail their case. Suite median 31.1 s before, 25.6 s after; S-A 5.9 s before, 1.8 s after. Deferrals: none.
- Task 4 (WorktreeMergedCleanupEligibility rows 94-98, 106, 107): done at d368dd9c. Tests: Suite passes alone after each row; four mutations each fail the named case. Suite median 34.4 s before, 30.7 s after. Deferrals: none.
- Task 5 (WorktreeSweepRemoteBase rows 125-130): done at 6c1b99e2. Tests: Suite passes alone; seed-check and hook-log mutations fail; parses in Windows PowerShell 5.1. Suite median 34.6 s before, 27.2 s after. Deferrals: none.
- Task 6 (BacklogStaleOpen row 118): done at 0b77939e. Tests: Suite passes alone and on Linux; one-fewer and write-nothing mutations fail. Suite median 23.8 s before, 17.1 s after. Deferrals: none.
- Task 7 (MeasureTestModes rows 134, 135): done at 0e5c6cba. Tests: Suite passes; lock, break and exit-code mutations fail. Suite median 48.5 s before, 47.7 s after. D2 stopwatches removed; tree equals HEAD. Linux before list saved, with one extra baseline exception from issue 468. Deferrals: none.

## Verify failure at 3d113d68

- Failing command: `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` with `AHKFLOW_GATE_REUSE=off`.
  `CitationFreshness.Tests.ps1` failed with "This repository must hold no stale citation, found 2".
  Both are in `backlog/done/137-powershell-worktree-suites-fail-13b421fb.md`, at lines 68 and 76.
  They cite `tests/WorktreeSweepRemoteBase.Tests.ps1` lines that R-B moved down by 41.
- Recovery task R1: update the seven citations of that paragraph to the current lines.
- Recovery task R2, from the final review: the S-A committer date `2030-01-01` stops being in the
  future on that date, and both S-A cases then fail. Derive the date from the current time.
