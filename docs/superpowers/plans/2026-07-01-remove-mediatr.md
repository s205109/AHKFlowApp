# Remove MediatR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove MediatR from AHKFlowApp runtime code, tests, package references, active documentation, and active agent skills.

**Architecture:** Replace MediatR with explicit Application-layer use cases. API controllers inject typed `IUseCase<TRequest,TResult>` services, handlers implement internal `IUseCaseHandler<TRequest,TResult>`, and `ValidatingUseCase<TRequest,TResult>` preserves pre-handler FluentValidation behavior.

**Tech Stack:** .NET 10, ASP.NET Core MVC controllers, EF Core, FluentValidation, Ardalis.Result, xUnit, WebApplicationFactory, Testcontainers SQL Server, PowerShell.

---

## Summary

- Keep command/query records, handler classes, validators, and layer folders.
- Remove all MediatR marker interfaces, handler interfaces, pipeline behavior, DI registration, and package references.
- Add explicit use-case contracts and a validation decorator in `AHKFlowApp.Application`.
- Update controllers to call typed use cases directly.
- Update `SeedAllCommandHandler` to compose the three seed use cases directly inside the existing transaction.
- Update active agent skills and active architecture docs so new work does not reintroduce MediatR.

## Task 1: Add Use-Case Contracts and Validation Decorator

**Files:**

- Create: `src/Backend/AHKFlowApp.Application/Abstractions/IUseCase.cs`
- Create: `src/Backend/AHKFlowApp.Application/Abstractions/IUseCaseHandler.cs`
- Create: `src/Backend/AHKFlowApp.Application/Behaviors/ValidatingUseCase.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Behaviors/ValidationBehaviorTests.cs`

- [ ] Add public controller-facing `IUseCase<TRequest,TResult>`:

```csharp
namespace AHKFlowApp.Application.Abstractions;

public interface IUseCase<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
```

- [ ] Add internal handler-facing `IUseCaseHandler<TRequest,TResult>`:

```csharp
namespace AHKFlowApp.Application.Abstractions;

internal interface IUseCaseHandler<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
```

- [ ] Add `ValidatingUseCase<TRequest,TResult>` using the same validation logic as the old `ValidationBehavior`:

```csharp
using AHKFlowApp.Application.Abstractions;
using FluentValidation;

namespace AHKFlowApp.Application.Behaviors;

internal sealed class ValidatingUseCase<TRequest, TResult>(
    IEnumerable<IValidator<TRequest>> validators,
    IUseCaseHandler<TRequest, TResult> inner)
    : IUseCase<TRequest, TResult>
    where TRequest : notnull
{
    public async Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct)
    {
        if (!validators.Any())
            return await inner.ExecuteAsync(request, ct);

        var context = new ValidationContext<TRequest>(request);

        FluentValidation.Results.ValidationResult[] results = await Task.WhenAll(
            validators.Select(v => v.ValidateAsync(context, ct)));

        List<FluentValidation.Results.ValidationFailure> failures = [.. results
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)];

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await inner.ExecuteAsync(request, ct);
    }
}
```

- [ ] Replace `ValidationBehaviorTests` with `ValidatingUseCaseTests` in the same test file or a renamed file. Keep these scenarios: no validators calls inner, passing validation calls inner, failing validation throws `ValidationException`, multiple validators combine errors.

