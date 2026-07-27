---
name: dck-openapi
description: Use when changing AHKFlowApp OpenAPI, Swagger, API docs, response annotations, XML comments, or security schemes.
---

# OpenAPI

## Core Principles

1. **Swagger UI for API documentation** — AHKFlowApp uses `Swashbuckle.AspNetCore` (`AddSwaggerGen` + `UseSwagger` + `UseSwaggerUI`). Available in development at `/swagger`.
2. **`[ProducesResponseType]` on every controller action** — Explicit annotations drive the OpenAPI schema. Don't rely on inference alone.
3. **XML documentation comments** — Enable `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in the API project for summary/description in Swagger UI.
4. **Controller-based metadata** — `[ApiController]`, `[Route]`, `[HttpGet]`, `[ProducesResponseType]` are the primary metadata sources. No `.WithName()` or `.WithSummary()` (those are Minimal API patterns).

## Patterns

### Basic Setup (Program.cs)

Swagger setup is behind two extension methods, not inlined in `Program.cs`: `AddSwaggerDocs()` and `UseSwaggerDocs()` in `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:50-101`, called conditionally in Development from `src/Backend/AHKFlowApp.API/Program.cs:102,196`. Read the extension methods rather than copying an inline shape — they also register `AddSwaggerExamplesFromAssemblies` and read XML comments from both `AHKFlowApp.API` and `AHKFlowApp.Application` assemblies.

### ProducesResponseType on Controller Actions

Every action must declare all possible response types. `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` is the live, much larger example — 15 actions, each with XML `<summary>`/`<response>` comments and `[ProducesResponseType]` per possible status. It also carries class-level `[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]` / `...Status403Forbidden` that a per-action-only approach would miss — those apply to every action via `[Authorize]` + `[RequiredScope]` and don't need repeating per action.

### Enable XML Documentation

```csharp
<!-- src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj:4-5 (also set in AHKFlowApp.Application.csproj:3) -->
<GenerateDocumentationFile>true</GenerateDocumentationFile>
<NoWarn>$(NoWarn);CS1591</NoWarn>
```

### Bearer Token Security Scheme

The real registration is in `AddSwaggerDocs()` (`ApiExtensions.cs:61-74`) and uses the newer `Microsoft.OpenApi` shape — `OpenApiSecuritySchemeReference("Bearer", doc)` inside `AddSecurityRequirement(doc => ...)`, not the older `OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }` shape. Copy the live extension method rather than an older-API block; the two are not interchangeable across `Microsoft.OpenApi` versions.

### ProblemDetails Schema

```csharp
// src/Backend/AHKFlowApp.API/Program.cs:75-77 — also stamps a traceId extension on every problem response
builder.Services.AddProblemDetails(options =>
    options.CustomizeProblemDetails = ctx =>
        ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);
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
