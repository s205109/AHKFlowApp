# Scaffold Initial Solution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the complete solution skeleton — Domain, Application, Infrastructure, API, and Blazor WASM frontend — with MudBlazor wired up and all project references configured.

**Architecture:** Clean Architecture (Domain → Application → Infrastructure → API). No test projects (backlog 004), no DB migrations (backlog 007), no Docker (backlog 009). MediatR + Ardalis.Result + FluentValidation installed and wired for future feature work, but no business logic yet.

**Tech Stack:** .NET 10 (`10.0.201`), Blazor WebAssembly PWA, MudBlazor 9.x, ASP.NET Core Web API (controller-based), MediatR, FluentValidation, Ardalis.Result, EF Core + SQL Server.

---

## Files Overview

**Already exists (no action needed):**
- `.editorconfig` — already committed at root; `EnforceCodeStyleInBuild` will use it

**Create:**
- `global.json`
- `Directory.Build.props`
- `Directory.Packages.props`
- `AHKFlowApp.slnx`
- `src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj`
- `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`
- `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`
- `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj`
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`
- `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs`
- `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`
- `src/Backend/AHKFlowApp.API/Program.cs`
- `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs`
- `src/Backend/AHKFlowApp.API/appsettings.json`
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`
- `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj`
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Shared/MainLayout.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Shared/NavMenu.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`

**Modify:**
- `README.md` — add local run section

---

### Task 1: Solution root configuration files

**Files:**
- Create: `global.json`
- Create: `Directory.Build.props`
- Create: `Directory.Packages.props`

- [ ] **Step 1: Create `global.json`**

```json
{
  "sdk": {
    "version": "10.0.201",
    "rollForward": "latestFeature"
  }
}
```

Verify: `dotnet --version` should print `10.0.x`.

- [ ] **Step 2: Create `Directory.Build.props`**

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Create `Directory.Packages.props`** (empty stub; `dotnet add package` will populate it)

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
  </ItemGroup>
</Project>
```

- [ ] **Step 4: Commit**

```bash
git add global.json Directory.Build.props Directory.Packages.props
git commit -m "chore: add solution root build configuration"
```

---

### Task 2: Domain project

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj`
- Create: `src/Backend/AHKFlowApp.Domain/Entities/.gitkeep`

- [ ] **Step 1: Scaffold the project**

```bash
dotnet new classlib -n AHKFlowApp.Domain -o src/Backend/AHKFlowApp.Domain
rm src/Backend/AHKFlowApp.Domain/Class1.cs
mkdir -p src/Backend/AHKFlowApp.Domain/Entities
touch src/Backend/AHKFlowApp.Domain/Entities/.gitkeep
```

- [ ] **Step 2: Strip inherited properties from the .csproj**

The generated file will have `<TargetFramework>`, `<Nullable>`, and `<ImplicitUsings>` which are now inherited from `Directory.Build.props`. Replace the entire file with:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Commit**

```bash
git add src/Backend/AHKFlowApp.Domain/
git commit -m "chore: scaffold Domain project"
```

---

### Task 3: Application project

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`
- Create: `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`
- Create: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`

- [ ] **Step 1: Scaffold the project**

```bash
dotnet new classlib -n AHKFlowApp.Application -o src/Backend/AHKFlowApp.Application
rm src/Backend/AHKFlowApp.Application/Class1.cs
mkdir -p src/Backend/AHKFlowApp.Application/Commands
mkdir -p src/Backend/AHKFlowApp.Application/Queries
mkdir -p src/Backend/AHKFlowApp.Application/DTOs
mkdir -p src/Backend/AHKFlowApp.Application/Behaviors
touch src/Backend/AHKFlowApp.Application/Commands/.gitkeep
touch src/Backend/AHKFlowApp.Application/Queries/.gitkeep
touch src/Backend/AHKFlowApp.Application/DTOs/.gitkeep
```

- [ ] **Step 2: Strip inherited properties and add Domain reference**

Replace `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj` with:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\AHKFlowApp.Domain\AHKFlowApp.Domain.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add packages** (versions are resolved automatically and written to `Directory.Packages.props`)

```bash
cd src/Backend/AHKFlowApp.Application
dotnet add package MediatR
dotnet add package FluentValidation.DependencyInjectionExtensions
dotnet add package Ardalis.Result
cd ../../..
```

- [ ] **Step 4: Create `Behaviors/ValidationBehavior.cs`**

**Design note:** This behavior throws `ValidationException` on failure rather than returning `Result.Invalid()`. Because `TResponse` is generic, returning `Result.Invalid()` directly requires type constraints not feasible here. The throw is intentional — `GlobalExceptionMiddleware` is the app boundary that catches it and converts it to a 400 ProblemDetails response. This is the only place in the codebase where an exception crosses a layer boundary by design.

```csharp
using FluentValidation;
using MediatR;

