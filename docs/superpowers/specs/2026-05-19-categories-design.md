# Categories Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Add a flat, freeform `Category` concept (M:M with Hotstrings and Hotkeys) for UI organization and filtering. Categories are user-owned, do not influence script generation. Seed a small starter set on first use that the user can delete.

## Architecture

New `Category` aggregate alongside `Hotstring`/`Hotkey`. Two new join tables: `HotstringCategory`, `HotkeyCategory`. Categories are orthogonal to Profiles — Profiles decide which `.ahk` script an item belongs to; Categories decide how it is organized in the UI.

## Tech Stack

.NET 10, EF Core, MediatR, Ardalis.Result, FluentValidation, MudBlazor 9.x, xUnit, Testcontainers.

## Current State

- No `Category` entity, no junction tables.
- `Hotstring` and `Hotkey` only group via `Profile` M:M (`HotstringProfile`, `HotkeyProfile`).
- List queries filter by `profileId` and free-text `search` (`Trigger`/`Replacement` or `Description`/`Key`/`Parameters`).

## Domain

`Category` entity (`src/Backend/AHKFlowApp.Domain/Entities/Category.cs`):
- `Guid Id`
- `Guid OwnerOid`
- `string Name` (max 30, unique per owner, case-insensitive)
- `DateTimeOffset CreatedAt`, `DateTimeOffset UpdatedAt`
- Factory `Create()`, instance `Update()` mirroring `Profile`.

Join tables:
- `HotstringCategory(HotstringId, CategoryId)` — composite PK, cascade delete on either side.
- `HotkeyCategory(HotkeyId, CategoryId)` — same shape.

Seeded starter set (created lazily on the user's first `GET /categories` call when they own zero categories, mirroring the existing `Profile` default-creation behavior):

`Autocorrect`, `Communication`, `DateTime`, `Email`, `Code`, `Symbols`, `Window Management`, `App Launcher`.

**Read-with-side-effect semantics — explicit contract:**

- The endpoint remains `GET` (not `POST`) to preserve consistency with the existing `Profile` default-creation pattern.
- The first call for a user that has never been seeded inserts the eight starter categories inside the same request, then returns the list.
- Subsequent calls are pure reads — no writes, no duplicates.
- **Seed state is tracked by an explicit marker, not by row count.** `UserPreference` gains a nullable `CategoriesSeededAt: DateTimeOffset?` field. Null = never seeded. Non-null = already seeded once, never again. This means a user who deletes all eight defaults does **not** get them re-seeded on the next `GET /categories` — the marker remains set.
- Concurrent first-time calls rely on `(OwnerOid)` PK on `UserPreference` plus `(OwnerOid, Name)` unique index on `Category`: the second write loses with a duplicate-key violation; the handler swallows it and proceeds to the read.
- Response carries `Cache-Control: no-store` to avoid caching the seeding write at proxies.

**List shape — paginated:**

`GET /api/v1/categories` returns `PagedList<CategoryDto>` with the same shape as `ListHotstringsQuery`'s response:

- Query params: `page` (1-based, default 1, max 10000), `pageSize` (default 50, max 200), `search` (max 200 chars, LIKE match against `Name`).
- Validator mirrors `ListHotstringsQueryValidator`.
- For the chip-filter use case on Hotstring/Hotkey pages (which needs every category), the frontend issues `GET /categories?pageSize=200`. Since the realistic category count per user is well below 200, this is sufficient. (If a user creates >200 categories, the chip set quietly truncates — acceptable trade-off.)

## API Surface

- `GET /api/v1/categories` — paginated list (filters: `search`).
- `GET /api/v1/categories/{id}` — single.
- `POST /api/v1/categories` — create (`CreateCategoryDto { Name }`).
- `PUT /api/v1/categories/{id}` — update name.
- `DELETE /api/v1/categories/{id}` — delete (cascade clears joins; hotstrings/hotkeys are not affected).

Hotstring and Hotkey commands gain `CategoryIds: Guid[]`. DTOs gain `CategoryIds`.

`ListHotstringsQuery` / `ListHotkeysQuery` gain optional `categoryIds: Guid[]` filter:

- Wire format: repeated query parameter (`?categoryIds=<guid>&categoryIds=<guid>`). ASP.NET Core model binding handles this natively for `Guid[]` action parameters. CSV is **not** supported.
- Empty / missing → no category filter applied (existing behavior).
- Semantics: **OR among `categoryIds`** — an item matches when its category set intersects the requested set (at least one match). This matches the UI chip-filter semantics defined under "UI Surface".
- Combination with existing `search` and `profileId` is AND.

## UI Surface

- New `Categories.razor` page: simple MudDataGrid with create/edit/delete.
- Hotstrings/Hotkeys pages: chip-filter row above the grid, chips populated from the user's categories. **Multi-select OR-semantics**: selecting multiple chips returns items in *any* of those categories. The chip filter composes with the existing text `search` box via AND (item must match `search` AND match at least one selected chip).
- Editor dialogs gain a multi-select Categories input (`MudAutocomplete<CategoryDto>` with `MultiSelection`).

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.Domain/Entities/Category.cs` (new)
- `src/Backend/AHKFlowApp.Domain/Entities/HotstringCategory.cs`, `HotkeyCategory.cs` (new)
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` (new DbSets)
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/*` (3 new configurations)
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/` (new migration `AddCategories`)
- `src/Backend/AHKFlowApp.Application/Commands/Categories/*` (Create/Update/Delete)
- `src/Backend/AHKFlowApp.Application/Queries/Categories/*` (Get/List)
- `src/Backend/AHKFlowApp.Application/Validators/Categories/*`
- `src/Backend/AHKFlowApp.Application/DTOs/CategoryDto.cs`
- `src/Backend/AHKFlowApp.API/Controllers/CategoriesController.cs`
- Hotstring/Hotkey commands/queries/handlers/DTOs/validators updated for `CategoryIds`.

### Frontend

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Categories.razor` (new)
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/CategoriesApiClient.cs` (new)
- Updates to `Hotstrings.razor`, `Hotkeys.razor` for chip filters and category multi-select editor.

### Tests

- `tests/AHKFlowApp.API.Tests/Controllers/CategoriesControllerTests.cs`
- Existing Hotstring/Hotkey integration tests updated for `CategoryIds`.
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/CategoriesPageTests.cs`

## Test Strategy

- Integration: CRUD round-trip; unique-name-per-owner; cascade on category delete leaves hotstrings/hotkeys intact; first list call seeds defaults; assigning a category not owned by the user is rejected.
- Validator: name length, name presence.
- bUnit: chip filter composes with global search; multi-select editor produces correct `CategoryIds` payload.

## Risks and Watchouts

- Chips use OR among themselves; text search composes with the chip set via AND (see UI Surface). Document this in the page-level help text.
- Lazy-seed runs inside the list query handler; treat creation as best-effort idempotent (catch unique-violation race for paranoid).
- New `CategoryIds` field on existing Hotstring/Hotkey DTOs is additive — clients tolerate, but the OpenAPI polish spec needs to capture the change.

## Done Criteria

- Migration adds three new tables; existing data unaffected.
- All hotstring/hotkey CRUD and list endpoints honor categories.
- Default categories appear for new users on their first list call.
- Blazor pages filter and assign categories via chips.
- Integration test suite green.
