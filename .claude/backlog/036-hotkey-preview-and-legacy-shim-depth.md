# 036 - Hotkey preview extraction + legacy shim depth

## Metadata

- **Epic**: Hotkey redesign
- **Type**: Chore
- **Interfaces**: UI | API

## Summary

The `/simplify` pass over `feature/wt-hotkey-ui-plan` (HEAD 3607dce) applied the cheap reuse,
simplification, efficiency and altitude findings in 29339d6. Four remaining findings were skipped
there because each either reaches well outside the reviewed diff or changes visible behavior. They
are recorded here rather than dropped.

## Acceptance criteria

- [ ] Extract the live-preview machinery shared by `HotkeyEditDialog` and `HotstringEditDialog` —
      `SchedulePreview` / `CancelPendingPreview` / `RunPreviewAsync` / `CopyPreviewAsync`, the
      cts+generation field set, the `MudExpansionPanels` block, and all four rules of
      `HotkeyEditDialog.razor.css` are near-verbatim copies (~120 lines). A
      `Components/Common/AhkCodePreviewPanel` plus a `PreviewScheduler<TRequest,TResult>` would
      leave each dialog supplying only a request factory and a result handler. Keep the existing
      `data-test` names — the bUnit tests key on them.
- [ ] Move `HotkeyEditDialog.ApplyFieldErrors` next to `Services/ApiErrorMessageFactory` as a
      shared `MapFieldErrors(errors, knownFields, target)`. The hotkey version (dictionary) is
      strictly better than `HotstringEditDialog.MapFieldErrors` (positional 4-tuple); fold the
      hotstring dialog onto it.
- [ ] Author `Constants/DefaultHotkeyCatalog` in the typed model instead of the retired
      `(HotkeyAction, Parameters)` shape run through `LegacyHotkeyDefinitionConverter.FromLegacy`.
      A back-compat converter should not be the authoring format for data that has no legacy; it
      also keeps `LegacyHotkeyDefinitionConverter.HotkeyAction` alive as a public production type.
      Note this is where "Maximize window" seeds as `SendKeys {Up}` rather than the `Window` kind
      that now exists for it — decide deliberately whether to keep the current output.
- [ ] Decide whether `LegacyHotkeySnapshotConverter` stays permanent runtime code or becomes a
      third migration over `EntityHistory.SnapshotJson`. Keeping it freezes the legacy enum, the
      two optional members on `HistorySnapshots`, and the frontend's legacy display arms. The
      *definition* converter is correctly permanent — the migration T-SQL mirrors it and the parity
      test depends on it.

## Out of scope

- Normalizing legacy history snapshots on the wire in `GetHotkeyHistoryVersionQuery`. That would
  make legacy rows display as the kind a revert actually produces instead of "Legacy", contradicting
  the deliberate decision in 6972f90.
- Structured `SendCtrl/SendAlt/.../SendKey` preview+save DTOs to remove the client's copy of the
  SendKeys grammar. Real altitude finding, but a wire-contract change, not a cleanup.

## Notes / dependencies

- Source: `/simplify` review of feature/wt-hotkey-ui-plan (HEAD 3607dce), 2026-07-24. Everything
  else that review surfaced is fixed in 29339d6.
