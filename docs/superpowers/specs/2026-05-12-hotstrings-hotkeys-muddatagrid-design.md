# Hotstrings and Hotkeys MudDataGrid Migration Design

**Date:** 2026-05-12
**Status:** Design - ready for implementation planning

## Goal

Replace the `MudTable` implementations on the Hotstrings and Hotkeys pages with `MudDataGrid`, adding server-backed filtering and sorting plus native `MudDataGrid` inline editing while preserving existing CRUD behavior, auth gating, loading states, snackbar feedback, and delete confirmation flows.

## Architecture

Blazor WebAssembly pages continue to use typed API clients. `MudDataGrid` server state must be translated through the UI clients into controller query parameters and MediatR list queries, with explicit allow-listed sort and filter fields in the application layer.

## Tech Stack

.NET 10, Blazor WebAssembly, MudBlazor 9.x, MediatR, EF Core, Ardalis.Result, FluentValidation, xUnit, bUnit, FluentAssertions, NSubstitute.

## Current State

- `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor` and `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor` both use `MudTable` with `ServerData`.
- Both pages already support:
  - a toolbar Add button
  - a toolbar Reload button
  - a debounced global search input
  - inline row editing driven by `_editing` and `_commitAttempted`
  - server paging through `page` and `pageSize`
  - snackbar feedback and delete confirmation dialogs
- The frontend list clients only support `profileId`, `search`, `page`, and `pageSize`.
- The backend list queries only support the same inputs and currently sort by `CreatedAt DESC, Id`.
- Existing bUnit coverage already verifies load, error alerts, add/reload/search affordances, and create/update validation behavior for both pages.

## Scope Decisions

1. Keep the current external toolbar search box.
2. Add `MudDataGrid` column filtering and column sorting on top of the existing global search.
3. Move from the current custom draft-row editing workflow to native `MudDataGrid` inline editing.
4. Preserve current validation rules, profile selection UX, delete confirmation behavior, and snackbar messages.
5. Add backend/API support needed to safely translate grid state into server-side query behavior.

## Likely Files In Scope

### Frontend

- `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor`
- `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotstringsApiClient.cs`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotstringsApiClient.cs`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotkeysApiClient.cs`
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotkeysApiClient.cs`

### Backend

- `src\Backend\AHKFlowApp.API\Controllers\HotstringsController.cs`
- `src\Backend\AHKFlowApp.API\Controllers\HotkeysController.cs`
- `src\Backend\AHKFlowApp.Application\Queries\Hotstrings\ListHotstringsQuery.cs`
- `src\Backend\AHKFlowApp.Application\Queries\Hotkeys\ListHotkeysQuery.cs`

### Tests

- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotstringsPageTests.cs`
- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotkeysPageTests.cs`
- Backend query/controller tests covering sort/filter/search translation.

## Server-Side DataGrid State

The current list endpoints only understand `page`, `pageSize`, `profileId`, and `search`. `MudDataGrid` sorting and filtering is not a UI-only change in this codebase because both current pages already use server loading.

The implementation plan should define an explicit request shape for grid paging, sorting, filtering, and global search. Sortable and filterable fields must be allow-listed per entity instead of accepting arbitrary UI property names. The server should preserve existing paging semantics and total-count behavior while composing global search with column filters.

## Hotstrings Page Migration

`src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor` should move from `MudTable` to `MudDataGrid<HotstringDto>` and translate `GridState<HotstringDto>` into the typed API client request.

Expected columns:

- Trigger
- Replacement
- Profiles
- Ending character
- Trigger-inside-word flag
- Actions

Filtering and sorting should be enabled only where the backend query explicitly supports it. The existing toolbar search box should remain and compose with grid filters rather than being replaced by them.

Native `MudDataGrid` inline editing should replace the current draft placeholder row approach using `Guid.Empty`. The implementation plan should call out the add-row design explicitly because native DataGrid editing may require a different flow while preserving visible behavior.

## Hotkeys Page Migration

`src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor` should move from `MudTable` to `MudDataGrid<HotkeyDto>` and translate `GridState<HotkeyDto>` into the typed API client request.

Expected columns:

- Description
- Key
- Modifier flags
- Action
- Parameters
- Profiles
- Actions

Hotkeys has more edit controls than Hotstrings, so template or editor columns will likely be needed for modifier flags, enum selection, and profile selection.

## Test Strategy

The implementation plan should update coverage in:

- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotstringsPageTests.cs`
- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotkeysPageTests.cs`
- The appropriate backend test projects for query/controller coverage.

Tests should stay behavior-oriented rather than asserting brittle `MudDataGrid` markup. Coverage should include server-backed sorting/filtering translation, global search composed with column filters, and invalid create/edit commits remaining blocked.

## Risks and Watchouts

- Native `MudDataGrid` editing may not map one-to-one to the current draft-row workflow, so the add/edit UX may need a small reshape while preserving behavior.
- Column filtering plus global search can produce ambiguous results if the query-composition rules are not explicit.
- Template-heavy columns may require more test adjustment than the current `MudTable` implementation.
- The backend must not trust arbitrary UI field names for sorting and filtering.

## Done Criteria

- Both pages use `MudDataGrid` instead of `MudTable`.
- Toolbar search still works.
- Column filtering and sorting work server-side.
- Native inline editing supports create/update flows without regressing validation.
- Delete confirmation and snackbar feedback still work.
- Relevant UI and backend tests cover the new behavior.
