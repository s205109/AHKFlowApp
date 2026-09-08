# 148 - WindowSnap E2E test times out waiting for the add hotkey button

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

## Summary

`WindowSnapFlowTests.SendKeysWinPlusArrow_ShowsAdvisoryUntilWinCleared_AndStillSaves` timed out
once in CI. It waited 30 seconds for `button.add-hotkey` on the hotkeys page and never saw it.
The same test passes locally, and its sibling passed 7 seconds earlier in the same CI run. This
item finds out whether the wait is simply too short for a loaded CI runner, or whether something
real makes the page slow to boot.

## User story

As a developer, I want the E2E suite to fail only on real defects, so that a red required check
tells me the branch is broken.

## Evidence

The failure comes from CI run 34200726352, job `build-test`, on 2026-09-08, for pull request 395:

```
[xUnit.net 00:01:18.57]     AHKFlowApp.E2E.Tests.WindowSnapFlowTests.SendKeysWinPlusArrow_ShowsAdvisoryUntilWinCleared_AndStillSaves [FAIL]
[xUnit.net 00:01:18.57]       System.TimeoutException : Timeout 30000ms exceeded.
[xUnit.net 00:01:18.57]         tests/AHKFlowApp.E2E.Tests/WindowSnapFlowTests.cs(81,0)
  Failed AHKFlowApp.E2E.Tests.WindowSnapFlowTests.SendKeysWinPlusArrow_ShowsAdvisoryUntilWinCleared_AndStillSaves [30 s]
```

Line 81 is `await page.WaitForSelectorAsync("button.add-hotkey");`, the first wait after the test
opens `/hotkeys`.

Four facts point away from a defect in the page and towards a slow runner:

- The sibling test `CreateSnapLeftHotkey_PreviewKeepsBlockBodyLines_ThenGridShowsWindowAction`
  passed in the same run, in 7 seconds. Its first two lines are identical.
- `tests/AHKFlowApp.E2E.Tests/E2ETestCollection.cs` sets `DisableParallelization = true`, so the
  two tests ran one after the other against the same SPA host. The host was serving the app
  seconds before the timeout.
- The CI log shows `AHKFlowApp.UI.Blazor.Tests` running at the same timestamps, so other test
  projects were loading the runner while this test waited.
- The whole E2E suite passed locally on the same commit: 58 of 58.

None of this proves the cause, which is why Difficulty is `to-be-determined`. A one-off timeout
that nobody can reproduce may need a recurrence before anyone can name the line, the way
backlog 068 does.

## Acceptance criteria

- [ ] This item names why the wait timed out, with the evidence behind the answer: a loaded
      runner, a slow WebAssembly boot, or a defect in the page.
- [ ] The repository states one wait budget for a first page load in an E2E test, and
      `tests/AHKFlowApp.E2E.Tests/WindowSnapFlowTests.cs` uses it.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes.

## Out of scope

- Retrying a failed E2E test automatically. A retry hides the signal this item is chasing.
- The two flaky tests in backlog 068. Those are PowerShell suites and share no code with this one.
- The unexplained E2E harness overhead in backlog 140. That item measures total run time; this
  one is about a single wait.

## Notes / dependencies

- Found while addressing review findings on pull request 395, which changed the E2E publish and
  nothing else. The branch touched four files: a backlog item, the E2E project file, and two test
  files. It changed no UI code and no SPA host code, so it did not cause this failure.
- Related: `backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md` holds
  the repository's reasoning on what to do with a failure seen only once.
- Related: `backlog/140-account-for-the-unexplained-e2-12479560.md`.
- Spec: none — no design question until the cause is known.
- Plan: none — Stage 3 writes the pointer here once Difficulty is settled.
