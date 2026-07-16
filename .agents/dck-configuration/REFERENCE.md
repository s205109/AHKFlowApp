---
name: dck-configuration
description: Use when changing AHKFlowApp appsettings, options binding, user-secrets, App Service configuration, or environment config.
---

# Configuration

## Project Shape

AHKFlowApp uses committed safe defaults in `appsettings.json`, gitignored local development files, `dotnet user-secrets` for local backend secrets, and Azure App Service Configuration for TEST/PROD runtime settings. Key Vault appears in older/planned deployment notes, but it is not the current primary secrets path.

## Core Principles

1. **No secrets in source** - Never commit real credentials, connection strings with passwords, tokens, or `.env` files.
2. **Strongly typed options** - Bind configuration sections to option classes when services need repeated access.
3. **Validate early** - Use startup validation for required operational settings.
4. **Respect environment layering** - Know whether the API, Blazor WASM, CLI, or deployment script owns a value.
5. **Frontend settings are public** - Blazor `wwwroot/appsettings*.json` values are downloadable by users.

## Local Development

Backend secrets:

```bash
dotnet user-secrets set "AzureAd:TenantId" "<tenant-id>" --project src/Backend/AHKFlowApp.API
dotnet user-secrets set "AzureAd:ClientId" "<client-id>" --project src/Backend/AHKFlowApp.API
```

The helper script `scripts/setup-dev-entra.ps1` sets backend user-secrets and writes the frontend `wwwroot/appsettings.Development.json`.

## Azure Runtime Configuration

Deployment scripts set App Service configuration values:

```powershell
az webapp config appsettings set --name <app> --resource-group <rg> --settings KEY=VALUE
```

Use App Service Configuration for backend TEST/PROD secrets and operational settings. Treat Key Vault as a future option unless the current task explicitly provisions and wires it.

## Options Pattern

```csharp
public sealed class ScriptGenerationOptions
{
    public const string SectionName = "ScriptGeneration";

    [Range(1, 10000)]
    public int MaxDefinitionsPerScript { get; init; } = 1000;
}
```

```csharp
builder.Services.AddOptions<ScriptGenerationOptions>()
    .BindConfiguration(ScriptGenerationOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

Use `IOptions<T>` for stable singleton settings, `IOptionsSnapshot<T>` for scoped reloadable settings, and `IOptionsMonitor<T>` for singleton services that must observe changes.

## Configuration Ownership

| Surface | Config source |
|---|---|
| API local secrets | `dotnet user-secrets` |
| API TEST/PROD secrets | Azure App Service Configuration |
| Blazor WASM public config | `wwwroot/appsettings*.json` and deploy substitution |
| CLI shipped defaults | `src/Tools/AHKFlowApp.CLI/appsettings.json` patched during packaging |
| Worktree local dev | setup/remove worktree scripts |

## Anti-Patterns

- Reading `IConfiguration["Some:Key"]` throughout business services.
- Committing real `appsettings.Development.json` values.
- Treating Blazor WASM config as secret.
- Adding Key Vault code without provisioning and deployment support.
- Duplicating config rules in multiple scripts without tests.
- Skipping validation for required startup settings.

## Decision Guide

| Scenario | Recommendation |
|---|---|
| Backend local secret | `dotnet user-secrets` |
| TEST/PROD backend secret | App Service Configuration |
| Service setting | Options class with validation |
| Frontend public endpoint/client ID | Blazor appsettings/deploy substitution |
| New secret store | Plan infra, deployment, local dev, and tests together |
