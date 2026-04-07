# Testing Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create all test projects, shared TestUtilities, write tests for existing code, and configure Coverlet code coverage (Cobertura + HTML).

**Architecture:** 6 test projects (5 new + 1 refactored) following Clean Architecture layer separation. Shared `TestUtilities` project provides `SqlContainerFixture`, `CustomWebApplicationFactory`, test data builders, and xUnit collection definitions. Coverage via `coverlet.collector` + `ReportGenerator` global tool.

**Tech Stack:** xUnit 2.9.3, FluentAssertions 8.9.0, NSubstitute, Testcontainers.MsSql 4.11.0, bUnit, coverlet.collector 6.0.4, ReportGenerator

**Spec:** `docs/superpowers/specs/2026-04-04-testing-infrastructure-design.md`

---

## File Structure

### New files to create

```
tests/
  AHKFlowApp.TestUtilities/
    AHKFlowApp.TestUtilities.csproj
    Fixtures/SqlContainerFixture.cs
    Fixtures/CustomWebApplicationFactory.cs
    Fixtures/Collections.cs
    Builders/HealthResponseBuilder.cs

  AHKFlowApp.Domain.Tests/
    AHKFlowApp.Domain.Tests.csproj

  AHKFlowApp.Application.Tests/
    AHKFlowApp.Application.Tests.csproj
    Behaviors/ValidationBehaviorTests.cs

  AHKFlowApp.Infrastructure.Tests/
    AHKFlowApp.Infrastructure.Tests.csproj
    Persistence/AppDbContextTests.cs
    Persistence/MigrationTests.cs

  AHKFlowApp.UI.Blazor.Tests/
    AHKFlowApp.UI.Blazor.Tests.csproj
    Pages/HealthPageTests.cs
    Services/AhkFlowAppApiHttpClientTests.cs
```

### Existing files to modify

```
Directory.Packages.props                          — add NSubstitute, bunit packages
AHKFlowApp.slnx                                  — add 5 new test projects
.gitignore                                        — add coverage-report/ directory
AGENTS.md                                         — fix Infrastructure.Test → Infrastructure.Tests

tests/AHKFlowApp.API.Tests/
  AHKFlowApp.API.Tests.csproj                     — add TestUtilities reference, remove Testcontainers.MsSql
  Health/HealthControllerTests.cs                  — use shared CustomWebApplicationFactory
  Health/HealthApiFactory.cs                       — delete (replaced by shared fixtures)

tests/AHKFlowApp.API.Tests/
  Middleware/GlobalExceptionMiddlewareTests.cs     — new
  Program/ProgramTests.cs                         — new
```

---

## Task 1: Add packages to Directory.Packages.props

**Files:**
- Modify: `Directory.Packages.props`

- [ ] **Step 1: Add NSubstitute package**

```bash
dotnet add tests/AHKFlowApp.API.Tests package NSubstitute
```

This adds the `PackageVersion` entry to `Directory.Packages.props` (CPM) and a `PackageReference` to the test project. We'll remove the reference from `API.Tests` later since it doesn't need NSubstitute directly.

- [ ] **Step 2: Add bunit package**

```bash
dotnet add tests/AHKFlowApp.API.Tests package bunit
```

Same approach — adds to CPM. We'll move the reference to the right project later.

- [ ] **Step 3: Clean up API.Tests.csproj**

Remove the `NSubstitute` and `bunit` package references from `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj` — they were only added to get the versions into `Directory.Packages.props`.

- [ ] **Step 4: Verify build**

```bash
dotnet build --configuration Release
```

Expected: Build succeeds, no warnings.

- [ ] **Step 5: Commit**

```bash
git add Directory.Packages.props tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj
git commit -m "chore: add NSubstitute and bunit to central package management"
```

---

## Task 2: Create TestUtilities project with SqlContainerFixture

