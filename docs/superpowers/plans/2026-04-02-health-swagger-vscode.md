# Health Endpoint, Swagger UI & VS Code Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Swagger UI, a structured health endpoint, a Blazor health page with typed HTTP client, and VS Code debug configuration to AHKFlowApp.

**Architecture:** Official ASP.NET Core health checks (`AddDbContextCheck<AppDbContext>`) power the health logic; a custom `HealthController` calls `HealthCheckService` to expose a rich JSON response. The frontend consumes this via a typed `IAhkFlowAppApiHttpClient`. Swagger UI replaces the built-in OpenAPI UI.

**Tech Stack:** ASP.NET Core 10, `Swashbuckle.AspNetCore`, `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`, Blazor WebAssembly, MudBlazor 9.x, xUnit, FluentAssertions, Testcontainers.MsSql, WebApplicationFactory.

---

## File Map

### Created
- `.vscode/launch.json` — VS Code debug launch configurations
- `.vscode/tasks.json` — pre-launch Swagger polling tasks
- `.vscode/settings.json` — workspace settings
- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` — `AddSwaggerDocs()` / `UseSwaggerDocs()`
- `src/Backend/AHKFlowApp.API/Models/HealthResponse.cs` — API-layer response record
- `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs` — structured health endpoint
- `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj` — new test project
- `tests/AHKFlowApp.API.Tests/Health/HealthApiFactory.cs` — WebApplicationFactory with Testcontainers
- `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs` — integration tests
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json` — adds `ApiBaseUrl`
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HealthResponse.cs` — frontend DTO
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/IAhkFlowAppApiHttpClient.cs` — HTTP client interface
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/AhkFlowAppApiHttpClient.cs` — HTTP client implementation
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor` — Blazor health page

### Modified
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` — full profile set (Docker SQL, LocalDB, Docker Compose)
- `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj` — add Swashbuckle and health checks packages
- `src/Backend/AHKFlowApp.API/Program.cs` — wire Swagger, health checks, remove `AddOpenApi`/`MapOpenApi`
- `Directory.Packages.props` — add versions for all new packages
- `AHKFlowApp.slnx` — add test project under `/tests/` folder
- `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj` — add resilience package
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` — register typed HTTP client
- `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor` — add Health nav link

---

## Task 1: VS Code Config & Launch Profiles

**Files:**
- Create: `.vscode/launch.json`
- Create: `.vscode/tasks.json`
- Create: `.vscode/settings.json`
- Modify: `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`

- [ ] **Step 1: Create `.vscode/launch.json`**

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "API: https + Docker SQL (Recommended)",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "Open Swagger (Docker SQL)",
      "program": "${workspaceFolder}/src/Backend/AHKFlowApp.API/bin/Debug/net10.0/AHKFlowApp.API.dll",
      "cwd": "${workspaceFolder}/src/Backend/AHKFlowApp.API",
      "launchSettingsFilePath": "${workspaceFolder}/src/Backend/AHKFlowApp.API/Properties/launchSettings.json",
      "launchSettingsProfile": "https + Docker SQL (Recommended)",
      "console": "externalTerminal"
    },
    {
      "name": "API: https + LocalDB SQL",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "Open Swagger (LocalDB)",
      "program": "${workspaceFolder}/src/Backend/AHKFlowApp.API/bin/Debug/net10.0/AHKFlowApp.API.dll",
      "cwd": "${workspaceFolder}/src/Backend/AHKFlowApp.API",
      "launchSettingsFilePath": "${workspaceFolder}/src/Backend/AHKFlowApp.API/Properties/launchSettings.json",
      "launchSettingsProfile": "https + LocalDB SQL",
      "console": "externalTerminal"
    },
    {
      "name": "UI: https",
      "type": "dotnet",
      "request": "launch",
      "projectPath": "${workspaceFolder}/src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj"
    }
  ],
  "compounds": [
    {
      "name": "Full Stack: https + Docker SQL (Recommended)",
      "configurations": [
        "API: https + Docker SQL (Recommended)",
        "UI: https"
      ],
      "stopAll": true
    },
    {
      "name": "Full Stack: https + LocalDB SQL",
      "configurations": [
        "API: https + LocalDB SQL",
        "UI: https"
      ],
      "stopAll": true
    }
  ]
}
```

- [ ] **Step 2: Create `.vscode/tasks.json`**

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Open Swagger (Docker SQL)",
      "type": "shell",
      "command": "powershell",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "for ($i = 0; $i -lt 60; $i++) { try { Invoke-WebRequest -Uri 'https://localhost:7600/swagger' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop | Out-Null; Start-Process 'https://localhost:7600/swagger'; break } catch { Start-Sleep -Seconds 1 } }"
      ],
      "isBackground": true,
      "problemMatcher": []
    },
    {
      "label": "Open Swagger (LocalDB)",
      "type": "shell",
      "command": "powershell",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "for ($i = 0; $i -lt 60; $i++) { try { Invoke-WebRequest -Uri 'https://localhost:7600/swagger' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop | Out-Null; Start-Process 'https://localhost:7600/swagger'; break } catch { Start-Sleep -Seconds 1 } }"
      ],
      "isBackground": true,
      "problemMatcher": []
    }
  ]
}
```

