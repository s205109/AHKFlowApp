# 154 - E2E first page loads capture no boot diagnosis

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (test code only)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

When the Blazor app fails to boot in an E2E test, the test fails with a bare Playwright timeout.
It records no browser console, no page errors, and no boot error state. Only one test class
reports that evidence today. This item makes every E2E first page load report it, so the next
failure names its own cause.

## User story

As a developer, I want a failed first page load in any E2E test to say why the app did not
boot, so that I can fix the cause instead of running CI again.

## Evidence

The same failure has now happened twice.

**First occurrence.** Backlog 148 found it in CI run 34200726352, in
`WindowSnapFlowTests`. The page loaded the document twice, and neither boot finished. The
server answered every request. Backlog 148 could not say why the WebAssembly runtime failed to
start, because the run captured no browser console. It added `FirstPageLoad.OpenAsync`, which
captures that evidence, but only `WindowSnapFlowTests` uses it.

**Second occurrence.** CI run 34603837355, attempt 1, job `build-test`, on 2026-09-11, for pull
request 402. The failing test was
`HotkeysMobileFlowTests.PhoneViewport_MarkedRowWithTheLongestCombo_KeepsTheTriggerCellInsideItsColumn`:

```
System.TimeoutException : Timeout 30000ms exceeded.
Call log:
  - waiting for Locator(".mobile-branch tr.mobile-row").Filter(new() { HasText = "Task manager row" }) to be visible
```

The SPA host for stack B (port 46215) logged every request the browser made:

```
13:26:02.027  GET /hotkeys                         <- the test's own navigation
13:26:02.198  GET /_framework/blazor.webassembly.js
13:26:02.200  GET /_content/MudBlazor/MudBlazor.min.js   <- last request of any kind
13:26:32.452  GET /hotkeys                         <- the next test, 30 seconds later
```

A healthy load, like the next test's, asks for `js/downloads.js` and
`js/registerServiceWorker.js` within 50 ms of `MudBlazor.min.js`. This page never did. So the
browser stopped before the app started, and the seeded row could never appear.

Three facts rule out the pull request and the test data:

- Pull request 402 and the `main` it merged changed no E2E test, no UI code, and no SPA host
  code.
- Each E2E stack uses its own database. `ApiFactoryTests` asserts that the four database names
  are unique, so one stack cannot delete another stack's rows.
- The same test passed in every other recent CI run that was checked.

This test opens its page with `GotoAsync` directly
(`tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs:145`, "await row.WaitForAsync();"), so
the timeout carried none of the evidence `FirstPageLoad.OpenAsync` would have collected.

## The design question

A search for `GotoAsync(` or `FirstPageLoad.OpenAsync(` in `tests/AHKFlowApp.E2E.Tests` finds
61 matches in 18 files. Only two of them go through `FirstPageLoad.OpenAsync`.

There are two ways to close the gap, and Design must choose:

1. **Move each first page load onto `FirstPageLoad.OpenAsync`.** This uses code that already
   exists. It is a large, repetitive change, and a new test can skip the helper again.
2. **Capture the evidence centrally.** For example, attach `BootWatch` wherever a stack fixture
   creates a browser context, and write its report when a test fails. Every test gets the
   diagnosis, including tests written later. This needs new plumbing in the fixture.

Not every `GotoAsync` call is a first page load. `BootFailureFlowTests` reloads on purpose, and
some tests navigate again inside a page that already booted. Design must say which calls count.

## Acceptance criteria

- [ ] When a first page load in any E2E test does not show the app, the test failure names how
      many documents the page loaded, whether the boot error screen is showing, and every browser
      console error and uncaught page error.
- [ ] A new E2E test gets that report without extra code, or a check fails a new test that opens
      a first page load without it.
- [ ] A deliberately broken boot proves the report in a durable test, and that test passes.
- [ ] `FirstPageLoad.TimeoutMs` still reads 30000, and no E2E test retries automatically.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes.

## Out of scope

- Finding out why the WebAssembly runtime fails to start. This item collects the evidence. A
  follow-up item uses it.
- Retrying a failed E2E test automatically. Backlog 148 explains why a retry hides the signal.
- Raising the 30 second budget. Backlog 148 showed the page had already stopped, so a longer wait
  does not help.

## Notes / dependencies

- Follows `backlog/done/148-windowsnap-e2e-test-times-out-w-b226493b.md`, which found the first
  occurrence and added `FirstPageLoad.OpenAsync`.
- Related: `backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md`
  holds the repository's reasoning on a failure seen only once. This one has now been seen twice.
- Found while fixing the CI build for pull request 402. That pull request's failed job was run
  again rather than changed, because this failure is not its defect.
- Spec: none yet — Difficulty is `complex`, so Design writes one.
- Plan: none yet — Plan follows Design.
