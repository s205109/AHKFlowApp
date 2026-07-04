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

```csharp
namespace AHKFlowApp.Application.Commands;

public sealed record CreateHotstringCommand(CreateHotstringDto Input);
```

```csharp
namespace AHKFlowApp.Application.Commands;

internal sealed class CreateHotstringHandler(AppDbContext db, TimeProvider timeProvider)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(
        CreateHotstringCommand request,
        CancellationToken cancellationToken)
    {
        var hotstring = Hotstring.Create(
            ownerOid,
            request.Input.Trigger,
            request.Input.Replacement,
            timeProvider.GetUtcNow());

        db.Hotstrings.Add(hotstring);
        await db.SaveChangesAsync(cancellationToken);

        return Result.Success(new HotstringDto(hotstring.Id, hotstring.Trigger, hotstring.Replacement));
    }
}
```

Register the use case in Application DI:

```csharp
services.AddUseCase<CreateHotstringCommand, Result<HotstringDto>, CreateHotstringHandler>();
```

## Validator

```csharp
namespace AHKFlowApp.Application.Commands;

public sealed class CreateHotstringValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringValidator()
    {
        RuleFor(x => x.Input.Trigger).NotEmpty().MaximumLength(50);
        RuleFor(x => x.Input.Replacement).NotEmpty().MaximumLength(500);
    }
}
```

## Query and Handler

```csharp
namespace AHKFlowApp.Application.Queries;

public sealed record GetHotstringQuery(Guid Id);
```

```csharp
namespace AHKFlowApp.Application.Queries;

internal sealed class GetHotstringHandler(AppDbContext db)
    : IUseCaseHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(
        GetHotstringQuery request,
        CancellationToken cancellationToken)
    {
        var entity = await db.Hotstrings.FindAsync([request.Id], cancellationToken);
        return entity is null
            ? Result.NotFound()
            : Result.Success(new HotstringDto(entity.Id, entity.Trigger, entity.Replacement));
    }
}
```

## Controller

```csharp
namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
public sealed class HotstringsController(
    IUseCase<CreateHotstringCommand, Result<HotstringDto>> createHotstring,
    IUseCase<GetHotstringQuery, Result<HotstringDto>> getHotstring)
    : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create(CreateHotstringDto dto, CancellationToken cancellationToken)
    {
        var result = await createHotstring.ExecuteAsync(new CreateHotstringCommand(dto), cancellationToken);
        return result.ToActionResult(this);
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
    {
        var result = await getHotstring.ExecuteAsync(new GetHotstringQuery(id), cancellationToken);
        return result.ToActionResult(this);
    }
}
```

## Entity and EF Configuration

Entities use private setters, constructor/factory methods, and domain methods:

```csharp
namespace AHKFlowApp.Domain.Entities;

public sealed class Hotstring
{
    private Hotstring()
    {
        Trigger = string.Empty;
        Replacement = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Trigger { get; private set; }
    public string Replacement { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static Hotstring Create(Guid ownerOid, string trigger, string replacement, DateTimeOffset now) =>
        new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Trigger = trigger,
            Replacement = replacement,
            CreatedAt = now,
            UpdatedAt = now
        };
}
```

```csharp
internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring>
{
    public void Configure(EntityTypeBuilder<Hotstring> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Trigger).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Replacement).HasMaxLength(500).IsRequired();
        builder.HasIndex(x => new { x.OwnerOid, x.Trigger }).IsUnique();
    }
}
```

## Integration Test Shape

Use `WebApplicationFactory` and SQL Server Testcontainers. Replace `DbContextOptions<AppDbContext>` with `services.RemoveAll<DbContextOptions<AppDbContext>>()`, run migrations, and assert behavior through HTTP or handler results.

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
