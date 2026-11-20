# 215 - Restored snapshot tooltip test flakes after reload

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup
- **Issue**: #490

## Summary

The E2E test `VersionHistoryFlowTests.RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload`
fails some of the time on CI. After the reload it hovers the "No profile" chip, and no open
tooltip appears within 5 seconds. It failed in CI runs 43961612031, 43968017996 and
44246967539, on two different branches. The root cause is not known yet.

## User story

As a developer, I want this E2E test to pass every time the product works, so that a red CI
run means a real problem.

## Acceptance criteria

- [ ] The item states the root cause, with `file:line` evidence or a log line.
- [ ] `RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload` passes in 30 repeated local runs in a row.
- [ ] The test still checks that the "No profile" tooltip names the broken rule after a reload.

## Out of scope

- Other flaky E2E tests. File each one as its own item.

## Notes / dependencies

- GitHub issue #490 holds the triage comment and the first guess at the cause.
- The failing assertion is at `tests/AHKFlowApp.E2E.Tests/VersionHistoryFlowTests.cs:317`.
- Spec: <path, or "none — reason">
- Plan: <path, or "none — reason">
