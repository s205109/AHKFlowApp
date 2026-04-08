# Design: API Health Checks and Problem Details (RFC 9457)

**Backlog item:** 008
**Date:** 2026-04-08

---

## Prerequisites

Create the feature branch from the current 007 branch (which is not yet merged):

```bash
git checkout feature/007-database-foundation-ef-core
git checkout -b feature/008-api-health-checks-problem-details
```

---

## Context

Most of the 008 acceptance criteria are already partially implemented in the 007 branch. This work closes the remaining gaps:

| Criterion | Current state | Gap |
|---|---|---|
| Health endpoints + DB check | ✅ `HealthController` + `AddDbContextCheck<AppDbContext>` + plain `/health` | None |
| Swagger in development | 🟡 Enabled in all environments | Restrict to dev only |
| RFC 9457 Problem Details | 🟡 Custom middleware writes `application/problem+json` but bypasses built-in `IProblemDetailsService` | No `traceId`; no 422 for model-binding errors |
| Integration tests | 🟡 Health + middleware tests exist | Missing 422 test; missing `traceId` assertions; missing `errors` assertion on 400 |

---

## Architecture

### Problem Details — Three Layers

```
Error source                    Handler                                  Result
────────────────────────────────────────────────────────────────────────────────────
ValidationException             GlobalExceptionMiddleware                400 + errors dict
Unhandled exception             GlobalExceptionMiddleware                500
Model-binding failure           InvalidModelStateResponseFactory         422 + errors dict
────────────────────────────────────────────────────────────────────────────────────
All of the above                AddProblemDetails CustomizeProblemDetails → adds traceId
```

### `traceId` strategy

`AddProblemDetails(options => options.CustomizeProblemDetails = ...)` is the **sole** source of `traceId` for responses that go through `IProblemDetailsService.WriteAsync`. The customizer **adds** to the existing `Extensions` dictionary — it does not replace it. `errors` and `traceId` coexist safely in the 400 response.

- `GlobalExceptionMiddleware` calls `IProblemDetailsService.WriteAsync(...)` which triggers the customizer. Do **not** also set `traceId` manually in the middleware's Extensions.
- `InvalidModelStateResponseFactory` returns an `IActionResult` directly (bypassing `IProblemDetailsService`), so `traceId` is set manually via `context.HttpContext.TraceIdentifier`.

### `HasStarted` guard

Add `if (context.Response.HasStarted) { throw; }` at the start of **both** catch blocks (`ValidationException` and `Exception`).

When `context.Response.HasStarted` is true, headers are already flushed to the client. Writing a problem details body at this point would produce a malformed response. Re-throwing exits the middleware pipeline entirely; ASP.NET Core will abort the connection. This is intentional — there is nothing better to do. In practice this edge case only occurs with streaming responses, which this API does not currently use.

Note: C# catch blocks are sibling scopes — re-throwing inside `catch (ValidationException)` does **not** get caught by the sibling `catch (Exception)` block. The re-throw propagates to the calling middleware frame.

### `UseExceptionHandler` — not used

`AddProblemDetails` alone does not add exception-handling middleware. Do **not** add `app.UseExceptionHandler()` — it would conflict with `GlobalExceptionMiddleware`.

---

## Components

### 1. `Program.cs` — New registrations

`AddProblemDetails` must be called before `builder.Build()`. Register it before `AddControllers`:

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

### 2. `Program.cs` — Swagger restricted to development

The guards belong in `Program.cs`. The `AddSwaggerDocs()` and `UseSwaggerDocs()` extension methods in `ApiExtensions.cs` are unchanged.

```csharp
// In the builder section — replace the existing unconditional AddSwaggerDocs() call:
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSwaggerDocs();
}
```

