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

## Failure edge to 4-execute (2026-10-29)

**Red evidence:**

```
$env:AHKFLOW_GATE_REUSE = 'off'; pwsh .\scripts\test-fast.ps1 -Mode PowerShell   (at 3d113d68)
**1 of 73 suite(s) failed:** CitationFreshness.Tests.ps1
This repository must hold no stale citation, found 2:
  backlog/done/137-powershell-worktree-suites-fail-13b421fb.md:68 tier 2: (`tests/WorktreeSweepRemoteBase.Tests.ps1:478`, "Test-Path -LiteralPath '$parentMarkerObserved'") does not match, and the text is on lines 519, 520.
  backlog/done/137-powershell-worktree-suites-fail-13b421fb.md:76 tier 2: (`tests/WorktreeSweepRemoteBase.Tests.ps1:510`, "foreach ($id in @($parent.Id, $childId))") does not match, and the text is on lines 545, 551.
```

**Recovery task:** R1: re-point the backlog/done/137 citations that R-B moved (committed as 660915b1). R2: derive the S-A committer date from the current time, so it never falls behind the seed commit (final review, Important 1).

- Recovery R1 and R2: done at b2b6584d. R1 re-pointed the backlog/done/137 citations (660915b1); CitationFreshness passes. R2 derives the S-A date from the clock; the Sweep Suite passes, and a date one day back fails the first S-A case. Deferrals: none.

## Failure edge to 4-execute (2026-10-29)

**Red evidence:**

```
$env:AHKFLOW_GATE_REUSE = 'off'; pwsh .\scripts\test-fast.ps1 -Mode PowerShell   (at db2d938c)
**1 of 73 suite(s) failed:** CitationFreshness.Tests.ps1
This repository must hold no stale citation, found 2: PLAN-PROGRESS.md lines 31 and 32.
They are the old item 137 citations, quoted word for word as evidence in the first failure record.
```

**Recovery task:** R3: mark the two quoted evidence lines in PLAN-PROGRESS.md with citation-check:ignore, so the checker skips them.