- [ ] Run focused tests:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ValidatingUseCase" --verbosity normal
```

Expected result: tests pass after implementation. If the file is not renamed yet, use the actual final test class name in the filter.

## Task 2: Convert Command and Query Handlers

**Files:**

- Modify all command/query files under `src/Backend/AHKFlowApp.Application/Commands/`
- Modify all command/query files under `src/Backend/AHKFlowApp.Application/Queries/`
- Modify Application handler tests under `tests/AHKFlowApp.Application.Tests/`

- [ ] For every command/query record, remove `using MediatR;` and remove `: IRequest<...>`.

Example:

```csharp
public sealed record CreateHotstringCommand(CreateHotstringDto Input);
```

- [ ] For every handler, add `using AHKFlowApp.Application.Abstractions;`, replace `IRequestHandler<TRequest,TResult>` with `IUseCaseHandler<TRequest,TResult>`, and rename the method from `Handle(...)` to `ExecuteAsync(...)`.

Example:

```csharp
internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(CreateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotstringDto input = request.Input;

        bool duplicate = await db.Hotstrings.AnyAsync(
            h => h.OwnerOid == ownerOid && h.Trigger == input.Trigger, ct);
        if (duplicate)
            return Result.Conflict("A hotstring with this trigger already exists.");

        // Continue with the existing create logic from the current Handle method:
        // profile/category ownership checks, entity creation, SaveChangesAsync,
        // duplicate-key conflict handling, profile reload, and Result.Success(entity.ToDto()).
    }
}
```

- [ ] Convert direct handler tests from `.Handle(...)` to `.ExecuteAsync(...)`.

- [ ] Update test class names only if they mention MediatR or pipeline behavior. Handler test names such as `CreateHotstringCommandHandlerTests` can stay.

- [ ] Run a compile check:

```powershell
dotnet build AHKFlowApp.slnx --configuration Release
```

Expected result at this stage: build may still fail in controllers and DI because they still use MediatR. It should not fail because Application handler method bodies were changed incorrectly.

## Task 3: Wire Explicit Use Cases in Dependency Injection

**Files:**

- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Delete later in Task 7: `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`

- [ ] Replace `services.AddMediatR(...)` with:

```csharp
services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);
services.AddScoped(typeof(IUseCase<,>), typeof(ValidatingUseCase<,>));
```

- [ ] Add this private helper inside `DependencyInjection`:

```csharp
private static IServiceCollection AddUseCase<TRequest, TResult, THandler>(this IServiceCollection services)
    where TRequest : notnull
    where THandler : class, IUseCaseHandler<TRequest, TResult>
{
    return services.AddScoped<IUseCaseHandler<TRequest, TResult>, THandler>();
}
```

- [ ] Register every Application use case explicitly with the helper. Use the request/result pair from each existing handler. The required groups are:

```csharp
services
    .AddUseCase<CreateCategoryCommand, Result<CategoryDto>, CreateCategoryCommandHandler>()
    .AddUseCase<UpdateCategoryCommand, Result<CategoryDto>, UpdateCategoryCommandHandler>()
    .AddUseCase<DeleteCategoryCommand, Result, DeleteCategoryCommandHandler>()
    .AddUseCase<ListCategoriesQuery, Result<PagedList<CategoryDto>>, ListCategoriesQueryHandler>()
    .AddUseCase<GetCategoryQuery, Result<CategoryDto>, GetCategoryQueryHandler>()
    .AddUseCase<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>, SeedCategoriesCommandHandler>()
    .AddUseCase<CreateHotstringCommand, Result<HotstringDto>, CreateHotstringCommandHandler>()
    .AddUseCase<UpdateHotstringCommand, Result<HotstringDto>, UpdateHotstringCommandHandler>()
    .AddUseCase<DeleteHotstringCommand, Result, DeleteHotstringCommandHandler>()
    .AddUseCase<BulkDeleteHotstringsCommand, Result<BulkDeleteResultDto>, BulkDeleteHotstringsCommandHandler>()
    .AddUseCase<ListHotstringsQuery, Result<PagedList<HotstringDto>>, ListHotstringsQueryHandler>()
    .AddUseCase<GetHotstringQuery, Result<HotstringDto>, GetHotstringQueryHandler>()
    .AddUseCase<SeedHotstringsCommand, Result<PagedList<HotstringDto>>, SeedHotstringsCommandHandler>()
    .AddUseCase<CreateHotkeyCommand, Result<HotkeyDto>, CreateHotkeyCommandHandler>()
    .AddUseCase<UpdateHotkeyCommand, Result<HotkeyDto>, UpdateHotkeyCommandHandler>()
    .AddUseCase<DeleteHotkeyCommand, Result, DeleteHotkeyCommandHandler>()
    .AddUseCase<BulkDeleteHotkeysCommand, Result<BulkDeleteResultDto>, BulkDeleteHotkeysCommandHandler>()
    .AddUseCase<ListHotkeysQuery, Result<PagedList<HotkeyDto>>, ListHotkeysQueryHandler>()
    .AddUseCase<GetHotkeyQuery, Result<HotkeyDto>, GetHotkeyQueryHandler>()
    .AddUseCase<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>, SeedHotkeysCommandHandler>()
    .AddUseCase<CreateProfileCommand, Result<ProfileDto>, CreateProfileCommandHandler>()
    .AddUseCase<UpdateProfileCommand, Result<ProfileDto>, UpdateProfileCommandHandler>()
    .AddUseCase<DeleteProfileCommand, Result, DeleteProfileCommandHandler>()
    .AddUseCase<ListProfilesQuery, Result<IReadOnlyList<ProfileDto>>, ListProfilesQueryHandler>()
    .AddUseCase<GetProfileQuery, Result<ProfileDto>, GetProfileQueryHandler>()
    .AddUseCase<GetUserPreferenceQuery, Result<UserPreferenceDto>, GetUserPreferenceQueryHandler>()
    .AddUseCase<UpdateUserPreferenceCommand, Result<UserPreferenceDto>, UpdateUserPreferenceCommandHandler>()
    .AddUseCase<GetDashboardStatsQuery, Result<DashboardStatsDto>, GetDashboardStatsQueryHandler>()
    .AddUseCase<GenerateProfileScriptQuery, Result<ProfileScript>, GenerateProfileScriptQueryHandler>()
    .AddUseCase<GetProfileScriptPreviewQuery, Result<ProfileScriptPreviewDto>, GetProfileScriptPreviewQueryHandler>()
    .AddUseCase<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>, GenerateAllProfileScriptsQueryHandler>()
    .AddUseCase<SeedAllCommand, Result<SeedAllResultDto>, SeedAllCommandHandler>();
