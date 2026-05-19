# Test & Dev Tooling Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Extend the existing test-data builders to cover Categories and the new fields added by other 2026-05-19 specs, and use the combined `/api/v1/dev/seed-all` endpoint (delivered by the Seed Expansion spec) as a one-shot dev bootstrap.

## Current State (Verified)

- `tests/AHKFlowApp.TestUtilities/AHKFlowApp.TestUtilities.csproj` already exists and is referenced from every test project (`AHKFlowApp.slnx`).
- Builders already present in `tests/AHKFlowApp.TestUtilities/Builders/`:
  - `HotstringBuilder.cs` — supports `WithOwner`, `InProfile`, `WithProfiles`, `AppliesToAllProfiles`, `WithTrigger`, `WithReplacement`, `WithEndingCharacterRequired`, `WithTriggerInsideWord`, `WithClock`, `Build()`.
  - `HotkeyBuilder.cs`
  - `ProfileBuilder.cs` — supports `WithOwner`, `WithName`, `AsDefault`, `WithHeader`, `WithFooter`, `WithClock`, `Build()`.
  - `HealthResponseBuilder.cs`
- Existing tests use these builders; **the original spec was wrong** about there being no shared test-support project.

## Scope (Revised)

This spec is now a small set of extensions, not a greenfield project.

1. **Add `CategoryBuilder`** (after the Categories spec lands):
   ```csharp
   CategoryBuilder.WithOwner(ownerOid).Named("Email").WithClock(clock).Build();
   ```

2. **Extend `HotstringBuilder`** (after the Schema Polish spec lands):
   - `WithDescription(string? description)` — sets `Description` on the produced entity.

3. **Extend `HotstringBuilder` and `HotkeyBuilder`** (after the Categories spec lands):
   - `WithCategory(Guid categoryId)` / `WithCategories(params Guid[] ids)` — attaches junction rows in `Build()`, matching the existing `InProfile`/`WithProfiles` pattern.

4. **Reuse existing builders** for `AhkScriptGenerator`-related tests added by the Header Template spec — no new builder type needed; `ProfileBuilder.WithHeader(...)` already exists.

5. **`/api/v1/dev/seed-all` test usage**: `WebApplicationFactory`-based integration tests gain a small helper extension (`SeedAllAsync(this HttpClient client, bool reset = true)`) on a shared test helper class. Use sparingly — most existing tests should keep their narrow `DbContext`-based fixtures because they're faster and easier to reason about.

## Files In Scope

### Existing project (extensions only)

- `tests/AHKFlowApp.TestUtilities/Builders/CategoryBuilder.cs` (new file)
- `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs` (add `WithDescription`, `WithCategory(ies)`)
- `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` (add `WithCategory(ies)`)
- `tests/AHKFlowApp.TestUtilities/Helpers/SeedAllHelper.cs` (new, optional — only if integration tests adopt it)

### Test projects

- Existing tests that construct `Hotstring`/`Hotkey` for category-aware paths get the new builder methods applied. Touched files only; no opportunistic refactor.

## Test Strategy

- One golden test per new builder method verifies the produced entity matches a direct `Entity.Create(...)` invocation for the same inputs.
- Existing tests stay green; `dotnet test` is the gate.

## Risks and Watchouts

- Builder defaults must remain safe: `WithCategory(...)` accumulates rather than replaces, while `WithCategories(...)` replaces — match the established `InProfile`/`WithProfiles` semantics so users aren't surprised.
- Don't reference `AHKFlowApp.TestUtilities` from production code (it's in `tests/`).
- The `/api/v1/dev/seed-all` helper is for end-to-end-shape tests only; for unit-style integration tests, seeding via `DbContext` directly in the fixture remains preferable.

## Done Criteria

- `CategoryBuilder` lands after Categories ship.
- `HotstringBuilder.WithDescription` lands after Schema Polish.
- `HotstringBuilder.WithCategory(ies)` and `HotkeyBuilder.WithCategory(ies)` land alongside Categories.
- `dotnet test` green.
