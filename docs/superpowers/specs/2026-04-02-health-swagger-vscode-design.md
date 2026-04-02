# Health Endpoint, Swagger UI & VS Code Config

**Date:** 2026-04-02
**Status:** Draft

## Overview

Add a health check endpoint using official ASP.NET Core health checks, Swagger UI via Swashbuckle, a Blazor health page with typed HTTP client, and VS Code debug/launch configuration adapted from the old AHKFlow project.

## Backend

### Swagger UI

- **Package:** `Swashbuckle.AspNetCore` (latest stable)
- **Extension methods** in `Extensions/ApiExtensions.cs`:
  - `AddSwaggerDocs()` — registers `AddEndpointsApiExplorer()` + `AddSwaggerGen()`
  - `UseSwaggerDocs()` — registers `UseSwagger()` + `UseSwaggerUI()` with route prefix `swagger`
- **Root redirect:** Handled via `UseSwaggerDocs()` which adds a rewrite rule for `/` → `/swagger` (avoids Minimal API `MapGet`)
- **Remove** existing `MapOpenApi()` call and `AddOpenApi()` from `Program.cs` — Swashbuckle replaces the built-in OpenAPI support with Swagger UI, which is more useful for development
- **launchUrl** in all profiles set to `"swagger"`

### Health Checks

**Registration** in `Program.cs`:

```csharp
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>(
        name: "database",
        failureStatus: HealthStatus.Unhealthy);

// Infrastructure endpoint for load balancers/k8s (plain text)
// This is the standard ASP.NET Core health check middleware —
// no controller-based alternative exists. Intentional exception to controller-only rule.
app.MapHealthChecks("/health");
```

- EF Core's `AddDbContextCheck` tests connection without requiring tables or migrations

**HealthController** — API-layer controller for structured JSON responses:

```csharp
[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class HealthController(
    HealthCheckService healthCheckService,
    IHostEnvironment hostEnvironment) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<HealthResponse>> GetHealthAsync(CancellationToken cancellationToken)
    {
        // ...calls healthCheckService.CheckHealthAsync(cancellationToken)
        // Returns 200 when healthy, 503 when any check is unhealthy
    }
}
```

**Note:** This controller injects `HealthCheckService` directly instead of using MediatR. Health checks are infrastructure plumbing, not domain commands/queries — MediatR adds no value here.

**HealthResponse** record in `API/Models/`:

```csharp
public sealed record HealthResponse(
    string Status,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks);
```

`Models/` folder is for API-layer response types that don't flow through MediatR. Domain DTOs go in Application layer.

### Packages needed

- `Swashbuckle.AspNetCore` — Swagger UI
- `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore` — provides `AddDbContextCheck<T>()`

## Frontend

### Typed HTTP Client

- `Services/IAhkFlowAppApiHttpClient.cs` — interface with `Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken)`
- `Services/AhkFlowAppApiHttpClient.cs` — implementation using `HttpClient`
- Registered in `Program.cs`:

```csharp
builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ApiBaseUrl"]
        ?? throw new InvalidOperationException("'ApiBaseUrl' is not configured."));
}).AddStandardResilienceHandler();
```

- `appsettings.json` key: `"ApiBaseUrl": "https://localhost:7600"`
- This is the first HTTP client in the frontend — requires `Microsoft.Extensions.Http.Resilience` package

### HealthResponse DTO

`DTOs/HealthResponse.cs` — mirrors backend record. Uses mutable properties for `System.Text.Json` deserialization compatibility in Blazor WASM:

```csharp
public sealed record HealthResponse
{
    public string Status { get; init; } = string.Empty;
    public string Environment { get; init; } = string.Empty;
    public DateTimeOffset Timestamp { get; init; }
    public Dictionary<string, string> Checks { get; init; } = [];
}
```

### Health.razor Page

- Route: `/health`
- Calls `IAhkFlowAppApiHttpClient.GetHealthAsync(CancellationToken)` on init
- MudBlazor `MudSimpleTable` for status/environment/timestamp
- Second table for individual component checks with color coding (green = Healthy, red = Unhealthy/Degraded)
- Refresh button
- Error alert if API unreachable
- Nav link added to `Layout/NavMenu.razor`
- Implements `IDisposable` for `CancellationTokenSource` cleanup

## Launch Profiles & VS Code Config

### launchSettings.json

Replace current profiles with full set from old project, adapted to `AHKFlowApp`:

| Profile | Ports | Notes |
|---|---|---|
| `https + Docker SQL (Recommended)` | 7600/5600 | Sets `AHKFLOW_START_DOCKER_SQL=true`, connection string env var |
| `https + LocalDB SQL` | 7600/5600 | Uses appsettings connection string |
| `Docker Compose (No Debugging)` | 5602 | Runs `docker compose up --build` |
| `Docker (API only)` | 5604 | Requires SQL on localhost:1433 |

All profiles: `launchUrl: "swagger"`.

### .vscode/launch.json

Debug configurations adapted from old project:
- `API: https + Docker SQL (Recommended)`
- `API: https + LocalDB SQL`
- `UI: https`
- Compounds: `Full Stack: https + Docker SQL`, `Full Stack: https + LocalDB SQL`

All paths reference `AHKFlowApp.API`.

### .vscode/tasks.json

Pre-launch tasks:
- `Open Swagger (Docker SQL)` — polls `https://localhost:7600/swagger` then opens browser
- `Open Swagger (LocalDB)` — same behavior

### .vscode/settings.json

Workspace settings from old project (browser prefs, Claude Code settings).

## Testing

- **API integration test** for `GET /health` (plain text endpoint) — healthy scenario
- **API integration test** for `GET api/v1/health` — verifies structured JSON response with status, environment, timestamp, checks
- **API integration test** for `api/v1/health` when DB is unreachable — verifies 503 response
- Tests use `WebApplicationFactory` + Testcontainers (SQL Server) per project conventions

## Out of Scope

- Version service / `IVersionService`
- `ApiUrl` field in health response
- Frontend URL health check
- Authentication on health endpoints
- Docker Compose file changes
- Frontend component tests (bUnit) — add when more pages exist
