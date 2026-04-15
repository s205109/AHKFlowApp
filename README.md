# AHKFlowApp

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

# Start API (http://localhost:5600, OpenAPI at /swagger/v1/swagger.json)
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"

# Start frontend in a separate terminal (http://localhost:5601)
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
```

**Option 2 — Docker Compose (recommended):**

See `docs/development/docker-setup.md`.

### URLs

| Service | URL |
|---------|-----|
| API | http://localhost:5600 |
| OpenAPI JSON | http://localhost:5600/swagger/v1/swagger.json |
| Frontend | http://localhost:5601 |

### Environments

The application supports three distinct environments:

| Environment | Description | ASPNETCORE_ENVIRONMENT | Deployment |
|-------------|-------------|------------------------|------------|
| **DEV** | Local development | `Development` | Local machine (LocalDB or Docker SQL) |
| **TEST** | Pre-production testing | `Test` | Azure (auto-deploy from `main` branch) |
| **PROD** | Production | `Production` | Azure (manual deployment via workflow) |

Each Azure environment (TEST/PROD) has isolated resources:
- Resource Group: `rg-ahkflowapp-{test|prod}`
- App Service: `ahkflowapp-api-{test|prod}`
- SQL Server: `ahkflowapp-sql-{test|prod}`
- Static Web App: `ahkflowapp-swa-{test|prod}`

See `docs/deployment/getting-started.md` for provisioning instructions.

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```
