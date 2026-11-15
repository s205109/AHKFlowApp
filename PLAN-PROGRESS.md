# Progress: backlog 203

Plan: `docs/superpowers/plans/2026-11-15-non-e2e-net-test-audit-plan-203.md` (frozen at eb69059 in the plans repository).

- Task 1: done at -. Tests: driver dry pass ok, session script 3261 results, moved test refused. Deferrals: none.
- Task 3: done at da7326c2. Tests: Fast 5/5 and Integration 5/5 counted runs passed, B = bd683fc5. Deferrals: none.
- Task 2: waiting. The Gate fails on this machine in WorkflowPdfGenerator.Tests.ps1 (Edge 157 render race). It runs after the fix is merged into this branch.
- Task 4: done at 2b3500f9. Tests: refuter upheld 2 of 2, worktree clean; 5 rows approved. Deferrals: none.
- Task 5: done at 940c6a48, d8516796, 45c337c6. Tests: changed classes pass; row 2 merged test fails on the no-history mutation; row 3 fails on a 1 s default. Deferrals: rows 4 and 5 wait for Task 7.
- Task 6: done at 905921eb. Tests: middle Fast 5/5, Integration 5/5 passed; rows 1-3 save 2.10, 2.53, 2.01 s, all kept. S = fbf90f71. Deferrals: none.
- Task 7: done at 6cae7882. Tests: row 4 CLI suite 32/32, fails 15/21 without X-Test-Oid; after Fast 5/5, Integration 5/5 passed; row 4 kept 2.86 s, row 5 reverted (-0.04 s). Deferrals: row 5 and 18 P8 proposals listed.
- Task 2: done at db0c306a. Tests: Gate before 3/3 counted runs passed on 0cb0ec55, median 511.09 s. Deferrals: none.