**Files:**
- Create: `tests/AHKFlowApp.TestUtilities/AHKFlowApp.TestUtilities.csproj`
- Create: `tests/AHKFlowApp.TestUtilities/Fixtures/SqlContainerFixture.cs`
- Modify: `AHKFlowApp.slnx` — add TestUtilities project

- [ ] **Step 1: Create the project**

```bash
dotnet new classlib -n AHKFlowApp.TestUtilities -o tests/AHKFlowApp.TestUtilities
```

Delete the auto-generated `Class1.cs`.

- [ ] **Step 2: Configure the .csproj**

Replace `tests/AHKFlowApp.TestUtilities/AHKFlowApp.TestUtilities.csproj` with:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="Testcontainers.MsSql" />
    <PackageReference Include="xunit" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.Infrastructure\AHKFlowApp.Infrastructure.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.TestUtilities/AHKFlowApp.TestUtilities.csproj --solution-folder tests
```

- [ ] **Step 4: Write SqlContainerFixture**

Create `tests/AHKFlowApp.TestUtilities/Fixtures/SqlContainerFixture.cs`:

```csharp
using Testcontainers.MsSql;
using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class SqlContainerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder(
        "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04").Build();

    public string ConnectionString => _container.GetConnectionString();

    public Task InitializeAsync() => _container.StartAsync();

    public async Task DisposeAsync() => await _container.DisposeAsync();
}
```

- [ ] **Step 5: Verify build**

```bash
dotnet build --configuration Release
```

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add tests/AHKFlowApp.TestUtilities/ AHKFlowApp.slnx
git commit -m "feat: add TestUtilities project with SqlContainerFixture"
```

---

## Task 3: Add CustomWebApplicationFactory and collection definitions

**Files:**
- Create: `tests/AHKFlowApp.TestUtilities/Fixtures/CustomWebApplicationFactory.cs`
- Create: `tests/AHKFlowApp.TestUtilities/Fixtures/Collections.cs`

- [ ] **Step 1: Write CustomWebApplicationFactory**

Create `tests/AHKFlowApp.TestUtilities/Fixtures/CustomWebApplicationFactory.cs`:

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class CustomWebApplicationFactory(
    SqlContainerFixture sqlFixture) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            var descriptors = services
                .Where(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>)
                         || d.ServiceType == typeof(AppDbContext))
                .ToList();

            foreach (ServiceDescriptor d in descriptors)
                services.Remove(d);

            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(sqlFixture.ConnectionString,
                    sql => sql.EnableRetryOnFailure()));
        });
    }
}
```

- [ ] **Step 2: Write collection definitions**

Create `tests/AHKFlowApp.TestUtilities/Fixtures/Collections.cs`:

```csharp
using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

[CollectionDefinition("SqlServer")]
public sealed class SqlServerCollection : ICollectionFixture<SqlContainerFixture>;

[CollectionDefinition("WebApi")]
public sealed class WebApiCollection : ICollectionFixture<SqlContainerFixture>;
```

Note: `WebApi` collection provides `SqlContainerFixture`. Individual test classes create `CustomWebApplicationFactory` from the fixture. This avoids the factory being shared across unrelated test classes (each test class gets its own factory instance with its own test server).

- [ ] **Step 3: Verify build**

```bash
dotnet build --configuration Release
```

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.TestUtilities/Fixtures/
git commit -m "feat: add CustomWebApplicationFactory and xUnit collection definitions"
```

---

## Task 4: Add HealthResponseBuilder

**Files:**
- Create: `tests/AHKFlowApp.TestUtilities/Builders/HealthResponseBuilder.cs`

- [ ] **Step 1: Write the builder**

Create `tests/AHKFlowApp.TestUtilities/Builders/HealthResponseBuilder.cs`:

```csharp
using AHKFlowApp.API.Models;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HealthResponseBuilder
{
    private string _status = "Healthy";
    private string _environment = "Test";
    private DateTimeOffset _timestamp = DateTimeOffset.UtcNow;
    private readonly Dictionary<string, string> _checks = new() { ["database"] = "Healthy" };

    public HealthResponseBuilder WithStatus(string status)
    {
        _status = status;
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

    public HealthResponse Build() => new(_status, _environment, _timestamp, new Dictionary<string, string>(_checks));
}
```

- [ ] **Step 2: Add API project reference to TestUtilities**

The `HealthResponseBuilder` references `AHKFlowApp.API.Models.HealthResponse`. Add a project reference:

```bash
dotnet add tests/AHKFlowApp.TestUtilities reference src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj
```

**Important:** This changes the SDK. Since `AHKFlowApp.API` is a web project, `TestUtilities` may need `Microsoft.NET.Sdk.Web` or the API project reference may pull in web dependencies. Check that the build works. If it causes issues, change the TestUtilities SDK to `Microsoft.NET.Sdk.Web` or alternatively have the builder live closer to where it's used. The existing `API.Tests` already references the API project, so this pattern is established.

- [ ] **Step 3: Verify build**

```bash
dotnet build --configuration Release
```

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.TestUtilities/
git commit -m "feat: add HealthResponseBuilder with builder pattern"
```

---

## Task 5: Refactor API.Tests to use shared fixtures

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj`
- Modify: `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs`
- Delete: `tests/AHKFlowApp.API.Tests/Health/HealthApiFactory.cs`

- [ ] **Step 1: Add TestUtilities reference and remove duplicated packages**

Modify `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj`:
- Add project reference to `TestUtilities`
- Remove `Testcontainers.MsSql` package reference (now comes via TestUtilities)
- Remove `Microsoft.AspNetCore.Mvc.Testing` package reference (now comes via TestUtilities)
- Keep `coverlet.collector`, `FluentAssertions`, `Microsoft.NET.Test.Sdk`, `xunit`, `xunit.runner.visualstudio`

The `.csproj` should become:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj" />
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 2: Refactor HealthControllerTests to use shared fixtures**

Replace `tests/AHKFlowApp.API.Tests/Health/HealthControllerTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Models;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Health;

[Collection("WebApi")]
public sealed class HealthControllerTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task GetHealth_WhenDatabaseReachable_Returns200WithHealthyStatus()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body.Should().NotBeNull();
        body!.Status.Should().Be("Healthy");
        body.Checks.Should().ContainKey("database");
        body.Checks["database"].Should().Be("Healthy");
    }

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
        body.Timestamp.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromMinutes(1));
    }

    [Fact]
    public async Task GetHealth_InfrastructureEndpoint_ReturnsHealthyText()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/health");
        string body = await response.Content.ReadAsStringAsync();

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Be("Healthy");
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 3: Delete the old HealthApiFactory**

Delete `tests/AHKFlowApp.API.Tests/Health/HealthApiFactory.cs` — its functionality is now in `SqlContainerFixture` + `CustomWebApplicationFactory` + `Collections.cs`.

- [ ] **Step 4: Run existing tests to verify no regressions**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/
git commit -m "refactor: migrate API.Tests to shared TestUtilities fixtures"
```

---

## Task 6: Add GlobalExceptionMiddleware integration tests

**Files:**
- Create: `tests/AHKFlowApp.API.Tests/Middleware/GlobalExceptionMiddlewareTests.cs`

- [ ] **Step 1: Add InternalsVisibleTo for the API project**

`GlobalExceptionMiddleware` is `internal`. Add to `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`:

```xml
<ItemGroup>
  <InternalsVisibleTo Include="AHKFlowApp.API.Tests" />
</ItemGroup>
```

- [ ] **Step 2: Write the tests**