```

- [ ] Add or adjust `using` statements for all command/query namespaces and `Ardalis.Result`.

- [ ] Keep existing registrations for `HeaderTokenRenderer`, `AhkScriptGenerator`, and `ProfileScriptLoader`.

## Task 4: Convert Seed-All Composition

**Files:**

- Modify: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs`

- [ ] Replace `IMediator mediator` in `SeedAllCommandHandler` with typed seed use cases:

```csharp
IUseCase<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>> seedCategories,
IUseCase<SeedHotstringsCommand, Result<PagedList<HotstringDto>>> seedHotstrings,
IUseCase<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>> seedHotkeys,
```

- [ ] Replace the three `mediator.Send(...)` calls with `ExecuteAsync(...)` calls using the same transaction token:

```csharp
Result<IReadOnlyList<CategoryDto>> catResult =
    await seedCategories.ExecuteAsync(new SeedCategoriesCommand(request.Reset), token);
```

- [ ] Update `SeedAllCommandHandlerTests.BuildProvider` to call `services.AddApplication()` or to register the new use-case services manually. Prefer `services.AddApplication()` so the test covers the same DI wiring used by the API.

- [ ] Replace `sp.GetRequiredService<IMediator>().Send(new SeedAllCommand(...))` with:

```csharp
await sp.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
    .ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);
```

- [ ] Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~SeedAllCommandHandlerTests" --verbosity normal
```

Expected result: all seed-all tests pass, including rollback and unauthorized propagation.

## Task 5: Convert API Controllers

**Files:**

- Modify: `src/Backend/AHKFlowApp.API/Controllers/CategoriesController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/DevController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/PreferencesController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs`

- [ ] Remove `using MediatR;` from every controller.

- [ ] Add `using AHKFlowApp.Application.Abstractions;`.

- [ ] Replace each `IMediator mediator` primary constructor parameter with the exact `IUseCase<TRequest,TResult>` dependencies used by that controller.

- [ ] Replace every `mediator.Send(request, ct)` call with the matching use case `ExecuteAsync(request, ct)`.

- [ ] Keep all existing HTTP response mapping logic unchanged.

- [ ] Run representative API validation tests:

```powershell
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HotstringsEndpointsTests|FullyQualifiedName~HotkeysEndpointsTests|FullyQualifiedName~CategoriesEndpointsTests|FullyQualifiedName~ProfilesEndpointsTests|FullyQualifiedName~PreferencesEndpointsTests" --verbosity normal
```

Expected result: invalid requests still return 400 ProblemDetails, duplicate conflicts still return 409, unauthorized requests still return 401, and successful CRUD behavior is unchanged.

## Task 6: Remove MediatR Package and Runtime Leftovers

**Files:**

- Modify: `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`
- Modify: `Directory.Packages.props`
- Delete: `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`

- [ ] Remove the Application project package reference:

```xml
<PackageReference Include="MediatR" />
```

- [ ] Remove the central package version:

```xml
<PackageVersion Include="MediatR" Version="14.1.0" />
```

- [ ] Delete the old `ValidationBehavior.cs` file after `ValidatingUseCase` tests pass.

- [ ] Search for runtime/test leftovers:

```powershell
rg -n "MediatR|IMediator|IRequest|IRequestHandler|IPipelineBehavior|AddMediatR" src tests Directory.Packages.props
```

Expected result: no matches in `src`, `tests`, or `Directory.Packages.props`.

- [ ] Run:

```powershell
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

