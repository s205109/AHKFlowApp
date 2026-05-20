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

5. **`/api/v1/dev/seed-all` test usage**: **Deferred — no task in this batch.** A `SeedAllAsync(this HttpClient client, bool reset = true)` helper on a shared test helper class is the intended shape *if and when* an integration test wants it. Promotion criterion: the first integration test that wants `seed-all` against a `WebApplicationFactory` shapes the signature and adds the helper in the same commit. Until then, narrow `DbContext`-based fixtures remain preferable (faster, easier to reason about) and no helper file is created.

## Files In Scope

### Existing project (extensions only)

- `tests/AHKFlowApp.TestUtilities/Builders/CategoryBuilder.cs` (new file)
- `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs` (add `WithDescription`, `WithCategory(ies)`)
- `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` (add `WithCategory(ies)`)
- `tests/AHKFlowApp.TestUtilities/Helpers/SeedAllHelper.cs` — **deferred, not in this batch**. Created only when the first integration test adopts it (see Scope #5).

### Test projects

- Existing tests that construct `Hotstring`/`Hotkey` for category-aware paths get the new builder methods applied. Touched files only; no opportunistic refactor.

## Test Strategy

- The new builder methods are trivial pass-throughs to `Entity.Create(...)` and junction-collection appends. Coverage comes from the consuming handler/integration tests added in the same task batches (Categories Tasks 8–12, 18; Schema Polish Task 8) — if those tests pass, the builder method behaved correctly. No standalone "builder under test" suite is added.
- Builder methods that diverge from this pass-through pattern (e.g. add validation, defaulting beyond `Entity.Create`, or non-trivial transformation) **do** require a focused test alongside.
- Existing tests stay green; `dotnet test` is the gate.

## Risks and Watchouts

- Builder defaults must remain safe: `WithCategory(...)` accumulates rather than replaces, while `WithCategories(...)` replaces — match the established `InProfile`/`WithProfiles` semantics so users aren't surprised.
- Don't reference `AHKFlowApp.TestUtilities` from production code (it's in `tests/`).
- The `/api/v1/dev/seed-all` helper is deferred; if ever promoted, it is for end-to-end-shape tests only. For unit-style integration tests, seeding via `DbContext` directly in the fixture remains preferable.

## Done Criteria

- `CategoryBuilder` lands after Categories ship.
- `HotstringBuilder.WithDescription` lands after Schema Polish.
- `HotstringBuilder.WithCategory(ies)` and `HotkeyBuilder.WithCategory(ies)` land alongside Categories.
- `SeedAllAsync` helper is **explicitly deferred** — not part of this spec's done criteria. Re-introduce as a new spec/task when an integration test actually wants it.
- `dotnet test` green.