namespace AHKFlowApp.Application.Behaviors;

// Deliberately throws ValidationException — caught at the app boundary
// in GlobalExceptionMiddleware and converted to 400 ProblemDetails.
// This is NOT flow-control abuse; it is a single structured boundary crossing.
internal sealed class ValidationBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!validators.Any())
            return await next(ct);

        var context = new ValidationContext<TRequest>(request);

        var failures = validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next(ct);
    }
}
```

- [ ] **Step 5: Create `DependencyInjection.cs`**

```csharp
using AHKFlowApp.Application.Behaviors;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(DependencyInjection).Assembly);
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });

        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);

        return services;
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/ Directory.Packages.props
git commit -m "chore: scaffold Application with MediatR, FluentValidation, Ardalis.Result"
```

---

### Task 4: Infrastructure project

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj`
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`
- Create: `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs`

- [ ] **Step 1: Scaffold the project**

```bash
dotnet new classlib -n AHKFlowApp.Infrastructure -o src/Backend/AHKFlowApp.Infrastructure
rm src/Backend/AHKFlowApp.Infrastructure/Class1.cs
mkdir -p src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations
```

- [ ] **Step 2: Strip inherited properties and add project references**

Replace `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj` with:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
  <ItemGroup>
    <!-- Domain is accessible transitively through Application — no direct reference needed -->
    <ProjectReference Include="..\AHKFlowApp.Application\AHKFlowApp.Application.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add EF Core SQL Server package**

```bash
cd src/Backend/AHKFlowApp.Infrastructure
dotnet add package Microsoft.EntityFrameworkCore.SqlServer
cd ../../..
```

- [ ] **Step 4: Create `Persistence/AppDbContext.cs`**

```csharp
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
```

- [ ] **Step 5: Create `DependencyInjection.cs`**

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddDbContext<AppDbContext>(options =>
            options.UseSqlServer(
                configuration.GetConnectionString("DefaultConnection"),
                sql => sql.EnableRetryOnFailure()));

        return services;
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Infrastructure/ Directory.Packages.props
git commit -m "chore: scaffold Infrastructure with EF Core AppDbContext stub"
```

---

### Task 5: API project

**Files:**
- Create: `src/Backend/AHKFlowApp.API/` (via `dotnet new`)
- Create: `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs`
- Modify: `src/Backend/AHKFlowApp.API/Program.cs`
- Modify: `src/Backend/AHKFlowApp.API/appsettings.json`
- Modify: `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`

- [ ] **Step 1: Scaffold the project**

```bash
dotnet new webapi -n AHKFlowApp.API -o src/Backend/AHKFlowApp.API --use-controllers
```

If `--use-controllers` is not valid for .NET 10, check `dotnet new webapi --help` for the correct flag.

**Verify controller output** — after scaffolding, check that a `Controllers/` folder was created:
```bash
ls src/Backend/AHKFlowApp.API/Controllers/
```
If the folder is absent, the template generated a Minimal API skeleton. In that case, create the `Controllers/` folder manually and proceed — Step 5 replaces `Program.cs` entirely regardless.

