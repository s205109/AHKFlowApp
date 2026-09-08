# 148 - WindowSnap E2E test times out waiting for the add hotkey button

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — test code only)
- **Difficulty**: moderate
- **Stage**: 3-plan

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

None of this proves the cause. The reading above was the reading at filing time, and Findings
below overturns it: the SPA host's request log shows the app failed to boot, twice, inside the
30 seconds. Difficulty moved from `to-be-determined` to `moderate` on that evidence.

## Findings

The wait was not too short. The app never booted. The four facts above pointed the wrong
way, and the SPA host's own request log overturns them.

`tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs` runs a real Kestrel host, so CI run
34200726352 logged every request the browser made. The whole 30 seconds is on the record.

### The page loaded the document twice

```
07:47:51.243  GET /hotkeys   <- the test's own navigation
07:47:51.832  GET /hotkeys   <- the page reloaded itself, 0.59 s later
07:47:52.274  last request of any kind
07:48:21.428  GET /hotkeys   <- the next test, 29 seconds later
```

Across the whole E2E run, every test loads exactly one document. This test loaded two. The
only other double load in the run belongs to `BootFailureFlowTests`, which reloads on purpose.

### Neither boot finished

A healthy boot fetches 139 files from `_framework/`, then asks for `appsettings.json` about
0.6 seconds after the document. The sibling test did exactly that at 07:47:43.602 and
07:47:44.182.

The failing test did not. The first boot fetched 20 files before the reload cut it off. The
second fetched 76 and then stopped. `appsettings.json` was never requested, so `Program.Main`
never ran, and nothing the page needed was ever rendered.

### The server was healthy throughout

Every request in the window returned 200. None failed, and none was left unfinished. The
stall is entirely inside the browser.

### What reloaded the page

`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/bootBlazor.js` is the only code that reloads
during boot. It reloads at once for a platform-start failure and waits 10 seconds for a
download failure, so a reload 0.59 seconds in was a start failure. Its guard allows one
retry per tab, so the second failure showed the "Couldn't load the app" screen instead of
reloading again.

`wwwroot/js/registerServiceWorker.js` also reloads, but only when a service worker already
controls the page. Each test opens a fresh browser context with its own storage, so no
service worker existed and that branch could not run.

### What is still unknown

Why the .NET WebAssembly runtime failed to start. The run captured no browser console, no
page errors, and no screenshot, and the E2E project captures none of these today. The likely
explanation is resource pressure: `dotnet test` runs every test project in parallel on a
four-core runner, and `AHKFlowApp.UI.Blazor.Tests` was still running its 956 tests when this
boot failed. That is unproven, and this evidence cannot prove it.

This failure has happened once in the last 40 CI runs.

### What this means for the fix

A longer wait would not have saved this run, because the page had already given up. So the
wait budget is worth stating once and using once, but it is not the repair. The repair is to
make the next occurrence name itself: capture the browser console and the boot-error state
when a first page load does not arrive.

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
