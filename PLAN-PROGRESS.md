# Plan progress - backlog 106. Draft PR: https://github.com/s205109/AHKFlowApp/pull/324
Task 1 | 674d1336 | checks: both directions green - a merge that left the item open fails, one that moved it to done/ passes | deferrals: none
Task 2 | e1d69914 | checks: 6 table cases + 2 default-limit cases green; mutation-checked the bulk-edit case (flipping Expect to 0 fails with the real message) | deferrals: none
Task 3 | c9a9a584 | checks: real backlog/ clean, base ref resolves; full suite runner started | deferrals: none
Task 3 runner | all 34 PowerShell suites passed, BacklogStaleOpen.Tests.ps1 included (14s)
Task 4 | 38a55e7a | checks: citation freshness green (repo + plans), process parity green, 9 doc-reading suites pass; the workflow.md paragraph shifted 9 citations by ten lines, all repointed | deferrals: none
Stage 5 | b437c574 | simplify: folded three git-output idioms into Invoke-BacklogGit's Text property; suite still green | deferrals: none
Stage 6 | gate green | build 17 projects 0 warnings, format clean, 34/34 PowerShell suites, coverage line 94.6% branch 82.6% all thresholds met, git diff --check main...HEAD clean | artifact: tests/BacklogStaleOpen.Tests.ps1, no exemption claimed
