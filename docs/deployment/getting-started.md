# Deploying AHKFlowApp to Azure

This guide walks you through provisioning your own AHKFlowApp instance on Azure.

**Prerequisites:** Azure subscription, Windows PowerShell 5.1 or newer, .NET 10 SDK, Azure CLI, and GitHub CLI. `sqlcmd` is optional.

## Quick Start (Recommended)

Run the deploy script from the repo root:

```powershell
git clone https://github.com/your-org/AHKFlowApp.git
cd AHKFlowApp
.\scripts\deploy.ps1
```

The script will:

1. Check that required tools are installed (.NET 10 SDK, Azure CLI, GitHub CLI)
2. Prompt for your environment name (`test` or `prod`), Azure region, and GitHub repository
3. Create an Azure resource group and provision all resources via Bicep
4. Set up Entra ID (app registration, SQL access, OIDC for GitHub Actions)
5. Create the SQL database user for the application
6. Configure GitHub secrets and variables so CI/CD works automatically
7. Trigger the frontend deploy workflow on GitHub
8. Save your configuration to `scripts/.env.{environment}` for future use

When done, the script queues the frontend deployment automatically. The API still deploys when `deploy-api.yml` runs, typically on the next push to `main`.

## What Gets Provisioned

| Resource | Name Pattern | Notes |
|----------|-------------|-------|
| Resource Group | `rg-ahkflowapp-{env}` | Contains all resources |
| App Service Plan | `ahkflowapp-plan-{env}` | Linux B1 |
| App Service | `ahkflowapp-api-{env}` | Container (GHCR) |
| SQL Server | `ahkflowapp-sql-{env}` | Entra-only auth |
| SQL Database | `ahkflowapp-db-{env}` | Basic tier |
| Static Web App | `ahkflowapp-swa-{env}` | Free tier |
| Deployer UAMI | `ahkflowapp-uami-deployer-{env}` | Used by GitHub Actions OIDC |
| Runtime UAMI | `ahkflowapp-uami-runtime-{env}` | Used by App Service → SQL |
| Log Analytics Workspace | `ahkflowapp-loganalytics-{env}` | Backs Application Insights |
| Application Insights | `ahkflowapp-appinsights-{env}` | Production telemetry & diagnostics |

Estimated cost for the `test` environment: **~$15–25/month** (B1 App Service Plan + Basic SQL DB).

## Required Tools

The deploy script checks for these and will tell you how to install them if missing:

- **Windows PowerShell 5.1+** — included on supported Windows versions
- **.NET 10 SDK** — [install](https://dotnet.microsoft.com/download/dotnet/10.0)
- **Azure CLI** — [install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- **GitHub CLI** (`gh`) — [install](https://cli.github.com)
- **sqlcmd** (optional) — [install](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility). If absent, the script prints a SQL snippet to run in the Azure Portal instead.

## Deploying Multiple Environments

Run the script once per environment:

```powershell
.\scripts\deploy.ps1 -Environment test
.\scripts\deploy.ps1 -Environment prod
```

Each environment gets its own isolated resource group and GitHub secrets.

## Application Insights

Each environment provisions an Application Insights instance backed by a Log Analytics workspace. The API automatically sends structured logs and telemetry when the `ApplicationInsights:ConnectionString` app setting is configured (set by `deploy.ps1`).

- **Local development:** No Application Insights — the connection string is empty in `appsettings.json`, so the sink is not registered.
- **Test/Prod:** The connection string is set as an App Service configuration value (`ApplicationInsights__ConnectionString`) during provisioning.

To view telemetry, open the Application Insights resource (`ahkflowapp-appinsights-{env}`) in the Azure Portal.

## Updating After a Code Change

CI/CD handles this automatically via GitHub Actions on every push to `main`. To force an immediate update:

```powershell
.\scripts\update.ps1 -Environment test
```

## Tearing Down an Environment

```powershell
.\scripts\teardown.ps1 -Environment test
```

The teardown script will confirm by asking you to type the resource group name before deleting anything.

## Advanced: CI-Driven Provisioning

If you need to re-provision from GitHub Actions (e.g., after a Bicep change):

1. Go to **Actions** → **Provision Azure Infrastructure**
2. Click **Run workflow** and select an environment

> **Note:** This only runs the Bicep deployment. Imperative steps (Entra group, OIDC federation, SQL user, GitHub secrets) must be done locally with `deploy.ps1`.

## Entra ID App Registration Setup

`deploy.ps1` already creates or updates the Entra ID app registration for `test` and `prod`. Use `setup-entra-app.ps1` only as a manual fallback when you need to refresh redirect URIs or repair app-registration state without re-running the full provisioning flow:

```powershell
.\scripts\setup-entra-app.ps1 -Environment test
.\scripts\setup-entra-app.ps1 -Environment prod
```

The script outputs the `ClientId`, `TenantId`, and `DefaultScope` values. If you run it manually, update the matching GitHub Variables so the deploy workflows can inject them:

```bash
gh variable set AZURE_AD_TENANT_ID_TEST --body "<TenantId>"
gh variable set AZURE_AD_CLIENT_ID_TEST --body "<ClientId>"
gh variable set AZURE_AD_DEFAULT_SCOPE_TEST --body "<DefaultScope>"
# repeat with _PROD suffix for prod
```

For local development, use user-secrets instead — see [entra-setup.md](entra-setup.md).

## Troubleshooting

**Container image not pulling:**  
GHCR packages are private by default. After the first CI push, make the package public at `https://github.com/orgs/{your-org}/packages`.

**Health check fails:**  
Check App Service logs:
```powershell
az webapp log tail --name ahkflowapp-api-test --resource-group rg-ahkflowapp-test
```

**SQL connection refused:**  
Ensure the Entra group and runtime UAMI were created correctly. Re-run `deploy.ps1` — it is idempotent.
