# Design: API Health Checks and Problem Details (RFC 9457)

**Backlog item:** 008
**Branch:** `feature/008-api-health-checks-problem-details` (from `feature/007-database-foundation-ef-core`)
**Date:** 2026-04-08

---

## Context

Most of the 008 acceptance criteria are already partially implemented in the 007 branch. This work closes the remaining gaps:

| Criterion | Current state | Gap |
|---|---|---|
| Health endpoints + DB check | ✅ `HealthController` + `AddDbContextCheck<AppDbContext>` + plain `/health` | None |
| Swagger in development | 🟡 Enabled in all environments | Restrict to dev only |
| RFC 9457 Problem Details | 🟡 Custom middleware writes `application/problem+json` but bypasses built-in `IProblemDetailsService` | No `traceId`; no 422 for model-binding errors |
| Integration tests | 🟡 Health + middleware tests exist | Missing 422 test; missing `traceId` assertions |

---

## Architecture

### Problem Details — Three Layers

```
Error source                    Handler                          Result
─────────────────────────────────────────────────────────────────────────────
ValidationException             GlobalExceptionMiddleware        400 + errors dict
Unhandled exception             GlobalExceptionMiddleware        500
Model-binding failure           InvalidModelStateResponseFactory 422 + errors dict
─────────────────────────────────────────────────────────────────────────────
All of the above                AddProblemDetails CustomizeProblemDetails  → adds traceId
```

The key integration point: `GlobalExceptionMiddleware` injects `IProblemDetailsService` and calls `WriteAsync(new ProblemDetailsContext { ... })` instead of `WriteAsJsonAsync(...)`. This routes all problem details through the built-in customizer, which adds `traceId` automatically.

`InvalidModelStateResponseFactory` bypasses the built-in factory entirely (it returns an `IActionResult` directly), so `traceId` is added manually via `context.HttpContext.TraceIdentifier`.

---

## Components

### 1. `Program.cs` — New registrations

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

```csharp
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSwaggerDocs();
}
// ...
if (app.Environment.IsDevelopment())
{
    app.UseSwaggerDocs();
    app.Use(async (context, next) =>  // root → /swagger redirect
    {
        if (context.Request.Path == "/") { context.Response.Redirect("/swagger"); return; }
        await next(context);
    });
}
```

### 3. `GlobalExceptionMiddleware` — Use `IProblemDetailsService`

**Constructor change:** add `IProblemDetailsService problemDetailsService` parameter.

**Response writing change (both catch blocks):**
```csharp
// Before
await context.Response.WriteAsJsonAsync(new ProblemDetails { ... }, options: null, contentType: "application/problem+json");

// After
context.Response.StatusCode = StatusCodes.Status400BadRequest; // or 500
await problemDetailsService.WriteAsync(new ProblemDetailsContext
{
    HttpContext = context,
    ProblemDetails = new ProblemDetails { ... }  // same fields as before
});
```

`ValidationException` catch block keeps the rich `errors` extension dictionary.
Both responses gain `traceId` automatically via `CustomizeProblemDetails`.

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

### 422 — Model-binding failure (`[ApiController]`)

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.5.21",
  "title": "One or more validation errors occurred.",
  "status": 422,
  "detail": "See the errors field for details.",
  "instance": "/api/v1/hotstrings",
  "errors": {
    "name": ["The name field is required."]
  },
  "traceId": "00-abc123..."
}
```

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

### Existing tests — updates

**`GlobalExceptionMiddlewareTests`:** Add `traceId` assertion to both existing tests:
```csharp
problem!.Extensions.Should().ContainKey("traceId");
problem.Extensions["traceId"].Should().NotBeNull();
```

### New test class — `ValidationProblemDetailsTests`

Uses `WithWebHostBuilder` (same pattern as `GlobalExceptionMiddlewareTests`) with a test controller that declares a required model parameter so model binding fails.

Asserts:
- HTTP 422
- `Content-Type: application/problem+json`
- `title` = "One or more validation errors occurred."
- `errors` field populated (at least one key)
- `traceId` non-null

---

## Out of Scope

- Advanced observability integrations
- `UseStatusCodePagesWithReExecution` for plain 404s (no controller matched)
- Authentication error shapes (backlog item 012)