Create `tests/AHKFlowApp.API.Tests/Middleware/GlobalExceptionMiddlewareTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.API.Tests.Middleware;

[Collection("WebApi")]
public sealed class GlobalExceptionMiddlewareTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task Middleware_WhenValidationExceptionThrown_Returns400ProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddRouting();
            });
            builder.Configure(app =>
            {
                app.UseMiddleware<AHKFlowApp.API.Middleware.GlobalExceptionMiddleware>();
                app.UseRouting();
                app.UseEndpoints(endpoints =>
                {
                    endpoints.MapGet("/test/validation-error", _ =>
                    {
                        var failures = new List<ValidationFailure>
                        {
                            new("Name", "Name is required"),
                            new("Name", "Name must be at least 3 characters"),
                            new("Email", "Email is invalid")
                        };
                        throw new ValidationException(failures);
                    });
                });
            });
        }).CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/test/validation-error");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ProblemDetails? problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem.Should().NotBeNull();
        problem!.Status.Should().Be(400);
        problem.Title.Should().Be("Validation failed");
    }

    [Fact]
    public async Task Middleware_WhenUnhandledExceptionThrown_Returns500ProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddRouting();
            });
            builder.Configure(app =>
            {
                app.UseMiddleware<AHKFlowApp.API.Middleware.GlobalExceptionMiddleware>();
                app.UseRouting();
                app.UseEndpoints(endpoints =>
                {
                    endpoints.MapGet("/test/unhandled-error", _ =>
                        throw new InvalidOperationException("Something broke"));
                });
            });
        }).CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/test/unhandled-error");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ProblemDetails? problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem.Should().NotBeNull();
        problem!.Status.Should().Be(500);
        problem.Title.Should().Be("An unexpected error occurred");
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Expected: All 5 tests pass (3 existing + 2 new).

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/Middleware/ src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj
git commit -m "test: add GlobalExceptionMiddleware integration tests"
```

---

## Task 7: Add Program integration tests

**Files:**
- Create: `tests/AHKFlowApp.API.Tests/Program/ProgramTests.cs`

- [ ] **Step 1: Write the tests**

Create `tests/AHKFlowApp.API.Tests/Program/ProgramTests.cs`:

```csharp
using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Program;

[Collection("WebApi")]
public sealed class ProgramTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task Root_RedirectsToSwagger()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient(
            new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
            {
                AllowAutoRedirect = false
            });

        // Act
        HttpResponseMessage response = await client.GetAsync("/");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Redirect);
        response.Headers.Location!.ToString().Should().Be("/swagger");
    }

    [Fact]
    public async Task HealthEndpoint_ReturnsPlainTextHealthy()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/health");
        string body = await response.Content.ReadAsStringAsync();

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Be("Healthy");
    }

    [Fact]
    public async Task SwaggerEndpoint_Returns200()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/swagger/index.html");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 2: Run tests**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Expected: All 8 tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/Program/
git commit -m "test: add Program integration tests (swagger, health, root redirect)"
```

---

## Task 8: Create Application.Tests with ValidationBehavior tests

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.csproj`
- Create: `tests/AHKFlowApp.Application.Tests/Behaviors/ValidationBehaviorTests.cs`

- [ ] **Step 1: Create the project**

```bash
dotnet new xunit -n AHKFlowApp.Application.Tests -o tests/AHKFlowApp.Application.Tests
```

Delete auto-generated test files (`UnitTest1.cs`, `GlobalUsings.cs` if redundant).

- [ ] **Step 2: Configure the .csproj**

Replace `tests/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.Application\AHKFlowApp.Application.csproj" />
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.csproj --solution-folder tests
```

- [ ] **Step 4: Write ValidationBehaviorTests**

Note: `ValidationBehavior` is `internal`. Add `InternalsVisibleTo` to the Application project:

Create or modify the Application project to expose internals. Add to `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`:

```xml
<ItemGroup>
  <InternalsVisibleTo Include="AHKFlowApp.Application.Tests" />
</ItemGroup>
```

Then create `tests/AHKFlowApp.Application.Tests/Behaviors/ValidationBehaviorTests.cs`:

```csharp
using AHKFlowApp.Application.Behaviors;
using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using MediatR;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Behaviors;

