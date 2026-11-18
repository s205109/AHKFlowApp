# 213 - Raw hotkey Body error missing after changing between invalid bodies

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

In the hotkey edit dialog, a field that shows a preview error loses that error when the owner edits
it into another invalid value. The preview panel then says "Fix the highlighted fields to see the
generated code.", but no field is highlighted. This is GitHub issue #472.

## User story

As an owner editing a Raw hotkey body, I want the Body field to show why each invalid body is
invalid, so that I know what to fix without first typing a valid body.

## Root cause

The evidence for the bug gate at Design entry.

1. The dialog keeps a field's preview error until the next preview response replaces it.
   `ApplyPreviewResult` clears `_previewFieldErrors` only when a response arrives:
   (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor:704`, "_previewFieldErrors.Clear();").
   So while the owner edits the Body field, the dialog keeps sending `Error="true"` to it.
2. MudBlazor 9.3.0 validates a field when its value changes, and writes the result into the
   field's own error state. `MudFormComponent.ValidateValue` calls
   `ErrorState.SetValueAsync(errors.Count > 0)`:
   [`MudFormComponent.cs` line 425 at v9.3.0](https://github.com/MudBlazor/MudBlazor/blob/v9.3.0/src/MudBlazor/Base/MudFormComponent.cs#L425).
   The Body field has no client rule for these errors, so its state becomes `false`.
3. MudBlazor takes a new value from the parent only when it differs from the last value the parent
   sent. `ParameterStateInternal<T>.OnParametersSet` compares against `_lastValue`, not against the
   current state:
   [`ParameterStateInternalOfT.cs` line 166 at v9.3.0](https://github.com/MudBlazor/MudBlazor/blob/v9.3.0/src/MudBlazor/State/ParameterStateInternalOfT.cs#L166).
   The dialog sends `true` again, so the field keeps `false`. It takes the new `ErrorText`, but
   shows the helper text, because it is not in error.
4. A valid body in between hides the bug. The dialog then sends `false` and later `true`, which is a
   change.

Repro: a bUnit probe in `HotkeyEditDialogTests` expanded the preview, got the error "First error."
on the Body field, typed a second body, and released a held response with "Second error.". It
failed with this output:

```
Expected provider.Find(".raw-body-wrap .mud-input-helper-text").TextContent "Emitted verbatim
after ::. Include your own { } for a block body. Braces must balance; # directives and lines that
define another hotkey or hotstring are rejected." to contain "Second error.".
```

The same probe passed after one added line removed the Body field's preview error before the new
request. It failed again when that line was taken out.

The hotstring edit dialog does not have this bug. It clears its preview errors before every new
request:
(`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor:877`, "_previewFieldErrors.Clear();").

## Acceptance criteria

- [x] With the preview panel expanded, a hotkey field that shows a preview error, and is then edited
      into another invalid value, shows the new error on the field with `aria-invalid="true"`.
- [x] `HotkeyEditDialogTests` holds a bUnit test that moves the Body field from one preview error to
      another. The test fails when the fix is taken out.
- [x] `RawBodyInjectingAnotherHotkey_BlocksPreviewGeneration` goes straight from the injected body to
      the unbalanced-braces body, with no valid body in between.
- [x] No comment under `src/` or `tests/` says that a bUnit test cannot pin the Body field's inline
      error.

## Out of scope

- The hotstring edit dialog. It already clears its preview errors before each request.
- Save errors. `ClearSaveError` already drops a field's save error when the owner edits the field.

## Notes / dependencies

- GitHub issue #472. Found in PR #471, review finding 4.
- Backlog 051 reported the same missing error and then could not reproduce it. Its later bUnit
  probe typed one invalid body only, so the dialog's `Error` went from `false` to `true`, which
  MudBlazor detects. The steps of 051's first report are not recorded.
- Spec: none — a moderate bug with a known root cause. The plan records its one design choice.
- Plan: `docs/superpowers/plans/2026-11-17-raw-hotkey-body-error-plan-213.md`
