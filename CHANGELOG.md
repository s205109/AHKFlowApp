# Changelog

All notable changes to AHKFlow are documented in this file.

This changelog starts forward-only. Existing releases before this file was introduced are not backfilled.

## [Unreleased]

### Added

- In-app changelog page generated from this file.
- Hotstring option toggles: case sensitive and omit ending character.
- Type/Options badge column in the hotstrings grid (replaces the two option checkbox columns).
- "Edit details" dialog for hotstrings on desktop.
- `ahkflow hotstring list` shows a Kind column.
- DateTime hotstring kind: curated date/time format presets with optional date offset, emitted as `SendText(FormatTime(...))`. Supported in the edit dialog, grid, mobile list, history, and CLI.
- Macro hotstring kind: replacements can place the cursor and insert key presses (Enter, Tab), emitted as a scripted AutoHotkey sequence. Supported in the edit dialog (insert toolbar, live AutoHotkey preview, and Text-to-Macro suggestion), grid, mobile list, and CLI.
- "Generated AutoHotkey code" preview panel in the hotstring edit dialog: shows the exact script snippet a hotstring will produce, for every kind. Updates live while typing, shows an "Updating preview…" indicator, maps validation errors to the Trigger/Replacement fields, and includes a copy button.
- Macro insert toolbar guards: the Cursor button disables once a cursor token exists, and Enter/Tab insertion behind the cursor is blocked with an inline hint.

### Changed

- Generated scripts always emit the `T` (literal text) option for text hotstrings, so replacements are inserted exactly as typed.
