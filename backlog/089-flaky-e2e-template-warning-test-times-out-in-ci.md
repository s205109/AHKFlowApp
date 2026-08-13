# 089 - Flaky E2E template warning test times out in CI

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI

## Summary

`ShortcutWarningFlowTests.AHotkeyOnAKeyTheProfileHeaderUses_IsWarnedAbout` fails in CI without a
related code change, then passes on a plain re-run of the same commit. The test waits 30 seconds
for the template warning to appear in the hotkey dialog, and times out.

## User story

As a developer, I want the E2E suite to fail only for a real defect, so that a red CI run always
means my change broke something.

## Evidence

- Test: `tests/AHKFlowApp.E2E.Tests/ShortcutWarningFlowTests.cs:321`
- Failure: `System.TimeoutException : Timeout 30000ms exceeded.`
  Call log: `waiting for Locator(".hotkey-edit-dialog [data-test=\"template-warning\"]") to be visible`
- Run: <https://github.com/s205109/AHKFlowApp/actions/runs/31696017304> on commit `b7398e25`
  (PR #293). That PR changed only the guard script, the guard tests, the guard docs, and one
  backlog file. A re-run of the same commit passed with no code change.
- The test first saves a profile header, then opens the create dialog and binds `CapsLock`. The
  warning needs the saved header to reach the dialog. So the first places to look are the wait
  after the `Profile updated.` message, and any profile state shared between tests in the class.

## Acceptance criteria

- [ ] Name the root cause with `file:line` evidence, not a guess. Say whether the cause is a race
      in the test, a race in the UI, or state shared between tests.
- [ ] Fix the cause. A longer timeout or a retry is not a fix.
- [ ] Show the test passing on 10 runs in a row of `ShortcutWarningFlowTests`.
- [ ] Check the other tests in the class for the same pattern, and fix them in the same change.

## Out of scope

- A general CI retry policy for the E2E suite.
- Any change to the shortcut warning feature itself.

## Notes / dependencies

- Verification artifact: the existing `*FlowTests.cs` E2E test, run with
  `pwsh .\scripts\test-fast.ps1 -Mode E2E`.
- The failure happened once so far. If the cause stays unclear, collect a second occurrence
  before you change code.
