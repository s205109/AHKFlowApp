# Seed Data Expansion Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Expand dev-only seed data from 3 hotstrings + 0 hotkeys to **12 hotstrings + 12 hotkeys**, plus seed the eight default categories. Add a parallel hotkey seeding command and a combined `/seed-all` convenience endpoint.

## Dependencies

- Categories spec (`2026-05-19-categories-design.md`) must ship first so seed items can be tagged.

## Current State

`src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs` handles 3 entries via a static array (`s_samples`). Exposed by `DevController` as `POST /api/v1/dev/hotstrings/seed?reset={bool}`. Dev-only (env check at handler line 30-31). No equivalent for hotkeys. No category seeding.

## Scope

1. Extend `SeedHotstringsCommand.s_samples` to 12.
2. Add `SeedHotkeysCommand` + handler mirroring the hotstring pattern.
3. Add `SeedCategoriesCommand` (idempotent — skips already-present names).
4. Add `DevController` endpoints:
   - `POST /api/v1/dev/hotkeys/seed?reset={bool}`
   - `POST /api/v1/dev/seed-all?reset={bool}` — runs all three in order (categories first).
5. Each seed item is assigned to the correct categories via `CategoryIds`.

## Hotstring Seed Set

| # | Trigger | Replacement | EndingChar | InsideWord | Categories |
|---|---|---|---|---|---|
| 1 | `recieve` | `receive` | true | true | Autocorrect |
| 2 | `btw` | `by the way` | true | false | Communication |
| 3 | `brb` | `be right back` | true | false | Communication |
| 4 | `fyi` | `for your information` | true | false | Communication |
| 5 | `/today` | `{{date:yyyy-MM-dd}}` | false | false | DateTime |
| 6 | `/now` | `{{datetime:HH:mm}}` | false | false | DateTime |
| 7 | `@sig` | `Bart Segers\nbart@segocom.nl\nSegocom` (multi-line placeholder) | false | false | Email |
| 8 | `;arrow` | `→` | false | false | Symbols |
| 9 | `;check` | `✓` | false | false | Symbols |
| 10 | `;shrug` | `¯\_(ツ)_/¯` | false | false | Symbols |
| 11 | `;e:` | `ë` | false | false | Symbols |
| 12 | `;todo` | `TODO(name): ` | false | false | Code |

Note: `{{date:fmt}}` placeholders are **literal text in v1** — not runtime AHK evaluation. Future: emit AHK `FormatTime` expressions instead.

## Hotkey Seed Set

| # | Modifiers | Key | Action | Parameters | Description | Categories |
|---|---|---|---|---|---|---|
| 1 | Ctrl+Alt | T | Run | `wt.exe` | Launch Windows Terminal | App Launcher |
| 2 | Ctrl+Alt | N | Run | `notepad.exe` | Launch Notepad | App Launcher |
| 3 | Ctrl+Alt | E | Run | `explorer.exe` | Launch File Explorer | App Launcher |
| 4 | Ctrl+Alt | B | Run | `https://` | Open default browser | App Launcher |
| 5 | Win+Alt | Up | Send | `{Up}` *(placeholder)* | Maximize window | Window Management |
| 6 | Win+Alt | Down | Send | `{Down}` *(placeholder)* | Minimize window | Window Management |
| 7 | Win+Alt | Left | Send | `{Left}` *(placeholder)* | Snap window left | Window Management |
| 8 | Win+Alt | Right | Send | `{Right}` *(placeholder)* | Snap window right | Window Management |
| 9 | Ctrl+Shift | V | Send | `^v` *(placeholder)* | Paste as plain text | Code |
| 10 | Ctrl+Alt | D | Send | `{{date:yyyy-MM-dd}}` *(placeholder)* | Insert today's date | DateTime |
| 11 | Ctrl+Alt | L | Run | `rundll32.exe user32.dll,LockWorkStation` | Lock workstation | App Launcher |
| 12 | Ctrl+Alt | R | Run | `Reload` *(placeholder)* | Reload AHK script | App Launcher |

*"Placeholder"* notes flag values that need richer AHK expressions but are accepted as literal `Send`/`Run` parameters today.

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs` — expand sample array, assign `CategoryIds`.
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedCategoriesCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs` (new — orchestrates)
- `src/Backend/AHKFlowApp.API/Controllers/DevController.cs` — three new endpoints.

### Tests

- `tests/AHKFlowApp.API.Tests/Controllers/DevControllerTests.cs` — extended.

## Test Strategy

- Integration: each seed endpoint returns the expected count, is idempotent (rerun produces no duplicates), `reset=true` clears prior data first, returns 404 outside Development environment.
- Category linkage verified by joining via the new junction tables in assertions.

## Risks and Watchouts

- Multi-line `@sig` replacement requires the existing `Hotstring.Replacement` storage to accept `\n` — confirm during test.
- `Description` validation on `Hotkey` already allows 200 chars; all seed descriptions fit.
- Some hotkey "parameters" are placeholders that AutoHotkey won't actually execute (e.g. `{Up}` for window maximize). Document this as a known limitation; future spec expands.

## Done Criteria

- `POST /api/v1/dev/seed-all` produces 8 categories, 12 hotstrings, 12 hotkeys with correct links.
- Each individual endpoint also works.
- All seeding remains dev-only (404 in non-Development).
- Re-running endpoints is safe (no duplicates).
