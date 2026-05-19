# Schema Polish Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Three targeted schema/domain refinements:

1. Resolve `AppliesToAllProfiles` dual-mechanism ambiguity on `Hotstring`/`Hotkey`.
2. Add a `Description` field on `Hotstring` (parity with `Hotkey`).
3. Add SQL Server `rowversion` optimistic concurrency tokens on the four editable aggregates (`Hotstring`, `Hotkey`, `Profile`, `Category`).

## Current State

- `Hotstring.AppliesToAllProfiles` (bool) **and** `HotstringProfile` join table — two sources of truth. Same on `Hotkey`/`HotkeyProfile`. Nothing enforces consistency.
- `Hotkey` has `Description` (max 200). `Hotstring` does not.
- No concurrency token on any entity. Last-write-wins between concurrent tabs.

## (1) AppliesToAllProfiles Cleanup

**Decision:** keep the boolean as the canonical signal. Enforce invariant *"if `AppliesToAllProfiles == true`, the join set is empty"*.

- Domain guard inside `Hotstring.Create`/`Hotstring.Update` and the `Hotkey` equivalents: throw `InvalidOperationException` if both the flag is set and any profile id is supplied.
- Validator `CreateHotstringCommandValidator` / `UpdateHotstringCommandValidator` (and hotkey equivalents) enforce the same at the boundary.
- Migration backfill: for any existing row with `AppliesToAllProfiles == true` AND non-empty join set, the flag wins — clear the join. (Survey of current data shows few/no such rows from seed.)
- Document `AppliesToAllProfiles == true` semantics: "applies to every profile owned by the user, including future profiles." Existing query logic already matches this.

Rejected alternative: introduce an "All" sentinel profile and drop the flag. Reason: more migration churn, breaks the existing API contract (DTOs expose the boolean).

## (2) Description on Hotstring

- New `string? Description` on `Hotstring` (max 200, nullable). Mirror `Hotkey.Description` shape.
- EF config sets max length and column type.
- `HotstringDto`, `CreateHotstringCommand`, `UpdateHotstringCommand`, validators, handlers, and `ListHotstringsQuery.search` predicate all include the field.
- UI: optional `Description` field in the hotstring editor and a column on the data grid (hidden by default until user toggles).

## (3) RowVersion Concurrency

- Add `byte[] RowVersion` to `Hotstring`, `Hotkey`, `Profile`, `Category`.
- EF config: `.IsRowVersion()` — SQL Server emits `rowversion` column, auto-managed.
- DTOs expose `RowVersion` as base64 `string` (matches MudBlazor edit-and-resubmit flow).
- `Update*Command` accepts `RowVersion` and passes through to EF. `DbUpdateConcurrencyException` is caught at the handler layer and mapped to `Result.Conflict()`.
- Controllers map `Result.Conflict()` to `409 Conflict` (already covered by `ToActionResult()`).
- UI: edit form preserves the row's `RowVersion` and sends it back on save; on 409, show a snackbar prompting reload.

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` — Description field, RowVersion, invariant in factory/update.
- `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` — RowVersion, invariant in factory/update.
- `src/Backend/AHKFlowApp.Domain/Entities/Profile.cs` — RowVersion.
- `src/Backend/AHKFlowApp.Domain/Entities/Category.cs` — RowVersion (after Categories spec).
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/*` — `IsRowVersion()` on each.
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_SchemaPolish.cs` — adds Description column on `Hotstrings`, RowVersion column on all four tables, plus the AppliesToAll backfill SQL.
- `src/Backend/AHKFlowApp.Application/DTOs/*` — fields added to DTOs.
- `src/Backend/AHKFlowApp.Application/Commands/*` and `src/Backend/AHKFlowApp.Application/Validators/*` — new fields and invariant validation.
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` — include Description in `search`.

### Frontend

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — Description editor + column toggle.
- Editor dialogs in both pages — roundtrip RowVersion; handle 409 with reload prompt.

### Tests

- `tests/AHKFlowApp.Application.Tests/Validators/*` — invariant rejected when flag + profile ids both set.
- `tests/AHKFlowApp.API.Tests/Controllers/*` — concurrent update returns 409.
- Existing tests updated for new DTO fields (additive, mostly mechanical).

## Test Strategy

- Validator unit test: `CreateHotstringCommand` rejects flag+profileIds together.
- Integration: two parallel updates to the same row — first succeeds, second returns 409 with `Result.Conflict()`.
- Integration: search by Description text.
- Migration applies cleanly on existing seed data.

## Risks and Watchouts

- Migration changes four tables in one file. If a deploy fails mid-migration, EF Core rolls back transactionally on SQL Server (default).
- `RowVersion` round-tripping requires DTOs and validators to skip the field on create (no version yet) and require it on update.
- Existing tests that build entities via `Hotstring.Create(...)` need a new `description = null` parameter — coordinate with the Test/Dev Tooling spec (builders) to minimize churn.

## Done Criteria

- One migration adds Description column, RowVersion columns, backfills any `AppliesToAll` inconsistencies.
- Update endpoints return 409 on concurrent edit.
- Hotstring CRUD honours Description.
- Domain invariant enforced at factory + validator.
