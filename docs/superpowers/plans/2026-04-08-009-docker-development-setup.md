# 009 — Docker Development Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docker compose up --build` work end-to-end by adding the missing API Dockerfile and a repo-root `.dockerignore`.

**Architecture:** A standard 4-stage VS-compatible Dockerfile (`base` → `build` → `publish` → `final`) targeting `mcr.microsoft.com/dotnet/{sdk,aspnet}:10.0`. The `base` stage is preserved so the existing `Docker (API only)` Visual Studio launch profile keeps working in fast-mode debug. The compose build context is the repo root, so the `.dockerignore` lives there.

**Tech Stack:** .NET 10, ASP.NET Core, Docker, Docker Compose, SQL Server 2022, MinVer, Serilog, Central Package Management.

**Spec:** `docs/superpowers/specs/2026-04-08-009-docker-development-setup-design.md`

**Branch:** `feature/009-docker-development-setup` (already created from `origin/main`)

---

## File Structure

| File | Purpose | Action |
|---|---|---|
| `src/Backend/AHKFlowApp.API/Dockerfile` | Multi-stage build for the API container | Create |
| `.dockerignore` (repo root) | Excludes irrelevant files from compose build context | Create |
| `docker-compose.yml` | Already references the Dockerfile correctly | No change |
| `docs/development/docker-setup.md` | Already comprehensive | No change unless verification surfaces a discrepancy |

No source code or tests are touched. Verification is manual (docker compose) — there is nothing to TDD. The standard "write failing test first" loop does not apply here; verification gates the work instead.

---

## Task 1: Create the API Dockerfile

**Files:**
- Create: `src/Backend/AHKFlowApp.API/Dockerfile`

**Why this exists:** `docker-compose.yml` already references this path (`src/Backend/AHKFlowApp.API/Dockerfile`). Without the file, `docker compose up --build` fails immediately. The Dockerfile must:
- Use `mcr.microsoft.com/dotnet/sdk:10.0` and `mcr.microsoft.com/dotnet/aspnet:10.0` (matches `<TargetFramework>net10.0</TargetFramework>` in `Directory.Build.props`).
- Preserve the `base` stage (VS `commandName: Docker` profile mounts source over `/app` in fast-mode).
- Create `/app/AppData/Logs` and `chown` it to `app` BEFORE the `USER` switch (Serilog file sink in `appsettings.json` writes there).
- Pass `/p:MinVerSkip=true` on publish only (`.git/` is excluded from context, MinVer would warn, `TreatWarningsAsErrors=true` would fail the build). No separate `dotnet build` step — `dotnet publish` compiles and produces output in a single pass.
- Copy CPM files (`Directory.Build.props`, `Directory.Packages.props`) before restore.
- Copy only the four backend csproj files for restore-layer caching.
- Run as `USER app` and expose port 8080 (matches `ASPNETCORE_HTTP_PORTS=8080` in compose).

- [ ] **Step 1: Create the Dockerfile**

Create `src/Backend/AHKFlowApp.API/Dockerfile` with exactly this content:

```dockerfile
# syntax=docker/dockerfile:1.7

# base — runtime image used by VS fast-mode debug (commandName: Docker)
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080
# Serilog file sink writes to /app/AppData/Logs at startup;
# create the directory as root and hand it to the non-root user before dropping privileges.
RUN mkdir -p /app/AppData/Logs && chown -R app:app /app/AppData
USER app

# build — restore + copy sources
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
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

# publish — produce final binaries
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
WORKDIR "/src/src/Backend/AHKFlowApp.API"
# MinVerSkip=true: .git/ is excluded from build context (.dockerignore), so MinVer cannot
# read tags. Skipping it prevents MINVER0001 — which would fail the build under
# TreatWarningsAsErrors=true. Local dev containers don't need real versions; CI/CD owns that.
RUN dotnet publish "AHKFlowApp.API.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false \
    /p:MinVerSkip=true

# final — runtime image used by docker compose / production
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "AHKFlowApp.API.dll"]
```

- [ ] **Step 2: Sanity-check the file landed correctly**

Run:
```bash
ls C:/Dev/segocom-github/AHKFlowApp/src/Backend/AHKFlowApp.API/Dockerfile
```
Expected: file path printed (no error).

