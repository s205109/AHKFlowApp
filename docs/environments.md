# Environments

| Environment | `ASPNETCORE_ENVIRONMENT` | Database | Deploys |
|---|---|---|---|
| **DEV** | `Development` | LocalDB or Docker SQL | `dotnet run` / `docker compose up` |
| **TEST** | `Test` | Azure SQL | Auto on push to `main` |
| **PROD** | `Production` | Azure SQL | Manual workflow dispatch |

Local DEV setup: see [README.md](../README.md) and [docs/development/docker-setup.md](development/docker-setup.md).

Azure TEST / PROD provisioning and deployment: see [docs/deployment/getting-started.md](deployment/getting-started.md). After `deploy.ps1`, the deterministic resource names and FQDNs are saved to `scripts/.env.<env>`.

## Configuration file load order

API backend (`src/Backend/AHKFlowApp.API/appsettings*.json`):

1. `appsettings.json`
2. `appsettings.{Environment}.json` (`Development` / `Test` / `Production`)
3. Environment variables
4. Azure App Service configuration (TEST / PROD only)

Blazor frontend (`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings*.json`):

1. `appsettings.json`
2. `appsettings.{BlazorEnvironment}.json` — chosen at build time by the `WasmApplicationEnvironmentName` MSBuild property (`Test` or `Production` passed by `deploy-frontend.yml`, `Development` or `NoAuth` passed by `scripts/run-frontend.ps1`). For local-install / homelab, `appsettings.Local.json` is baked into the container image.

No secrets live in frontend config; all values are public.

## Connection strings

DEV (LocalDB):

```
Server=(localdb)\mssqllocaldb;Database=AHKFlowApp;Trusted_Connection=True;MultipleActiveResultSets=true
```

DEV (Docker SQL):

```
Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True
```

TEST / PROD (Entra ID auth, set by `deploy.ps1`):

```
Server=tcp:{SQL_SERVER_FQDN},1433;Database={SQL_DATABASE_NAME};Authentication=Active Directory Default;Encrypt=True;
```

## Troubleshooting

- **DEV: DB connection fails** — ensure LocalDB is installed or Docker is running, then `dotnet ef database update`.
- **TEST/PROD: deploy fails** — verify GitHub secrets/variables have `_TEST` / `_PROD` suffix, the deployer UAMI has RBAC, and the SQL firewall allows the runner IP.
- **TEST/PROD: API returns 500** — `az webapp log tail --name <APP_SERVICE_NAME> --resource-group <RESOURCE_GROUP>` and check Application Insights.
- **Backend: wrong appsettings loaded** — `ASPNETCORE_ENVIRONMENT` is case-sensitive (`Development` / `Test` / `Production`).
- **Frontend: wrong appsettings loaded** — `ASPNETCORE_ENVIRONMENT` does not apply. A standalone Blazor WebAssembly app picks its environment at build time from the `WasmApplicationEnvironmentName` MSBuild property, which .NET 10 bakes into `_framework/dotnet.js`. Rebuild with the right value — see [`docs/development/configuration-strategy.md`](development/configuration-strategy.md).
- **Frontend shows "Couldn't load the app"** — one or more `_framework` files failed to download. The page already reloaded itself once. Reload again; if that does not help, check the browser console for the failing request.