- [ ] **Step 3: Create `.vscode/settings.json`**

```json
{
  "chat.tools.terminal.autoApprove": {
    "Test-Path": true,
    "ForEach-Object": true,
    "Resolve-Path": true,
    "dotnet run": true
  },
  "workbench.externalBrowser": "chrome",
  "liveServer.settings.CustomBrowser": "chrome",
  "chat.useClaudeHooks": true,
  "chat.useCustomAgentHooks": true,
  "claudeCode.useCtrlEnterToSend": true
}
```

- [ ] **Step 4: Replace `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`**

```json
{
  "$schema": "https://json.schemastore.org/launchsettings.json",
  "profiles": {
    "https + Docker SQL (Recommended)": {
      "commandName": "Project",
      "launchBrowser": true,
      "launchUrl": "swagger",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "AHKFLOW_START_DOCKER_SQL": "true",
        "ConnectionStrings__DefaultConnection": "Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=AHKFlow_Dev!2026;TrustServerCertificate=True;MultipleActiveResultSets=true"
      },
      "dotnetRunMessages": true,
      "applicationUrl": "https://localhost:7600;http://localhost:5600"
    },
    "https + LocalDB SQL": {
      "commandName": "Project",
      "launchBrowser": true,
      "launchUrl": "swagger",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      },
      "dotnetRunMessages": true,
      "applicationUrl": "https://localhost:7600;http://localhost:5600"
    },
    "Docker Compose (No Debugging)": {
      "commandName": "Executable",
      "executablePath": "powershell",
      "commandLineArgs": "-NoProfile -ExecutionPolicy Bypass -Command \"docker compose up --build -d; $url = 'http://localhost:5602/swagger'; for ($i = 0; $i -lt 60; $i++) { try { $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2; if ($response.StatusCode -ge 200) { Start-Process $url; exit 0 } } catch { }; Start-Sleep -Seconds 1 }; Start-Process $url\"",
      "workingDirectory": "$(SolutionDir)",
      "launchBrowser": true,
      "launchUrl": "http://localhost:5602/swagger",
      "environmentVariables": {
        "COMPOSE_PROJECT_NAME": "ahkflowapp"
      }
    },
    "Docker (API only - requires SQL on localhost:1433)": {
      "commandName": "Docker",
      "launchBrowser": true,
      "launchUrl": "http://localhost:5604/swagger",
      "httpPort": 5604,
      "useSSL": false,
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ConnectionStrings__DefaultConnection": "Server=host.docker.internal,1433;Database=AHKFlowAppDb;User Id=sa;Password=AHKFlow_Dev!2026;TrustServerCertificate=True;MultipleActiveResultSets=true"
      },
      "publishAllPorts": false
    }
  }
}
```

