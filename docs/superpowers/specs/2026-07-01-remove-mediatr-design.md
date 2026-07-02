# Remove MediatR Design

## Summary

AHKFlowApp will remove MediatR from runtime code, tests, active documentation, and active agent skills. The replacement is explicit application use cases: controllers depend on typed use-case services, request records remain in the Application layer, and handlers continue to own business logic and persistence through `IAppDbContext`.

The current behavior must stay intact:

- Controllers remain thin and controller-based.
- Application handlers continue returning `Ardalis.Result` / `Result<T>`.
- FluentValidation still runs before handler logic for every command/query with validators.
- `GlobalExceptionMiddleware` continues mapping `FluentValidation.ValidationException` to 400 ProblemDetails.
- No repository pattern, mapper library, minimal APIs, feature folders, or controller-owned business logic is introduced.

## Current State

MediatR is used in these runtime surfaces:

- `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` registers MediatR and adds `ValidationBehavior<,>`.
- Command/query records implement `IRequest<Result>` or `IRequest<Result<T>>`.
- Command/query handler classes implement `IRequestHandler<TRequest, TResult>`.
- API controllers inject `IMediator` and call `mediator.Send(...)`.
- `SeedAllCommandHandler` composes the category, hotstring, and hotkey seed steps through `IMediator.Send(...)` inside one EF execution strategy and transaction.
- `tests/AHKFlowApp.Application.Tests/Behaviors/ValidationBehaviorTests.cs` directly tests the MediatR pipeline behavior.
- `tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs` builds a MediatR-backed service provider.
- `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj` references `MediatR`, with the central package version in `Directory.Packages.props`.

MediatR is also embedded in active guidance:

- `AGENTS.md`
- `.github/instructions/personal-defaults.md`
- `.agents/cck-scaffolding/SKILL.md`
- `.agents/cck-testing/SKILL.md`
- `.agents/cck-error-handling/SKILL.md`
- `.agents/cck-openapi/SKILL.md`
- `.agents/cck-ef-core/SKILL.md`
- `.agents/cck-build-fix/SKILL.md`
- The duplicate plugin copies under `.agents/plugins/plugins/ahkflowapp/skills/`

Historical plans, specs, and backlog entries can keep MediatR mentions when they describe past architecture. Active project guidance should not continue instructing agents to add or repair MediatR.

## Design

### Application use-case contract

Add a public Application-layer contract:

```csharp
namespace AHKFlowApp.Application.Abstractions;

public interface IUseCase<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
```

Add an internal handler contract:

```csharp
namespace AHKFlowApp.Application.Abstractions;

internal interface IUseCaseHandler<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
```

Handlers implement `IUseCaseHandler<TRequest, TResult>`. API controllers inject `IUseCase<TRequest, TResult>`, not concrete handler classes. This keeps handler implementations internal while making controller dependencies explicit and typed.

### Validation replacement

Replace `ValidationBehavior<TRequest,TResponse>` with an Application-layer decorator:

```csharp
internal sealed class ValidatingUseCase<TRequest, TResult>(
    IEnumerable<IValidator<TRequest>> validators,
    IUseCaseHandler<TRequest, TResult> inner)
    : IUseCase<TRequest, TResult>
    where TRequest : notnull
{
    public async Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct)
    {
        // Same validation semantics as the current MediatR behavior.
        // Throw ValidationException before inner handler execution.
    }
}
```

`ValidatingUseCase` preserves the current boundary: invalid requests throw `ValidationException`, and `GlobalExceptionMiddleware` converts that exception into 400 ProblemDetails. Handlers continue to trust boundary validation and should not duplicate FluentValidation rules internally.

### Request and handler shape

Command/query records remain in the existing `Commands/` and `Queries/` folders but no longer implement MediatR interfaces:

```csharp
public sealed record CreateHotstringCommand(CreateHotstringDto Input);
```

Handlers keep the same business logic and dependencies, but implement `IUseCaseHandler` and expose `ExecuteAsync`:

```csharp
internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(CreateHotstringCommand request, CancellationToken ct)
    {
        // Existing handler body, unchanged except method name.
    }
}
```

Direct handler unit tests should call `ExecuteAsync`. API integration tests should prove the decorated `IUseCase` path still runs validation.

### Dependency injection

`AddApplication` registers:

