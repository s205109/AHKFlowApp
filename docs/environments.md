# Environment Configuration Guide

## Overview

| Environment | ASPNETCORE_ENVIRONMENT | Hosting | Database | Deployment path |
|-------------|------------------------|---------|----------|-----------------|
| **DEV** | `Development` | Local machine | Windows LocalDB or x64 Docker SQL Server | Manual `dotnet run` / Docker Compose |
| **TEST** | `Test` | Azure | Azure SQL Database | Auto on push to `main` |
| **PROD** | `Production` | Azure | Azure SQL Database | Manual workflow dispatch |

## DEV

- **Windows LocalDB path:** `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "LocalDB SQL"`
- **Windows/x64 Docker SQL path:** `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"`
- **Docker Compose path:** `docker compose up -d --build` starts **API + SQL Server only**; run the frontend separately with `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor`
- **Raspberry Pi / ARM64:** not supported for the bundled Docker stack because `docker-compose.yml` uses SQL Server 2022

See [docs/development/docker-setup.md](development/docker-setup.md) and [docs/development/configuration-strategy.md](development/configuration-strategy.md).

## TEST / PROD

- Provision Azure resources with `.\scripts\deploy.ps1 -Environment test|prod`
- `deploy.ps1` creates or updates the Entra app registration, configures GitHub secrets/variables, and dispatches `deploy-frontend.yml`
- `deploy-api.yml` publishes the API container on push to `main` for **TEST** and on manual dispatch for **PROD**

See [docs/deployment/getting-started.md](deployment/getting-started.md) and [docs/deployment/entra-setup.md](deployment/entra-setup.md).
