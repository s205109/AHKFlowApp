# MinVer Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce automated semantic versioning via MinVer so every build exposes a consistent version derived from git tags.

**Architecture:** MinVer is added as a build-only tool to the API and Blazor projects. A `VersionService` in Infrastructure reads the MinVer-generated `AssemblyInformationalVersionAttribute` at runtime and exposes it via a dedicated `GET /api/v1/version` endpoint; the health endpoint also includes it. No git tags exist yet, so builds will produce `0.0.0-alpha.0+<sha>` until a tag is created.

**Tech Stack:** MinVer (latest stable via NuGet), Central Package Management (Directory.Packages.props), xUnit + FluentAssertions + WebApplicationFactory integration tests.

---

## File Map

| Action | File |
|--------|------|
| Modify | `Directory.Packages.props` — add MinVer PackageVersion |
| Modify | `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj` — add MinVer build tool ref |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj` — add MinVer build tool ref |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Services/IVersionService.cs` |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Services/VersionService.cs` |
| Modify | `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs` — register IVersionService as singleton |
| Create | `tests/AHKFlowApp.API.Tests/Version/VersionControllerTests.cs` — integration test (write first) |
| Create | `src/Backend/AHKFlowApp.API/Controllers/VersionController.cs` |
| Modify | `src/Backend/AHKFlowApp.API/Models/HealthResponse.cs` — add Version field |
| Modify | `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs` — inject IVersionService, set Version |
| Modify | `tests/AHKFlowApp.TestUtilities/Builders/HealthResponseBuilder.cs` — add WithVersion / default |
| Modify | `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs` — assert Version in response (write first) |
| Create | `docs/development/versioning.md` — versioning scheme docs |

---

## Task 1: Add MinVer to projects

No tests needed — MinVer is a build tool with no runtime DLL.

- [ ] **Step 1: Resolve latest MinVer version**

```bash
dotnet add package MinVer --project src/Backend/AHKFlowApp.API/
```

With CPM enabled, the SDK adds the version to `Directory.Packages.props` and a version-free reference to the `.csproj`. Inspect the result before continuing.

If the `.csproj` ends up with `Version="X.Y.Z"` on the PackageReference, move that version to `Directory.Packages.props` under a `<PackageVersion Include="MinVer" Version="X.Y.Z" />` entry and remove `Version=` from the `.csproj`.

- [ ] **Step 2: Set build-tool asset metadata in API.csproj**

The plain `dotnet add` won't set the required asset attributes. Edit `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj` so the MinVer entry looks exactly like this (no `Version=` attribute since version is in `Directory.Packages.props`):

```xml
<PackageReference Include="MinVer">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

- [ ] **Step 3: Add MinVer to Blazor project**

Edit `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj` and add the same entry:

```xml
<PackageReference Include="MinVer">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

No need to run `dotnet add` again; the version is already in `Directory.Packages.props`.

- [ ] **Step 4: Verify build succeeds**

```bash
dotnet build --configuration Release
```

Expected: build succeeds. MinVer logs a line like:
`MinVer: version 0.0.0-alpha.0.N+<sha>` in the output.

- [ ] **Step 5: Commit**

```bash
git add Directory.Packages.props \
        src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj \
        src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj
git commit -m "chore: add MinVer build tool to API and Blazor projects"
```

---

## Task 2: VersionService + VersionController (TDD)

Write the integration test first; everything will be red until the implementation is added.

- [ ] **Step 1: Write failing VersionController test**

Create `tests/AHKFlowApp.API.Tests/Version/VersionControllerTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Version;

[Collection("WebApi")]
public sealed class VersionControllerTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task GetVersion_Returns200WithNonEmptyVersion()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/version");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        VersionResponse? body = await response.Content.ReadFromJsonAsync<VersionResponse>();
        body.Should().NotBeNull();
        body!.Version.Should().NotBeNullOrWhiteSpace();
    }

    public void Dispose() => _factory.Dispose();

    private sealed record VersionResponse(string Version);
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~VersionControllerTests" --configuration Release
```

Expected: FAIL — `404 Not Found` (controller doesn't exist yet).

- [ ] **Step 3: Create IVersionService**

Create `src/Backend/AHKFlowApp.Infrastructure/Services/IVersionService.cs`:

```csharp
namespace AHKFlowApp.Infrastructure.Services;

