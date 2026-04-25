# Plan: 006 - Add Serilog Structured Logging

## Context

The API currently uses only the default ASP.NET Core `Microsoft.Extensions.Logging` abstraction with no structured logging provider. Backlog item 006 requires adding Serilog to support diagnostics and operations: structured HTTP request logs, per-environment log level configuration, and a foundation for future Application Insights integration (backlog 011).

---

## Approach

Mirror the old project reference pattern: two-stage bootstrap initialization, `AddSerilog()` with `ReadFrom.Configuration()`, `UseSerilogRequestLogging()` middleware, and Serilog config in `appsettings.json`.

TDD: write a failing integration test first, then implement until it passes.

---

## Steps

### 1. Create feature branch

```bash
git checkout -b feature/006-add-logging-serilog
```

### 2. Add packages (no version — CPM resolves latest stable)

```bash
dotnet add src/Backend/AHKFlowApp.API package Serilog.AspNetCore
dotnet add src/Backend/AHKFlowApp.API package Serilog.Sinks.File
dotnet add tests/AHKFlowApp.API.Tests package Serilog.Sinks.InMemory
```

`Serilog.AspNetCore` already pulls in `Serilog.Sinks.Console`. `Serilog.Sinks.InMemory` is used only in tests to capture log events.

Move all three resolved versions into `Directory.Packages.props` and remove `Version=` from `.csproj` entries (CPM rule).

### 3. Write failing integration test (TDD red)

**File:** `tests/AHKFlowApp.API.Tests/Logging/SerilogRequestLoggingTests.cs`

Using a Serilog `InMemorySink`, register it in `CustomWebApplicationFactory` via `WithWebHostBuilder`, make a GET request to `/api/v1/health`, then assert:

- At least one log event exists with `RequestPath` = `/api/v1/health`
- The event has `StatusCode` = `200`
- The event has an `Elapsed` property (> 0)
- No event contains property names like `Password`, `Token`, or `Secret`

This test will fail until `UseSerilogRequestLogging` is added.

### 4. Implement Serilog in Program.cs

**File:** `src/Backend/AHKFlowApp.API/Program.cs`

Replace the first line with the bootstrap logger pattern from the skill:

```csharp
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Information)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting AHKFlowApp API");
    var builder = WebApplication.CreateBuilder(args);

    builder.Services.AddSerilog((services, lc) => lc
        .ReadFrom.Configuration(builder.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .Enrich.WithMachineName()
        .Enrich.WithEnvironmentName()
        .Enrich.WithProperty("Application", "AHKFlowApp.API"));

    // ... existing registrations ...

    app.UseSerilogRequestLogging(options =>
    {
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            diagnosticContext.Set("RequestHost", httpContext.Request.Host.Value);
            diagnosticContext.Set("UserAgent", httpContext.Request.Headers.UserAgent.ToString());
        };
    });

    // ... existing middleware ...

    Log.Information("AHKFlowApp API started successfully");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "AHKFlowApp API terminated unexpectedly");
}
finally
{
    await Log.CloseAndFlushAsync();
}
```

`UseSerilogRequestLogging` must be placed **before** `UseRouting`/controller mapping.

### 5. Configure appsettings.json

**File:** `src/Backend/AHKFlowApp.API/appsettings.json`

Replace the `Logging` section with `Serilog`:

```json
"Serilog": {
  "MinimumLevel": {
    "Default": "Warning",
    "Override": {
      "AHKFlowApp": "Information",
      "Microsoft.Hosting.Lifetime": "Information",
      "Microsoft": "Warning",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore": "Warning",
      "System": "Warning"
    }
  },
  "WriteTo": [
    {
      "Name": "Console",
      "Args": {
        "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}"
      }
    },
    {
      "Name": "File",
      "Args": {
        "path": "logs/ahkflowapp.api-.log",
        "rollingInterval": "Day",
        "retainedFileCountLimit": 30,
        "fileSizeLimitBytes": 104857600
      }
    }
  ],
  "Enrich": ["FromLogContext", "WithMachineName", "WithEnvironmentName"],
  "Properties": {
    "Application": "AHKFlowApp.API"
  }
}
```

### 6. Configure appsettings.Development.json

More verbose in dev — `AHKFlowApp` namespace at `Debug`, default at `Information`:

```json
"Serilog": {
  "MinimumLevel": {
    "Default": "Information",
    "Override": {
      "AHKFlowApp": "Debug",
      "Microsoft.Hosting.Lifetime": "Information",
      "Microsoft": "Warning",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore": "Warning",
      "System": "Warning"
    }
  }
}
```

(WriteTo and Enrich are inherited from base appsettings.)

### 7. Verify test passes + run full suite

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release
dotnet build --configuration Release
dotnet test --configuration Release
```

---

## Critical Files

| File | Change |
|---|---|
| `Directory.Packages.props` | Add Serilog package versions |
| `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj` | Add Serilog package refs (no version) |
| `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj` | Add Serilog.Sinks.InMemory ref |
| `src/Backend/AHKFlowApp.API/Program.cs` | Two-stage bootstrap + AddSerilog + UseSerilogRequestLogging |
| `src/Backend/AHKFlowApp.API/appsettings.json` | Replace Logging section with Serilog config |
| `src/Backend/AHKFlowApp.API/appsettings.Development.json` | Add Serilog dev overrides |
| `tests/AHKFlowApp.API.Tests/Logging/SerilogRequestLoggingTests.cs` | New: integration test for request logging |

---

## Verification

1. `dotnet build --configuration Release` — no warnings or errors
2. `dotnet test tests/AHKFlowApp.API.Tests` — all tests pass including new logging test
3. `dotnet test --configuration Release` — full suite green
4. Run `dotnet run --project src/Backend/AHKFlowApp.API` and inspect console: should see `[HH:mm:ss INF]` format with request log lines after hitting `/api/v1/health`
5. Check `logs/` folder for rolled log file after first request

---

## Unresolved questions

None.
