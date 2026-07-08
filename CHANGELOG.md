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

### Changed

- Generated scripts always emit the `T` (literal text) option for text hotstrings, so replacements are inserted exactly as typed.