public sealed class ValidationBehaviorTests
{
    private record TestRequest(string Name) : IRequest<string>;

    [Fact]
    public async Task Handle_WhenNoValidators_CallsNext()
    {
        // Arrange
        var validators = Enumerable.Empty<IValidator<TestRequest>>();
        var behavior = new ValidationBehavior<TestRequest, string>(validators);
        var request = new TestRequest("test");
        var next = Substitute.For<RequestHandlerDelegate<string>>();
        next.Invoke(Arg.Any<CancellationToken>()).Returns("result");

        // Act
        string result = await behavior.Handle(request, next, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        await next.Received(1).Invoke(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_WhenValidationPasses_CallsNext()
    {
        // Arrange
        var validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult());

        var behavior = new ValidationBehavior<TestRequest, string>([validator]);
        var request = new TestRequest("valid");
        var next = Substitute.For<RequestHandlerDelegate<string>>();
        next.Invoke(Arg.Any<CancellationToken>()).Returns("result");

        // Act
        string result = await behavior.Handle(request, next, CancellationToken.None);

        // Assert
        result.Should().Be("result");
        await next.Received(1).Invoke(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_WhenValidationFails_ThrowsValidationException()
    {
        // Arrange
        var failures = new List<ValidationFailure>
        {
            new("Name", "Name is required")
        };
        var validator = Substitute.For<IValidator<TestRequest>>();
        validator.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult(failures));

        var behavior = new ValidationBehavior<TestRequest, string>([validator]);
        var request = new TestRequest("");
        var next = Substitute.For<RequestHandlerDelegate<string>>();

        // Act
        Func<Task> act = () => behavior.Handle(request, next, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<ValidationException>()
            .Where(ex => ex.Errors.Any(e => e.ErrorMessage == "Name is required"));
        await next.DidNotReceive().Invoke(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_WhenMultipleValidatorsFail_CombinesAllErrors()
    {
        // Arrange
        var validator1 = Substitute.For<IValidator<TestRequest>>();
        validator1.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Too short")]));

        var validator2 = Substitute.For<IValidator<TestRequest>>();
        validator2.ValidateAsync(Arg.Any<ValidationContext<TestRequest>>(), Arg.Any<CancellationToken>())
            .Returns(new ValidationResult([new ValidationFailure("Name", "Invalid chars")]));

        var behavior = new ValidationBehavior<TestRequest, string>([validator1, validator2]);
        var next = Substitute.For<RequestHandlerDelegate<string>>();

        // Act
        Func<Task> act = () => behavior.Handle(new TestRequest("x"), next, CancellationToken.None);

        // Assert
        var ex = await act.Should().ThrowAsync<ValidationException>();
        ex.Which.Errors.Should().HaveCount(2);
    }
}
```

- [ ] **Step 5: Run tests**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --verbosity normal
```

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add tests/AHKFlowApp.Application.Tests/ src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj AHKFlowApp.slnx
git commit -m "test: add ValidationBehavior unit tests with NSubstitute"
```

---

## Task 9: Create Infrastructure.Tests with AppDbContext and migration tests

**Files:**
- Create: `tests/AHKFlowApp.Infrastructure.Tests/AHKFlowApp.Infrastructure.Tests.csproj`
- Create: `tests/AHKFlowApp.Infrastructure.Tests/Persistence/AppDbContextTests.cs`
- Create: `tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs`

- [ ] **Step 1: Create the project**

```bash
dotnet new xunit -n AHKFlowApp.Infrastructure.Tests -o tests/AHKFlowApp.Infrastructure.Tests
```

Delete auto-generated test files.

- [ ] **Step 2: Configure the .csproj**

Replace `tests/AHKFlowApp.Infrastructure.Tests/AHKFlowApp.Infrastructure.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.Infrastructure\AHKFlowApp.Infrastructure.csproj" />
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.Infrastructure.Tests/AHKFlowApp.Infrastructure.Tests.csproj --solution-folder tests
```

- [ ] **Step 4: Write AppDbContextTests**

Create `tests/AHKFlowApp.Infrastructure.Tests/Persistence/AppDbContextTests.cs`:

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class AppDbContextTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string? databaseName = null)
    {
        // Use a unique database name to isolate from MigrationTests
        // (EnsureCreated and Migrate conflict if they hit the same DB)
        string connectionString = sqlFixture.ConnectionString;
        if (databaseName is not null)
            connectionString = connectionString.Replace("master", databaseName);

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString,
                sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task CanConnect_WhenDatabaseExists_ReturnsTrue()
    {
        // Arrange
        await using AppDbContext context = CreateContext("AppDbContextTests_CanConnect");
        await context.Database.EnsureCreatedAsync();

        // Act
        bool canConnect = await context.Database.CanConnectAsync();

        // Assert
        canConnect.Should().BeTrue();
    }

    [Fact]
    public async Task EnsureCreated_AppliesSchemaWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("AppDbContextTests_EnsureCreated");

        // Act
        Func<Task> act = () => context.Database.EnsureCreatedAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }
}
```

- [ ] **Step 5: Write MigrationTests**

Create `tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs`:

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class MigrationTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string? databaseName = null)
    {
        string connectionString = sqlFixture.ConnectionString;
        if (databaseName is not null)
            connectionString = connectionString.Replace("master", databaseName);

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString,
                sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task Migrate_AppliesPendingMigrationsWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("MigrationTests_Apply");

        // Act
        Func<Task> act = () => context.Database.MigrateAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task Migrate_IsIdempotent_RunsTwiceWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("MigrationTests_Idempotent");
        await context.Database.MigrateAsync();

        // Act
        Func<Task> act = () => context.Database.MigrateAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }
}
```

- [ ] **Step 6: Run tests**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --configuration Release --verbosity normal
```

Expected: All 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add tests/AHKFlowApp.Infrastructure.Tests/ AHKFlowApp.slnx
git commit -m "test: add Infrastructure integration tests (AppDbContext, migrations)"
```

---

## Task 10: Create Domain.Tests scaffold

**Files:**
- Create: `tests/AHKFlowApp.Domain.Tests/AHKFlowApp.Domain.Tests.csproj`

- [ ] **Step 1: Create the project**

```bash
dotnet new xunit -n AHKFlowApp.Domain.Tests -o tests/AHKFlowApp.Domain.Tests
```

Delete auto-generated test files.

- [ ] **Step 2: Configure the .csproj**

Replace `tests/AHKFlowApp.Domain.Tests/AHKFlowApp.Domain.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.Domain\AHKFlowApp.Domain.csproj" />
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.Domain.Tests/AHKFlowApp.Domain.Tests.csproj --solution-folder tests
```

- [ ] **Step 4: Verify build**

```bash
dotnet build --configuration Release
```

- [ ] **Step 5: Commit**

```bash
git add tests/AHKFlowApp.Domain.Tests/ AHKFlowApp.slnx
git commit -m "chore: scaffold empty Domain.Tests project"
```

---

## Task 11: Create UI.Blazor.Tests with Health page and HTTP client tests

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/AHKFlowApp.UI.Blazor.Tests.csproj`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HealthPageTests.cs`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/AhkFlowAppApiHttpClientTests.cs`

- [ ] **Step 1: Create the project**

```bash
dotnet new xunit -n AHKFlowApp.UI.Blazor.Tests -o tests/AHKFlowApp.UI.Blazor.Tests
```

Delete auto-generated test files.

- [ ] **Step 2: Configure the .csproj**

Replace `tests/AHKFlowApp.UI.Blazor.Tests/AHKFlowApp.UI.Blazor.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="bunit" />
    <PackageReference Include="coverlet.collector">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="MudBlazor" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Frontend\AHKFlowApp.UI.Blazor\AHKFlowApp.UI.Blazor.csproj" />
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add to solution**

```bash
dotnet sln AHKFlowApp.slnx add tests/AHKFlowApp.UI.Blazor.Tests/AHKFlowApp.UI.Blazor.Tests.csproj --solution-folder tests
```

- [ ] **Step 4: Write HealthPageTests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HealthPageTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HealthPageTests : TestContext
{
    private readonly IAhkFlowAppApiHttpClient _apiClient = Substitute.For<IAhkFlowAppApiHttpClient>();

    public HealthPageTests()
    {
        Services.AddSingleton(_apiClient);
        Services.AddMudServices();
    }

    [Fact]
    public void Health_WhenApiReturnsData_DisplaysStatus()
    {
        // Arrange
        var response = new HealthResponse
        {
            Status = "Healthy",
            Environment = "Test",
            Timestamp = DateTimeOffset.UtcNow,
            Checks = new Dictionary<string, string> { ["database"] = "Healthy" }
        };
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(response));

        // Act
        IRenderedComponent<Health> cut = RenderComponent<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Healthy");
        cut.Markup.Should().Contain("Test");
        cut.Markup.Should().Contain("database");
    }

    [Fact]
    public void Health_WhenApiThrows_DisplaysErrorAlert()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .ThrowsAsync(new HttpRequestException("Connection refused"));

        // Act
        IRenderedComponent<Health> cut = RenderComponent<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Unable to retrieve health status");
    }

    [Fact]
    public void Health_WhenApiReturnsNull_DisplaysErrorAlert()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(null));

        // Act
        IRenderedComponent<Health> cut = RenderComponent<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Unable to retrieve health status");
    }

    [Fact]
    public async Task Health_WhenRefreshClicked_RefetchesData()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(new HealthResponse
            {
                Status = "Healthy",
                Environment = "Test",
                Timestamp = DateTimeOffset.UtcNow,
                Checks = []
            }));

        IRenderedComponent<Health> cut = RenderComponent<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Act
        cut.Find("button").Click();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        await _apiClient.Received(2).GetHealthAsync(Arg.Any<CancellationToken>());
    }
}
```

- [ ] **Step 5: Write AhkFlowAppApiHttpClientTests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Services/AhkFlowAppApiHttpClientTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class AhkFlowAppApiHttpClientTests
{
    [Fact]
    public async Task GetHealthAsync_WhenApiReturnsJson_DeserializesResponse()
    {
        // Arrange
        var expected = new HealthResponse
        {
            Status = "Healthy",
            Environment = "Production",
            Timestamp = DateTimeOffset.Parse("2026-04-04T12:00:00Z"),
            Checks = new Dictionary<string, string> { ["database"] = "Healthy" }
        };

        using HttpClient httpClient = CreateMockHttpClient(
            HttpStatusCode.OK,
            JsonContent.Create(expected));

        var client = new AhkFlowAppApiHttpClient(httpClient);

        // Act
        HealthResponse? result = await client.GetHealthAsync();

        // Assert
        result.Should().NotBeNull();
        result!.Status.Should().Be("Healthy");
        result.Environment.Should().Be("Production");
        result.Checks.Should().ContainKey("database");
    }

    [Fact]
    public async Task GetHealthAsync_WhenApiReturns500_ThrowsHttpRequestException()
    {
        // Arrange
        using HttpClient httpClient = CreateMockHttpClient(
            HttpStatusCode.InternalServerError,
            new StringContent("Server Error"));

        var client = new AhkFlowAppApiHttpClient(httpClient);

        // Act
        Func<Task> act = () => client.GetHealthAsync();

        // Assert
        await act.Should().ThrowAsync<HttpRequestException>();
    }

    private static HttpClient CreateMockHttpClient(HttpStatusCode statusCode, HttpContent content)
    {
        var handler = new MockHttpMessageHandler(statusCode, content);
        return new HttpClient(handler) { BaseAddress = new Uri("https://localhost") };
    }

    private sealed class MockHttpMessageHandler(
        HttpStatusCode statusCode,
        HttpContent content) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(statusCode) { Content = content });
        }
    }
}
```

- [ ] **Step 6: Run tests**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --verbosity normal
```

Expected: All 6 tests pass. If bUnit + MudBlazor has rendering issues (common with MudBlazor's JS interop), you may need to add `JSInterop.SetupVoid()` or similar bUnit JSInterop stubs. Adjust as needed during implementation.

- [ ] **Step 7: Commit**

```bash
git add tests/AHKFlowApp.UI.Blazor.Tests/ AHKFlowApp.slnx
git commit -m "test: add Blazor UI tests (Health page bUnit, HTTP client unit)"
```

---

## Task 12: Configure code coverage

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Install ReportGenerator global tool**

```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
```

If already installed, this will report that. Not an error.

- [ ] **Step 2: Add coverage-report/ to .gitignore**

Append to `.gitignore`:

```
# Code coverage reports
coverage-report/
**/TestResults/
```

Note: `coverage*.json`, `coverage*.xml`, `coverage*.info` are already in `.gitignore` (lines 161-163). The `TestResults/` directory is where `--collect:"XPlat Code Coverage"` places output by default.

- [ ] **Step 3: Run coverage collection**

```bash
dotnet test --configuration Release --collect:"XPlat Code Coverage" --results-directory ./TestResults
```

Verify Cobertura XML files appear under `TestResults/`.

- [ ] **Step 4: Generate HTML report**

```bash
reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"coverage-report" -reporttypes:"Html;Cobertura"
```

Verify `coverage-report/index.html` exists and is browsable.

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: configure code coverage with Coverlet and ReportGenerator"
```

---

## Task 13: Update AGENTS.md and run full verification

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Fix Infrastructure.Test → Infrastructure.Tests in AGENTS.md**

In `AGENTS.md`, find the project structure section and change `AHKFlowApp.Infrastructure.Test/` to `AHKFlowApp.Infrastructure.Tests/`:

```
  AHKFlowApp.Infrastructure.Tests/ # Repository integration tests
```

- [ ] **Step 2: Run full build**

```bash
dotnet build --configuration Release
```

Expected: Build succeeds with zero warnings.

- [ ] **Step 3: Run all tests**

```bash
dotnet test --configuration Release --verbosity normal
```

Expected: All tests pass across all 5 test projects (Domain.Tests has 0 tests, which is fine).

- [ ] **Step 4: Run coverage and generate report**

```bash
dotnet test --configuration Release --collect:"XPlat Code Coverage" --results-directory ./TestResults && reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"coverage-report" -reporttypes:"Html;Cobertura"
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: fix Infrastructure.Test naming in AGENTS.md"
```

---

## Summary

| Task | What | Tests added |
|------|------|-------------|
| 1 | Add NSubstitute + bunit to CPM | — |
| 2 | Create TestUtilities + SqlContainerFixture | — |
| 3 | Add CustomWebApplicationFactory + collections | — |
| 4 | Add HealthResponseBuilder | — |
| 5 | Refactor API.Tests to shared fixtures | 3 (migrated) |
| 6 | GlobalExceptionMiddleware tests | 2 |
| 7 | Program integration tests | 3 |
| 8 | Application.Tests + ValidationBehavior | 4 |
| 9 | Infrastructure.Tests + DbContext + migrations | 4 |
| 10 | Domain.Tests scaffold | 0 |
| 11 | UI.Blazor.Tests + Health page + HTTP client | 6 |
| 12 | Code coverage configuration | — |
| 13 | AGENTS.md fix + full verification | — |

**Total: ~22 tests across 5 projects**
