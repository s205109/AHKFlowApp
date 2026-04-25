# Fix Fullstack Launch Profiles with ApiBaseUrlResolver

## Context

The fullstack VS Code launch profiles ("Full Stack: https + Docker SQL" and "Full Stack: https + LocalDB SQL") don't work because:

1. **No CORS** — Backend at `https://localhost:7600` has zero CORS config, so the Blazor frontend at `https://localhost:7601` gets blocked by browser same-origin policy.
2. **Hardcoded API URL** — Frontend `appsettings.json` pins `"ApiBaseUrl": "https://localhost:7600"`. No auto-discovery for Docker Compose (`5602`) or Docker-only (`5604`) profiles.
3. **No ApiBaseUrlResolver** — The old project had smart endpoint probing; the new project lacks it.

## Plan

### Step 1: Add CORS to Backend

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` — add `AddConfiguredCors()` extension
- Modify: `src/Backend/AHKFlowApp.API/Program.cs` — wire CORS services + middleware
- Modify: `src/Backend/AHKFlowApp.API/appsettings.json` — add empty `Cors:AllowedOrigins`
- Modify: `src/Backend/AHKFlowApp.API/appsettings.Development.json` — add frontend origins `["https://localhost:7601", "http://localhost:5601"]`

Pattern from old project (`old_project_reference/AHKFlow/src/Backend/AHKFlow.API/Extensions/ApiExtensions.cs`):
```csharp
internal static IServiceCollection AddConfiguredCors(
    this IServiceCollection services, string[] allowedOrigins, string policyName)
{
    return services.AddCors(options =>
        options.AddPolicy(policyName, policy =>
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyMethod()
                  .AllowAnyHeader()
                  .AllowCredentials()));
}
```

In `Program.cs`, add before `Build()`:
```csharp
const string corsPolicyName = "AllowConfiguredOrigins";
string[] allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddConfiguredCors(allowedOrigins, corsPolicyName);
```

In middleware pipeline (after `UseHttpsRedirection`, before `UseAuthorization`):
```csharp
if (allowedOrigins.Length > 0)
{
    app.UseCors(corsPolicyName);
}
```

### Step 2: Port ApiBaseUrlResolver to Frontend

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiBaseUrlResolver.cs`

Adapted from `old_project_reference/AHKFlow/src/Frontend/AHKFlow.UI.Blazor/Services/ApiBaseUrlResolver.cs` with these changes:
- Probe `/api/v1/health` instead of `/api/v1/version` (health endpoint exists, version doesn't)
- Keep the same auto-detection logic: build candidates, order by host scheme, probe each with 2s timeout
- Use `Console.WriteLine` instead of `Serilog.Log` (Blazor WASM uses browser console)

### Step 3: Update Frontend Configuration

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json` — change to `ApiHttpClient` section with `BaseAddress` and `BaseAddressCandidates`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json` — dev-specific candidates

Production `appsettings.json`:
```json
{
  "ApiHttpClient": {
    "BaseAddress": "https://localhost:7600"
  }
}
```

Development `appsettings.Development.json`:
```json
{
  "ApiHttpClient": {
    "BaseAddress": "https://localhost:7600",
    "BaseAddressCandidates": [
      "https://localhost:7600",
      "http://localhost:5600",
      "http://localhost:5602",
      "http://localhost:5604"
    ]
  }
}
```

### Step 4: Update Frontend Program.cs

**File:** `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

Replace hardcoded URL with resolver call:
```csharp
string apiBaseUrl = await ApiBaseUrlResolver.ResolveAsync(
    builder.HostEnvironment.BaseAddress,
    builder.Configuration["ApiHttpClient:BaseAddress"],
    builder.Configuration.GetSection("ApiHttpClient:BaseAddressCandidates").Get<string[]>());

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
}).AddStandardResilienceHandler();
```

### Step 5: Verify with Playwright CLI

Playwright is installed (v1.59.1). Test plan:

1. Start API with LocalDB profile: `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + LocalDB SQL"`
2. Start frontend: `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor --launch-profile "https"`
3. Use Playwright to navigate to `https://localhost:7601/health` and verify health data loads (no CORS errors, API auto-detected)
4. Stop both, repeat with Docker SQL profile if Docker is available

### Step 6: Build + Test

- `dotnet build --configuration Release`
- `dotnet test --configuration Release --verbosity normal`

## Critical Files

| File | Action |
|------|--------|
| `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` | Add `AddConfiguredCors()` |
| `src/Backend/AHKFlowApp.API/Program.cs` | Wire CORS |
| `src/Backend/AHKFlowApp.API/appsettings.json` | Add `Cors:AllowedOrigins: []` |
| `src/Backend/AHKFlowApp.API/appsettings.Development.json` | Add frontend origins |
| `src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiBaseUrlResolver.cs` | Create (port from old project) |
| `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json` | Restructure to `ApiHttpClient` |
| `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json` | Create with candidates |
| `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` | Use resolver |

## Unresolved Questions

- Docker SQL available on your machine right now? (determines which fullstack profile I test with Playwright)
- Should production `appsettings.json` have a real Azure API URL for `BaseAddress`, or leave as localhost for now?
