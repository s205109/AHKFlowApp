---
name: cck-clean-architecture
description: >
  Clean Architecture for AHKFlowApp (.NET 10). Covers the 4-project layout (Domain,
  Application, Infrastructure, API), strict inward dependencies, MediatR handlers
  with direct DbContext injection, controller-based APIs, and layer folder organization.
  Load when: Clean Architecture, layered architecture, dependency inversion, use cases,
  "add layer", "project structure", "where does this code go".
---

# Clean Architecture

## Core Principles

1. **Dependency direction is inward** — Domain has zero project references. Application references only Domain. Infrastructure references Application and Domain. API references all but depends on abstractions.
2. **Layer folders, not feature folders** — Organize by layer: `Controllers/`, `Commands/`, `Queries/`, `DTOs/`, `Validators/`, `Behaviors/`. Never `Features/Hotstrings/`.
3. **No repository pattern** — MediatR handlers inject `AppDbContext` directly. EF Core's DbSet is already a repository. No `IHotstringRepository`, no `IAppDbContext` interface.
4. **Controller-based APIs only** — `[ApiController]` + `[Route("api/v1/[controller]")]`. No Minimal APIs, no `IEndpointGroup`, no `app.MapGroup()`.
5. **Thin controllers** — Accept request, send via `IMediator`, return `result.ToActionResult(this)`. Zero business logic.

## Project Layout

```
src/Backend/
  AHKFlowApp.Domain/
    Entities/
      Hotstring.cs               # Entity — no EF attributes, no external deps
    Enums/
    Common/

  AHKFlowApp.Application/
    Behaviors/
      ValidationBehavior.cs      # MediatR IPipelineBehavior
    Commands/
      CreateHotstringCommand.cs  # record : IRequest<Result<HotstringDto>>
      CreateHotstringHandler.cs  # internal sealed class
      CreateHotstringValidator.cs
    Queries/
      GetHotstringQuery.cs
      GetHotstringHandler.cs
      ListHotstringQuery.cs
      ListHotstringHandler.cs
    DTOs/
      HotstringDto.cs            # sealed record

  AHKFlowApp.Infrastructure/
    Persistence/
      AppDbContext.cs
      Configurations/
        HotstringConfiguration.cs  # IEntityTypeConfiguration<Hotstring>
      Migrations/
    DependencyInjection.cs

  AHKFlowApp.API/
    Controllers/
      HotstringsController.cs    # [ApiController] thin controller
    Middleware/
      GlobalExceptionMiddleware.cs
    Program.cs
```

### Dependency References

```xml
<!-- AHKFlowApp.Application references Domain -->
<ProjectReference Include="..\AHKFlowApp.Domain\AHKFlowApp.Domain.csproj" />

<!-- AHKFlowApp.Infrastructure references Application + Domain -->
<ProjectReference Include="..\AHKFlowApp.Application\AHKFlowApp.Application.csproj" />
<ProjectReference Include="..\AHKFlowApp.Domain\AHKFlowApp.Domain.csproj" />

<!-- AHKFlowApp.API references all -->
<ProjectReference Include="..\AHKFlowApp.Application\AHKFlowApp.Application.csproj" />
<ProjectReference Include="..\AHKFlowApp.Infrastructure\AHKFlowApp.Infrastructure.csproj" />
```

Domain and Application have **no reference** to EF Core or infrastructure packages.

## Patterns

### Domain Entity

Pure C# — no EF Core attributes, no external dependencies.

```csharp
// Domain/Entities/Hotstring.cs
namespace AHKFlowApp.Domain.Entities;

public sealed class Hotstring
{
    public int Id { get; set; }
    public string Trigger { get; set; } = string.Empty;
    public string Replacement { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}
```

### MediatR Command + Handler

Handler injects `AppDbContext` directly — no IAppDbContext interface needed.

```csharp
// Application/Commands/CreateHotstringCommand.cs
namespace AHKFlowApp.Application.Commands;

public sealed record CreateHotstringCommand(string Trigger, string Replacement)
    : IRequest<Result<HotstringDto>>;
```

```csharp
// Application/Commands/CreateHotstringHandler.cs
namespace AHKFlowApp.Application.Commands;

internal sealed class CreateHotstringHandler(AppDbContext db)
    : IRequestHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(
        CreateHotstringCommand request, CancellationToken ct)
    {
        var exists = await db.Hotstrings.AnyAsync(h => h.Trigger == request.Trigger, ct);
        if (exists) return Result.Conflict();

        var entity = new Hotstring { Trigger = request.Trigger, Replacement = request.Replacement };
        db.Hotstrings.Add(entity);
        await db.SaveChangesAsync(ct);

        return Result.Success(new HotstringDto(entity.Id, entity.Trigger, entity.Replacement));
    }
}
```

