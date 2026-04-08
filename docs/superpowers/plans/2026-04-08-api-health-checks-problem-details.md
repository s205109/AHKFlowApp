# API Health Checks and Problem Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining 008 gaps — RFC 9457 Problem Details with `traceId`, 422 model-binding errors, and Swagger restricted to development.

**Architecture:** `AddProblemDetails` registers `IProblemDetailsService` and a `CustomizeProblemDetails` callback that injects `traceId` into every response going through `WriteAsync`. `GlobalExceptionMiddleware` is refactored to use `IProblemDetailsService.WriteAsync` instead of raw `WriteAsJsonAsync`. Model-binding failures are handled by `ConfigureApiBehaviorOptions.InvalidModelStateResponseFactory`, which sets `traceId` manually (it bypasses `IProblemDetailsService`). Swagger is wrapped in `IsDevelopment()` guards in `Program.cs`.

**Tech Stack:** ASP.NET Core 10, `IProblemDetailsService`, `ProblemDetailsContext`, `ValidationProblemDetails`, xUnit, FluentAssertions, Testcontainers (SQL Server), `CustomWebApplicationFactory`.

**Spec:** `docs/superpowers/specs/2026-04-08-api-health-checks-problem-details-design.md`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `src/Backend/AHKFlowApp.API/Program.cs` | Modify | Add `AddProblemDetails`, `ConfigureApiBehaviorOptions`, wrap Swagger in dev guards |
| `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs` | Modify | Inject `IProblemDetailsService`, add `HasStarted` guard, use `WriteAsync` |
| `tests/AHKFlowApp.API.Tests/Middleware/GlobalExceptionMiddlewareTests.cs` | Modify | Add `AddProblemDetails` to each test's `ConfigureServices`, add `traceId`/`errors` assertions |
| `tests/AHKFlowApp.API.Tests/Middleware/ValidationProblemDetailsTests.cs` | Create | New test class for 422 model-binding errors |

---

## Task 1: Create feature branch

- [ ] **Step 1: Create and checkout the feature branch**

```bash
git checkout -b feature/008-api-health-checks-problem-details
```

Expected: `Switched to a new branch 'feature/008-api-health-checks-problem-details'`

---

## Task 2: Update `GlobalExceptionMiddlewareTests` — add failing assertions

The existing tests pass but lack `traceId` and `errors` assertions, and `IProblemDetailsService` is not registered in the stripped-down test pipeline. Add both now so the tests fail, driving the middleware refactor in Task 3.

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/Middleware/GlobalExceptionMiddlewareTests.cs`

- [ ] **Step 1: Add `AddProblemDetails` to the 400 test's `ConfigureServices`**

In `Middleware_WhenValidationExceptionThrown_Returns400ProblemDetails`, change:

```csharp
builder.ConfigureServices(services =>
{
    services.AddRouting();
    services.AddLogging();
});
```

to:

```csharp
builder.ConfigureServices(services =>
{
    services.AddRouting();
    services.AddLogging();
    services.AddProblemDetails(options =>
        options.CustomizeProblemDetails = ctx =>
            ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);
});
```

- [ ] **Step 2: Add `traceId` and `errors` assertions to the 400 test**

After the existing assertions (`problem.Title.Should().Be("Validation failed")`), add:

```csharp
problem!.Extensions.Should().ContainKey("errors");
problem.Extensions.Should().ContainKey("traceId");
problem.Extensions["traceId"].Should().NotBeNull();
```

- [ ] **Step 3: Add `AddProblemDetails` to the 500 test's `ConfigureServices`**

In `Middleware_WhenUnhandledExceptionThrown_Returns500ProblemDetails`, apply the same `ConfigureServices` change as Step 1.

- [ ] **Step 4: Add `traceId` assertion to the 500 test**

After the existing assertions (`problem.Title.Should().Be("An unexpected error occurred")`), add:

```csharp
problem!.Extensions.Should().ContainKey("traceId");
problem.Extensions["traceId"].Should().NotBeNull();
```

- [ ] **Step 5: Run middleware tests — expect FAIL**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~GlobalExceptionMiddlewareTests" --configuration Release --verbosity normal
```

