# Docker Development Setup

## Quick Start

```bash
# From solution root
docker compose up -d --build
```

Access API at: http://localhost:5600/swagger

SQL Server is available on: `localhost:1433`

> The bundled compose stack runs **API + SQL Server only**. Run the Blazor frontend separately with `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor`.
>
> The bundled compose stack is **x64/amd64 only**. It is not supported on Raspberry Pi / ARM64 because it uses `mcr.microsoft.com/mssql/server:2022-latest`.

## Visual Studio Launch Profiles

Launch profiles are defined in `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`.

All profiles bind **`http://localhost:5600`** — only one backend scenario can run at a time.

### 1. `LocalDB SQL`

- Uses SQL Server LocalDB on Windows
- Best for pure .NET development without Docker
- API URL: `http://localhost:5600`
- Swagger: `http://localhost:5600/swagger`
- Database server: `(localdb)\MSSQLLocalDB`
- Connection string: set in `appsettings.Development.json`

### 2. `Docker SQL (Recommended)`

- Runs the API locally
- Starts the SQL Server Docker container automatically when `AHKFLOW_START_DOCKER_SQL=true`
  - Implementation: `src/Backend/AHKFlowApp.API/DevDockerSqlServer.cs`
  - Also stops a stale `ahkflowapp-api` container (if any) so port 5600 is free
  - Command executed from solution root: `docker compose up sqlserver -d --wait`
- Database server: `localhost,1433`
- Connection string: overridden by environment variable in launch profile

### 3. `Docker Compose (No Debugging)`

- Starts both API and SQL Server containers
- Runs `docker compose up --build -d` from solution root
- Access API at `http://localhost:5600/swagger`
- Uses `COMPOSE_PROJECT_NAME=ahkflowapp`
- API connects to SQL Server using `sqlserver,1433` (Docker network alias)
- Connection string: set in `docker-compose.yml` as environment variable

### 4. `Docker (API only - requires SQL on localhost:1433)`

- Runs only the API in Docker
- Requires manually starting SQL Server (see below)
- Useful for debugging API container issues
- Access API at `http://localhost:5600/swagger`
- Database server (from inside the container): `host.docker.internal,1433`
- Connection string: overridden by environment variable in launch profile


## Manual SQL Server Setup

If using the `Docker (API only - requires SQL on localhost:1433)` profile, start SQL Server first.

### Option A: Start SQL Server via Docker Compose (recommended)

```bash
# From solution root
docker compose up sqlserver -d --wait
```

### Option B: Start SQL Server manually (docker run)

```bash
docker run -d \
  --name ahkflowapp-sqlserver-manual \
  -e "ACCEPT_EULA=Y" \
  -e "SA_PASSWORD=AHKFlowApp_Dev!2026" \
  -e "MSSQL_PID=Developer" \
  -p 1433:1433 \
  mcr.microsoft.com/mssql/server:2022-latest
```

## Connection Strings

The default connection string is configured in `src/Backend/AHKFlowApp.API/appsettings.Development.json`:

```json
"ConnectionStrings": {
  "DefaultConnection": "Server=(localdb)\\MSSQLLocalDB;Database=AHKFlowAppDb;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True"
}
```

Docker and launch profiles override this via the `ConnectionStrings__DefaultConnection` environment variable:

| Profile | Server | Set By |
|---------|--------|--------|
| `LocalDB SQL` | `(localdb)\MSSQLLocalDB` | `appsettings.Development.json` |
| `Docker SQL (Recommended)` | `localhost,1433` | `launchSettings.json` |
| `Docker Compose (No Debugging)` | `sqlserver,1433` | `docker-compose.yml` |
| `Docker (API only - requires SQL on localhost:1433)` | `host.docker.internal,1433` | `launchSettings.json` |

### Overriding Connection Strings

You can override via environment variables:
```bash
ConnectionStrings__DefaultConnection="Server=myserver;Database=AHKFlowAppDb;..."
```

## Architecture

### Docker Compose

```plaintext
┌──────────────────┐     ┌──────────────────────┐
│  ahkflowapp-api  │────▶│ ahkflowapp-sqlserver │
│ (host port 5600) │     │      (port 1433)     │
└──────────────────┘     └──────────────────────┘
        │
        ▼
   ahkflowapp-network
```

Both containers run on the `ahkflowapp-network` bridge network, allowing the API to reach SQL Server using the hostname `sqlserver`.

### Local API + Docker SQL Server

```plaintext
┌────────────────────────┐     ┌──────────────────────┐
│ AHKFlowApp.API (local) │────▶│ ahkflowapp-sqlserver │
│    (5600, Swagger)     │     │   (localhost:1433)   │
└────────────────────────┘     └──────────────────────┘
```