- [ ] **Step 5: Verify build is unaffected**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add .vscode/launch.json .vscode/tasks.json .vscode/settings.json
git add src/Backend/AHKFlowApp.API/Properties/launchSettings.json
git commit -m "chore: add vscode debug config and full launch profiles"
```

---

## Task 2: Swagger UI

**Files:**
- Modify: `Directory.Packages.props`
- Modify: `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`
- Create: `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs`
- Modify: `src/Backend/AHKFlowApp.API/Program.cs`

- [ ] **Step 1: Add Swashbuckle package**

Run from repo root:
```bash
dotnet add src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj package Swashbuckle.AspNetCore
```

With Central Package Management (CPM), this adds a `<PackageVersion>` entry to `Directory.Packages.props` and a version-free `<PackageReference>` to the `.csproj`. Verify both files were updated correctly — if `dotnet add` doesn't update `Directory.Packages.props`, add the version entry manually (check what version was resolved from `obj/project.assets.json`).

- [ ] **Step 2: Create `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs`**

```csharp
using Microsoft.OpenApi.Models;

namespace AHKFlowApp.API.Extensions;

internal static class ApiExtensions
{
    internal static IServiceCollection AddSwaggerDocs(this IServiceCollection services)
    {
        services.AddEndpointsApiExplorer();
        services.AddSwaggerGen(options =>
        {
            options.SwaggerDoc("v1", new OpenApiInfo
            {
                Title = "AHKFlowApp API",
                Version = "v1"
            });
        });
        return services;
    }

    internal static WebApplication UseSwaggerDocs(this WebApplication app)
    {
        app.UseSwagger();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/swagger/v1/swagger.json", "AHKFlowApp API v1");
            options.RoutePrefix = "swagger";
        });

        // Redirect root to Swagger UI
        app.Use(async (context, next) =>
        {
            if (context.Request.Path == "/")
            {
                context.Response.Redirect("/swagger");
                return;
            }
            await next(context);
        });

        return app;
    }
}
```

- [ ] **Step 3: Update `src/Backend/AHKFlowApp.API/Program.cs`**

Replace the existing content with:

```csharp
using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSwaggerDocs();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

WebApplication app = builder.Build();

app.UseMiddleware<GlobalExceptionMiddleware>();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseSwaggerDocs();
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();

public partial class Program { }
```

Note: `AddOpenApi()` and `MapOpenApi()` are removed — Swashbuckle replaces them.

- [ ] **Step 4: Build and verify**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 5: Smoke test (manual)**

Run: `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + LocalDB SQL"`
Expected: Browser opens at `https://localhost:7600/swagger` and shows the Swagger UI.
Stop the app after verification.

- [ ] **Step 6: Commit**

```bash
git add Directory.Packages.props
git add src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj
git add src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs
git add src/Backend/AHKFlowApp.API/Program.cs
git commit -m "feat: add Swagger UI via Swashbuckle"
```

---

## Task 3: Health Endpoint + Integration Tests

**Files:**
- Modify: `Directory.Packages.props`
- Modify: `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`
- Create: `src/Backend/AHKFlowApp.API/Models/HealthResponse.cs`
- Create: `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Program.cs`
- Create: `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj`
- Modify: `AHKFlowApp.slnx`
- Create: `tests/AHKFlowApp.API.Tests/Health/HealthApiFactory.cs`
- Create: `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs`

- [ ] **Step 1: Add health checks packages to API project**

Run from repo root:
```bash
dotnet add src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj package Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore
```

