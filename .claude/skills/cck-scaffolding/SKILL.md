---
name: scaffolding
description: >
  Code scaffolding patterns for AHKFlowApp (.NET 10, Clean Architecture).
  Generates complete feature slices: controller, MediatR command/query + handler,
  FluentValidation validator, DTOs, EF config, and integration tests.
  Load when: "scaffold", "create feature", "add feature", "new endpoint",
  "generate", "add entity", "new entity", "scaffold test".
---

# Scaffolding

## Core Principles

1. **Architecture is fixed** — AHKFlowApp uses Clean Architecture with controller-based APIs, MediatR, Ardalis.Result, and layer folders. Never scaffold Minimal APIs, IEndpointGroup, feature folders, or repository pattern.
2. **Complete feature slices** — A scaffold includes controller action, command/query + handler, validator, DTOs, EF configuration, and integration test as one unit.
3. **Tests included by default** — Every scaffolded feature includes at least one integration test using `WebApplicationFactory` + Testcontainers (SQL Server). Skip only if explicitly told to.
4. **Modern C# patterns** — Primary constructors, records for DTOs/commands/queries, `sealed` on handlers, file-scoped namespaces.

### Scaffold Checklist (MANDATORY)

Every scaffolded feature MUST include ALL of the following. Do not skip any item:

- [ ] **Result pattern** — Handlers return `Result<T>` (Ardalis.Result). Controllers call `result.ToActionResult(this)`.
- [ ] **CancellationToken** on every async method, passed to every async call
- [ ] **FluentValidation** validator class with meaningful rules (ranges, required fields, max lengths)
- [ ] **FluentValidation runs in MediatR pipeline** — NOT in controller, NOT as endpoint filter
- [ ] **[ProducesResponseType]** on every controller action
- [ ] **Controller uses IMediator.Send()** and maps result via `result.ToActionResult(this)`
- [ ] **Global error handler** — Verify `GlobalExceptionMiddleware` exists in Program.cs; scaffold if missing
- [ ] **Integration test** with proper DI replacement using `services.RemoveAll<DbContextOptions<T>>()`
- [ ] **Layer folders** — Commands/ for commands + handlers, Queries/ for queries + handlers, DTOs/ for records

## Patterns

### Layer Folder Structure

```
src/Backend/
  AHKFlowApp.Application/
    Commands/
      CreateHotstringCommand.cs      # record : IRequest<Result<HotstringDto>>
      CreateHotstringHandler.cs      # internal sealed class
      CreateHotstringValidator.cs    # AbstractValidator<CreateHotstringCommand>
    Queries/
      GetHotstringQuery.cs           # record : IRequest<Result<HotstringDto>>
      GetHotstringHandler.cs
      ListHotstringQuery.cs
      ListHotstringHandler.cs
    DTOs/
      HotstringDto.cs                # sealed record
      CreateHotstringDto.cs          # sealed record

  AHKFlowApp.API/
    Controllers/
      HotstringsController.cs        # [ApiController] thin controller
```

### Command + Handler

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
        var hotstring = new Hotstring { Trigger = request.Trigger, Replacement = request.Replacement };
        db.Hotstrings.Add(hotstring);
        await db.SaveChangesAsync(ct);
        return Result.Success(new HotstringDto(hotstring.Id, hotstring.Trigger, hotstring.Replacement));
    }
}
```

### Validator

```csharp
// Application/Commands/CreateHotstringValidator.cs
namespace AHKFlowApp.Application.Commands;

public sealed class CreateHotstringValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringValidator()
    {
        RuleFor(x => x.Trigger).NotEmpty().MaximumLength(50);
        RuleFor(x => x.Replacement).NotEmpty().MaximumLength(500);
    }
}
```

### Query + Handler

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

### Controller

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

    [HttpGet]
    [ProducesResponseType<IReadOnlyList<HotstringDto>>(StatusCodes.Status200OK)]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await mediator.Send(new ListHotstringQuery(), ct);
        return result.ToActionResult(this);
    }
}
```

### DTOs

```csharp
// Application/DTOs/HotstringDto.cs
namespace AHKFlowApp.Application.DTOs;

public sealed record HotstringDto(int Id, string Trigger, string Replacement);
public sealed record CreateHotstringDto(string Trigger, string Replacement);
public sealed record UpdateHotstringDto(string Trigger, string Replacement);
```