Run (Grep):
```
grep -n "MinVerSkip" src/Backend/AHKFlowApp.API/Dockerfile
```
Expected: 1 match (in publish stage only).

- [ ] **Step 3: Commit**

```bash
git -C C:/Dev/segocom-github/AHKFlowApp add src/Backend/AHKFlowApp.API/Dockerfile
git -C C:/Dev/segocom-github/AHKFlowApp commit -m "feat: add API Dockerfile (multi-stage net10)"
```

Expected output: `1 file changed, ~50 insertions(+)`.

---

## Task 2: Create the repo-root `.dockerignore`

**Files:**
- Create: `.dockerignore` (at `C:/Dev/segocom-github/AHKFlowApp/.dockerignore`)

**Why this exists:** The compose build context is `.` (repo root). Without a `.dockerignore`, the entire repo (including `bin/`, `obj/`, `.git/`, `tests/`, `docs/`, `old_project_reference/`, `.claude/`) is sent to the Docker daemon — slow, and pollutes the layer cache. `.git/` exclusion is intentional and the spec compensates with `/p:MinVerSkip=true`.

- [ ] **Step 1: Create the .dockerignore**

Create `.dockerignore` at the repo root with exactly this content:

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

- [ ] **Step 2: Sanity-check the file landed correctly**

Run:
```bash
ls C:/Dev/segocom-github/AHKFlowApp/.dockerignore
```
Expected: file path printed.

Run (Grep):
```
grep -nE "^\.git/|^old_project_reference/|^\*\*/bin/" .dockerignore
```
Expected: 3 matches.

- [ ] **Step 3: Commit**

```bash
git -C C:/Dev/segocom-github/AHKFlowApp add .dockerignore
git -C C:/Dev/segocom-github/AHKFlowApp commit -m "chore: add .dockerignore for compose build context"
```

Expected output: `1 file changed, ~25 insertions(+)`.

---

## Task 3: Pre-PR build & test gate

**Why this exists:** `AGENTS.md` requires `dotnet build` + `dotnet test` to pass before opening a PR. This catches regressions in the .csproj files even though the docker work itself is config-only.

- [ ] **Step 1: Build the solution in Release**

Run:
```bash
dotnet build C:/Dev/segocom-github/AHKFlowApp --configuration Release
```
Expected: `Build succeeded.` with 0 errors. Warnings are treated as errors per `Directory.Build.props`, so any warning fails the build.

If the build fails: STOP. Do not proceed to docker verification. Diagnose and fix before continuing.

- [ ] **Step 2: Run all tests in Release**

Run:
```bash
dotnet test C:/Dev/segocom-github/AHKFlowApp --configuration Release --no-build
```
Expected: All tests pass. Existing tests (Domain, Application, Infrastructure, API, UI.Blazor) must remain green — none of this work should affect runtime behavior.

If tests fail: STOP. Diagnose. The Dockerfile and .dockerignore should not affect any test, so a failure here means an unrelated regression on `origin/main` — surface it before continuing.

---

## Task 4: Docker verification (user runs locally)

**Why this exists:** This is the actual acceptance test for backlog item 009. The user said they will run this on their machine (Q4 from brainstorming). Document the exact steps so the user can run them mechanically.

- [ ] **Step 1: Verify the API image builds**

User runs:
```bash
docker compose -f C:/Dev/segocom-github/AHKFlowApp/docker-compose.yml build ahkflowapp-api
```
Expected: `Successfully built` (or BuildKit equivalent), no errors. First build will take a few minutes (pulling base images, restoring NuGet packages).

If this fails:
- `MINVER0001` warning treated as error → confirm the `dotnet publish` line has `/p:MinVerSkip=true`.
- `COPY` failed for a csproj → confirm the four `COPY` lines match the actual project paths.
- `permission denied` writing to `/app/AppData/Logs` → confirm `mkdir`/`chown` runs in the `base` stage BEFORE `USER $APP_UID`.

- [ ] **Step 2: Start the full stack**

User runs:
```bash
docker compose -f C:/Dev/segocom-github/AHKFlowApp/docker-compose.yml up --build -d
```
Expected: Both services start. `sqlserver` reaches `(healthy)` (~30s, watch with `docker compose ps`). `ahkflowapp-api` then starts and stays Running.