Verify `Directory.Packages.props` was updated (or add manually if CPM doesn't auto-update).

- [ ] **Step 2: Create `src/Backend/AHKFlowApp.API/Models/HealthResponse.cs`**

```csharp
namespace AHKFlowApp.API.Models;

public sealed record HealthResponse(
    string Status,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks);
```

- [ ] **Step 3: Create `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs`**

```csharp
using AHKFlowApp.API.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class HealthController(
    HealthCheckService healthCheckService,
    IHostEnvironment hostEnvironment) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<HealthResponse>> GetHealthAsync(CancellationToken cancellationToken)
    {
        HealthReport report = await healthCheckService.CheckHealthAsync(cancellationToken);

        var checks = report.Entries.ToDictionary(
            e => e.Key,
            e => e.Value.Status.ToString());

        var response = new HealthResponse(
            Status: report.Status.ToString(),
            Environment: hostEnvironment.EnvironmentName,
            Timestamp: DateTimeOffset.UtcNow,
            Checks: checks);

        return report.Status == HealthStatus.Unhealthy
            ? StatusCode(StatusCodes.Status503ServiceUnavailable, response)
            : Ok(response);
    }
}
```

- [ ] **Step 4: Register health checks in `Program.cs`**

Add after `builder.Services.AddInfrastructure(builder.Configuration)`:

```csharp
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AHKFlowApp.Infrastructure.Persistence.AppDbContext>(
        name: "database",
        failureStatus: HealthStatus.Unhealthy);
```

Add after `app.MapControllers()`:

```csharp
// Plain-text infrastructure endpoint (for load balancers, k8s probes)
app.MapHealthChecks("/health");
```

Also add the using: `using Microsoft.Extensions.Diagnostics.HealthChecks;`

Full `Program.cs` after changes:

```csharp
using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.Extensions.Diagnostics.HealthChecks;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSwaggerDocs();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>(
        name: "database",
        failureStatus: HealthStatus.Unhealthy);

WebApplication app = builder.Build();

app.UseMiddleware<GlobalExceptionMiddleware>();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseSwaggerDocs();
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

public partial class Program { }
```

- [ ] **Step 5: Build and verify**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 6: Create the test project**

Run from repo root:
```bash
dotnet new xunit -n AHKFlowApp.API.Tests -o tests/AHKFlowApp.API.Tests --no-restore
```

- [ ] **Step 7: Add test packages**

```bash
dotnet add tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj package Microsoft.AspNetCore.Mvc.Testing
dotnet add tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj package FluentAssertions
dotnet add tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj package Testcontainers.MsSql
```

Also add project reference:
```bash
dotnet add tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj reference src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj
```

- [ ] **Step 8: Verify `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj`**

After adding packages, the file should look like:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="Testcontainers.MsSql" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj" />
  </ItemGroup>
</Project>
```

With CPM enabled, `PackageVersion` entries for all new packages must exist in `Directory.Packages.props`. Check that file after running `dotnet add package` and add any missing entries manually.

- [ ] **Step 9: Add test project to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj --solution-folder tests
```

Verify `AHKFlowApp.slnx` now has a `/tests/` folder entry.

- [ ] **Step 10: Delete the scaffolded placeholder test**

Delete `tests/AHKFlowApp.API.Tests/UnitTest1.cs`.

- [ ] **Step 11: Create `tests/AHKFlowApp.API.Tests/Health/HealthApiFactory.cs`**

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.MsSql;

namespace AHKFlowApp.API.Tests.Health;

public sealed class HealthApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _sqlContainer = new MsSqlBuilder().Build();

    public async Task InitializeAsync() => await _sqlContainer.StartAsync();

    public new async Task DisposeAsync()
    {
        await _sqlContainer.DisposeAsync();
        await base.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove all DbContext-related descriptors to avoid orphaned registrations
            var descriptors = services
                .Where(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>)
                         || d.ServiceType == typeof(AppDbContext))
                .ToList();
            foreach (var d in descriptors)
                services.Remove(d);

            // Register with the test container connection string
            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(_sqlContainer.GetConnectionString()));
        });
    }
}

