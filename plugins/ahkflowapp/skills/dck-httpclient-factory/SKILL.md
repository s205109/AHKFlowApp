---
name: dck-httpclient-factory
description: Use when configuring AHKFlowApp HttpClient, IHttpClientFactory, typed clients, handlers, retries, resilience, or external API calls.
---

# HttpClient Factory

## Core Principles

1. **No ad-hoc clients** - Use `IHttpClientFactory` or DI-registered clients instead of `new HttpClient()`.
2. **Resilience on every external client** - Apply `.AddStandardResilienceHandler()` to all outbound HTTP clients.
3. **Handlers for cross-cutting behavior** - Auth, correlation IDs, and logging belong in `DelegatingHandler`s.
4. **CancellationToken everywhere** - Pass the token through every HTTP call.
5. **Controller-based APIs only** - Examples must fit AHKFlowApp controllers and use cases, not Minimal APIs.

## Named Client

```csharp
builder.Services.AddHttpClient("github", client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("AHKFlowApp/1.0");
})
.AddStandardResilienceHandler();
```

```csharp
internal sealed class GitHubReleaseClient(IHttpClientFactory httpClientFactory)
{
    public async Task<ReleaseDto?> GetLatestAsync(CancellationToken cancellationToken)
    {
        var client = httpClientFactory.CreateClient("github");
        return await client.GetFromJsonAsync<ReleaseDto>(
            "repos/owner/repo/releases/latest",
            cancellationToken);
    }
}
```

## Keyed Client in a Controller

```csharp
builder.Services.AddHttpClient("payments", client =>
{
    client.BaseAddress = new Uri("https://api.payments.example/");
})
.AddStandardResilienceHandler()
.AddAsKeyed();
```

```csharp
[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
public sealed class PaymentsController(
    [FromKeyedServices("payments")] HttpClient paymentsClient)
    : ControllerBase
{
    [HttpPost("charge")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status502BadGateway)]
    public async Task<IActionResult> Charge(ChargeRequest request, CancellationToken cancellationToken)
    {
        using var response = await paymentsClient.PostAsJsonAsync("charges", request, cancellationToken);
        return response.IsSuccessStatusCode ? NoContent() : StatusCode(StatusCodes.Status502BadGateway);
    }
}
```

Prefer use-case handlers for business workflows; controller examples only show DI shape.

## Standard Resilience Handler

`AddStandardResilienceHandler()` provides total timeout, attempt timeout, retry, circuit breaker, and rate limiting defaults.

```csharp
builder.Services.AddHttpClient("external-api")
    .AddStandardResilienceHandler(options =>
    {
        options.Retry.MaxRetryAttempts = 3;
        options.Retry.DisableForUnsafeHttpMethods();
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(30);
    });
```

## DelegatingHandler

```csharp
public sealed class CorrelationIdHandler(IHttpContextAccessor accessor) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        if (accessor.HttpContext?.TraceIdentifier is { Length: > 0 } traceId)
        {
            request.Headers.TryAddWithoutValidation("X-Correlation-Id", traceId);
        }

        return base.SendAsync(request, cancellationToken);
    }
}
```

```csharp
builder.Services.AddTransient<CorrelationIdHandler>();
builder.Services.AddHttpClient("external-api")
    .AddHttpMessageHandler<CorrelationIdHandler>()
    .AddStandardResilienceHandler();
```

## Testing

Use a fake `HttpMessageHandler` for code that accepts an `HttpClient`, or register a test client in DI. Do not mock framework-owned `HttpClient` methods.

```csharp
public sealed class StubHttpMessageHandler(HttpResponseMessage response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken) =>
        Task.FromResult(response);
}
```

## Anti-Patterns

- `using var client = new HttpClient()` inside request paths.
- Missing `.AddStandardResilienceHandler()`.
- Mutating `DefaultRequestHeaders.Authorization` per request on a shared client.
- Typed clients captured by singletons without understanding handler lifetime.
- Dropping `CancellationToken`.
- Adding retry around non-idempotent operations without explicitly disabling unsafe-method retries.

## Decision Guide

| Scenario | Pattern |
|---|---|
| One external API | Named or keyed client |
| Auth header | DelegatingHandler |
| Per-request correlation | DelegatingHandler |
| Singleton service | `IHttpClientFactory` or correctly scoped keyed client |
| Non-idempotent POST | Standard resilience with unsafe retries disabled |
