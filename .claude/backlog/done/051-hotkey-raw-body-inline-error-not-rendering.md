# 051 - Hotkey Raw body field never shows its inline validation error

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI

## Summary

The Raw action body field in `HotkeyEditDialog.razor` never shows a server validation error inline,
for any Raw rule — not just the one backlog 037 added. A user editing a broken Raw body sees no
highlight on the field and, on Save, no alert at all. The dialog just stays open with no visible
explanation.

## User story

As an Owner editing a Raw hotkey with an invalid body, I want to see why it is invalid on the field
itself, so I know what to fix.

## Acceptance criteria

- [x] Expanding the preview panel with an invalid Raw body shows the error text on the `Action body`
      field itself (`ErrorText`/`Error` on the `MudTextField`, `data-test="raw-body-input"`), not
      only the panel's generic "Fix the highlighted fields to see the generated code." message.
- [x] Clicking Save with an invalid Raw body shows a visible error — currently it shows nothing.
- [x] A regression test (E2E or Blazor component test) pins the fix so it cannot silently regress.

## Outcome — not reproducible, closed with coverage

The reported symptom does not happen. Both paths already put the message on the field. No
production code needed changing; the item closes with the guard tests it was missing.

What was checked, in order:

1. A bUnit probe typed an invalid Raw body and failed the preview with `Input.Body`. The rendered
   `raw-panel` markup carried `aria-invalid="true"` and the helper text held the server message. So
   the component wiring was never broken, and a bUnit test cannot pin this behaviour either way.
2. Because bUnit could not reproduce it, the check moved to a real browser against the real
   validation rule. `RawBodyPreviewError_ShowsInlineOnTheBodyField` passes on first run — before any
   change to production code. The preview path was already correct.
3. `RawBodySaveError_ShowsInlineOnTheBodyField` covers the second criterion. It leaves the preview
   panel collapsed, so only the Save response can produce the message it asserts.

Why the original investigation saw nothing is not established. The most likely reading is that
`aria-invalid` was polled on the wrong element — the Body input is a `textarea`, not an `input`, so
a selector written for the other fields would match nothing and never change.

## Out of scope

- Any other field's error rendering — only the Raw body field showed this symptom during
  investigation.

## Notes / dependencies

- Found 2026-08-03 while writing the E2E test for backlog 037 (raw hotkey body definition guard).
  Reproduced with two different server messages, including the pre-existing "Raw body braces are
  unbalanced." rule, so this pre-dates 037 and is not caused by it.
- Confirmed via network capture during that investigation: the API returns the correct
  `errors: {"Body": [...]}`, and `_previewFieldErrors["Body"]` does get populated — proven because
  the panel's generic blocked message (`[data-test="preview-blocked"]`) renders correctly. The bug
  is specifically that the `MudTextField`'s own `Error`/`ErrorText` parameters
  (`HotkeyEditDialog.razor:176-177`) never reflect it: `aria-invalid` stayed `false` and the helper
  text never changed, polled for 6 seconds after the response landed.
- The Save path hits the same rendering gap for a different reason: `FieldErrorMapper.Map` routes a
  known field like `Body` into `_saveFieldErrors` rather than the generic `_error` alert
  (`HotkeyEditDialog.razor:414`), so Save also depends on the same broken field-level rendering.
- 037's own E2E coverage (`tests/AHKFlowApp.E2E.Tests/HotkeysCrudFlowTests.cs`,
  `RawBodyInjectingAnotherHotkey_BlocksPreviewGeneration`) only asserts the panel-level
  blocked message for this reason — it could not honestly assert the field-level highlight.
  That test's comment claiming the binding is broken has been corrected.