Watch logs:
```bash
docker compose -f C:/Dev/segocom-github/AHKFlowApp/docker-compose.yml logs -f ahkflowapp-api
```
Expected: Serilog `Starting AHKFlowApp API`, `Applying database migrations...`, `Database migrations applied successfully.`, `AHKFlowApp API started successfully`. No exceptions.

- [ ] **Step 3: Hit `/health` from the host**

User runs:
```bash
curl http://localhost:5602/health
```
Expected: `Healthy` (HTTP 200). This proves the API is reachable, the DB connection works, and `AddDbContextCheck<AppDbContext>` passes.

- [ ] **Step 4: Verify Swagger UI in browser**

User opens `http://localhost:5602/swagger` in a browser.
Expected: Swagger UI loads, `Health` controller is listed.

- [ ] **Step 5: Clean teardown**

User runs:
```bash
docker compose -f C:/Dev/segocom-github/AHKFlowApp/docker-compose.yml down -v
```
Expected: Both containers stop, the `sqlserver-data` volume is removed, no errors.

- [ ] **Step 6: Report verification result**

If all 5 steps passed → proceed to Task 5.
If any step failed → file an issue against the spec, fix the Dockerfile/.dockerignore, amend the relevant commit (or add a `fix:` commit), and re-run from Task 4 Step 1.

---

## Task 5: Open the pull request

- [ ] **Step 1: Push the branch**

```bash
git -C C:/Dev/segocom-github/AHKFlowApp push -u origin feature/009-docker-development-setup
```
Expected: Branch published to origin.

- [ ] **Step 2: Create the PR via gh**

```bash
gh pr create \
  --base main \
  --head feature/009-docker-development-setup \
  --title "feat: docker development setup (009)" \
  --body "$(cat <<'EOF'
## Summary
- Add multi-stage `Dockerfile` for `AHKFlowApp.API` (.NET 10, 4-stage VS-compatible layout)
- Add repo-root `.dockerignore` (excludes `bin/`, `obj/`, `.git/`, `tests/`, `docs/`, `old_project_reference/`, `.claude/`)
- Closes backlog item 009

## Why
`docker-compose.yml` already references `src/Backend/AHKFlowApp.API/Dockerfile` (added in `d5c6bae`), but the file did not exist — `docker compose up --build` fails today. This adds the missing Dockerfile and a lean build context.

## Design notes
- 4-stage layout (`base`/`build`/`publish`/`final`) preserves the existing `Docker (API only)` VS launch profile (fast-mode source mount on the `base` stage).
- `/app/AppData/Logs` is created and chowned in the `base` stage so the Serilog file sink works under `$APP_UID`.
- `/p:MinVerSkip=true` on publish: `.git/` is excluded from the context to keep the image lean, so MinVer can't read tags. Without the skip, `MINVER0001` fails the build under `TreatWarningsAsErrors=true`. A single `dotnet publish` pass compiles and outputs the binaries. CI/CD (item 010) will run publish outside Docker for real versioning.

## Out of scope
- Production container hardening (chiseled images, multi-arch) — not in AC.
- Frontend Blazor Dockerfile.
- CI image build / push to registry — deferred to backlog item 010.

## Test plan
- [x] `dotnet build --configuration Release` — clean
- [x] `dotnet test --configuration Release` — all tests pass
- [x] `docker compose build ahkflowapp-api` — image builds
- [x] `docker compose up --build -d` — both services healthy
- [x] `curl http://localhost:5602/health` returns `Healthy`
- [x] Swagger UI loads at `http://localhost:5602/swagger`
- [x] `docker compose down -v` — clean teardown

Spec: `docs/superpowers/specs/2026-04-08-009-docker-development-setup-design.md`
EOF
)"
```
Expected: PR URL printed. Tick off the test-plan items based on actual verification results.

- [ ] **Step 3: Report PR URL to user**

Print the PR URL.

---

## Rollback plan

If the work is rejected during code review or breaks something downstream:
1. Close the PR.
2. `git -C C:/Dev/segocom-github/AHKFlowApp checkout main`
3. `git -C C:/Dev/segocom-github/AHKFlowApp branch -D feature/009-docker-development-setup`
4. The repo returns to its current state (no changes on `origin/main`).
