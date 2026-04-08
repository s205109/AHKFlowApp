# 009 — Docker Development Setup — Design

## Context

Backlog item [`009-docker-development-setup.md`](../../../.claude/backlog/009-docker-development-setup.md). Most of the Docker dev setup already landed on `main` in commit `d5c6bae` (`Added DevDockerSqlServer`):

- `docker-compose.yml` (root) — `sqlserver` + `ahkflowapp-api` services, healthcheck, bridge network, persistent volume.
- `src/Backend/AHKFlowApp.API/DevDockerSqlServer.cs` — dev helper that runs `docker compose up sqlserver -d --wait` from the `https + Docker SQL (Recommended)` launch profile.
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` — 4 launch profiles (LocalDB, Docker SQL, Docker Compose, Docker API-only).
- `docs/development/docker-setup.md` — comprehensive walkthrough of the four profiles.

The remaining gap: `docker-compose.yml` references `src/Backend/AHKFlowApp.API/Dockerfile`, which does not exist. `docker compose up --build` therefore fails today.

## Goal

Make `docker compose up --build` work end-to-end. Satisfy all three acceptance criteria of backlog item 009.

## Acceptance criteria mapping

| AC | Status | Closed by |
|---|---|---|
| Dockerfile for API exists | Missing | This spec |
| `docker-compose.yml` includes API + SQL Server | Done | `d5c6bae` |
| Documentation shows how to run with Docker | Done | `docs/development/docker-setup.md` |

## Out of scope

- Production container optimizations (chiseled / distroless images, multi-arch, BuildKit cache mounts).
- Frontend Blazor Dockerfile.
- CI image build / push to a registry — deferred to backlog item [`010-create-ci-cd-pipeline.md`](../../../.claude/backlog/010-create-ci-cd-pipeline.md).
- Automated tests for Docker builds.

## Design

### 1. New file: `src/Backend/AHKFlowApp.API/Dockerfile`

Lean 2-stage multi-stage build (build/publish merged, runtime separate). Drops the redundant `base` and `build` stages of the VS-generated reference Dockerfile.

```dockerfile
# syntax=docker/dockerfile:1.7
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS publish
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy solution-level files first for layer caching
COPY ["Directory.Build.props", "Directory.Packages.props", "./"]

# Copy csproj files only — restore layer caches until a csproj changes
COPY ["src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj", "src/Backend/AHKFlowApp.API/"]
COPY ["src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj", "src/Backend/AHKFlowApp.Application/"]
COPY ["src/Backend/AHKFlowApp.Domain/AHKFlowApp.Domain.csproj", "src/Backend/AHKFlowApp.Domain/"]
COPY ["src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj", "src/Backend/AHKFlowApp.Infrastructure/"]
RUN dotnet restore "src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj"

COPY . .
RUN dotnet publish "src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
USER $APP_UID
EXPOSE 8080
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "AHKFlowApp.API.dll"]
```

Decisions:

- **2 stages**, not 4. The VS-generated reference file has `base`/`build`/`publish`/`final`; the `base` stage only matters for VS fast-mode debugging, and `build` is redundant when `publish` is used.
- **Targets `net10.0`** via `dotnet/sdk:10.0` and `dotnet/aspnet:10.0` (matches `AHKFlowApp.API.csproj`).
- **CPM aware** — copies `Directory.Build.props` and `Directory.Packages.props` before restore. `nuget.config` is intentionally omitted (does not exist at repo root).
- **Frontend not copied** — only the four backend csproj files are pulled for restore. The final `COPY . .` includes everything not excluded by `.dockerignore`.
- **`USER $APP_UID`** for non-root runtime (matches the official .NET image conventions).
- **`EXPOSE 8080`** matches `ASPNETCORE_HTTP_PORTS=8080` set in `docker-compose.yml`.
- **No `HEALTHCHECK`** in the Dockerfile — Compose owns service-level healthchecks.

### 2. New file: `.dockerignore` (repo root)

The compose build context is `.` (repo root), so `.dockerignore` must live at the root.

```
# VCS / IDE
.git/
.vs/
.vscode/
.idea/

# Build output
**/bin/
**/obj/
**/TestResults/

# User-local files
**/*.user
**/*.suo

# Tests, docs, and reference material — not needed in the image
tests/
docs/
old_project_reference/
.claude/
.github/
*.md

# Misc
**/node_modules/
**/.DS_Store
```

Decisions:

- Excludes `tests/` — Dockerfile only publishes `AHKFlowApp.API.csproj`, but excluding the directory shrinks the build context sent to the daemon.
- Excludes `old_project_reference/` (large) and `.claude/` (irrelevant to runtime).
- Keeps the leading `*.md` exclusion narrow (does not whitelist anything).

### 3. Files NOT changed

- `docker-compose.yml` — already correct. Only touched if verification reveals a discrepancy.
- `docs/development/docker-setup.md` — already covers all four profiles. Only touched if verification reveals a discrepancy.

## Verification

User will run on their machine after the PR is up:

1. `docker compose build ahkflowapp-api` — image builds.
2. `docker compose up --build -d` — both services start; `sqlserver` healthcheck passes; `ahkflowapp-api` reaches Running.
3. `curl http://localhost:5602/health` — returns `Healthy`.
4. Open `http://localhost:5602/swagger` — Swagger UI loads.
5. `docker compose down -v` — clean teardown.

If any step fails, fix and amend the PR before merging.

## Branch & commit plan

- Branch: `feature/009-docker-development-setup` from `origin/main`.
- The two unpushed local commits on `main` (`bfd42f0`, `7761113` — unrelated skill cleanup) stay on local `main` for a separate PR (per user direction).
- Atomic commits:
  1. `feat: add API Dockerfile (multi-stage net10)` — Dockerfile only.
  2. `chore: add .dockerignore` — repo-root .dockerignore.
  3. (only if verification finds an issue) `fix: …` or `docs: …` as needed.
- PR opened after step 3 of verification passes.

## Risks

- **Docker Desktop not installed** on the verifying machine — user already runs Docker Compose locally per `docs/development/docker-setup.md`. Low risk.
- **`Directory.Packages.props` drift** — if a new project is added later, the Dockerfile must add a `COPY` line for it. Acceptable: caught by the next docker build.
- **CPM transitive pinning** — restore inside the container must see `Directory.Packages.props`. Handled by copying it before `dotnet restore`.
