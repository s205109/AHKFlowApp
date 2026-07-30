# 040 - Mobile layout for the known shortcuts page

## Metadata

- **Epic**: Hotkey safety
- **Type**: Feature
- **Interfaces**: UI

## Summary

The known shortcuts page renders one `MudTable` for every screen size. Every other list page in the app renders a desktop branch and a mobile branch. On a phone the table has six columns, and the Actions column is the one most likely to be pushed out of reach.

## User story

As an owner on a phone, I want the known shortcuts list to read like the other list pages, so that I can silence a warning without fighting a wide table.

## Acceptance criteria

- [ ] The page renders a `.desktop-branch` and a `.mobile-branch`, gated in `Pages/KnownShortcuts.razor.css` at `959.95px`, matching `Pages/Hotkeys.razor` and `Pages/Hotstrings.razor`
- [ ] The mobile branch shows the combination, what uses it, and what it does, plus the row's one action
- [ ] Search still filters both branches
- [ ] An E2E flow test at a phone viewport silences a use and brings it back

## Out of scope

- Changing the desktop table.
- Adding an edit action. Owner records are delete-and-recreate, as decided in the Stage 2 plan.

## Notes / dependencies

- Convention is described in `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`, under the list-page bullet.
- Existing mobile flows to copy from: `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`.
- Raised while reviewing the hotkey shortcut warnings feature on 2026-07-29. The current table does carry `DataLabel` on every cell, so it degrades rather than breaking — this is polish, not a defect.
