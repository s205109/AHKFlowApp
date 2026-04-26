# AHKFlowApp

## Local Development

### Prerequisites

.NET 10 SDK and Docker (or LocalDB). Full list — including Windows symlink setup — in [docs/development/prerequisites.md](docs/development/prerequisites.md).

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

**Option 3 — Run locally without Azure (homelab / trusted-LAN):**

Runs the full stack — SQL Server, API, and Blazor frontend — with no Azure AD sign-in. Authentication is bypassed via a synthetic `Local User` identity on every request. nginx in the UI container reverse-proxies `/api/` to the API service, so the browser only ever talks to a single origin.

> **Trust model.** The synthetic auth provider authenticates *every* request as the same fixed user. This is acceptable for **single-user homelab use on a trusted LAN only**. Do not expose this configuration to the public internet. The API throws on startup if `Auth:UseTestProvider=true` is set in any environment other than `Development`.

```bash
git clone <repo>
cd AHKFlowApp
docker compose up --build
```

Open http://localhost:5601 in a browser. The app loads as `Local User` with no sign-in prompt. The "Log out" button is disabled (real sign-out requires Entra ID).

| Service | URL |
|---|---|
| Blazor UI | http://localhost:5601 |
| API (direct) | http://localhost:5600 |
| API health | http://localhost:5600/health |
| API OpenAPI | http://localhost:5600/swagger/v1/swagger.json |
| SQL Server | localhost:1433 (sa / `Dev!LocalOnly_2026`) |

To populate sample hotstrings:

```bash
curl -X POST http://localhost:5600/api/v1/dev/hotstrings/seed
```

**How the toggle works:**
- API reads `Auth:UseTestProvider` from configuration (set to `true` via `Auth__UseTestProvider=true` in `docker-compose.yml`). When true, it registers a `TestAuthenticationHandler` that injects a fixed identity instead of validating Azure AD JWTs. Only allowed in `Development` environment.
- Blazor UI image bakes `appsettings.Local.json` into `appsettings.json` at build time and strips the env-specific `appsettings.{Production,Test,Development,E2E}.json` files so they cannot override. The synthetic auth provider sets the same fixed identity on the client.

**To run with real Entra ID instead** — see [docs/architecture/authentication.md](docs/architecture/authentication.md). You'll need to use the standard `dotnet run` workflow (Option 1) — this docker-compose path is local-install-only.

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
