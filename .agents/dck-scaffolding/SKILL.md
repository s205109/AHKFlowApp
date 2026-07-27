---
name: dck-scaffolding
description: Use when scaffolding an AHKFlowApp feature, endpoint, entity, DTO, validator, handler, EF config, or test.
---

# Scaffolding

## Core Principles

1. **Architecture is fixed** - Controller APIs, explicit use cases, Ardalis.Result, EF Core DbContext injection, and layer folders.
2. **Complete slices** - Controller action, command/query, handler, validator, DTO, EF config, migration, and tests travel together when applicable.
3. **Tests by default** - Add behavior tests unless explicitly told not to.
4. **Modern C#** - Primary constructors, records, sealed classes, collection expressions, file-scoped namespaces.
5. **No incompatible templates** - Never scaffold Minimal APIs, feature folders, repository pattern, Mapster/AutoMapper, or MediatR.

## Mandatory Checklist

- [ ] Handler returns `Result<T>` or another declared typed result.
- [ ] Controller injects `IUseCase<TRequest,TResult>` and calls `ExecuteAsync(...)`.
- [ ] FluentValidation validator exists for mutable commands.
- [ ] Validation runs through `ValidatingUseCase<TRequest,TResult>`, not controllers or endpoint filters.
- [ ] Every async method accepts and propagates `CancellationToken`.
- [ ] Controller action has `[Authorize]` or `[AllowAnonymous]`.
- [ ] Controller action has `[ProducesResponseType]` entries.
- [ ] Entity uses private setters and domain methods/factories for state changes.
- [ ] EF mapping lives in `IEntityTypeConfiguration<T>`, not data annotations.
- [ ] Tests use real behavior and SQL Server Testcontainers for integration paths.

## Layer Structure

```text
src/Backend/AHKFlowApp.Application/
  Commands/
  Queries/
  DTOs/
  Abstractions/

src/Backend/AHKFlowApp.API/
  Controllers/

src/Backend/AHKFlowApp.Domain/
  Entities/

src/Backend/AHKFlowApp.Infrastructure/
  Persistence/
```

## Command and Handler

`src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs` is a live example: command record + validator + handler share one file, the handler class is `{CommandName}Handler` (e.g. `CreateHotkeyCommandHandler`, not `CreateHotkeyHandler`), it injects `IAppDbContext` (not `AppDbContext`) plus `ICurrentUser` and `TimeProvider`, and DI registration is a chained `.AddUseCase<TCommand, TResult, THandler>()` call in `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` (see lines 33-40 for the chain shape).

## Validator

Validators are usually a nested class in the same file as the command they validate (see `CreateHotkeyCommandValidator` in `CreateHotkeyCommand.cs` above) — not a separate file, despite the Layer Structure diagram above implying otherwise for large validators. Follow the co-located shape unless a validator grows large enough to warrant its own file.

## Query and Handler

`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs` is the live shape — handler class `GetHotstringQueryHandler` (not `GetHotstringHandler`), `IAppDbContext` + `ICurrentUser` injected, `AsNoTracking()` + `Include()` + `.ToDto()` rather than a `.Select()` projection. See `.agents/dck-ef-core/SKILL.md` for the EF Core side of this pattern.

## Controller

`src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` is the live shape. Note three things the simplified template above misses: results map via `result.ToProblemActionResult(this)` (an in-repo RFC 9457 extension, `src/Backend/AHKFlowApp.API/Extensions/ProblemDetailsResultExtensions.cs`), not the bare `Ardalis.Result.AspNetCore.ToActionResult`; class-level attributes add `[RequiredScope("access_as_user")]` and `[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]` / `...Status403Forbidden`; and action methods return `ActionResult<T>`, not `IActionResult`.

## Entity and EF Configuration

`src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (entity: private setters, `Create` factory) and `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs` (EF config: required/max-length properties, enum-as-int conversions, a filtered unique index) are the live, much richer versions of the toy example above — read them before scaffolding a new entity, don't copy the simplified shape here.

## Integration Test Shape

Use the shared `ApiTestFixture` (`tests/AHKFlowApp.TestUtilities/Fixtures/ApiTestFixture.cs`) via `[Collection("WebApi")]` — see `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15`. Don't stand up a new `WebApplicationFactory`/`MsSqlContainer` per test class.

## Anti-Patterns

- Minimal API endpoint groups.
- `ValidationFilter<T>` or validation inside controllers.
- `IMediator`, `IRequest`, or `IRequestHandler`.
- Repository wrappers over EF Core.
- Public entity setters for domain state.
- AutoMapper/Mapster.
- Feature folders.
- InMemory EF provider for integration behavior.

## Decision Guide

| Scenario | Scaffold |
|---|---|
| New command | command record, validator, handler, DI registration, tests |
| New query | query record, handler, DI registration, tests |
| New API action | controller method, response annotations, auth attribute |
| New entity | domain entity, EF config, DbSet, migration, reset/test fixture updates |
| New validation | FluentValidation rule on command/query boundary |
