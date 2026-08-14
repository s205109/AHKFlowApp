# 038 - Flag known-shortcut matches on the hotkeys list

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI
- **Stage**: 9-ship

## Summary

The shortcut warning shows only inside the hotkey edit dialog. A hotkey that already matches a known shortcut stays invisible until its owner happens to open it. Someone with many existing hotkeys may never see the warning at all.

## User story

As an owner, I want my hotkeys list to show which hotkeys match a known shortcut, so that I do not have to open each one to find out.

## Acceptance criteria

- [x] A row whose combination matches a known shortcut carries a visible marker
- [x] The marker names what uses the combination, on hover or on tap
- [x] The desktop `MudDataGrid` branch and the mobile list branch both show it
- [x] The list reads the catalog through `IKnownShortcutCatalog`, so it costs no extra fetch

## Out of scope

- Blocking or bulk-fixing. The marker is advice, exactly like the dialog warning

## Notes / dependencies

- Needs Stage 1 of the hotkey shortcut warnings plan (2026-07-29) merged
- Both list branches live in `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/`