Expected result: restore and build pass without MediatR.

## Task 7: Update Active Documentation and Skills

**Files:**

- Modify: `AGENTS.md`
- Modify: `.github/instructions/personal-defaults.md`
- Modify: `docs/architecture/product-vision.md`
- Modify: `docs/development/testing-workflow.md`
- Modify: `.agents/cck-scaffolding/SKILL.md`
- Modify: `.agents/cck-testing/SKILL.md`
- Modify: `.agents/cck-error-handling/SKILL.md`
- Modify: `.agents/cck-openapi/SKILL.md`
- Modify: `.agents/cck-ef-core/SKILL.md`
- Modify: `.agents/cck-build-fix/SKILL.md`
- Modify duplicate skill files under `.agents/plugins/plugins/ahkflowapp/skills/`

- [ ] Update `AGENTS.md` to remove MediatR from the tech stack and architecture rules. Replace the request flow with:

```text
HTTP Request -> Controller (thin, maps Result to HTTP)
  -> IUseCase<TRequest,TResult>.ExecuteAsync()
    -> ValidatingUseCase<TRequest,TResult> (FluentValidation)
      -> IUseCaseHandler<TRequest,TResult> (business logic, returns Result<T>)
        -> AppDbContext (EF Core, direct injection)
```

- [ ] Update active docs to describe explicit use cases and validation decoration, not MediatR handlers or pipeline behavior.

- [ ] Update active skills so scaffolding examples use:

```csharp
public sealed record CreateHotstringCommand(CreateHotstringDto Input);

internal sealed class CreateHotstringCommandHandler(AppDbContext db)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(CreateHotstringCommand request, CancellationToken ct)
    {
        Hotstring entity = Hotstring.Create(
            ownerOid: Guid.NewGuid(),
            trigger: request.Input.Trigger,
            replacement: request.Input.Replacement,
            description: request.Input.Description,
            appliesToAllProfiles: request.Input.AppliesToAllProfiles,
            isEndingCharacterRequired: request.Input.IsEndingCharacterRequired,
            isTriggerInsideWord: request.Input.IsTriggerInsideWord,
            clock: TimeProvider.System);

        db.Hotstrings.Add(entity);
        await db.SaveChangesAsync(ct);

        return Result.Success(entity.ToDto());
    }
}
```

- [ ] Update controller examples in skills to inject `IUseCase<..., ...>` and call `ExecuteAsync(...)`.

- [ ] Update error-handling/testing skills to say FluentValidation runs through `ValidatingUseCase<TRequest,TResult>`.

- [ ] Do not edit old historical `docs/superpowers/*` plans/specs or `.claude/backlog/*` items only to remove MediatR mentions.

- [ ] Search active guidance:

```powershell
rg -n "MediatR|IMediator|IRequest|IRequestHandler|IPipelineBehavior|AddMediatR" AGENTS.md .agents .github docs/architecture docs/development
```

Expected result: no active guidance instructs new work to use MediatR. If a match is intentionally historical, move it out of active guidance or reword it as historical context.

## Task 8: Full Verification

**Files:**

- No planned edits.

- [ ] Run the full build:

```powershell
dotnet build AHKFlowApp.slnx --configuration Release
```

Expected result: build passes.

- [ ] Run the full test suite:

```powershell
dotnet test AHKFlowApp.slnx --configuration Release --no-build --verbosity normal
```

Expected result: all tests pass.

- [ ] Run format verification:

```powershell
dotnet format AHKFlowApp.slnx --verify-no-changes
```

Expected result: no formatting changes required.

- [ ] Run whitespace verification:

```powershell
git diff --check
```

Expected result: no whitespace errors.

- [ ] Run final MediatR search:

```powershell
rg -n "MediatR|IMediator|IRequest|IRequestHandler|IPipelineBehavior|AddMediatR" src tests Directory.Packages.props AGENTS.md .agents .github docs/architecture docs/development
```

Expected result: no runtime, test, package, or active-guidance references remain.

## Assumptions

- The implementation removes MediatR entirely rather than introducing a local mediator or dispatcher.
- Existing command/query names and handler class names remain to keep the diff reviewable.
- Direct handler unit tests continue to bypass FluentValidation, matching the current direct-handler test behavior.
- API integration tests are the proof that validation still runs before handler logic through DI.
- Archived plans/specs/backlog files can keep historical MediatR references.
