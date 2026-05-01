# 022 - Hotkeys UI CRUD

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI

## Summary

Implement the Hotkeys page so it matches the old AHKFlow reference UI: inline-edit table with columns **Description, Key, CTRL, ALT, SHIFT, Win, Action (enum dropdown), Profile (multi-select with "Any"), Parameters, Actions**.

## User story

As a user, I want to manage hotkeys in the Web UI so that I can define keyboard shortcuts and assign them to one or more profiles (or to all profiles via "Any").

## Acceptance criteria

- [ ] List hotkeys with the column set above; inline-edit per row (MudTable).
- [ ] Create and edit hotkeys with client-side validation feedback (Description, Key required; modifier-combo unique per user).
- [ ] Action column is a dropdown bound to the `HotkeyAction` enum (Send, Run; extensible).
- [ ] Profile column is a multi-select; an "Any" toggle sets `AppliesToAllProfiles=true` and clears specific selections.
- [ ] Delete hotkeys with a confirmation step.
- [ ] bUnit tests cover the main UI components, including modifier checkboxes, Action dropdown, Profile multi-select / "Any" toggle, and validation states.

## Out of scope

- Key-capture widget — plain text input only (`MudTextField`); user types `n`, `F5`, `Numpad0`. Capture widget can come later.
- Search/filtering UI (see 023).
- E2E (Playwright) — bUnit only, matching the 014 precedent.

## Notes / dependencies

- Depends on **022b** (Hotkey schema rebuild) and **024 + 024b** (Profile entity + M2M association).
- Design spec: `C:\Users\btase\.claude\plans\start-your-work-on-validated-walrus.md` (Phase 3).
- An earlier implementation on `feature/022-hotkeys-ui-crud` (unmerged) used a free-form `Trigger`/`Action`/`Description` model. It is superseded by this redesign; ACs above are intentionally reset.
