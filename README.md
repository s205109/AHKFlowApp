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

# Start API (https://localhost:7600, OpenAPI at /openapi/v1.json)
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
| OpenAPI JSON | https://localhost:7600/openapi/v1.json |
| Frontend | https://localhost:7601 |
| Docker Compose API | http://localhost:5602 |

### Building

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```
