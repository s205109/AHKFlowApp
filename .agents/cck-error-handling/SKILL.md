---
name: cck-error-handling
description: >
  Error handling strategy for AHKFlowApp (.NET 10). Covers Ardalis.Result for typed
  outcomes, MediatR ValidationBehavior pipeline, GlobalExceptionMiddleware,
  ProblemDetails (RFC 9457), and controller mapping via ToActionResult().
  Load when: "error handling", "Result pattern", "Ardalis.Result", "ProblemDetails",
  "exception", "validation", "FluentValidation", "error response",
  "global exception handler", "RFC 9457", "ValidationBehavior".
---

# Error Handling

## Core Principles

1. **Ardalis.Result for expected failures** — Handlers return `Result<T>`. Never throw exceptions for not-found, validation, or conflict. These are expected outcomes.
2. **FluentValidation in MediatR pipeline** — `ValidationBehavior<TRequest, TResponse>` runs before every handler. Handlers never receive invalid requests.
3. **Controllers map via `result.ToActionResult(this)`** — From `Ardalis.Result.AspNetCore`. No manual if/else status code mapping.
4. **Every API error returns ProblemDetails** — RFC 9457. `GlobalExceptionMiddleware` handles unhandled exceptions.
5. **Reserve exceptions for unexpected failures** — Infrastructure errors, null reference bugs, network timeouts. These propagate to the global handler.

## Patterns

### Ardalis.Result in Handlers

Use typed factory methods: `Result.Success(value)`, `Result.NotFound()`, `Result.Invalid(errors)`, `Result.Conflict()`, `Result.Error()`.

```csharp
// Application/Queries/GetHotstringHandler.cs
internal sealed class GetHotstringHandler(AppDbContext db)
    : IRequestHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(
        GetHotstringQuery request, CancellationToken ct)
    {
        var entity = await db.Hotstrings.FindAsync([request.Id], ct);
        return entity is not null
            ? Result.Success(new HotstringDto(entity.Id, entity.Trigger, entity.Replacement))
            : Result.NotFound();
    }
}
```

```csharp
// Application/Commands/CreateHotstringHandler.cs
internal sealed class CreateHotstringHandler(AppDbContext db)
    : IRequestHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(
        CreateHotstringCommand request, CancellationToken ct)
    {
        var exists = await db.Hotstrings.AnyAsync(h => h.Trigger == request.Trigger, ct);
        if (exists) return Result.Conflict();

        var hotstring = new Hotstring { Trigger = request.Trigger, Replacement = request.Replacement };
        db.Hotstrings.Add(hotstring);
        await db.SaveChangesAsync(ct);
        return Result.Success(new HotstringDto(hotstring.Id, hotstring.Trigger, hotstring.Replacement));
    }
}
```

### Controller Mapping with ToActionResult

```csharp
// API/Controllers/HotstringsController.cs
[ApiController]
[Route("api/v1/[controller]")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase
{
    [HttpGet("{id:int}")]
    [ProducesResponseType<HotstringDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(int id, CancellationToken ct)
    {
        var result = await mediator.Send(new GetHotstringQuery(id), ct);
        return result.ToActionResult(this);  // maps Result status to HTTP automatically
    }
}
```

`ToActionResult(this)` maps:
- `Result.Success(value)` → 200 OK (or 201 Created for POST)
- `Result.NotFound()` → 404
- `Result.Invalid(errors)` → 400 with validation errors
- `Result.Conflict()` → 409
- `Result.Error()` → 500

### MediatR ValidationBehavior Pipeline

```csharp
// Application/Behaviors/ValidationBehavior.cs
public sealed class ValidationBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
    where TResponse : Ardalis.Result.IResult
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!validators.Any()) return await next();

        var context = new ValidationContext<TRequest>(request);
        var failures = (await Task.WhenAll(
            validators.Select(v => v.ValidateAsync(context, ct))))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count != 0)
        {
            var errors = failures.Select(f =>
                new ValidationError(f.PropertyName, f.ErrorMessage, f.ErrorCode, ValidationSeverity.Error));
            return (dynamic)Result.Invalid(errors.ToList());
        }

        return await next();
    }
}
```

Register in DI:

