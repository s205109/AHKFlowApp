# Testing Infrastructure Setup — Design Spec

**Date:** 2026-04-04
**Backlog:** 004-testing-infrastructure-setup
**Status:** Approved

## Goal

Configure unit and integration testing infrastructure with xUnit, FluentAssertions, NSubstitute, Testcontainers, and Coverlet. Create all test projects, write tests for existing code, and set up code coverage reporting (Cobertura + HTML).

## Project Structure

```
tests/
  AHKFlowApp.TestUtilities/         # Shared fixtures, builders, base classes
  AHKFlowApp.Domain.Tests/          # Empty scaffold (future entity tests)
  AHKFlowApp.Application.Tests/     # ValidationBehavior unit tests
  AHKFlowApp.Infrastructure.Tests/  # AppDbContext + migration smoke tests
  AHKFlowApp.API.Tests/             # Existing tests refactored + middleware tests
  AHKFlowApp.UI.Blazor.Tests/       # bUnit component + service tests
```

> **Note:** AGENTS.md references `AHKFlowApp.Infrastructure.Test` (singular). This spec uses plural (`Infrastructure.Tests`) for consistency with all other test projects. AGENTS.md will be updated during implementation.

## Package Dependencies

### New packages in `Directory.Packages.props`

| Package | Purpose |
|---------|---------|
| `NSubstitute` | Mocking at third-party boundaries |
| `coverlet.collector` | Per-project coverage collection (already used by API.Tests; standardized across all test projects) |
| `bunit` | Blazor component testing |
| `ReportGenerator` (global tool) | Merge Cobertura XMLs into HTML report |

### Project references

- `TestUtilities` → `Infrastructure` (for `AppDbContext` in shared fixture)
- `Domain.Tests` → `Domain` + `TestUtilities`
- `Application.Tests` → `Application` + `TestUtilities`
- `Infrastructure.Tests` → `Infrastructure` + `TestUtilities`
- `API.Tests` → `API` + `TestUtilities` (replaces local `HealthApiFactory`)
- `UI.Blazor.Tests` → `UI.Blazor` + `TestUtilities`

### Common test project packages

All test projects: `xunit`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `FluentAssertions`, `coverlet.collector`.

## Shared TestUtilities

### SqlContainerFixture

Extracted from existing `HealthApiFactory`. Manages MsSql Testcontainer lifecycle via `IAsyncLifetime`. Exposes `ConnectionString` for any test project needing real SQL Server.

```
SqlContainerFixture
  ├── StartAsync()        → spins up SQL Server container
  ├── ConnectionString    → container connection string
  └── DisposeAsync()      → tears down container
```

### CustomWebApplicationFactory

Extends `WebApplicationFactory<Program>`. Accepts `SqlContainerFixture`, rewires `AppDbContext` to point at the container. Used by `API.Tests` and `Infrastructure.Tests`.

### Test Data Builders

Builder pattern for test object construction. Sensible defaults — `.Build()` with no customization produces a valid object. Builders are mutable, chainable, produce new instances on each `Build()`.

Initial builder: `HealthResponseBuilder`.

```csharp
var response = new HealthResponseBuilder()
    .WithStatus("Healthy")
    .WithCheck("database", "Healthy")
    .Build();
```

Pattern established for future entity builders as domain grows.

### Collection Definitions

Shared xUnit collection definitions so test classes within a project reuse the same container instance.

## Test Coverage Plan

### API.Tests (refactored + expanded)

| Test class | What it tests | Type |
|---|---|---|
| `HealthControllerTests` | Existing 3 tests, refactored to use shared `CustomWebApplicationFactory` | Integration |
| `GlobalExceptionMiddlewareTests` | `ValidationException` → 400 ProblemDetails, generic `Exception` → 500 ProblemDetails, RFC 9457 format | Integration (test endpoint that throws) |
| `ProgramTests` | Swagger redirect, `/health` plain text endpoint, DI resolution | Integration |

### Application.Tests

| Test class | What it tests | Type |
|---|---|---|
| `ValidationBehaviorTests` | Throws `ValidationException` on invalid, passes through on valid, works with no validators | Unit (NSubstitute for `IValidator<T>` and handler delegate) |

### Infrastructure.Tests

| Test class | What it tests | Type |
|---|---|---|
| `AppDbContextTests` | Context creates against real SQL, `EnsureCreated` applies schema, `OnModelCreating` runs cleanly | Integration (Testcontainers) |
| `MigrationTests` | Pending migrations apply cleanly, migration is idempotent | Integration (Testcontainers) |

### Domain.Tests

Empty scaffold — project structure ready for future entity and value object tests.

### UI.Blazor.Tests

| Test class | What it tests | Type |
|---|---|---|
| `HealthPageTests` | Loading state, health data on success, error alert on failure, refresh button | bUnit (NSubstitute for `IAhkFlowAppApiHttpClient`) |
| `AhkFlowAppApiHttpClientTests` | Deserializes response, handles HTTP errors | Unit (mock `HttpMessageHandler`) |

### Testing approach

- NSubstitute only at third-party boundaries
- No mocking `AppDbContext` — real SQL via Testcontainers
- Builder pattern for all test data construction
- `CancellationToken` propagated in all async test methods
- Test naming: `MethodName_Scenario_ExpectedResult`
- AAA pattern with blank line separation

## Code Coverage

### Collection

Each test `.csproj` includes `coverlet.collector` (the `dotnet test` data collector approach, consistent with existing `API.Tests`). Coverage collected via:

```bash
dotnet test --configuration Release \
  --collect:"XPlat Code Coverage" \
  --results-directory ./coverage
```

Per-project Cobertura XML files land under `coverage/` in each test project directory.

### Exclusions

- `Program` class (top-level statements)
- `*.Migrations.*`
- `*.Designer.cs`
- `TestUtilities` project

### Report generation

`dotnet-reportgenerator-globaltool` merges per-project Cobertura into unified report:

```bash
reportgenerator \
  -reports:"tests/*/coverage/coverage.cobertura.xml" \
  -targetdir:"coverage-report" \
  -reporttypes:"Html;Cobertura"
```

**Outputs:**
- `coverage-report/index.html` — browsable local HTML report
- `coverage-report/Cobertura.xml` — merged file for future CI

### .gitignore additions

- `coverage/`
- `coverage-report/`

## Out of Scope

- CI/CD pipeline (backlog item 010) — the backlog 004 acceptance criterion "CI runs unit and integration tests" is deferred to item 010, which owns all CI/CD workflow creation
- Test coverage targets/thresholds
- Tests for future domain entities (hotstrings, profiles, etc.)

## Design Decisions

- **`coverlet.collector` over `coverlet.msbuild`:** The existing `API.Tests` already uses `coverlet.collector`. Standardizing on `collector` avoids mixing two Coverlet integration strategies.
- **`Infrastructure.Tests` (plural):** AGENTS.md has `Infrastructure.Test` (singular) — a typo inconsistent with all other test project names. This spec corrects it.
- **`HealthResponseBuilder` targets API model:** Builds `AHKFlowApp.API.Models.HealthResponse` (positional record). The Blazor DTO version uses init properties and is constructed directly in UI tests.
- **`HttpMessageHandler` mocking:** Treating `HttpMessageHandler` as a third-party boundary is consistent with the "NSubstitute for third-party boundaries only" rule.
- **`ProgramTests` DI verification:** Tests that the app starts without DI exceptions (via `WebApplicationFactory`), not individual service resolution — the other integration tests implicitly cover this, so `ProgramTests` focuses on HTTP-level behavior (routes, redirects).

## Dependencies

- Backlog item 003 (project scaffold) — complete
