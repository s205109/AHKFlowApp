# Environment Configuration Guide

## Overview

AHKFlowApp supports three distinct environments with environment-specific configuration:

| Environment | Name | ASPNETCORE_ENVIRONMENT | Location | Database | Deployment |
|-------------|------|------------------------|----------|----------|------------|
| **DEV** | Development | `Development` | Local machine | LocalDB or Docker SQL | Manual (`dotnet run`) |
| **TEST** | Test | `Test` | Azure | Azure SQL Database | Auto (push to `main`) |
| **PROD** | Production | `Production` | Azure | Azure SQL Database | Manual (workflow dispatch) |

## DEV Environment (Local Development)

### Configuration

- **ASPNETCORE_ENVIRONMENT**: `Development`
- **Database**: LocalDB (`(localdb)\mssqllocaldb`) or Docker SQL Server (port 1433)
- **Connection String**: Configured in `appsettings.Development.json` (not committed) or Docker Compose
- **CORS**: Allows `https://localhost:7601` and `http://localhost:5601`
- **Logging**: Debug level for application code, Information for EF Core queries

### Running Locally

**Option 1 — LocalDB:**
```bash
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile https
```

**Option 2 — Docker SQL (Recommended):**
```bash
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + Docker SQL (Recommended)"
```

**Option 3 — Full Stack (Docker Compose):**
```bash
docker compose up --build
```

### URLs
- API: `http://localhost:5600` (single port for VS, docker-compose, Docker-only scenarios)
- Frontend: `http://localhost:5601`

## TEST Environment (Azure Pre-Production)

### Configuration

- **ASPNETCORE_ENVIRONMENT**: `Test` (set via App Service application setting)
- **Database**: Azure SQL Database — FQDN captured in `scripts/.env.test` after provisioning
- **Authentication**: Entra ID (Managed Identity) — no SQL passwords
- **Connection String**: Set via App Service connection string configuration
- **CORS**: Configured to allow Static Web App URL
- **Logging**: Information level for application, Warning for framework

### Azure Resources

All resources are in the `rg-ahkflowapp-test` resource group. App Service and SQL Server names
include a short deterministic suffix (derived from the subscription, resource group, and
environment) to avoid global-name collisions — the exact names are emitted by Bicep and saved
to `scripts/.env.test`:
- App Service: `ahkflowapp-api-test-<token>`
- SQL Server: `ahkflowapp-sql-test-<token>`
- SQL Database: `ahkflowapp-db`
- Static Web App: `ahkflowapp-swa-test`
- Key Vault: `ahkflowapp-kv-test`
- User-Assigned Managed Identity (deployer): `ahkflowapp-uami-deployer-test`
- User-Assigned Managed Identity (runtime): `ahkflowapp-uami-runtime-test`

### Provisioning

Run the Azure provisioning scripts with `ENVIRONMENT=test`:

```bash
cd scripts/azure

# Step 1: Verify prerequisites
cat 00-prerequisites.md

# Step 2: Provision Azure resources
# Set ENVIRONMENT=test in 01-provision-azure.md and run commands

# Step 3: Configure GitHub OIDC
# Set ENVIRONMENT=test in 02-configure-github-oidc.md and run commands
```

### Deployment

**Automatic:** Push to `main` branch triggers `deploy-api.yml` and `deploy-frontend.yml` workflows.

**Manual:** Use workflow dispatch in GitHub Actions.

### GitHub Secrets & Variables

**Secrets** (shared):
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_CLIENT_ID_TEST` (deployer managed identity)
- `AZURE_STATIC_WEB_APPS_API_TOKEN_TEST`

**Variables** (TEST-specific — values populated by `deploy.ps1`; App Service / SQL Server names
include the deterministic suffix described above):
- `AZURE_RESOURCE_GROUP_TEST=rg-ahkflowapp-test`
- `APP_SERVICE_NAME_TEST=ahkflowapp-api-test-<token>`
- `SQL_SERVER_NAME_TEST=ahkflowapp-sql-test-<token>`
- `SQL_SERVER_FQDN_TEST=ahkflowapp-sql-test-<token>.database.windows.net`
- `SQL_DATABASE_NAME_TEST=ahkflowapp-db`

### URLs
- API / API Health: `https://<APP_SERVICE_NAME_TEST>.azurewebsites.net[/health]` — read from `scripts/.env.test`
- Frontend: Get from `az staticwebapp show --name ahkflowapp-swa-test --query defaultHostname -o tsv`

