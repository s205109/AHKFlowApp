# 189 - Inline pickers and key field have no accessible name

## Metadata

- **Epic**: Accessibility
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 8-review

## Summary

When a hotstring or hotkey row is in edit mode, its profile picker and its category picker have
no label. The key field in a hotkey row has no label either. A screen reader cannot say which
control it is on.

## User story

As an owner who uses a screen reader, I want each picker and the key field in a row I edit to
say what it holds, so that I can edit a row without seeing it.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [x] Each control listed under Notes has an accessible name.
      The five controls pass `AriaLabel`. `KeyboardAccessFlowTests.InlinePickers_NameWhatTheyHold`
      reads the computed name in a browser for the three controls on the hotkeys page.
- [x] Each name matches what a sighted owner reads for that control, such as the column title
      `Profiles` or `Categories`.
      The pickers use the column titles. The key field uses `Key`, the label the hotkey dialog
      gives the same field, because its `Hotkey` column also holds the modifier checkboxes.
- [x] A bUnit test asserts the accessible name of each control listed under Notes.
      `EditRow_Pickers_NameWhatTheyHold` in `HotstringsPageTests` and `HotkeysPageTests` asserts
      the `aria-label` on the `<input>` of all five controls. bUnit reads the attribute, and the
      browser test above proves it becomes the name.

## Out of scope

- The text fields and the checkbox in the same rows. Backlog 186 names them.
- Dialog forms. Their pickers and their key field already carry a `Label`.

## Notes / dependencies

- Found while planning backlog 186, on 2026-10-18. Read from the source, not measured in a
  browser.
- These controls have a placeholder or nothing, and no `Label`. A placeholder is not a label.
  - `Pages/Hotstrings.razor`: `EntityMultiSelect` with `DataTest="profile-select"` (placeholder
    `Select profiles`), and `EntityMultiSelect` with `DataTest="category-select"` (placeholder
    `Select categories`).
  - `Pages/Hotkeys.razor`: the same two pickers, and `KeyPicker` with `DataTest="key-input"`.
- Both are shared components in `Components/Common/`. Each builds its own `UserAttributes` from
  its `DataTest` parameter, so a page cannot add an `aria-label` today. The fix is a new parameter
  on each component, not one more attribute on a page.
- Check at pickup where `UserAttributes` lands on `MudSelect` and on `MudAutocomplete` in
  MudBlazor 9.3.0: on the element that takes focus, or on a wrapper. An `aria-label` on a wrapper
  names nothing.
- Decide at Plan what the key field is called. The column title is `Hotkey`, but that column also
  holds the Ctrl, Alt, Shift and Win checkboxes. The hotkey dialog calls the same field `Key`.
- Backlog 186 sets the pattern: an `aria-label` with the same words as the column title. Its plan
  adds that rule to the frontend `CLAUDE.md`.
- Spec: none — known controls, one kind of fix.
- Plan: `docs/superpowers/plans/2026-10-26-inline-picker-names-plan-189.md`
- Checked at pickup, MudBlazor 9.3.0 source: `MudSelect` and `MudAutocomplete` both pass
  `UserAttributes` to their `MudInput`, which puts them on the `<input>` that takes focus.
  `MudSelect` hides that input only when `CanRenderValue` is true, and `CanRenderValue` is always
  false with `MultiSelection`, which `EntityMultiSelect` always sets.
