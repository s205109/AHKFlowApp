---
name: cck-testing
description: >
  Testing strategy for AHKFlowApp (.NET 10). Covers WebApplicationFactory integration
  tests with SQL Server Testcontainers, MediatR handler unit tests, Ardalis.Result
  assertions, FluentAssertions, NSubstitute, and the AAA pattern.
  Load when: "test", "xUnit", "WebApplicationFactory", "Testcontainers",
  "integration test", "unit test", "FluentAssertions", "NSubstitute",
  "MsSqlContainer", "test coverage", "AAA pattern".
---

# Testing (.NET 10)

## Core Principles

1. **Integration tests are highest-value** — A single `WebApplicationFactory` test covers routing, binding, MediatR pipeline, FluentValidation, handler, and SQL Server persistence in one shot.
2. **SQL Server Testcontainers — never in-memory** — Use `MsSqlContainer` from `Testcontainers.MsSql`. In-memory providers hide real SQL Server behavior (transactions, constraints, retry logic).
3. **AAA pattern is mandatory** — Every test: Arrange, Act, Assert — separated by blank lines.
4. **Test behavior, not implementation** — Assert on HTTP responses, database state, and `Result` status. Not which internal methods were called.
5. **FluentAssertions over Assert** — More readable failure messages. `result.IsSuccess.Should().BeTrue()` not `Assert.True(result.IsSuccess)`.

## Test Projects

```
tests/
  AHKFlowApp.API.Tests/            # Integration tests — WebApplicationFactory + Testcontainers
  AHKFlowApp.Application.Tests/    # Validator unit tests + handler unit tests
  AHKFlowApp.Domain.Tests/         # Domain entity logic unit tests
  AHKFlowApp.Infrastructure.Test/  # EF Core + migration tests with Testcontainers
  AHKFlowApp.UI.Blazor.Tests/      # Blazor component tests (bUnit)
```

## Patterns

### WebApplicationFactory Fixture (SQL Server)