// Collection definition — shared factory across all tests in the collection
[CollectionDefinition("HealthApi")]
public sealed class HealthApiCollection : ICollectionFixture<HealthApiFactory> { }
```

- [ ] **Step 12: Write the failing tests in `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs`**

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Models;
using FluentAssertions;

namespace AHKFlowApp.API.Tests.Health;

[Collection("HealthApi")]
public sealed class HealthControllerTests(HealthApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task GetHealth_WhenDatabaseReachable_Returns200WithHealthyStatus()
    {
        // Act
        var response = await _client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body.Should().NotBeNull();
        body!.Status.Should().Be("Healthy");
        body.Checks.Should().ContainKey("database");
        body.Checks["database"].Should().Be("Healthy");
    }

    [Fact]
    public async Task GetHealth_ReturnsExpectedShape()
    {
        // Act
        var response = await _client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body!.Environment.Should().NotBeNullOrEmpty();
        body.Timestamp.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromMinutes(1));
    }

    [Fact]
    public async Task GetHealth_InfrastructureEndpoint_ReturnsHealthyText()
    {
        // Act
        var response = await _client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Be("Healthy");
    }
}
```

- [ ] **Step 13: Run all tests and verify they pass**

Run: `dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal`
Expected: All 3 tests pass. If a test fails, check the error message and fix the implementation.

- [ ] **Step 14: Build everything**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 15: Commit**

```bash
git add Directory.Packages.props
git add src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj
git add src/Backend/AHKFlowApp.API/Models/HealthResponse.cs
git add src/Backend/AHKFlowApp.API/Controllers/HealthController.cs
git add src/Backend/AHKFlowApp.API/Program.cs
git add tests/AHKFlowApp.API.Tests/
git add AHKFlowApp.slnx
git commit -m "feat: add health endpoint with db check and integration tests"
```

---

## Task 4: Frontend Typed HTTP Client

**Files:**
- Modify: `Directory.Packages.props`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HealthResponse.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IAhkFlowAppApiHttpClient.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/AhkFlowAppApiHttpClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

- [ ] **Step 1: Add resilience package to frontend**

```bash
dotnet add src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj package Microsoft.Extensions.Http.Resilience
```

Verify `Directory.Packages.props` was updated.

- [ ] **Step 2: Create `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json`**

```json
{
  "ApiBaseUrl": "https://localhost:7600"
}
```

- [ ] **Step 3: Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HealthResponse.cs`**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HealthResponse
{
    public string Status { get; init; } = string.Empty;
    public string Environment { get; init; } = string.Empty;
    public DateTimeOffset Timestamp { get; init; }
    public Dictionary<string, string> Checks { get; init; } = [];
}
```

- [ ] **Step 4: Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/IAhkFlowAppApiHttpClient.cs`**

```csharp
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IAhkFlowAppApiHttpClient
{
    Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken = default);
}
```

- [ ] **Step 5: Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/AhkFlowAppApiHttpClient.cs`**

```csharp
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class AhkFlowAppApiHttpClient(HttpClient httpClient) : IAhkFlowAppApiHttpClient
{
    public async Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken = default)
    {
        return await httpClient.GetFromJsonAsync<HealthResponse>(
            "api/v1/health",
            cancellationToken);
    }
}
```

- [ ] **Step 6: Register the HTTP client in `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`**

```csharp
using AHKFlowApp.UI.Blazor.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ApiBaseUrl"]
        ?? throw new InvalidOperationException("'ApiBaseUrl' is not configured."));
}).AddStandardResilienceHandler();

await builder.Build().RunAsync();
```

- [ ] **Step 7: Build and verify**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add Directory.Packages.props
git add src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj
git add src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HealthResponse.cs
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/IAhkFlowAppApiHttpClient.cs
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/AhkFlowAppApiHttpClient.cs
git add src/Frontend/AHKFlowApp.UI.Blazor/Program.cs
git commit -m "feat: add typed HTTP client for API communication"
```

---

## Task 5: Frontend Health Page

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`

- [ ] **Step 1: Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor`**

```razor
@page "/health"
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.DTOs

@implements IDisposable

<PageTitle>Health Check</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">System Health</MudText>

