# Deploying AHKFlowApp to Azure

This guide walks you through provisioning your own AHKFlowApp instance on Azure.

**Prerequisites:** An Azure subscription. The deploy script will guide you through any additional tooling.

## Quick Start (Recommended)

Run the deploy script from the repo root:

```powershell
git clone https://github.com/your-org/AHKFlowApp.git
cd AHKFlowApp
.\scripts\deploy.ps1
```

The script will:

1. Check that required tools are installed (Azure CLI, GitHub CLI)
2. Prompt for your environment name (`test` or `prod`), Azure region, and GitHub repository
3. Create an Azure resource group and provision all resources via Bicep
4. Set up Entra ID (SQL access, OIDC for GitHub Actions)
5. Create the SQL database user for the application
6. Configure GitHub secrets and variables so CI/CD works automatically
7. Save your configuration to `scripts/.env.{environment}` for future use

When done, push to `main` — GitHub Actions will deploy the API container and Blazor frontend automatically.

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
