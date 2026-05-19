# Test & Dev Tooling Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Adopt the **builder pattern** for test data construction across all test projects, and back the development workflow with the combined `/api/v1/dev/seed-all` endpoint already specified in the Seed Expansion design.

User preference recorded in memory: builders are the expected pattern for test data and scenario construction.

## Current State

- Test files construct entities via factory methods inline (`Hotstring.Create(ownerOid, "btw", "by the way", appliesToAllProfiles: true, ...)`).
- Arrange blocks grow long and brittle as parameter counts increase (Hotkey.Create already takes 9 args).
- No shared test-support project — common helpers live as private statics scattered across `tests/*`.

## Builders

New shared project `tests/AHKFlowApp.TestSupport/AHKFlowApp.TestSupport.csproj` referenced by every test project:

```csharp
// Hotstring
var hs = HotstringBuilder.WithOwner(ownerOid)
    .WithTrigger("btw")
    .WithReplacement("by the way")
    .NeedsEndingChar()             // toggles IsEndingCharacterRequired
    .InsideWord()                  // toggles IsTriggerInsideWord
    .WithCategory(catId)
    .ForAllProfiles()              // sets flag, clears profile list
    .WithDescription("greeting")
    .Build(clock);

// Hotkey
var hk = HotkeyBuilder.WithOwner(ownerOid)
    .Ctrl().Alt().Key("T")
    .Run("wt.exe")
    .ForAllProfiles()
    .WithCategory(launcherCatId)
    .Described("Launch Windows Terminal")
    .Build(clock);

// Profile
var p = ProfileBuilder.WithOwner(ownerOid)
    .Named("Work")
    .AsDefault()
    .WithHeader(DefaultProfileTemplates.Header)
    .Build(clock);

// Category
var c = CategoryBuilder.WithOwner(ownerOid).Named("Email").Build(clock);
```

Builders compose with each entity's existing public `Create()` factory; they do **not** expose new entity APIs or break encapsulation. Defaults are sensible (e.g. `ForAllProfiles()` is the default for hotstring/hotkey to keep current test ergonomics).

## Migration of Existing Tests

- One PR per test project: replace inline `Entity.Create(...)` calls with builder calls. Behavior must not change.
- Keep `Result`/DB-state assertions as-is.
- Build pre-existing seed datasets used by `WebApplicationFactory` fixtures via the same builders for consistency.

## Combined Dev Endpoint Support

The `/seed-all` endpoint is delivered by the Seed Expansion spec. This spec only confirms the testing side: `WebApplicationFactory`-based tests can `POST /api/v1/dev/seed-all` against a Testcontainer to populate a known state, then assert via the public API rather than seeding through `DbContext` directly when an end-to-end shape is what's being tested.

(Existing fixture helpers that seed via `DbContext` are still useful for unit-style integration tests — they remain.)

## Files In Scope

### New project

- `tests/AHKFlowApp.TestSupport/AHKFlowApp.TestSupport.csproj`
- `tests/AHKFlowApp.TestSupport/Builders/HotstringBuilder.cs`
- `tests/AHKFlowApp.TestSupport/Builders/HotkeyBuilder.cs`
- `tests/AHKFlowApp.TestSupport/Builders/ProfileBuilder.cs`
- `tests/AHKFlowApp.TestSupport/Builders/CategoryBuilder.cs`

### Test projects

- All five existing `tests/*.csproj` add `<ProjectReference>` to `AHKFlowApp.TestSupport`.
- Existing tests migrated to builders (touched files only — no opportunistic refactors).

### Solution file

- `AHKFlowApp.slnx` includes the new project.

## Test Strategy

- One "golden" test per builder verifies the produced entity equals direct `Create()` invocation for the same inputs (sanity check).
- No regression on existing assertions after migration; `dotnet test` stays green.
- Builders carry no logic beyond mutating builder state — they don't deserve heavy testing themselves.

## Risks and Watchouts

- Coordinating with Schema Polish spec: when `Description` lands on `Hotstring`, `HotstringBuilder` gets `.WithDescription(...)`. Sequence so this spec lands second.
- Builders must default to safe values that don't accidentally hide validation gaps (e.g. don't default `Trigger` to a non-empty string — force the caller to supply it).
- New test-support project must NOT be referenced by production code.

## Done Criteria

- `AHKFlowApp.TestSupport` builds and is referenced by all test projects.
- All current tests use builders for `Hotstring`, `Hotkey`, `Profile`, `Category`.
- `dotnet test` green across all projects.