## PROD Environment (Azure Production)

### Configuration

- **ASPNETCORE_ENVIRONMENT**: `Production` (set via App Service application setting)
- **Database**: Azure SQL Database — FQDN captured in `scripts/.env.prod` after provisioning
- **Authentication**: Entra ID (Managed Identity) — no SQL passwords
- **Connection String**: Set via App Service connection string configuration
- **CORS**: Configured to allow Static Web App URL
- **Logging**: Warning level (minimal logging for performance)

### Azure Resources

All resources are in the `rg-ahkflowapp-prod` resource group. App Service and SQL Server names
include a short deterministic suffix (derived from the subscription + RG) to avoid global-name
collisions — the exact names are emitted by Bicep and saved to `scripts/.env.prod`:
- App Service: `ahkflowapp-api-prod-<token>`
- SQL Server: `ahkflowapp-sql-prod-<token>`
- SQL Database: `ahkflowapp-db`
- Static Web App: `ahkflowapp-swa-prod`
- Key Vault: `ahkflowapp-kv-prod`
- User-Assigned Managed Identity (deployer): `ahkflowapp-uami-deployer-prod`
- User-Assigned Managed Identity (runtime): `ahkflowapp-uami-runtime-prod`

### Provisioning

Run the Azure provisioning scripts with `ENVIRONMENT=prod`:

```bash
cd scripts/azure

# Step 1: Verify prerequisites
cat 00-prerequisites.md

# Step 2: Provision Azure resources
# Set ENVIRONMENT=prod in 01-provision-azure.md and run commands

# Step 3: Configure GitHub OIDC
# Set ENVIRONMENT=prod in 02-configure-github-oidc.md and run commands
```

### Deployment

**Manual Only:** Use workflow dispatch in GitHub Actions:
1. Go to Actions → Deploy API (or Deploy Frontend)
2. Click "Run workflow"
3. Select environment: `prod`
4. Confirm and run

### GitHub Secrets & Variables

**Secrets** (shared):
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_CLIENT_ID_PROD` (deployer managed identity)
- `AZURE_STATIC_WEB_APPS_API_TOKEN_PROD`

**Variables** (PROD-specific — values populated by `deploy.ps1`; App Service / SQL Server names
include the deterministic suffix described above):
- `AZURE_RESOURCE_GROUP_PROD=rg-ahkflowapp-prod`
- `APP_SERVICE_NAME_PROD=ahkflowapp-api-prod-<token>`
- `SQL_SERVER_NAME_PROD=ahkflowapp-sql-prod-<token>`
- `SQL_SERVER_FQDN_PROD=ahkflowapp-sql-prod-<token>.database.windows.net`
- `SQL_DATABASE_NAME_PROD=ahkflowapp-db`

### URLs
- API / API Health: `https://<APP_SERVICE_NAME_PROD>.azurewebsites.net[/health]` — read from `scripts/.env.prod`
- Frontend: Get from `az staticwebapp show --name ahkflowapp-swa-prod --query defaultHostname -o tsv`

## Environment-Specific Configuration Files

### API Backend

```
src/Backend/AHKFlowApp.API/
  appsettings.json                 # Base configuration (committed)
  appsettings.Development.json     # DEV overrides (committed, CORS only)
  appsettings.Test.json            # TEST overrides (committed)
  appsettings.Production.json      # PROD overrides (committed)
```

**Load order:** `appsettings.json` → `appsettings.{Environment}.json` → Environment variables → Azure App Configuration (future)

### Frontend Blazor