### MediatR Query + Handler

```csharp
// Application/Queries/GetHotstringQuery.cs
namespace AHKFlowApp.Application.Queries;

public sealed record GetHotstringQuery(int Id) : IRequest<Result<HotstringDto>>;
```

```csharp
// Application/Queries/GetHotstringHandler.cs
namespace AHKFlowApp.Application.Queries;

internal sealed class GetHotstringHandler(AppDbContext db)
    : IRequestHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(
        GetHotstringQuery request, CancellationToken ct)
    {
        var entity = await db.Hotstrings.FindAsync([request.Id], ct);
        return entity is not null
            ? Result.Success(new HotstringDto(entity.Id, entity.Trigger, entity.Replacement))
            : Result.NotFound();
    }
}
```

### Thin Controller

```csharp
// API/Controllers/HotstringsController.cs
namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Create(CreateHotstringDto dto, CancellationToken ct)
    {
        var result = await mediator.Send(new CreateHotstringCommand(dto.Trigger, dto.Replacement), ct);
        return result.ToActionResult(this);
    }

    [HttpGet("{id:int}")]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(int id, CancellationToken ct)
    {
        var result = await mediator.Send(new GetHotstringQuery(id), ct);
        return result.ToActionResult(this);
    }
}
```

### Infrastructure DI Registration

```csharp
// Infrastructure/DependencyInjection.cs
namespace AHKFlowApp.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration config)
    {
        var connectionString = config.GetConnectionString("DefaultConnection")!;

        services.AddDbContext<AppDbContext>(options =>
            options.UseSqlServer(connectionString,
                sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(10), null)));

        return services;
    }
}
```

## Request Flow

```
HTTP Request
  → HotstringsController (thin — maps HTTP → MediatR)
    → IMediator.Send(CreateHotstringCommand)
      → ValidationBehavior<TRequest, TResponse> (FluentValidation pipeline)
        → CreateHotstringHandler (business logic, returns Result<T>)
          → AppDbContext (EF Core — direct injection)
  ← result.ToActionResult(this) (maps Result to HTTP status)
```

## Anti-patterns

### Minimal APIs / IEndpointGroup

```csharp
// BAD — Minimal API pattern not used in AHKFlowApp
public sealed class HotstringEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app) { ... }
}

// GOOD — [ApiController] thin controller
[ApiController]
[Route("api/v1/[controller]")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase { }
```

### Repository Pattern

```csharp
// BAD — wrapping EF Core in a repository
public interface IHotstringRepository
{
    Task<Hotstring?> GetByIdAsync(int id);
}

// GOOD — inject AppDbContext directly
internal sealed class GetHotstringHandler(AppDbContext db) : IRequestHandler<...>
```

### Feature Folders

```csharp
// BAD — feature folder organization
Application/Hotstrings/Commands/CreateHotstringCommand.cs
Application/Hotstrings/Queries/GetHotstringQuery.cs

// GOOD — layer folder organization
Application/Commands/CreateHotstringCommand.cs
Application/Queries/GetHotstringQuery.cs
```

### EF Core in Domain or Application

```csharp
// BAD — Domain references EF Core
using Microsoft.EntityFrameworkCore;  // in Domain project — NEVER

// GOOD — Domain is pure C#. EF configuration lives in Infrastructure/Persistence/Configurations/
```

### Business Logic in Controller

```csharp
// BAD — logic in controller
[HttpPost]
public async Task<IActionResult> Create(CreateHotstringDto dto)
{
    var exists = await db.Hotstrings.AnyAsync(h => h.Trigger == dto.Trigger);
    if (exists) return Conflict();
    // ...
}

// GOOD — controller delegates entirely to handler via MediatR
var result = await mediator.Send(new CreateHotstringCommand(dto.Trigger, dto.Replacement), ct);
return result.ToActionResult(this);
```

## Decision Guide

| Scenario | Recommendation |
|---|---|
| Where does business logic go? | MediatR handler in Application/Commands/ or Application/Queries/ |
| Where does data access go? | `AppDbContext` injected into handler — Infrastructure provides it |
| Where does EF config go? | `IEntityTypeConfiguration<T>` in Infrastructure/Persistence/Configurations/ |
| Where does validation go? | `AbstractValidator<TCommand>` in Application/Commands/ or Application/Queries/ |
| Where do domain entities go? | Domain/Entities/ — no EF attributes, no external deps |
| Add a new endpoint | Controller action → Command/Query → Handler → AppDbContext |
| Add a new entity | Entity in Domain + Configuration in Infrastructure + migration |
