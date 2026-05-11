---
name: cck-openapi
description: >
  OpenAPI documentation for AHKFlowApp (.NET 10, controller-based APIs).
  Covers Swagger UI setup (AddSwaggerGen + UseSwaggerUI), ProducesResponseType
  annotations on controller actions, security schemes, XML comments, and
  build-time generation.
  Load when: "OpenAPI", "Swagger", "API documentation", "AddSwaggerGen",
  "UseSwaggerUI", "ProducesResponseType", "API docs", "document transformer",
  "security scheme", "XML comments".
---

# OpenAPI

## Core Principles

1. **Swagger UI for API documentation** — AHKFlowApp uses `Swashbuckle.AspNetCore` (`AddSwaggerGen` + `UseSwagger` + `UseSwaggerUI`). Available in development at `/swagger`.
2. **`[ProducesResponseType]` on every controller action** — Explicit annotations drive the OpenAPI schema. Don't rely on inference alone.
3. **XML documentation comments** — Enable `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in the API project for summary/description in Swagger UI.
4. **Controller-based metadata** — `[ApiController]`, `[Route]`, `[HttpGet]`, `[ProducesResponseType]` are the primary metadata sources. No `.WithName()` or `.WithSummary()` (those are Minimal API patterns).

## Patterns

### Basic Setup (Program.cs)

```csharp
// Program.cs
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "AHKFlowApp API",
        Version = "v1",
        Description = "API for managing AutoHotkey hotstrings and hotkeys."
    });

    // Include XML comments from the API project
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    options.IncludeXmlComments(xmlPath);
});

// ...

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "AHKFlowApp API v1");
        options.RoutePrefix = "swagger";  // available at /swagger
    });
}
```

### ProducesResponseType on Controller Actions

Every action must declare all possible response types.

```csharp
[ApiController]
[Route("api/v1/[controller]")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase
{
    /// <summary>Creates a new hotstring.</summary>
    /// <param name="dto">Trigger and replacement text.</param>
    /// <response code="201">Hotstring created successfully.</response>
    /// <response code="400">Validation failed.</response>
    /// <response code="409">A hotstring with this trigger already exists.</response>
    [HttpPost]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Create(CreateHotstringDto dto, CancellationToken ct)
    {
        var result = await mediator.Send(new CreateHotstringCommand(dto.Trigger, dto.Replacement), ct);
        return result.ToActionResult(this);
    }

    /// <summary>Gets a hotstring by ID.</summary>
    /// <param name="id">The hotstring ID.</param>
    /// <response code="200">Returns the hotstring.</response>
    /// <response code="404">Hotstring not found.</response>
    [HttpGet("{id:int}")]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(int id, CancellationToken ct)
    {
        var result = await mediator.Send(new GetHotstringQuery(id), ct);
        return result.ToActionResult(this);
    }

    /// <summary>Lists all hotstrings.</summary>
    /// <response code="200">Returns the list of hotstrings.</response>
    [HttpGet]
    [ProducesResponseType<IReadOnlyList<HotstringDto>>(StatusCodes.Status200OK)]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await mediator.Send(new ListHotstringQuery(), ct);
        return result.ToActionResult(this);
    }
}
```

### Enable XML Documentation

In `AHKFlowApp.API.csproj`:

```xml
<PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <NoWarn>$(NoWarn);1591</NoWarn>  <!-- suppress missing XML comment warnings -->
</PropertyGroup>
```

### Bearer Token Security Scheme

For Azure AD (MSAL) authentication in Swagger UI:

```csharp
builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Enter JWT token"
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            []
        }
    });
});
```

### ProblemDetails Schema

Register `AddProblemDetails()` to ensure ProblemDetails appears correctly in the OpenAPI schema:

```csharp
builder.Services.AddProblemDetails();
```

## Anti-patterns

### Missing ProducesResponseType

```csharp
// BAD — no response type annotations, schema won't include response types
[HttpGet("{id:int}")]
public async Task<IActionResult> GetById(int id, CancellationToken ct) { ... }

// GOOD — explicit annotations
[HttpGet("{id:int}")]
[ProducesResponseType<HotstringDto>(StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<IActionResult> GetById(int id, CancellationToken ct) { ... }
```

### Minimal API OpenAPI Patterns in Controllers

```csharp
// BAD — Minimal API metadata on controllers (doesn't apply)
[HttpGet]
public IActionResult List()
{
    // .WithName() and .WithSummary() are Minimal API, not controller attributes
}

// GOOD — XML doc comments + [ProducesResponseType] for controller-based OpenAPI
/// <summary>Lists all hotstrings.</summary>
[HttpGet]
[ProducesResponseType<IReadOnlyList<HotstringDto>>(StatusCodes.Status200OK)]
public async Task<IActionResult> List(CancellationToken ct) { ... }
```

### Exposing Swagger in Production

```csharp
// BAD — Swagger always enabled
app.UseSwagger();
app.UseSwaggerUI();

// GOOD — development only
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
```

## Decision Guide

| Scenario | Recommendation |
|---|---|
| API documentation UI | Swagger UI at `/swagger` (development only) |
| Response documentation | `[ProducesResponseType<T>(statusCode)]` on every action |
| Method/param descriptions | XML doc comments (`<summary>`, `<param>`, `<response>`) |
| Security scheme in docs | `AddSecurityDefinition` + `AddSecurityRequirement` in `AddSwaggerGen` |
| ProblemDetails schema | `builder.Services.AddProblemDetails()` |
| Generate OpenAPI spec at build | `Microsoft.Extensions.ApiDescription.Server` package |