public interface IVersionService
{
    Task<string> GetVersionAsync(CancellationToken cancellationToken = default);
}
```

- [ ] **Step 4: Create VersionService**

Create `src/Backend/AHKFlowApp.Infrastructure/Services/VersionService.cs`:

```csharp
using System.Reflection;

namespace AHKFlowApp.Infrastructure.Services;

public sealed class VersionService : IVersionService
{
    public Task<string> GetVersionAsync(CancellationToken cancellationToken = default)
    {
        string version = Assembly.GetEntryAssembly()?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion ?? "0.0.0-dev";

        return Task.FromResult(version);
    }
}
```

- [ ] **Step 5: Register IVersionService in DI**

Edit `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs` — add one line inside `AddInfrastructure`:

```csharp
services.AddSingleton<IVersionService, VersionService>();
```

Full file after change:

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddDbContext<AppDbContext>(options =>
            options.UseSqlServer(
                configuration.GetConnectionString("DefaultConnection"),
                sql => sql.EnableRetryOnFailure()));

        services.AddSingleton<IVersionService, VersionService>();

        return services;
    }
}
```

- [ ] **Step 6: Create VersionController**

Create `src/Backend/AHKFlowApp.API/Controllers/VersionController.cs`:

```csharp
using AHKFlowApp.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class VersionController(IVersionService versionService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(VersionResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<VersionResponse>> GetVersionAsync(CancellationToken cancellationToken)
    {
        string version = await versionService.GetVersionAsync(cancellationToken);
        return Ok(new VersionResponse(version));
    }

    public sealed record VersionResponse(string Version);
}
```

- [ ] **Step 7: Run test to verify it passes**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~VersionControllerTests" --configuration Release
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.Infrastructure/Services/IVersionService.cs \
        src/Backend/AHKFlowApp.Infrastructure/Services/VersionService.cs \
        src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs \
        src/Backend/AHKFlowApp.API/Controllers/VersionController.cs \
        tests/AHKFlowApp.API.Tests/Version/VersionControllerTests.cs
git commit -m "feat: add VersionService and GET /api/v1/version endpoint"
```

---

## Task 3: Add Version to HealthResponse (TDD)

- [ ] **Step 1: Update HealthController test to assert Version**

Edit `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs`.

Update `GetHealth_ReturnsExpectedShape` to also assert that `body.Version` is not null or empty:

```csharp
[Fact]
public async Task GetHealth_ReturnsExpectedShape()
{
    // Arrange
    using HttpClient client = _factory.CreateClient();

    // Act
    HttpResponseMessage response = await client.GetAsync("/api/v1/health");

    // Assert
    response.StatusCode.Should().Be(HttpStatusCode.OK);
    HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
    body!.Environment.Should().NotBeNullOrEmpty();
    body.Version.Should().NotBeNullOrWhiteSpace();
    body.Timestamp.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromMinutes(1));
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HealthControllerTests" --configuration Release
```

Expected: FAIL — compilation error because `HealthResponse` has no `Version` property yet.

- [ ] **Step 3: Add Version to HealthResponse**

Edit `src/Backend/AHKFlowApp.API/Models/HealthResponse.cs`:

```csharp
namespace AHKFlowApp.API.Models;

public sealed record HealthResponse(
    string Status,
    string Version,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks);
