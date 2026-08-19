# Plan progress - backlog 106. Draft PR: https://github.com/s205109/AHKFlowApp/pull/324
Task 1 | 674d1336 | checks: both directions green - a merge that left the item open fails, one that moved it to done/ passes | deferrals: none
Task 2 | e1d69914 | checks: 6 table cases + 2 default-limit cases green; mutation-checked the bulk-edit case (flipping Expect to 0 fails with the real message) | deferrals: none
Task 3 | c9a9a584 | checks: real backlog/ clean, base ref resolves; full suite runner started | deferrals: none
Task 3 runner | all 34 PowerShell suites passed, BacklogStaleOpen.Tests.ps1 included (14s)
Task 4 | 38a55e7a | checks: citation freshness green (repo + plans), process parity green, 9 doc-reading suites pass; the workflow.md paragraph shifted 9 citations by ten lines, all repointed | deferrals: none
Stage 5 | b437c574 | simplify: folded three git-output idioms into Invoke-BacklogGit's Text property; suite still green | deferrals: none
Stage 6 | gate green | build 17 projects 0 warnings, format clean, 34/34 PowerShell suites, coverage line 94.6% branch 82.6% all thresholds met, git diff --check main...HEAD clean | artifact: tests/BacklogStaleOpen.Tests.ps1, no exemption claimed
Stage 7 | docs done in Task 4: scripts/README.md row, AGENTS.md:273 rule, workflow.md Stage 9 paragraph; nothing else enumerates the suites
Stage 8 | review returned 6 findings; failure edge back to 4-execute. Recovery tasks:
  R1 CONFIRMED | PLAN-PROGRESS.md:9 carries a bare AGENTS.md:273 citation; tier 3 fails, branch is CI-red. Verified: check-citation-freshness.ps1 exits 1.
  R2 CONFIRMED | backlog-staleness.common.ps1 distance counts from the stamp, so it measures branch age. Verified: fixture scores 16 at the merge with nothing after it. Fix: count from the landing merge, `git rev-list --ancestry-path --merges $stamp..$BaseRef | tail -1`. Verified on real history: 071 landing = 3cb9cc73, distance 24 (still caught); false-positive fixture drops to 0.
  R3 to triage | #Requires 7.0 but reading $PSNativeCommandUseErrorActionPreference under StrictMode needs 7.3+.
  R4 to triage | the 'HEAD' base fallback makes every in-flight item a candidate in a single-branch clone.
  R5 to triage | arm 2 (9-ship still open) is absent from workflow.md and scripts/README.md.
  R6 to triage | two pre-existing stale workflow.md citations in tests/, non-canonical so the checker ignores them.
