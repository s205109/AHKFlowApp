# Schema Polish Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Two targeted schema/domain refinements:

1. Resolve `AppliesToAllProfiles` dual-mechanism ambiguity on `Hotstring`/`Hotkey`.
2. Add a `Description` field on `Hotstring` (parity with `Hotkey`).

**Removed from original scope:** RowVersion optimistic concurrency. Reason: single-user-per-tenant data model with low concurrent-edit contention. Adding `byte[] RowVersion` across four entities, every update DTO, every command/validator, every editor dialog, plus EF `OriginalValue` wiring (see below) is high-cost for marginal benefit at current scale. Revisit if concurrent-edit issues are reported.

> Implementation note for any future RowVersion work: EF Core's concurrency check uses `Entry(entity).Property(e => e.RowVersion).OriginalValue`. Update handlers currently load a fresh tracked entity via `FirstOrDefaultAsync` before saving — so the just-loaded DB value becomes the "original" and stale-client detection silently no-ops. Any future spec must explicitly require decoding the DTO `RowVersion` (base64 → `byte[]`) and assigning it to `OriginalValue` before `SaveChangesAsync`.

## Current State

- `Hotstring.AppliesToAllProfiles` (bool) **and** `HotstringProfile` join table — two sources of truth. Same on `Hotkey`/`HotkeyProfile`. Nothing enforces consistency at the domain layer. Handlers and validators have ad-hoc rules (see `UpdateHotstringCommand.cs:49` — junction rows replaced only when flag is false), but the rule isn't centralized.
- `Hotkey` has `Description` (max 200). `Hotstring` does not.

## (1) AppliesToAllProfiles Cleanup

**Decision:** keep the boolean as the canonical signal. Centralize the following two invariants at the validator + handler boundary. The domain entity `Create`/`Update` methods do not accept profile IDs today (junction rows are managed in the handler post-entity-creation, e.g. `CreateHotstringCommand.cs:70`), so no domain API change is needed.

**Invariants:**

1. **`AppliesToAllProfiles == true` ⇒ `ProfileIds` is null or empty.** Both set is rejected with `Result.Invalid("ProfileIds must be empty when AppliesToAllProfiles is true.")`.
2. **`AppliesToAllProfiles == false` ⇒ `ProfileIds` must contain at least one profile id.** Empty here means "applies to no profiles" — the item would exist but never appear in any generated script. Reject with `Result.Invalid("Provide at least one ProfileId, or set AppliesToAllProfiles = true.")`.

The second invariant tightens current behavior — the existing `UpdateHotstringCommand.cs:49` and `CreateHotstringCommand.cs:47` accept the "false + empty" combination silently. This spec changes that: orphaned items are not allowed by construction; the user must choose between "all profiles" and "at least one profile."

The migration backfill audits the current data set for rows in the "false + empty junction" state and either (a) flips them to `AppliesToAllProfiles = true` (preferred — preserves visibility) or (b) attaches them to the user's default profile. Decision: **option (a)** — flip to true. Document the migration step explicitly.

- **Validator**: `Application/Validation/ProfileAssociationRules.cs` (which `AddProfileAssociationRules(...)` already calls into) tightens the rule: when `AppliesToAllProfiles == true`, `ProfileIds` must be null or empty — already enforced; verify and add a test.
- **Handler**: explicit branch in create/update — when `AppliesToAllProfiles == true`, junction rows are not added (`CreateHotstringCommand.cs:70-74`, `UpdateHotstringCommand.cs:73-81`). Already present. Add unit-level handler tests that assert no junction rows are inserted when the flag is true.
- **Migration backfill**: one EF migration emits SQL that clears `HotstringProfile`/`HotkeyProfile` rows where the parent has `AppliesToAllProfiles == 1`. Decision: flag wins.
- **Document** `AppliesToAllProfiles == true` semantics in inline XML doc on the entity property and DTO field: "applies to every profile owned by the user, including future profiles."

Rejected alternative: introduce an "All" sentinel profile and drop the flag. Reason: more migration churn, breaks the existing API contract (DTOs expose the boolean).

## (2) Description on Hotstring

- New `string? Description` on `Hotstring` (max 200, nullable). Mirror `Hotkey.Description` shape.
- EF config sets max length and column type (`nvarchar(200) NULL`).
- `HotstringDto`, `CreateHotstringDto`, `UpdateHotstringDto`, validators, handlers, and `ListHotstringsQuery.search` predicate all include the field.
- UI: optional `Description` field in the hotstring editor dialog and a column on the data grid (hidden by default; toggleable via the grid column chooser).

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` — `Description` field, factory + update signature accept it.
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs` — column type + max length.
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_SchemaPolish.cs` — adds `Description` column on `Hotstrings`, backfills junction inconsistencies.
- `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`, `CreateHotstringDto.cs`, `UpdateHotstringDto.cs` — add `Description`.
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/*` — thread `Description` through create/update.
- `src/Backend/AHKFlowApp.Application/Validators/Hotstrings/*` — max-length rule on `Description`.
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` — include `Description` in `search` LIKE clause.

### Frontend

- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — `Description` editor input + grid column (toggleable).
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs` — DTO update.

### Tests

- `tests/AHKFlowApp.Application.Tests/Validators/HotstringValidatorTests.cs` — invariant test for `AppliesToAllProfiles == true` rejects non-empty `ProfileIds`.
- `tests/AHKFlowApp.Application.Tests/Commands/Hotstrings/UpdateHotstringCommandHandlerTests.cs` — junction rows are not inserted when flag is true.
- `tests/AHKFlowApp.API.Tests/Controllers/HotstringsControllerTests.cs` — `Description` round-trips through CRUD; search matches against `Description`.

## Test Strategy

- Validator unit tests: existing `AddProfileAssociationRules` rejects flag+profile IDs combination.
- Handler unit tests: confirm no junction rows are added when flag is true (Create and Update).
- Integration: search by `Description` text returns the matching hotstring.
- Migration applies cleanly on existing seed data.

## Risks and Watchouts

- Migration changes only the `Hotstrings` table schema (adds `Description`) plus a one-time DELETE on the two junction tables for any inconsistent rows. EF Core's SQL Server provider runs migrations transactionally; failure rolls back cleanly.
- Existing tests that build `Hotstring` via `Hotstring.Create(...)` need a new `description = null` parameter — coordinate with the Test/Dev Tooling spec (the existing `HotstringBuilder` should add `WithDescription(...)` so test churn is minimal).
- `Description` is in the LIKE search clause — confirm SQL generation does not produce unbounded full-table scans for very large user data sets. Add `LIKE 'pattern%'` prefix-only? No — keep `%pattern%` to match user intent; revisit only if performance shows a problem.

## Done Criteria

- One migration adds `Description` column and backfills any `AppliesToAll` inconsistencies.
- `Hotstring` CRUD round-trips `Description`; search hits it.
- Validator and handler tests cover the AppliesToAll invariant.
