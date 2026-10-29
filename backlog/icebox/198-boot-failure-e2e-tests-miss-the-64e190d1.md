# 198 - Boot failure E2E tests miss their time limit

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (test harness)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

> **Iceboxed. This is an observation, not a plan.** The tests passed on a rerun each time, and
> nobody was blocked. It becomes worth doing if these tests fail in CI, or if a local run fails on
> them twice in one day.

## Summary

Some boot-failure tests in `FirstPageLoadDiagnosticsTests` fail locally because detecting the
failure takes longer than their time limit. The app code is not at fault. The tests fail on time
only.

## User story

As a developer running the E2E slice, I want the boot-failure tests to pass whenever the boot
diagnosis works, so that a red run always means a real fault.

## Acceptance criteria

- [ ] The root cause of the slow failure detection is written into this item, with evidence.
- [ ] Each `FirstPageLoadDiagnosticsTests` test that measures elapsed time passes in ten local E2E
      runs in a row, on the machine that saw the failures.

## Out of scope

- Changing what `FirstPageLoad.OpenAsync` reports when the app fails to boot.

## Notes / dependencies

- Seen on 2026-10-26 while backlog 170 ran six local E2E runs. Two of the six runs failed on
  timing. In each, two of these tests failed, and not always the same two:
  - `FailedBoot_WhileWaitingForTheResponse_SurfacesTheBootFailureInsteadOfHanging`: 16 s and 22 s.
  - `FailedBoot_Open_GivesUpWithoutSpendingTheWholeBudget`: 24 s.
  - `FailedBoot_Open_ReportsTheLastRequestsThePageMade`: gave up after 21924 ms. Its message
    check failed as well.
- The limit is half the 30-second `FirstPageLoad.TimeoutMs` budget, so 15 s. A comment in
  `tests/AHKFlowApp.E2E.Tests/FirstPageLoadDiagnosticsTests.cs` calls that limit "generous on
  purpose", so that it "will not turn red on a loaded runner". The local runs show it can.
- The failure messages report two documents loaded. That fits `bootBlazor.js` reloading the page
  after a failed boot. The reload may be where the extra time goes. This is not proven.
- The same tests passed in the other four runs, with no code change between them.
- Spec: none — iceboxed.
- Plan: none — iceboxed.
