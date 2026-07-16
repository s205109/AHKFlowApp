---
name: dck-serilog
description: Use when configuring AHKFlowApp Serilog, structured logging, sinks, enrichers, request logging, or Application Insights.
---

# Serilog

## Project Shape

AHKFlowApp already uses two-stage Serilog startup in `src/Backend/AHKFlowApp.API/Program.cs`, `AddSerilog(...)`, `UseSerilogRequestLogging(...)`, console/file sinks, and optional Application Insights when `ApplicationInsights:ConnectionString` is configured.

## Core Principles

1. **Bootstrap early** - Keep `CreateBootstrapLogger()` before building the host.
2. **Use structured templates** - Prefer `{Property}` placeholders over string interpolation.
3. **Configure sinks by environment** - Keep log levels and sinks in `appsettings*.json` or App Service configuration.
4. **Never log secrets** - Tokens, passwords, connection strings, and sensitive user data do not belong in logs.
5. **Flush on exit** - Preserve `Log.CloseAndFlushAsync()`.

## Good Logging

```csharp
logger.LogInformation(
    "Generated AutoHotkey script for profile {ProfileId} with {HotstringCount} hotstrings",
    profileId,
    hotstringCount);
```

For exceptions:

```csharp
logger.LogError(ex, "Failed to generate script for profile {ProfileId}", profileId);
```

## Request Logging

Use `UseSerilogRequestLogging` after exception middleware and before route execution where practical. Enrich with request metadata that is useful and safe:

```csharp
app.UseSerilogRequestLogging(options =>
{
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
    {
        diagnosticContext.Set("RequestHost", httpContext.Request.Host.Value);
        diagnosticContext.Set("UserAgent", httpContext.Request.Headers.UserAgent.ToString());
    };
});
```

## Application Insights

Application Insights is conditional in this repo. Keep the connection string empty for local development and inject it through Azure App Service configuration for TEST/PROD.

Do not upgrade `Microsoft.ApplicationInsights.AspNetCore` to 3.x unless the user explicitly asks; project guidance keeps it on 2.x.

## LogContext

Use `LogContext.PushProperty(...)` for scoped properties that should flow through multiple log events:

```csharp
using (LogContext.PushProperty("OwnerOid", ownerOid))
{
    logger.LogInformation("Importing hotstrings");
}
```

## Anti-Patterns

- `$"User {userId} did X"` instead of `"User {UserId} did X"`.
- Logging access tokens, passwords, full connection strings, or raw auth headers.
- Catching and logging exceptions without adding context or rethrowing appropriately.
- Duplicating request logs with noisy middleware.
- Hardcoding sink endpoints in source code.
- Removing bootstrap logger or final flush.

## Decision Guide

| Scenario | Pattern |
|---|---|
| Startup errors | Bootstrap logger |
| Per-request summary | `UseSerilogRequestLogging` |
| Queryable event data | Message templates |
| TEST/PROD telemetry | App Service config + Application Insights sink |
| Repeated context | `LogContext.PushProperty` |
| Hot path logging | Consider `[LoggerMessage]` |