In the middleware pipeline, keep `UseSwaggerDocs()` at its current position (after `UseMiddleware<GlobalExceptionMiddleware>()`). Wrap it and the root-redirect block in an environment guard, replacing both existing unconditional blocks:

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseSwaggerDocs();   // keep at same pipeline position, just wrap it
    app.Use(async (context, next) =>
    {
        if (context.Request.Path == "/") { context.Response.Redirect("/swagger"); return; }
        await next(context);
    });
}
```

**Important:** Delete the two existing unconditional blocks — do not leave them alongside the new guarded versions.

### 3. `GlobalExceptionMiddleware` — Use `IProblemDetailsService`

**New using directive required:** `using Microsoft.AspNetCore.Http;` (for `ProblemDetailsContext`; it is in the `Microsoft.AspNetCore.Http` namespace, not `Microsoft.AspNetCore.Mvc`).

**Constructor:** add `IProblemDetailsService problemDetailsService` parameter.

**Response writing:** replace both `WriteAsJsonAsync` calls with `problemDetailsService.WriteAsync(...)`. `WriteAsync` sets `context.Response.StatusCode` from `ProblemDetails.Status` — the pre-assignment before the call is redundant but serves as a clear marker before the `HasStarted` guard, so keep it.

Preserve the `logger.LogError` call in the `Exception` catch block — do not remove it.

Do **not** set `traceId` in the Extensions — the `CustomizeProblemDetails` callback adds it automatically.

```csharp
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
                    .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray())
            }
        }
    });
}
catch (Exception ex)
{
    if (context.Response.HasStarted) throw;

    logger.LogError(ex, "Unhandled exception");   // preserve existing log call
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
```

---

## Error Response Shapes

### 400 — Validation (FluentValidation pipeline)

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1",
  "title": "Validation failed",
  "status": 400,
  "detail": "Name is required; Email is invalid",
  "instance": "/api/v1/hotstrings",
  "errors": {
    "Name": ["Name is required"],
    "Email": ["Email is invalid"]
  },
  "traceId": "00-abc123..."
}
```

Note: after `ReadFromJsonAsync<ProblemDetails>`, `Extensions["errors"]` is a `JsonElement`. Assert the key exists; cast to `JsonElement` if asserting the contents.

### 422 — Model-binding failure (`[ApiController]`)

```json
{
  "title": "One or more validation errors occurred.",
  "status": 422,
  "detail": "See the errors field for details.",
  "instance": "/api/v1/hotstrings",
  "errors": {
    "Name": ["The Name field is required."]
  },
  "traceId": "00-abc123..."
}
```

Note: the `type` field is set by the framework. Do not assert its exact value in tests. `errors` is a top-level property on `ValidationProblemDetails` (`body.Errors`), not inside `Extensions`.

### 500 — Unhandled exception

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.6.1",
  "title": "An unexpected error occurred",
  "status": 500,
  "instance": "/api/v1/hotstrings",
  "traceId": "00-abc123..."
}
```

---

## Testing

### Existing tests — updates to `GlobalExceptionMiddlewareTests`

Each test method builds its own isolated factory via `WithWebHostBuilder`. The stripped-down pipeline needs `AddProblemDetails` **with the customizer** so `IProblemDetailsService` resolves and `traceId` is populated:

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

Add assertions to both tests:

```csharp
problem!.Extensions.Should().ContainKey("traceId");
problem.Extensions["traceId"].Should().NotBeNull();

// 400 test only:
problem.Extensions.Should().ContainKey("errors");
```

### New test class — `ValidationProblemDetailsTests`

**Do not** use the stripped-down pipeline pattern from `GlobalExceptionMiddlewareTests` — that bypasses MVC entirely; `InvalidModelStateResponseFactory` is never invoked.

Use the real application factory. Follow the same class structure as `HealthControllerTests` — class-level `CustomWebApplicationFactory` field, `IDisposable`, `Dispose()` calls `_factory.Dispose()`.

Register a test controller via `AddApplicationPart` using `WithWebHostBuilder`:

```csharp
private readonly CustomWebApplicationFactory _factory;

public ValidationProblemDetailsTests(SqlContainerFixture sqlFixture)
{
    _factory = new CustomWebApplicationFactory(sqlFixture)
        .WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
                services.AddControllers()
                        .AddApplicationPart(typeof(ValidationProblemDetailsTests).Assembly)));
}
```

The test controller is an `internal` nested class in the test file (must be at least `internal` for MVC reflection-based discovery — `private` is not visible to the framework):

```csharp
// Required using: System.ComponentModel.DataAnnotations
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

Send a POST with `Content-Type: application/json` and body `{}` (valid JSON but missing the required `Name` field). This triggers `[Required]` validation with `errors` keyed to `Name`.

```csharp
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
    body.Errors.Should().ContainKey("Name");             // top-level .Errors, not .Extensions
    body.Extensions.Should().ContainKey("traceId");
    body.Extensions["traceId"].Should().NotBeNull();
}
```

---

## Definition of Done

- [ ] Swagger enabled in development only; non-dev environments return 404 for `/swagger`
- [ ] `GlobalExceptionMiddleware` uses `IProblemDetailsService.WriteAsync`; all problem details responses include `traceId`
- [ ] Model-binding failures return 422 `ValidationProblemDetails` with `traceId`
- [ ] All existing tests pass
- [ ] New `ValidationProblemDetailsTests.Post_WhenRequiredFieldMissing_Returns422WithValidationProblemDetails` passes
- [ ] `traceId` assertions added to both `GlobalExceptionMiddlewareTests` tests

---

## Out of Scope

- Advanced observability integrations
- `UseStatusCodePages` / `UseStatusCodePagesWithReExecution` — can conflict with `GlobalExceptionMiddleware` (response already started). Do not add without understanding the interaction.
- Authentication error shapes (backlog item 012)