```

- [ ] **Step 4: Inject IVersionService into HealthController and set Version**

Edit `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs`:

```csharp
using AHKFlowApp.API.Models;
using AHKFlowApp.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class HealthController(
    HealthCheckService healthCheckService,
    IHostEnvironment hostEnvironment,
    TimeProvider timeProvider,
    IVersionService versionService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<HealthResponse>> GetHealthAsync(CancellationToken cancellationToken)
    {
        HealthReport report = await healthCheckService.CheckHealthAsync(cancellationToken);
        string version = await versionService.GetVersionAsync(cancellationToken);

        var checks = report.Entries.ToDictionary(
            e => e.Key,
            e => e.Value.Status.ToString());

        var response = new HealthResponse(
            Status: report.Status.ToString(),
            Version: version,
            Environment: hostEnvironment.EnvironmentName,
            Timestamp: timeProvider.GetUtcNow(),
            Checks: checks);

        return report.Status == HealthStatus.Unhealthy
            ? StatusCode(StatusCodes.Status503ServiceUnavailable, response)
            : Ok(response);
    }
}
```

- [ ] **Step 5: Update HealthResponseBuilder**

`HealthResponseBuilder.Build()` uses positional construction which will break now that `Version` was inserted as the second positional parameter. Edit `tests/AHKFlowApp.TestUtilities/Builders/HealthResponseBuilder.cs`:

```csharp
using AHKFlowApp.API.Models;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HealthResponseBuilder
{
    private string _status = "Healthy";
    private string _version = "0.0.0-dev";
    private string _environment = "Test";
    private DateTimeOffset _timestamp = DateTimeOffset.UtcNow;
    private readonly Dictionary<string, string> _checks = new() { ["database"] = "Healthy" };

    public HealthResponseBuilder WithStatus(string status)
    {
        _status = status;
        return this;
    }

    public HealthResponseBuilder WithVersion(string version)
    {
        _version = version;
        return this;
    }

    public HealthResponseBuilder WithEnvironment(string environment)
    {
        _environment = environment;
        return this;
    }

    public HealthResponseBuilder WithTimestamp(DateTimeOffset timestamp)
    {
        _timestamp = timestamp;
        return this;
    }

    public HealthResponseBuilder WithCheck(string name, string status)
    {
        _checks[name] = status;
        return this;
    }

    public HealthResponseBuilder WithoutChecks()
    {
        _checks.Clear();
        return this;
    }

#pragma warning disable IDE0028 // Simplify collection initialization
    public HealthResponse Build() => new(_status, _version, _environment, _timestamp, new(_checks));
#pragma warning restore IDE0028 // Simplify collection initialization
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release
```

Expected: all tests PASS.

- [ ] **Step 7: Run full test suite**

```bash
dotnet test --configuration Release
```

Expected: all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Models/HealthResponse.cs \
        src/Backend/AHKFlowApp.API/Controllers/HealthController.cs \
        tests/AHKFlowApp.TestUtilities/Builders/HealthResponseBuilder.cs \
        tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs
git commit -m "feat: add Version field to health response"
```

---

## Task 4: Document versioning scheme

- [ ] **Step 1: Update/validate docs/development/versioning.md**

Review the existing `docs/development/versioning.md` and update it as needed so it accurately documents the MinVer-based versioning workflow described in this plan, including:

- how MinVer derives versions from git tags
- example version shapes for tagged and untagged histories
- how to create and push a release tag (using the `v` prefix, e.g. `v1.0.0`)
- where to check the version at runtime (`GET /api/v1/version` and `GET /api/v1/health`)

| State | Example version |
|---|---|
| No tags yet | `0.0.0-alpha.0.5+abc1234` |
| On tag `v1.0.0` | `1.0.0` |
| 3 commits after `v1.0.0` | `1.0.1-alpha.0.3+def5678` |

```bash
git tag v1.0.0
git push origin v1.0.0
```

Ensure the document stays aligned with the implemented behavior rather than creating a duplicate file.

- [ ] **Step 2: Commit**

```bash
git add docs/development/versioning.md
git commit -m "docs: update versioning scheme documentation"
```

---

## Unresolved questions

- Should the Blazor frontend display the API version anywhere in the UI? (Backlog item 005 doesn't require it; skip for now.)
- Should MinVer also be added to `AHKFlowApp.Infrastructure` and `AHKFlowApp.Application` to version those assemblies, or only the deployable outputs (API + Blazor)?
