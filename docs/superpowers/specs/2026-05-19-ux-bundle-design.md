# UX Bundle Design — Script Preview + Bulk Delete + Search

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Three independent UX wins shipped together: **(1)** live script preview before download, **(2)** bulk multi-select / bulk delete on hotstring + hotkey lists, **(3)** free-text search expanded to include categories. Each compounds with the categories + seed expansion work.

## Dependencies

- Categories spec — required for "search includes category names".
- Header Template Improvements spec — preview reuses the updated generator.

## Current State

- Download endpoint `GET /api/v1/downloads/profiles/{id}/script` returns the `.ahk` file; UI has no in-page preview.
- Lists support single-row delete via a row action.
- `ListHotstringsQuery`/`ListHotkeysQuery` already accept `search`. Hotstrings search hits `Trigger`/`Replacement`; hotkeys search hits `Description`/`Key`/`Parameters`. Neither searches categories.

## (1) Script Preview

### API

- New endpoint `GET /api/v1/profiles/{id}/preview` returning:
  ```json
  {
    "script": "string",
    "hotstringCount": 0,
    "hotkeyCount": 0,
    "generatedAt": "2026-05-19T00:00:00Z"
  }
  ```
- Handler reuses `AhkScriptGenerator` (post Header Template spec) so preview matches download byte-for-byte.

### UI

- Profile detail page (`Pages/Profiles.razor` or new detail page) gains a collapsible "Preview" pane.
- MudExpansionPanel with a `<pre>` block. Copy-to-clipboard button. Refresh button. No edit-in-place.

## (2) Bulk Multi-Select + Delete

### API

- `POST /api/v1/hotstrings/bulk-delete` body `{ "ids": ["guid", ...] }` → `BulkDeleteResultDto { deletedCount: int, missingIds: Guid[] }`.
- `POST /api/v1/hotkeys/bulk-delete` — same shape.
- Handler validates ownership per id; ids the user does not own (or that don't exist) are returned in `missingIds`. No exception — partial success is allowed and reported.
- Soft-cap request size at 500 ids per call (validator).

### UI

- MudDataGrid `SelectOnRowClick="false"` with selection checkboxes column.
- Toolbar Delete button appears when `selection.Count > 0`. Confirmation dialog showing count.
- Snackbar reports `deletedCount` and any `missingIds.Count`.

## (3) Search Expansion

- Extend `ListHotstringsQuery` search predicate to also LIKE-match against `Description` (after Schema Polish spec lands) and joined `Category.Name`.
- Extend `ListHotkeysQuery` similarly: also LIKE-match `Category.Name`.
- Case-insensitive (existing behavior); trim input; empty string is no-op.
- No fuzzy matching (Levenshtein) — DB-side LIKE is sufficient at current data sizes.

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs` — add preview action.
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` — add bulk-delete action.
- `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs` — add bulk-delete action.
- `src/Backend/AHKFlowApp.Application/Queries/Profiles/GetProfilePreviewQuery.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/BulkDeleteHotstringsCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/BulkDeleteHotkeysCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` — search expansion.
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` — search expansion.
- `src/Backend/AHKFlowApp.Application/DTOs/BulkDeleteResultDto.cs` (new)

### Frontend

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor` (or detail page) — preview pane.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — bulk select toolbar.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` — bulk select toolbar.
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/*` — typed client method additions.

## Test Strategy

- Integration: preview endpoint returns same script content as download for the same profile.
- Integration: bulk-delete with mixed valid/invalid/foreign ids returns expected `deletedCount` and `missingIds`.
- Integration: search by category name returns matching items.
- bUnit: selection state, toolbar visibility, preview pane toggle.

## Risks and Watchouts

- Bulk delete must not bypass `[Authorize]`; ownership check is per id.
- Preview pane must not show a stale view after a sibling edit — provide a manual refresh button rather than auto-refresh on every change.
- Joining categories in list query may need EF `Include` + `SelectMany` care to avoid duplicate rows in the result before paging.

## Done Criteria

- Preview pane shows generator-identical output on profile detail.
- Bulk delete works on both pages with confirmation and partial-success reporting.
- Search returns results when query matches category name.
