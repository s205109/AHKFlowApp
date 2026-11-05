# Plan progress: backlog 194

Plan: `docs/superpowers/plans/2026-11-01-net-test-audit-plan-194.md`

- Task 1 (workflow .NET mode): done at e6d55113. Tests: harness 6/6, seam mutation failed H3. Deferrals: none.
- Task 2 (Gate before): done at c1e1c9cb. Tests: Gate median 415.51 s, coverage step 180.19 s, 3 counted runs green. Deferrals: none.
- Task 3 (ranking and Candidate groups): done at 1575d0b5. Tests: before session 5/5 counted runs, 108/108 each, test count equals TRX count; B is d98dea6f. Deferrals: none.
- Task 4 (run 1 and approval): done at 01c526d4. Tests: 25/25 audited tests failed on the planted bug, 12 upheld, 13 refuted, tree clean after every refuter. Deferrals: rows 24, 25, 30-37 rejected, in test-audit-deferred.md.
- Task 5 (apply the rows): done at b6061ac5. Tests: every changed class ran green in Release; every MERGE row's target failed on its planted bug (rows 2, 5, 8, 9, 10, 20-23, 26-29); row 15's pin went RED, GREEN, RED on the 1000 ms fallback. Deferrals: none. Rows 8+17 share commit 0d6a45e7.
- Task 6 (after session and per-row times): done at d7fee61c. Tests: after session 5/5 counted runs, 90/90 each, median 76.07 s; every row saved >= 0.5 s (smallest row 19, 0.72 s). Deferrals: none, no row reverted.
- Task 7 (rebalance): done at d6695654. Tests: full E2E run 90/90 with no fixture-data errors; rebalance session 5/5 runs, 90/90, median 70.32 s; slowest busy 64.5 -> 59.1 s, kept. Deferrals: none.
- Task 8 (Gate after and result): done at 26568cf7. Tests: Gate 3 counted runs green, median 402.19 s, coverage step 159.51 s. Deferrals: none.