- `services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly)`
- `services.AddScoped(typeof(IUseCase<,>), typeof(ValidatingUseCase<,>))`
- One `IUseCaseHandler<TRequest,TResult>` registration per command/query handler
- Existing singleton/scoped application services

Use a small private registration helper to keep the explicit list readable:

```csharp
private static IServiceCollection AddUseCase<TRequest, TResult, THandler>(this IServiceCollection services)
    where TRequest : notnull
    where THandler : class, IUseCaseHandler<TRequest, TResult>
{
    return services.AddScoped<IUseCaseHandler<TRequest, TResult>, THandler>();
}
```

This avoids replacing MediatR with a reflection-heavy scanner while still making missing registrations fail at startup/test time through normal DI resolution.

### Controller flow

Controllers replace `IMediator` with typed use cases. For example, `HotstringsController` injects:

- `IUseCase<ListHotstringsQuery, Result<PagedList<HotstringDto>>>`
- `IUseCase<GetHotstringQuery, Result<HotstringDto>>`
- `IUseCase<CreateHotstringCommand, Result<HotstringDto>>`
- `IUseCase<BulkDeleteHotstringsCommand, Result<BulkDeleteResultDto>>`
- `IUseCase<UpdateHotstringCommand, Result<HotstringDto>>`
- `IUseCase<DeleteHotstringCommand, Result>`

Actions call `ExecuteAsync(...)` and keep the existing `ToProblemActionResult(this)`, `CreatedAtRoute`, and `NoContent` behavior.

### Seed-all composition

`SeedAllCommandHandler` must preserve the current transactional behavior. It should inject the three seed use cases directly:

- `IUseCase<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>>`
- `IUseCase<SeedHotstringsCommand, Result<PagedList<HotstringDto>>>`
- `IUseCase<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>>`

Inside the existing EF execution strategy and transaction, it calls each use case with the same `CancellationToken`, checks each result, rolls back on failures, and commits only after all three steps succeed. The rollback-on-inner-exception test must continue proving no rows remain after a mid-pipeline failure.

### Package and reference cleanup

After all code compiles without MediatR:

- Remove `<PackageReference Include="MediatR" />` from `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`.
- Remove `<PackageVersion Include="MediatR" ... />` from `Directory.Packages.props`.
- Delete `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`.
- Rename or replace tests for `ValidationBehavior` with tests for `ValidatingUseCase`.
- Verify `rg -n "MediatR|IMediator|IRequest|IRequestHandler|IPipelineBehavior|AddMediatR" src tests AGENTS.md .agents .github docs/development docs/architecture` has no active-code or active-guidance hits. Historical docs under `docs/superpowers` may still mention MediatR.

## Skill and Documentation Updates

Active guidance should describe the new pattern:

- Application uses explicit command/query records plus `IUseCase<TRequest,TResult>` and internal `IUseCaseHandler<TRequest,TResult>`.
- Controllers inject typed use cases and call `ExecuteAsync`.
- FluentValidation runs through `ValidatingUseCase<TRequest,TResult>`, not in controllers and not through MediatR.
- Handlers return `Result` / `Result<T>` and inject `IAppDbContext` directly.
- Integration tests still cover routing, model binding, validation decoration, handler behavior, and SQL persistence.

Update both top-level `.agents` skill files and the duplicated plugin skill files under `.agents/plugins/plugins/ahkflowapp/skills/`. Do not edit unrelated archived plans/backlog entries solely to remove historical text.

## Test Strategy

Use staged verification:

- Fast compile checks while converting signatures: `dotnet build AHKFlowApp.slnx --configuration Release`.
- Focused Application tests for the new decorator and seed-all composition.
- API endpoint tests that already assert invalid requests return 400, especially list pagination, create/update validation, and bulk delete validation for hotstrings, hotkeys, categories, profiles, and preferences.
- Full verification after cleanup: `dotnet test AHKFlowApp.slnx --configuration Release --no-build --verbosity normal`, `dotnet format AHKFlowApp.slnx --verify-no-changes`, and `git diff --check`.

## Assumptions

- The goal is to remove MediatR entirely, not replace it with a local mediator/dispatcher.
- Existing command/query record names and layer folders remain to minimize churn.
- `Ardalis.Result`, FluentValidation, EF Core direct `IAppDbContext` usage, and controller-based APIs remain.
- Historical docs can retain MediatR references when they describe old work; active instructions and current architecture docs should be updated.
- This refactor should be implemented in focused commits, but the final branch should not leave mixed MediatR/use-case runtime code.