### Entity Scaffold

Always pair entity + `IEntityTypeConfiguration<T>`. No data annotations on entities.

```csharp
// Domain/Entities/Hotstring.cs — clean, no attributes
namespace AHKFlowApp.Domain.Entities;

public sealed class Hotstring
{
    public int Id { get; set; }
    public string Trigger { get; set; } = string.Empty;
    public string Replacement { get; set; } = string.Empty;
}
```

```csharp
// Infrastructure/Persistence/Configurations/HotstringConfiguration.cs
namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring>
{
    public void Configure(EntityTypeBuilder<Hotstring> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Trigger).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Replacement).HasMaxLength(500).IsRequired();
        builder.HasIndex(x => x.Trigger).IsUnique();
    }
}
```

After creating entity + config:

```bash
dotnet ef migrations add AddHotstring --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

### Integration Test Scaffold

```csharp
// tests/AHKFlowApp.API.Tests/Fixtures/ApiFixture.cs
public sealed class ApiFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _mssql = new MsSqlBuilder().Build();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(_mssql.GetConnectionString()));
        });
    }

    public async Task InitializeAsync()
    {
        await _mssql.StartAsync();
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }

    public new async Task DisposeAsync()
    {
        await _mssql.DisposeAsync();
        await base.DisposeAsync();
    }
}
```

```csharp
// tests/AHKFlowApp.API.Tests/Controllers/HotstringsControllerTests.cs
public sealed class HotstringsControllerTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private readonly HttpClient _client = fixture.CreateClient();

    [Fact]
    public async Task Create_ValidRequest_Returns201()
    {
        // Arrange
        var dto = new { Trigger = "btw", Replacement = "by the way" };

        // Act
        var response = await _client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var result = await response.Content.ReadFromJsonAsync<HotstringDto>();
        result.Should().NotBeNull();
        result!.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task Create_EmptyTrigger_Returns400()
    {
        // Arrange
        var dto = new { Trigger = "", Replacement = "by the way" };

        // Act
        var response = await _client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GetById_NotFound_Returns404()
    {
        // Act
        var response = await _client.GetAsync("/api/v1/hotstrings/99999");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

## Anti-patterns

### No Minimal APIs or IEndpointGroup

```csharp
// BAD — AHKFlowApp uses controller-based APIs
public sealed class HotstringEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app) { ... }
}

// GOOD — controller with [ApiController]
[ApiController]
[Route("api/v1/[controller]")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase { }
```

### No ValidationFilter — Use MediatR Pipeline

```csharp
// BAD — validation in endpoint filter
group.MapPost("/", CreateHotstring)
    .AddEndpointFilter<ValidationFilter<CreateHotstringCommand>>();

// GOOD — FluentValidation registered as MediatR IPipelineBehavior
// ValidationBehavior<TRequest, TResponse> runs before every handler automatically
```

### No Repository Pattern

```csharp
// BAD — repository wrapping EF
public interface IHotstringRepository { Task<Hotstring?> GetByIdAsync(int id); }

// GOOD — handler injects DbContext directly
internal sealed class GetHotstringHandler(AppDbContext db) : IRequestHandler<...>
```

### No Feature Folders

```csharp
// BAD — feature folder
Application/Hotstrings/Create/CreateHotstringCommand.cs

// GOOD — layer folder
Application/Commands/CreateHotstringCommand.cs
```

### Entity Without EF Configuration

```csharp
// BAD — data annotations on entity
public class Hotstring { [Key] public int Id { get; set; } [MaxLength(50)] public string Trigger { get; set; } = ""; }

// GOOD — clean entity + separate IEntityTypeConfiguration<T>
public sealed class Hotstring { /* No attributes */ }
internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring> { /* All EF config */ }
```

## Decision Guide

| Scenario | Approach |
|---|---|
| New CRUD endpoint | Controller action + Command/Query + Handler + Validator + DTO |
| New entity | Entity class + `IEntityTypeConfiguration<T>` + migration |
| Validation | AbstractValidator<TCommand>, registered as MediatR IPipelineBehavior |
| Error result | `Result.NotFound()`, `Result.Invalid()`, `Result.Conflict()` — Ardalis.Result |
| HTTP mapping | `result.ToActionResult(this)` in controller — never manual if/else |
| Integration test | WebApplicationFactory + MsSqlContainer (Testcontainers) |