<MudPaper Class="pa-4">
    @if (_loading)
    {
        <MudProgressCircular Color="Color.Primary" Indeterminate="true" Size="Size.Small" />
        <MudText Typo="Typo.body2" Class="mt-2">Checking system health...</MudText>
    }
    else if (_healthCheck != null)
    {
        <MudSimpleTable Dense="true" Striped="true">
            <tbody>
                <tr>
                    <td><strong>Status</strong></td>
                    <td>
                        <MudText Typo="Typo.body1"
                                 Color="@(_healthCheck.Status == "Healthy" ? Color.Success : Color.Error)">
                            @_healthCheck.Status
                        </MudText>
                    </td>
                </tr>
                <tr>
                    <td><strong>Environment</strong></td>
                    <td>@_healthCheck.Environment</td>
                </tr>
                <tr>
                    <td><strong>Timestamp</strong></td>
                    <td>@_healthCheck.Timestamp.ToString("yyyy-MM-dd HH:mm:ss") UTC</td>
                </tr>
            </tbody>
        </MudSimpleTable>

        @if (_healthCheck.Checks.Count > 0)
        {
            <MudText Typo="Typo.h6" Class="mt-4 mb-2">Component Checks</MudText>
            <MudSimpleTable Dense="true" Striped="true">
                <thead>
                    <tr>
                        <th>Component</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach (var check in _healthCheck.Checks)
                    {
                        <tr>
                            <td>@check.Key</td>
                            <td>
                                <MudText Typo="Typo.body2"
                                         Color="@(check.Value == "Healthy" ? Color.Success : Color.Error)">
                                    @check.Value
                                </MudText>
                            </td>
                        </tr>
                    }
                </tbody>
            </MudSimpleTable>
        }

        <MudButton Variant="Variant.Outlined" Color="Color.Primary" Class="mt-4"
                   OnClick="RefreshHealthAsync">
            Refresh
        </MudButton>
    }
    else if (_hasError)
    {
        <MudAlert Severity="Severity.Error">
            <strong>Unable to retrieve health status</strong> — the API may not be running.
        </MudAlert>
        <MudButton Variant="Variant.Outlined" Color="Color.Primary" Class="mt-4"
                   OnClick="RefreshHealthAsync">
            Retry
        </MudButton>
    }
</MudPaper>

@inject IAhkFlowAppApiHttpClient ApiClient

@code {
    private HealthResponse? _healthCheck;
    private bool _loading = true;
    private bool _hasError;
    private readonly CancellationTokenSource _cts = new();

    protected override async Task OnInitializedAsync()
    {
        await LoadHealthAsync();
    }

    private async Task LoadHealthAsync()
    {
        _loading = true;
        _hasError = false;

        try
        {
            _healthCheck = await ApiClient.GetHealthAsync(_cts.Token);
            if (_healthCheck is null)
                _hasError = true;
        }
        catch (OperationCanceledException)
        {
            // page was disposed
        }
        catch
        {
            _hasError = true;
        }
        finally
        {
            _loading = false;
        }
    }

    private async Task RefreshHealthAsync() => await LoadHealthAsync();

    public void Dispose()
    {
        _cts.Cancel();
        _cts.Dispose();
    }
}
```

- [ ] **Step 2: Add nav link in `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`**

```razor
<MudNavMenu>
    <MudNavLink Href="" Match="NavLinkMatch.All"
                Icon="@Icons.Material.Filled.Home">
        Home
    </MudNavLink>
    <MudNavLink Href="health"
                Icon="@Icons.Material.Filled.MonitorHeart">
        Health
    </MudNavLink>
</MudNavMenu>
```

- [ ] **Step 3: Build and verify**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors.

- [ ] **Step 4: Run all tests**

Run: `dotnet test --configuration Release --verbosity normal`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor
git add src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor
git commit -m "feat: add health page to Blazor frontend"
```

---

## Final Verification

- [ ] Run full test suite: `dotnet test --configuration Release --verbosity normal`
- [ ] Start API with Docker SQL profile and confirm Swagger opens automatically at `/swagger`
- [ ] Navigate to `/health` in the frontend and confirm health data loads
- [ ] Create PR per git workflow guidelines