```csharp
// tests/AHKFlowApp.API.Tests/Fixtures/ApiFixture.cs
public sealed class ApiFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _mssql = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
        .Build();

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

### Integration Test (API Endpoint)

```csharp
// tests/AHKFlowApp.API.Tests/Controllers/HotstringsControllerTests.cs
public sealed class HotstringsControllerTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private readonly HttpClient _client = fixture.CreateClient();

    [Fact]
    public async Task Create_ValidRequest_Returns201()
    {
        // Arrange
        var dto = new CreateHotstringDto("btw", "by the way");

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
        var dto = new CreateHotstringDto("", "by the way");

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

### MediatR Handler Unit Test

Test the handler directly with a real (Testcontainers) database. Assert on `Result` status.

```csharp
// tests/AHKFlowApp.Application.Tests/Commands/CreateHotstringHandlerTests.cs
public sealed class CreateHotstringHandlerTests : IAsyncLifetime
{
    private readonly MsSqlContainer _mssql = new MsSqlBuilder().Build();
    private AppDbContext _db = null!;

    public async Task InitializeAsync()
    {
        await _mssql.StartAsync();
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_mssql.GetConnectionString())
            .Options;
        _db = new AppDbContext(options);
        await _db.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await _db.DisposeAsync();
        await _mssql.DisposeAsync();
    }

    [Fact]
    public async Task Handle_ValidCommand_ReturnsSuccess()
    {
        // Arrange
        var handler = new CreateHotstringHandler(_db);
        var command = new CreateHotstringCommand("btw", "by the way");

        // Act
        var result = await handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        result.Value.Trigger.Should().Be("btw");
        result.Value.Replacement.Should().Be("by the way");
    }

    [Fact]
    public async Task Handle_DuplicateTrigger_ReturnsConflict()
    {
        // Arrange
        var handler = new CreateHotstringHandler(_db);
        var command = new CreateHotstringCommand("btw", "by the way");
        await handler.Handle(command, CancellationToken.None);

        // Act
        var result = await handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
```

### FluentValidation Validator Unit Test

Validators are pure functions — no database needed.

```csharp
// tests/AHKFlowApp.Application.Tests/Commands/CreateHotstringValidatorTests.cs
public sealed class CreateHotstringValidatorTests
{
    private readonly CreateHotstringValidator _validator = new();

    [Fact]
    public async Task Validate_ValidCommand_PassesValidation()
    {
        // Arrange
        var command = new CreateHotstringCommand("btw", "by the way");

        // Act
        var result = await _validator.ValidateAsync(command);

        // Assert
        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("", "by the way")]
    [InlineData("btw", "")]
    public async Task Validate_InvalidFields_FailsValidation(string trigger, string replacement)
    {
        // Arrange
        var command = new CreateHotstringCommand(trigger, replacement);

        // Act
        var result = await _validator.ValidateAsync(command);

        // Assert
        result.IsValid.Should().BeFalse();
    }
}
```

### Ardalis.Result Assertions

```csharp
// Success
result.IsSuccess.Should().BeTrue();
result.Value.Should().NotBeNull();
result.Value.Trigger.Should().Be("btw");

// Not found
result.IsSuccess.Should().BeFalse();
result.Status.Should().Be(ResultStatus.NotFound);

// Invalid (validation failure)
result.Status.Should().Be(ResultStatus.Invalid);
result.ValidationErrors.Should().NotBeEmpty();

// Conflict
result.Status.Should().Be(ResultStatus.Conflict);
```

### Shared Fixture for Expensive Setup

Use `IClassFixture<T>` when multiple test classes share the same database container.

```csharp
[Collection("ApiTests")]
public sealed class HotstringsControllerTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    // fixture is shared — container starts once per test class
}
```

### Testing Time-Dependent Code

```csharp
[Fact]
public async Task Handle_SetsCreatedAt()
{
    // Arrange
    var clock = new FakeTimeProvider(new DateTimeOffset(2025, 1, 15, 0, 0, 0, TimeSpan.Zero));
    var handler = new CreateHotstringHandler(_db, clock);
    var command = new CreateHotstringCommand("btw", "by the way");

    // Act
    var result = await handler.Handle(command, CancellationToken.None);

    // Assert
    result.IsSuccess.Should().BeTrue();
    result.Value.CreatedAt.Should().Be(clock.GetUtcNow());
}
```

## Test Naming Convention

Pattern: `MethodName_Scenario_ExpectedResult`

```csharp
[Fact] public async Task Create_ValidRequest_Returns201() { }
[Fact] public async Task Create_EmptyTrigger_Returns400() { }
[Fact] public async Task GetById_HotstringExists_Returns200() { }
[Fact] public async Task GetById_NotFound_Returns404() { }
[Fact] public async Task Handle_DuplicateTrigger_ReturnsConflict() { }
[Fact] public async Task Validate_EmptyTrigger_FailsValidation() { }
```

## Anti-patterns

### Don't Use In-Memory Database

```csharp
// BAD — hides real SQL Server behavior, transactions, constraints
services.AddDbContext<AppDbContext>(options =>
    options.UseInMemoryDatabase("TestDb"));

// GOOD — Testcontainers with real SQL Server
services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(_mssql.GetConnectionString()));
```

### Don't Mock What You Own

```csharp
// BAD — mocking AppDbContext (you own it)
var mockDb = Substitute.For<AppDbContext>();

// GOOD — use real DbContext against Testcontainers SQL Server
var db = new AppDbContext(options);
```

### Don't Test Implementation Details

```csharp
// BAD — verifying method calls
mockMediator.Received(1).Send(Arg.Any<CreateHotstringCommand>(), Arg.Any<CancellationToken>());

// GOOD — assert on observable outcome
response.StatusCode.Should().Be(HttpStatusCode.Created);
var persisted = await db.Hotstrings.FirstOrDefaultAsync(h => h.Trigger == "btw");
persisted.Should().NotBeNull();
```

### Don't Use PostgreSQL Testcontainers

```csharp
// BAD — wrong database for this project
private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder().Build();

// GOOD — SQL Server
private readonly MsSqlContainer _mssql = new MsSqlBuilder().Build();
```

## Decision Guide

| Scenario | Recommendation |
|---|---|
| Testing an API endpoint | `WebApplicationFactory` + `MsSqlContainer` integration test |
| Testing a handler | Real `AppDbContext` + `MsSqlContainer` |
| Testing a validator | Unit test — no database needed |
| Testing domain entity logic | Unit test — pure C# |
| Database-dependent tests | `Testcontainers.MsSql` — never in-memory |
| Time-dependent logic | `FakeTimeProvider` from `Microsoft.Extensions.TimeProvider.Testing` |
| Shared expensive fixture | `IClassFixture<T>` with `IAsyncLifetime` |
| Asserting Result outcomes | `result.IsSuccess.Should().BeTrue()`, `result.Status.Should().Be(ResultStatus.NotFound)` |
| Parameterized cases | `[Theory]` with `[InlineData]` |
