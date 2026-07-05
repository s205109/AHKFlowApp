# AHKFlowApp

> **AutoHotkey Hotstring Manager & CLI** — define, organize, and generate `.ahk` scripts from a Blazor web UI or the `ahkflow` command-line client.

AHKFlow ships two first-class interfaces over one Web API: an interactive Blazor WebAssembly PWA and the `ahkflow` CLI for scripted, power-user workflows. Install the CLI from [docs/cli/windows-install.md](docs/cli/windows-install.md).

## What is AHKFlow?

AHKFlow lets you define reusable AutoHotkey **hotstrings** (type `btw` → get `by the way`) and **hotkeys**, organize them into **profiles** and **categories**, and generate a valid `.ahk` script per profile. Manage everything from the web UI or the `ahkflow` CLI. AHKFlow generates scripts — it never runs them; you run the downloaded `.ahk` with AutoHotkey v2.

### Getting started (users)

1. Sign in to the web UI.
2. Create a hotstring (a trigger and its replacement).
3. Assign it to a profile.
4. Open **Downloads** and download that profile's `.ahk` script.
5. With [AutoHotkey v2](https://www.autohotkey.com/) installed, run the `.ahk` file.

Prefer the terminal? Install the CLI (`winget install AHKFlow.CLI`, see [docs/cli/windows-install.md](docs/cli/windows-install.md)) and use `ahkflow login`, `ahkflow hotstring new`, and `ahkflow download ahk`.

## Local Development

### Prerequisites

.NET 10 SDK and Docker (or LocalDB). Full list — including Windows symlink setup — in [docs/development/prerequisites.md](docs/development/prerequisites.md).

### Running Locally

> **First-time setup (Option 1 only):** run `pwsh scripts/setup-dev-entra.ps1` once after cloning. It creates or repairs the dev Entra ID app registration, waits for the required redirect URI/scope/service-principal wiring to become visible, sets backend user-secrets, and writes `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json`. Skip for Option 2 (Docker Compose uses synthetic auth — no Azure AD).

**Option 1 — Root launcher (recommended):**

Starts the API and Blazor UI together and opens the browser. The API applies database migrations at startup in Development, so there is no manual migration step.

```bash
# Docker SQL (recommended) — starts a SQL Server container automatically
dotnet run --launch-profile "API + Docker SQL"

# Or LocalDB (Windows, no Docker)
dotnet run --launch-profile "API + LocalDB"
```

API on http://localhost:5600 (OpenAPI at `/swagger/v1/swagger.json`), UI on http://localhost:5601. To run the API and UI in separate terminals, see [docs/development/docker-setup.md](docs/development/docker-setup.md).

If the Microsoft sign-in page shows `AADSTS500011`, rerun `pwsh scripts/setup-dev-entra.ps1` from the repo root and try again. That page is hosted by Microsoft, so the Blazor app cannot replace it before the redirect returns.

**Option 2 — Docker Compose (no Azure AD, homelab / trusted-LAN):**

Runs the full stack — SQL Server, API, and Blazor frontend — in containers with no Azure AD sign-in. Authentication is bypassed via a synthetic `Local User` identity on every request (`Auth__UseTestProvider=true` in `docker-compose.yml`). nginx in the UI container reverse-proxies `/api/` to the API service, so the browser only ever talks to a single origin. See `docs/development/docker-setup.md` for details.

**x64 / amd64 only** — the SQL Server image has no ARM64 build, so this stack does not run on Apple Silicon or Raspberry Pi without changing the database backend.

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

To populate sample data — 12 hotstrings, 12 hotkeys, and 8 categories in one transaction:

```bash
curl -X POST http://localhost:5600/api/v1/dev/seed-all
```

Individual seed endpoints (`/dev/hotstrings/seed`, `/dev/hotkeys/seed`, `/dev/categories/seed`) and a
`?reset=true` query parameter are also available. All `/dev` endpoints return 404 outside Development.

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

### VS Code full-stack debugging

These VS Code debug safeguards are intentional:

- The UI launch profile uses `type: "blazorwasm"`; `dotnet` and `coreclr` do not provide the correct Blazor WebAssembly debug flow.
- The full-stack launch profiles start the UI from `serverReadyAction` after the API is listening instead of using a parallel compound launch.
- The UI launch profile sets `browserConfig.userDataDir` to a workspace-local Chrome profile so VS Code gets an isolated browser process; reusing the default profile caused cold-start UI crashes.
- Localhost development skips service-worker registration and unregisters existing localhost workers because persisted worker state destabilized VS Code Blazor/MSAL login debugging.

If you revisit `.vscode/launch.json` or `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/registerServiceWorker.js`, re-verify the cold-start and login-debug flow in VS Code before removing any of these safeguards.

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

### Releases

Versioning and GitHub Release creation use MinVer tags. Release prep also updates `CHANGELOG.md` and regenerates the in-app changelog asset with `pwsh ./scripts/ci/generate-changelog-json.ps1`. See [docs/development/versioning.md](docs/development/versioning.md) for the release process, including CLI package publishing.

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

### Scripts

Repository automation lives in `scripts/` — see [scripts/README.md](scripts/README.md) for the full index.