Remove generated example files:
```bash
rm -f src/Backend/AHKFlowApp.API/Controllers/WeatherForecastController.cs
rm -f src/Backend/AHKFlowApp.API/WeatherForecast.cs
```

- [ ] **Step 2: Strip inherited properties and add project references**

The generated `.csproj` will contain properties now in `Directory.Build.props`. Replace with:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\AHKFlowApp.Application\AHKFlowApp.Application.csproj" />
    <ProjectReference Include="..\AHKFlowApp.Infrastructure\AHKFlowApp.Infrastructure.csproj" />
  </ItemGroup>
</Project>
```

**Note:** If the template added `Swashbuckle.AspNetCore` or `Microsoft.AspNetCore.OpenApi` package references, retain them in the `.csproj` (without the `Version` attribute since CPM is enabled) and add the matching `<PackageVersion>` entries to `Directory.Packages.props`.

- [ ] **Step 3: Add Ardalis.Result.AspNetCore**

```bash
cd src/Backend/AHKFlowApp.API
dotnet add package Ardalis.Result.AspNetCore
cd ../../..
```

- [ ] **Step 4: Create `Middleware/GlobalExceptionMiddleware.cs`**

```bash
mkdir -p src/Backend/AHKFlowApp.API/Middleware
```

```csharp
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

namespace AHKFlowApp.API.Middleware;

internal sealed class GlobalExceptionMiddleware(
    RequestDelegate next,
    ILogger<GlobalExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (ValidationException ex)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            context.Response.ContentType = "application/problem+json";
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Title = "Validation failed",
                Status = StatusCodes.Status400BadRequest,
                Detail = string.Join("; ", ex.Errors.Select(e => e.ErrorMessage)),
                Extensions =
                {
                    ["errors"] = ex.Errors
                        .GroupBy(e => e.PropertyName)
                        .ToDictionary(
                            g => g.Key,
                            g => g.Select(e => e.ErrorMessage).ToArray())
                }
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception");
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/problem+json";
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Title = "An unexpected error occurred",
                Status = StatusCodes.Status500InternalServerError
            });
        }
    }
}
```

- [ ] **Step 5: Write `Program.cs`**

Replace the generated `Program.cs` entirely:

```csharp
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

app.UseMiddleware<GlobalExceptionMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();

public partial class Program { }
```

**Note:** If `AddSwaggerGen`/`UseSwaggerUI` conflict with a different OpenAPI package from the template, check what was generated and adapt accordingly (e.g., Scalar uses `app.MapScalarApiReference()` instead).

**Security placeholder:** Authentication is implemented in backlog 012. Until then, any skeleton controllers created during this scaffold must carry `[AllowAnonymous]` explicitly on the class. Per CLAUDE.md security rules, every controller must have either `[Authorize]` or `[AllowAnonymous]` — never neither.

- [ ] **Step 6: Write `appsettings.json`**

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=AHKFlowApp;Trusted_Connection=True;MultipleActiveResultSets=true"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
```

- [ ] **Step 7: Write `Properties/launchSettings.json`**

```json
{
  "$schema": "http://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "launchUrl": "swagger",
      "applicationUrl": "http://localhost:5600",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "https": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "launchUrl": "swagger",
      "applicationUrl": "https://localhost:7600;http://localhost:5600",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.API/ Directory.Packages.props
git commit -m "chore: scaffold API project with GlobalExceptionMiddleware and DI wiring"
```

---