Expected: both tests fail — the old `WriteAsJsonAsync` doesn't trigger `CustomizeProblemDetails`, so `traceId` is never set.

---

## Task 3: Refactor `GlobalExceptionMiddleware` to use `IProblemDetailsService`

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs`

- [ ] **Step 1: Replace the file contents**

```csharp
using FluentValidation;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace AHKFlowApp.API.Middleware;

internal sealed class GlobalExceptionMiddleware(
    RequestDelegate next,
    ILogger<GlobalExceptionMiddleware> logger,
    IProblemDetailsService problemDetailsService)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (ValidationException ex)
        {
            if (context.Response.HasStarted) throw;

            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await problemDetailsService.WriteAsync(new ProblemDetailsContext
            {
                HttpContext = context,
                ProblemDetails = new ProblemDetails
                {
                    Type = "https://tools.ietf.org/html/rfc9110#section-15.5.1",
                    Title = "Validation failed",
                    Status = StatusCodes.Status400BadRequest,
                    Detail = string.Join("; ", ex.Errors.Select(e => e.ErrorMessage)),
                    Instance = context.Request.Path,
                    Extensions =
                    {
                        ["errors"] = ex.Errors
                            .GroupBy(e => e.PropertyName)
                            .ToDictionary(
                                g => g.Key,
                                g => g.Select(e => e.ErrorMessage).ToArray())
                    }
                }
            });
        }
        catch (Exception ex)
        {
            if (context.Response.HasStarted) throw;

            logger.LogError(ex, "Unhandled exception");
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            await problemDetailsService.WriteAsync(new ProblemDetailsContext
            {
                HttpContext = context,
                ProblemDetails = new ProblemDetails
                {
                    Type = "https://tools.ietf.org/html/rfc9110#section-15.6.1",
                    Title = "An unexpected error occurred",
                    Status = StatusCodes.Status500InternalServerError,
                    Instance = context.Request.Path
                }
            });
        }
    }
}
```

- [ ] **Step 2: Run middleware tests — expect PASS**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~GlobalExceptionMiddlewareTests" --configuration Release --verbosity normal
```

Expected: both tests pass.

- [ ] **Step 3: Run full suite — confirm no regressions**

```bash
dotnet test --configuration Release --verbosity normal
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs tests/AHKFlowApp.API.Tests/Middleware/GlobalExceptionMiddlewareTests.cs
git commit -m "refactor: use IProblemDetailsService in GlobalExceptionMiddleware; add traceId/errors assertions"
```

---

## Task 4: Write `ValidationProblemDetailsTests` — failing test for 422

**Files:**
- Create: `tests/AHKFlowApp.API.Tests/Middleware/ValidationProblemDetailsTests.cs`

- [ ] **Step 1: Create the test file**

Note: the field-initializer form is used here (same as `HealthControllerTests`). C# 12 primary constructor parameters are in scope during field initializers, so `sqlFixture` is accessible. Either a field initializer or a constructor body works — field initializer is simpler.

```csharp
using System.ComponentModel.DataAnnotations;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Net.Http.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.API.Tests.Middleware;

[Collection("WebApi")]
public sealed class ValidationProblemDetailsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new CustomWebApplicationFactory(sqlFixture)
        .WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
                services.AddControllers()
                        .AddApplicationPart(typeof(ValidationProblemDetailsTests).Assembly)));

    [Fact]
    public async Task Post_WhenRequiredFieldMissing_Returns422WithValidationProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();
        using var content = new StringContent("{}", Encoding.UTF8, "application/json");

        // Act
        HttpResponseMessage response = await client.PostAsync("/test", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ValidationProblemDetails? body = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        body!.Title.Should().Be("One or more validation errors occurred.");
        body.Errors.Should().ContainKey("Name");
        body.Extensions.Should().ContainKey("traceId");
        body.Extensions["traceId"].Should().NotBeNull();
    }

    public void Dispose() => _factory.Dispose();
}

[ApiController]
[Route("test")]
[AllowAnonymous]
internal sealed class TestModelController : ControllerBase
{
    [HttpPost]
    public IActionResult Post([FromBody] RequiredModel model) => Ok(model);

    public sealed record RequiredModel([Required] string Name);
}
```