```
src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/
  appsettings.json                 # Base config (committed)
  appsettings.Development.json     # DEV overrides — localhost API (committed)
  appsettings.Test.json            # TEST overrides — TEST Azure API URL (committed)
  appsettings.Production.json      # PROD overrides — PROD Azure API URL (committed)
```

**Load order:** `appsettings.json` → `appsettings.{BlazorEnvironment}.json`

The active environment is controlled by the `Blazor-Environment` HTTP header:
- TEST SWA: set to `Test` via `staticwebapp.config.json`
- PROD SWA: patched to `Production` by `deploy-frontend.yml` before publishing
- Local dev: set to `Development` automatically by the ASP.NET Core dev server

No secrets are stored in frontend configuration — all values are public.

## Switching Between Environments

### Local Development → TEST
1. Ensure TEST environment is provisioned in Azure
2. Ensure GitHub secrets/variables are configured for TEST
3. Push to `main` branch or manually trigger workflow with environment=test

### TEST → PROD
1. Provision PROD environment in Azure
2. Configure GitHub secrets/variables for PROD
3. Manually trigger Deploy API workflow with environment=prod
4. Manually trigger Deploy Frontend workflow with environment=prod

## Environment Variable Reference

### All Environments

| Variable | DEV | TEST | PROD |
|----------|-----|------|------|
| `ASPNETCORE_ENVIRONMENT` | `Development` | `Test` | `Production` |
| `AZURE_CLIENT_ID` | (not set) | UAMI runtime client ID | UAMI runtime client ID |
| `WEBSITES_PORT` | (not set) | `8080` | `8080` |

### Connection Strings

**DEV:**
```
Server=(localdb)\mssqllocaldb;Database=AHKFlowApp;Trusted_Connection=True;MultipleActiveResultSets=true
```
or (Docker):
```
Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True
```

**TEST/PROD (Azure, Entra ID auth):**
```
Server=tcp:{SQL_SERVER_FQDN},1433;Database={SQL_DATABASE_NAME};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

## Troubleshooting

### DEV: Database connection fails
- Ensure SQL Server LocalDB is installed or Docker is running
- Run `dotnet ef database update` to apply migrations

### TEST/PROD: Deployment fails
- Check GitHub secrets and variables are set correctly with `_TEST` or `_PROD` suffix
- Verify Azure UAMI has correct RBAC permissions
- Check SQL firewall rules allow GitHub Actions runner IP

### TEST/PROD: API returns 500 errors
- Check App Service logs: `az webapp log tail --name {APP_SERVICE_NAME} --resource-group {RESOURCE_GROUP}`
- Verify `ASPNETCORE_ENVIRONMENT` is set correctly in App Service configuration
- Check Application Insights for exceptions

### Environment not loading correct appsettings
- Verify `ASPNETCORE_ENVIRONMENT` environment variable is set
- Check file exists: `appsettings.{Environment}.json`
- ASP.NET Core is case-sensitive for environment names (use `Development`, `Test`, `Production`)

## Security Considerations

### DEV
- SQL password in `docker-compose.yml` is for local development only
- Never commit real secrets to `appsettings.Development.json`
- Use `dotnet user-secrets` for sensitive local configuration

### TEST/PROD
- All secrets stored in Azure Key Vault or App Service configuration
- SQL authentication uses Entra ID only (no SQL logins)
- Managed identities eliminate long-lived secrets
- HTTPS enforced via HSTS
- Connection strings never committed to source control

## Next Steps

1. **Set up DEV:** Clone repo, run `dotnet run` or `docker compose up`
2. **Provision TEST:** Run `scripts/azure/01-provision-azure.md` with `ENVIRONMENT=test`
3. **Configure CI/CD for TEST:** Run `scripts/azure/02-configure-github-oidc.md` with `ENVIRONMENT=test`
4. **Deploy to TEST:** Push to `main` or manually trigger workflow
5. **Provision PROD:** Repeat steps 2-3 with `ENVIRONMENT=prod`
6. **Deploy to PROD:** Manually trigger workflow with `environment=prod`