### Task 6: Blazor WebAssembly frontend

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/` (via `dotnet new`)
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/index.html`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Shared/MainLayout.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Shared/NavMenu.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`

- [ ] **Step 1: Scaffold the project**

```bash
dotnet new blazorwasm -n AHKFlowApp.UI.Blazor -o src/Frontend/AHKFlowApp.UI.Blazor --pwa
```

If `blazorwasm` is not available in .NET 10, check `dotnet new list` for the Blazor WASM standalone template name.

- [ ] **Step 2: Strip inherited properties from .csproj**

The generated `.csproj` will contain `<TargetFramework>`, `<Nullable>`, and `<ImplicitUsings>` which are now in `Directory.Build.props`. **Retain all Blazor-specific build properties** (e.g. `<ServiceWorkerAssetsManifest>`, `<WasmStripILAfterAOT>`, `<PublishTrimmed>`, `<RunAOTCompilation>` if present) — only remove the three inherited properties. At minimum the file should look like:

```xml
<Project Sdk="Microsoft.NET.Sdk.BlazorWebAssembly">
  <PropertyGroup>
    <ServiceWorkerAssetsManifest>service-worker-assets.js</ServiceWorkerAssetsManifest>
    <!-- retain any other Blazor WASM-specific properties generated by the template -->
  </PropertyGroup>
  <ItemGroup>
    <ServiceWorker Include="wwwroot\service-worker.js"
                   PublishedContent="wwwroot\service-worker.published.js" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Add MudBlazor**

```bash
cd src/Frontend/AHKFlowApp.UI.Blazor
dotnet add package MudBlazor
cd ../../..
```

- [ ] **Step 4: Update `wwwroot/index.html` to include MudBlazor assets**

In the `<head>` block, add before `</head>`:

```html
    <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,500,700&display=swap" rel="stylesheet" />
    <link href="_content/MudBlazor/MudBlazor.min.css" rel="stylesheet" />
```

After `<script src="_framework/blazor.webassembly.js"></script>`, add:

```html
    <script src="_content/MudBlazor/MudBlazor.min.js"></script>
```

Also update `<title>` to `AHKFlowApp`.

- [ ] **Step 5: Replace `Program.cs`**

```csharp
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

await builder.Build().RunAsync();
```

- [ ] **Step 6: Replace `Shared/MainLayout.razor` with MudBlazor layout**

```razor
@inherits LayoutComponentBase

<MudThemeProvider />
<MudDialogProvider />
<MudSnackbarProvider />

<MudLayout>
    <MudAppBar Elevation="1">
        <MudIconButton Icon="@Icons.Material.Filled.Menu" Color="Color.Inherit"
                       Edge="Edge.Start" OnClick="ToggleDrawer" />
        <MudText Typo="Typo.h6" Class="ml-3">AHKFlowApp</MudText>
    </MudAppBar>
    <MudDrawer @bind-Open="_drawerOpen" Elevation="2">
        <NavMenu />
    </MudDrawer>
    <MudMainContent>
        <MudContainer MaxWidth="MaxWidth.Large" Class="mt-6">
            @Body
        </MudContainer>
    </MudMainContent>
</MudLayout>

@code {
    private bool _drawerOpen = true;
    private void ToggleDrawer() => _drawerOpen = !_drawerOpen;
}
```

- [ ] **Step 7: Replace `Shared/NavMenu.razor` with MudBlazor nav**

```razor
<MudNavMenu>
    <MudNavLink Href="" Match="NavLinkMatch.All"
                Icon="@Icons.Material.Filled.Home">
        Home
    </MudNavLink>
</MudNavMenu>
```

- [ ] **Step 8: Remove default template pages and create `Pages/Home.razor`**

```bash
rm -f src/Frontend/AHKFlowApp.UI.Blazor/Pages/Index.razor
rm -f src/Frontend/AHKFlowApp.UI.Blazor/Pages/Counter.razor
rm -f src/Frontend/AHKFlowApp.UI.Blazor/Pages/FetchData.razor
rm -f src/Frontend/AHKFlowApp.UI.Blazor/Shared/SurveyPrompt.razor
rm -rf src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/sample-data
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor`:

```razor
@page "/"

<PageTitle>AHKFlowApp</PageTitle>

<MudText Typo="Typo.h4" GutterBottom>Welcome to AHKFlowApp</MudText>

<MudText Class="mb-6">
    Manage your AutoHotkey hotstrings and hotkeys in one place.
</MudText>

<MudAlert Severity="Severity.Info" Class="mt-4">
    Hotstring management is coming soon.
</MudAlert>
```

- [ ] **Step 9: Create `CLAUDE.md` for the frontend project**

