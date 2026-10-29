# Plan progress: backlog 201

Plan: `docs/superpowers/plans/2026-10-29-apply-the-deferred-git-fixture-test-speed-ups-plan-201.md`

- Task 1 (template in WorktreeMergedCleanup.Common.ps1): done at 9fc18691. Tests: the three cleanup Suites pass alone, and on Linux for `WorktreeMergedCleanup`; T-A summed 16.8 s before, 6.8 s after. Deferrals: none.
- Task 2 (WorktreeMergedCleanup rows 120, 121): done at ebacc677. Both rows rejected on a bound below 1 s (0.48 s, 0.16 s); no code change. Suite median 34.6 s before, 25.3 s after (T-A). Deferrals: none.
- Task 3 (WorktreeMergedCleanupSweep rows 123, 124): done at 63e3d388. Tests: Sweep Suite passes alone; both past-date mutations fail their case. Suite median 31.1 s before, 25.6 s after; S-A 5.9 s before, 1.8 s after. Deferrals: none.
- Task 4 (WorktreeMergedCleanupEligibility rows 94-98, 106, 107): done at d368dd9c. Tests: Suite passes alone after each row; four mutations each fail the named case. Suite median 34.4 s before, 30.7 s after. Deferrals: none.
