# 186 - Inline edit fields have no accessible name

## Metadata

- **Epic**: Accessibility
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 7-document

## Summary

When a list row is in edit mode, its text fields and its checkbox have no label. A screen reader
can only say that it is on an edit field, not which one. This affects the categories, profiles,
hotstrings and hotkeys pages.

## User story

As an owner who uses a screen reader, I want each field in a row I edit to say what it holds,
so that I can edit a row without seeing it.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] Each field listed under Notes has an accessible name.
- [ ] Each name matches what a sighted owner reads for that field, such as the column header
      `Trigger` or the section title `Header template`.
- [ ] A bUnit test asserts the accessible name of each field listed under Notes.

## Out of scope

- Dialog forms and the known-shortcuts form. Their fields already carry a `Label`.
- Colour contrast.

## Notes / dependencies

- Found while planning backlog 168, on 2026-10-16. Read from the source, not measured in a
  browser.
- These fields carry a `data-test` attribute and nothing else that names them: no `Label`, and
  no `aria-label`. They are listed by `data-test` value, because backlog 168 moves their lines.
  - `Pages/Categories.razor`: `category-name-input`.
  - `Pages/Profiles.razor`: `profile-default-input` (a checkbox), `profile-name-input`,
    `profile-header-input`, `profile-footer-input`.
  - `Pages/Hotstrings.razor`: `trigger-input`, `replacement-input`, `description-input`.
  - `Pages/Hotkeys.razor`: `description-input`, `run-target-input`, `text-input`.
    `run-target-input` has a `Placeholder`, which is not a label.
- Check at pickup where `UserAttributes` lands on a `MudTextField` in MudBlazor 9.3.0: on the
  `input` itself, or on a wrapper. An `aria-label` on a wrapper names nothing.
- A visible `Label` would change how a dense row looks. Decide at Plan between `Label` and
  `aria-label`.
- Found while planning, on 2026-10-18: the profile and category pickers and the hotkey key
  field in the same rows have no name either. They are shared components, so they need a
  different fix. They are filed as backlog 189.
- Spec: none — known fields, one kind of fix.
- Plan: `docs/superpowers/plans/2026-10-18-inline-edit-field-names-plan-186.md`
