# Plan progress: backlog 213

Plan: `docs/superpowers/plans/2026-11-17-raw-hotkey-body-error-plan-213.md`

- Task 1 (clear preview field errors): done at 8e866c97. Tests: Step 2 failed as expected, the helper text kept "Emitted verbatim after ::." and lacked "Second error."; Step 4 `HotkeyEditDialogTests` passed 104 of 104; Step 5 the test failed again with the clear removed, and passed 104 of 104 after it came back. Deferrals: none.
- Task 2 (E2E straight between invalid bodies): done at 629d7158. Tests: Step 3 `RawBodyInjectingAnotherHotkey_BlocksPreviewGeneration` passed 1 of 1 in Release; Step 4 with the clear removed it failed at the helper-text assertion waiting for "The braces in Action body do not balance.", so the old failure came from the bug, not from a test that did not wait; it passed 1 of 1 after the clear came back. Deferrals: none.