```csharp
// Program.cs or DI extension
services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(typeof(CreateHotstringCommand).Assembly);
    cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
});
services.AddValidatorsFromAssembly(typeof(CreateHotstringValidator).Assembly);
```

### FluentValidation Validator

```csharp
// Application/Commands/CreateHotstringValidator.cs
public sealed class CreateHotstringValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringValidator()
    {
        RuleFor(x => x.Trigger)
            .NotEmpty().WithMessage("Trigger is required")
            .MaximumLength(50).WithMessage("Trigger must be 50 characters or less");

        RuleFor(x => x.Replacement)
            .NotEmpty().WithMessage("Replacement is required")
            .MaximumLength(500).WithMessage("Replacement must be 500 characters or less");
    }
}
```

### GlobalExceptionMiddleware

Catches unexpected exceptions and returns RFC 9457 ProblemDetails.

```csharp
// API/Middleware/GlobalExceptionMiddleware.cs
public sealed class GlobalExceptionMiddleware(RequestDelegate next, ILogger<GlobalExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception for {Method} {Path}",
                context.Request.Method, context.Request.Path);

            var problem = new ProblemDetails
            {
                Title = "An unexpected error occurred",
                Status = StatusCodes.Status500InternalServerError,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.6.1"
            };

            context.Response.StatusCode = problem.Status!.Value;
            context.Response.ContentType = "application/problem+json";
            await context.Response.WriteAsJsonAsync(problem);
        }
    }
}

// Registration in Program.cs
app.UseMiddleware<GlobalExceptionMiddleware>();
```

## Anti-patterns

### Don't Define a Custom Result Class

```csharp
// BAD — rolling your own Result type
public class Result<T>
{
    public bool IsSuccess { get; }
    public T Value { get; }
    public List<string> Errors { get; }
}

// GOOD — use Ardalis.Result package
// dotnet add package Ardalis.Result
// dotnet add package Ardalis.Result.AspNetCore
```

### Don't Use ValidationFilter Endpoint Filter

```csharp
// BAD — ValidationFilter as endpoint filter (Minimal API pattern)
group.MapPost("/", CreateHotstring)
    .AddEndpointFilter<ValidationFilter<CreateHotstringCommand>>();

// GOOD — FluentValidation as MediatR IPipelineBehavior
// ValidationBehavior<TRequest, TResponse> runs automatically for all commands/queries
```

### Don't Manually Map Result to HTTP

```csharp
// BAD — manual if/else status code mapping
var result = await mediator.Send(command, ct);
if (result.IsSuccess) return Ok(result.Value);
if (result.Status == ResultStatus.NotFound) return NotFound();
return BadRequest();

// GOOD — ToActionResult does it automatically
return result.ToActionResult(this);
```

### Don't Throw Exceptions for Flow Control

```csharp
// BAD — exception for expected outcome
var hotstring = await db.Hotstrings.FindAsync(id)
    ?? throw new NotFoundException($"Hotstring {id} not found");

// GOOD — Ardalis.Result
var entity = await db.Hotstrings.FindAsync([id], ct);
return entity is not null ? Result.Success(...) : Result.NotFound();
```

### Don't Return Raw Error Strings from APIs

```csharp
// BAD — inconsistent error format
return BadRequest("Something went wrong");
return BadRequest(new { error = "Invalid input" });

// GOOD — ProblemDetails via ToActionResult (automatic) or GlobalExceptionMiddleware
```

### Don't Catch and Swallow Exceptions

```csharp
// BAD
try { await ProcessAsync(ct); }
catch (Exception) { /* ignore */ }

// GOOD — log and return Result.Error()
try { await ProcessAsync(ct); }
catch (ExternalApiException ex)
{
    logger.LogWarning(ex, "External API failed");
    return Result.Error("External service unavailable");
}
```

## Decision Guide

| Scenario | Approach |
|---|---|
| Entity not found | `Result.NotFound()` |
| Input invalid | `Result.Invalid(errors)` — via ValidationBehavior pipeline |
| Duplicate / conflict | `Result.Conflict()` |
| External service failure | Catch specific exception, return `Result.Error()` |
| Unhandled crash | `GlobalExceptionMiddleware` → ProblemDetails 500 |
| Controller HTTP mapping | `result.ToActionResult(this)` — always |
| Validation runs where | MediatR `IPipelineBehavior` — before handler, never in handler |
