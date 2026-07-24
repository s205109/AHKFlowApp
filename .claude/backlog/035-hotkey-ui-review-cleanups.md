# 035 - Hotkey UI review cleanups

## Metadata

- **Epic**: Hotkey redesign
- **Type**: Chore
- **Interfaces**: UI | API

## Summary

Local review of the hotkey edit dialog (feature/wt-hotkey-ui-plan, HEAD e6b5cb1) surfaced four
non-defect improvement opportunities on the touched surface. Not bundled into the review's fix
commit (4af382f) to keep that change minimal.

## Acceptance criteria

- [ ] Centralize combo formatting shared by the grid, history dialog, and Recycle Bin — history
      duplicates it today and formats character casing differently
      (`Components/Hotkeys/HotkeyHistoryDialog.razor:128`)
- [ ] Combine action field names and values into one descriptor — `HotkeyEditModel` currently
      maintains parallel switches (`FieldNamesOwnedBy` / `ActiveFields`) despite claiming a
      one-place mapping (`Validation/HotkeyEditModel.cs:128`)
- [ ] Add `IsInEnum` validation for the nullable `ActionKind` list-query filter — an undefined
      numeric value currently produces an empty result instead of a 400
- [ ] Add accessible names to icon-only controls and mobile row checkbox labels — mostly
      pre-existing debt, but on the touched surface

## Out of scope

- Any behavior change beyond the four items above

## Notes / dependencies

- Source: local review of feature/wt-hotkey-ui-plan (HEAD e6b5cb1), 2026-07-23. High/Medium
  findings from the same review were fixed directly in 4af382f.