- [ ] **Step 2: Run the new test — expect FAIL**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~ValidationProblemDetailsTests" --configuration Release --verbosity normal
```

Expected: test fails with **two** independent failures — the status code assertion (400 vs 422, because `InvalidModelStateResponseFactory` is not yet configured) and the `traceId` assertion (absent, because `AddProblemDetails` is not yet registered in `Program.cs`). Both are resolved together in Task 5.

---

## Task 5: Update `Program.cs` — `AddProblemDetails`, 422 factory, Swagger dev-only

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Program.cs`

Current state for reference:
- Line 40: `builder.Services.AddControllers();`
- Line 42: `builder.Services.AddSwaggerDocs();`
- Line 97: `app.UseSwaggerDocs();` (unconditional)
- Lines 106–114: root-redirect `app.Use(...)` block (unconditional)

- [ ] **Step 1: Replace `AddControllers()` with `AddProblemDetails` + `AddControllers().ConfigureApiBehaviorOptions(...)`**

Replace:
```csharp
builder.Services.AddControllers();
```

with:
```csharp
builder.Services.AddProblemDetails(options =>
    options.CustomizeProblemDetails = ctx =>
        ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);

builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(options =>
        options.InvalidModelStateResponseFactory = ctx =>
        {
            var pd = new ValidationProblemDetails(ctx.ModelState)
            {
                Detail = "See the errors field for details.",
                Instance = ctx.HttpContext.Request.Path,
                Status = StatusCodes.Status422UnprocessableEntity,
                Title = "One or more validation errors occurred."
            };
            pd.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier;
            return new UnprocessableEntityObjectResult(pd)
            {
                ContentTypes = { "application/problem+json" }
            };
        });
```

- [ ] **Step 2: Wrap `AddSwaggerDocs()` in a dev guard**

Replace:
```csharp
builder.Services.AddSwaggerDocs();
```

with:
```csharp
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSwaggerDocs();
}
```

- [ ] **Step 3: Wrap `UseSwaggerDocs()` and the root-redirect block in a dev guard**

Replace the unconditional `app.UseSwaggerDocs();` call and the unconditional root-redirect `app.Use(...)` block with a single dev guard. The result should be:

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseSwaggerDocs();
    app.Use(async (context, next) =>
    {
        if (context.Request.Path == "/") { context.Response.Redirect("/swagger"); return; }
        await next(context);
    });
}

app.UseHttpsRedirection();
```

`UseSwaggerDocs()` stays at the same position in the pipeline (after `GlobalExceptionMiddleware`). Delete both unconditional originals — do not leave them alongside the guarded versions.

- [ ] **Step 4: Build**

```bash
dotnet build --configuration Release
```

Expected: 0 errors, 0 warnings (or only pre-existing warnings).

- [ ] **Step 5: Run all tests — expect all pass**

```bash
dotnet test --configuration Release --verbosity normal
```

Expected: all tests pass, including `ValidationProblemDetailsTests`.

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Program.cs tests/AHKFlowApp.API.Tests/Middleware/ValidationProblemDetailsTests.cs
git commit -m "feat: RFC 9457 problem details with traceId, 422 factory, Swagger dev-only"
```

---

## Definition of Done

- [ ] `GlobalExceptionMiddleware` uses `IProblemDetailsService.WriteAsync`
- [ ] All problem details responses include `traceId`
- [ ] Model-binding failures return 422 `ValidationProblemDetails` with `traceId`
- [ ] Swagger enabled in development only
- [ ] Both `GlobalExceptionMiddlewareTests` pass with `traceId`/`errors` assertions
- [ ] `ValidationProblemDetailsTests.Post_WhenRequiredFieldMissing_Returns422WithValidationProblemDetails` passes
- [ ] Full test suite green
