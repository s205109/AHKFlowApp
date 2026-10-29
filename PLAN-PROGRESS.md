# Plan progress: backlog 201

Plan: `docs/superpowers/plans/2026-10-29-apply-the-deferred-git-fixture-test-speed-ups-plan-201.md`

- Task 1 (template in WorktreeMergedCleanup.Common.ps1): done at 9fc18691. Tests: the three cleanup Suites pass alone, and on Linux for `WorktreeMergedCleanup`; T-A summed 16.8 s before, 6.8 s after. Deferrals: none.
- Task 2 (WorktreeMergedCleanup rows 120, 121): done at ebacc677. Both rows rejected on a bound below 1 s (0.48 s, 0.16 s); no code change. Suite median 34.6 s before, 25.3 s after (T-A). Deferrals: none.
