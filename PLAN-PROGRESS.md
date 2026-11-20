# Plan progress: backlog 215

Plan: `docs/superpowers/plans/2026-11-20-restored-snapshot-tooltip-test-plan-215.md`

- Task 1 (wait for the category chips before the hover): done at 7483e5f5. Tests: with the categories response held for 1500 ms, the chip was visible before the hover and the "No profile" chip stayed at y=326.875; with the wait removed, the chip was not visible and the row sat at y=278.875. 30 repeated runs: 30 passed. `VersionHistoryFlowTests`: 4 passed. Deferrals: none.
- Simplify: nothing to simplify. The diff is one `using` line and one wait with its comment.
- Verify: the artifact is the existing E2E test `RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload`, run 30 times in a row, plus the whole class once. No new test: the change is to that test.
- Document: the three acceptance boxes are ticked at 3deec7c5. At 6f2978d5 the item's `- Plan:` bullet got its backticks, and two citations moved to lines 322 and 323. Nothing else to document.
- Gate: green at 6f2978d5. Build, format, all PowerShell suites, coverage (94.8% line, 82% branch), and `git diff --check main...HEAD` passed.
