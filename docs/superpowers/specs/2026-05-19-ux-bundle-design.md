# UX Bundle Design — Script Preview + Bulk Delete

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Two independent UX wins shipped together: **(1)** live script preview before download, **(2)** bulk multi-select / bulk delete on hotstring + hotkey lists.

(Previously this bundle also included expanding free-text `search` to match category names. Dropped — the category chip filter delivered by the Categories spec already does that work; adding a JOIN+LIKE on category names is high-cost, marginal-value.)

## Dependencies

- Categories spec — required for the chip filter (filtering surface for lists).
- Header Template Improvements spec — preview reuses the updated `AhkScriptGenerator` output, including token substitution.

## Current State

- Download endpoint is `GET /api/v1/downloads/{profileId:guid}` returning the `.ahk` file as `text/plain; charset=utf-8` — see `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs:27`.
- Zip-all-profiles is `GET /api/v1/downloads/zip`.
- Lists support single-row delete via a row action. No bulk operation.
- UI has no in-page preview pane.

## (1) Script Preview

### API

New endpoint co-located on the existing `DownloadsController` to keep "anything about generating script content" in one place:

- `GET /api/v1/downloads/{profileId:guid}/preview` returns JSON:
  ```json
  {
    "script": "string",
    "hotstringCount": 0,
    "hotkeyCount": 0,
    "generatedAt": "2026-05-19T00:00:00Z"
  }
  ```
- Handler reuses the same query as `GET /api/v1/downloads/{profileId:guid}` (`GenerateProfileScriptQuery`), then projects to a new `ProfileScriptPreviewDto`.
- The byte-for-byte script content matches what the download endpoint returns for the same profile — both flow through `AhkScriptGenerator`.

### UI

- Profile detail page (or dialog) gains a collapsible "Preview" pane (`MudExpansionPanel`) with a `<pre>` block and a copy-to-clipboard button.
- Refresh button re-fetches the preview. No auto-refresh on every list edit — explicit refresh keeps the round-trip count down.

## (2) Bulk Multi-Select + Delete

### API

- `POST /api/v1/hotstrings/bulk-delete` body `{ "ids": ["guid", ...] }` → `BulkDeleteResultDto { deletedCount: int, missingIds: Guid[] }`.
- `POST /api/v1/hotkeys/bulk-delete` — same shape.
- Handler validates ownership per id; ids the user does not own (or that don't exist) are returned in `missingIds`.

**HTTP contract for partial success — explicit:**

- The response status is **always `200 OK`** when the request itself is well-formed and authorized. Partial success (some ids in `missingIds`) is *not* an error condition — the client receives the body and decides what to do.
- `deletedCount: 0` and a non-empty `missingIds` array is also `200 OK`. That's still "the request was processed; here is what happened."
- `400 Bad Request` is only returned when the request shape is invalid (e.g. `ids` empty, count > 500, malformed guid). The validator handles this — partial-success is not a validator case.
- `401`/`403` apply as usual to the authorization layer; the handler is never reached.
- This contract is stable for clients — they can rely on "if I get 200, parse the body" without branching on subset-success status codes (no `207 Multi-Status`).

- Soft-cap request size at 500 ids per call (validator). Anything larger returns `400` with `Result.Invalid` and a clear error message.

### UI

- `MudDataGrid` selection column (checkbox) on Hotstrings and Hotkeys pages.
- Toolbar Delete button appears when `selection.Count > 0`. Confirmation dialog shows the count.
- Snackbar reports `deletedCount` and any `missingIds.Count` (if non-zero).

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs` — add preview action.
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` — add bulk-delete action.
- `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs` — add bulk-delete action.
- `src/Backend/AHKFlowApp.Application/DTOs/ProfileScriptPreviewDto.cs` (new)
- `src/Backend/AHKFlowApp.Application/DTOs/BulkDeleteResultDto.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/BulkDeleteHotstringsCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/BulkDeleteHotkeysCommand.cs` (new)
- `src/Backend/AHKFlowApp.Application/Queries/Downloads/GetProfileScriptPreviewQuery.cs` (new — thin wrapper around `GenerateProfileScriptQuery`)

### Frontend

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor` — preview pane.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — bulk select toolbar.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` — bulk select toolbar.
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/*` — typed client method additions.

## Test Strategy

- Integration: preview endpoint returns same `script` content as the download endpoint for the same profile.
- Integration: bulk-delete with mixed valid / invalid / foreign ids returns expected `deletedCount` and `missingIds`.
- bUnit: selection state, toolbar visibility, preview pane toggle.

## Risks and Watchouts

- Bulk delete must not bypass `[Authorize]`; ownership check is per id.
- Preview pane must not show stale output after a sibling edit — provide a manual refresh button rather than auto-refresh.
- Both preview and download produce identical bytes — share the query handler to avoid drift.

## Done Criteria

- Preview pane on Profile detail returns generator-identical output.
- Bulk delete works on both pages with confirmation and partial-success reporting.
