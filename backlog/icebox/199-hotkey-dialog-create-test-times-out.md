# 199 - Hotkey dialog create test times out

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (test harness)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

> **Iceboxed. This is an observation, not a plan.** It failed once, and three reruns passed. It
> becomes worth doing if it fails again, in CI or in a pre-push run.

## Summary

The bUnit test `HotkeyEditDialogTests.SaveInCreateMode_CallsCreateAsync` failed once in the
pre-push fast slice. Its final `WaitForAssertion` timed out before `CreateAsync` was called.

## User story

As a developer pushing a branch, I want the fast slice to fail only on real faults, so that a
pre-push failure is worth reading.

## Acceptance criteria

- [ ] The root cause of the timeout is written into this item, with evidence.
- [ ] `SaveInCreateMode_CallsCreateAsync` passes in fifty runs in a row of the
      `HotkeyEditDialogTests` class.

## Out of scope

- Other `HotkeyEditDialogTests` tests, unless the root cause is shared.

## Notes / dependencies

- Seen on 2026-10-26, in the pre-push hook of backlog 170's Ship push. The branch did not touch
  the hotkey dialog.
- The failure: NSubstitute reported "Actually received no matching calls" for
  `CreateAsync(d => ((d.Description == "Open palette") AndAlso (d.Key == "K")), any CancellationToken)`.
  bUnit reported a check count of 1 and 34 component renders.
- The test types a description, sets the key through `SetKeyAsync`, clicks `button.commit-edit`,
  then waits for the call. A save that starts before the key value settles could explain a missing
  call. This is not proven.
- Right after the failure, the `HotkeyEditDialogTests` class passed 82 of 82 three times. The
  next pre-push run passed 1056 of 1056.
- Spec: none — iceboxed.
- Plan: none — iceboxed.