```markdown
# AHKFlowApp.UI.Blazor

Blazor WebAssembly PWA frontend for AHKFlowApp.

## Conventions

- MudBlazor components for all UI — no raw HTML inputs or buttons
- `[Inject]` properties with `= default!` for DI
- `_loading = true` before async calls, `false` after
- `ISnackbar.Add()` for success/error feedback
- `IDialogService.ShowAsync<T>` for create/edit forms
- No `StateHasChanged()` after standard event handlers — Blazor re-renders automatically

## Adding a Page

1. Create `Pages/MyPage.razor` with `@page "/my-page"` directive
2. Add nav link in `Shared/NavMenu.razor`
3. Use `MudContainer` + `MudTable` / `MudForm` as the page structure
```

- [ ] **Step 10: Update `launchSettings.json` for the frontend**

The generated file will be in `Properties/launchSettings.json`. Update the application URL:

```json
{
  "$schema": "http://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "applicationUrl": "http://localhost:5601",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "https": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "applicationUrl": "https://localhost:7601;http://localhost:5601",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

- [ ] **Step 11: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/ Directory.Packages.props
git commit -m "chore: scaffold Blazor WASM frontend with MudBlazor layout and Home page"
```

---

### Task 7: Solution file

**Files:**
- Create: `AHKFlowApp.slnx`

- [ ] **Step 1: Create `AHKFlowApp.slnx`**

```xml
<Solution>
  <Folder Name="/src/Backend/">
    <Project Path="src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj" />
    <Project Path="src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj" />
    <Project Path="src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj" />
    <Project Path="src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj" />
  </Folder>
  <Folder Name="/src/Frontend/">
    <Project Path="src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj" />
  </Folder>
</Solution>
```

- [ ] **Step 2: Restore and build**

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

Expected: `Build succeeded. 0 Error(s) 0 Warning(s)`

If code style warnings fail the build (`TreatWarningsAsErrors`), run `dotnet format AHKFlowApp.slnx` then rebuild.

- [ ] **Step 3: Commit**

```bash
git add AHKFlowApp.slnx
git commit -m "chore: add solution file"
```

---

### Task 8: Local run documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append local run section to `README.md`**

```markdown

## Local Development

### Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- SQL Server LocalDB (included with Visual Studio) or Docker

### Running Locally

**Option 1 — LocalDB:**

```bash
# Apply migrations (after backlog item 007)
dotnet ef database update \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API

# Start API (https://localhost:7600, Swagger at /swagger)
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile https

# Start frontend in a separate terminal (https://localhost:7601)
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
```

**Option 2 — Docker Compose (recommended):**

See `docs/development/docker-setup.md`.

### URLs

| Service | URL |
|---------|-----|
| API (HTTPS) | https://localhost:7600 |
| API (HTTP) | http://localhost:5600 |
| Swagger UI | https://localhost:7600/swagger |
| Frontend | https://localhost:7601 |
| Docker Compose API | http://localhost:5602 |

### Building

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add local run instructions to README"
```

---

### Task 9: Final build verification

- [ ] **Step 1: Full restore and release build**

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

Expected: `Build succeeded. 0 Error(s) 0 Warning(s)`

- [ ] **Step 2: Fix any style violations**

If `EnforceCodeStyleInBuild` causes errors:

```bash
dotnet format AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

- [ ] **Step 3: Verify Blazor build independently**

```bash
dotnet build src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj --configuration Release
```

Expected: `Build succeeded. 0 Error(s)`

---

## Unresolved Questions

1. Is `--use-controllers` the correct `dotnet new webapi` flag for .NET 10, or has the flag changed?
2. Is `blazorwasm` still the correct template name in .NET 10, or has it been unified into `blazor`?
3. Does `dotnet add package` with CPM enabled correctly split versions into `Directory.Packages.props`, or does it require manual editing?
4. Is MudBlazor 9.x available as a stable package at implementation time, or will `dotnet add package MudBlazor` resolve to an earlier stable version?
