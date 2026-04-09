# 010 — CI/CD Pipeline — Design

## Context

Backlog item [`010-create-ci-cd-pipeline.md`](../../../.claude/backlog/010-create-ci-cd-pipeline.md). First real CI/CD for AHKFlowApp. Depends on:

- Item 009 (Docker) — just landed. Provides `src/Backend/AHKFlowApp.API/Dockerfile` and root `docker-compose.yml`. CI reuses the Dockerfile.
- Item 003 (scaffold) — landed. Solution layout, `Directory.Build.props`, `global.json`, MinVer.

`.github/workflows/` is currently empty. CLAUDE.md / AGENTS.md reference 4 aspirational workflow files — this spec implements them for real. Old project reference at `old_project_reference/AHKFlow` used zip-publish + SQL password auth + service principal; this spec modernises that pattern.

## Goal

Satisfy all 4 backlog acceptance criteria:

| AC | Closed by |
|---|---|
| CI on PRs (build + unit tests) | `.github/workflows/ci.yml` |
| CD on main (build + tests + publish) | `.github/workflows/deploy-api.yml`, `deploy-frontend.yml` |
| UI deploys to Azure Static Web Apps | `.github/workflows/deploy-frontend.yml` |
| API deploys via container to Azure | `.github/workflows/deploy-api.yml` (GHCR → App Service for Linux) |

Plus: make a brand-new contributor able to stand up a working dev env in Azure from zero by running four markdown scripts under `scripts/azure/`.

## Out of scope

- Blue/green deployments, deployment slots (explicit AC exclusion).
- Production environment. This spec sets up **one** environment (`dev`); prod is documented as "re-run with `ENVIRONMENT=prod`".
- GitHub Environments protection rules / required reviewers.
- Bicep / ARM / Terraform infrastructure-as-code. Bash-in-markdown only.
- ACR (Azure Container Registry). GHCR only.
- Frontend Dockerfile. Frontend ships as static files to Static Web Apps.
- Test coverage reporting / SonarCloud / CodeQL (future items).
- Automated rollback. Manual re-deploy by re-running the previous workflow run is the rollback story.

## Locked design decisions

| Decision | Choice | Why |
|---|---|---|
| Workflow layout | 4 separate workflows (`ci`, `deploy-api`, `deploy-frontend`, `migrate-db`) | Matches aspirational layout in AGENTS.md; each file fits on one screen |
| API deploy target | Azure App Service for Linux, container mode | Reuses 009 Dockerfile; simpler than Container Apps for a backend dev |
| Frontend target | Azure Static Web Apps (Free tier) | Old project proven pattern; free |
| Container registry | GHCR (public) | Free, `GITHUB_TOKEN` auth, no extra Azure resource |
| GitHub → Azure auth | User-assigned Managed Identity + OIDC federated credentials via `azure/login@v2` | Zero long-lived secrets in GitHub; MS-recommended |
| SQL auth | **Entra ID only** — no SQL admin password anywhere | User request; eliminates Key Vault secret for SQL |
| EF migrations | `dotnet ef database update` from CI runner using Entra-auth connection string, with temporary SQL firewall rule for the runner's IP | Simpler than sqlcmd + script generation; no package installs; runner IP is added/removed per run for tight scope |
| Script format | Bash in markdown with variables at top | Matches old project; readable + executable; `az` CLI is bash-idiomatic |
| Script location | `scripts/azure/` | User choice |
| Region | `${LOCATION}` variable, default `westeurope` | User choice |
| Environment strategy | Single `dev`, parameterised via `ENVIRONMENT` variable | Simpler start; re-run with `prod` later |
| GitHub Environments | None initially | User opted out of protection rules |
| Action pinning | `azure/*` + `actions/*` by major tag; third-party by SHA | GitHub 2026 security roadmap |

## Architecture

### High-level flow

```
┌──────────────────────┐
│  Pull Request        │──► ci.yml ──► dotnet build + test
│  (any branch → main) │                 ↓
└──────────────────────┘              status check on PR

┌──────────────────────┐
│  Push to main        │──► deploy-api.yml (backend paths)
│                      │      ├─ build-test (produces migration.sql artifact)
│                      │      ├─ build-push-image ──► GHCR
│                      │      ├─ migrate-db (sqlcmd + Entra token)
│                      │      └─ deploy (webapp config container set + health check)
│                      │
│                      │──► deploy-frontend.yml (frontend paths)
│                      │      └─ dotnet publish + Azure/static-web-apps-deploy@v1
└──────────────────────┘

┌──────────────────────┐
│  workflow_dispatch   │──► migrate-db.yml  (manual / hotfix)
└──────────────────────┘
```

### Azure resource inventory

Created by `scripts/azure/01-provision-azure.md`, all in a single resource group `rg-ahkflow-${ENVIRONMENT}`:

| Resource | Name (dev) | Purpose | Tier |
|---|---|---|---|
| Resource group | `rg-ahkflow-dev` | Container for all below | — |
| Log Analytics workspace | `ahkflow-logs-dev` | Backing store for App Insights | Pay-as-you-go |
| Application Insights | `ahkflow-insights-dev` | Telemetry (shared API + frontend) | Workspace-based |
| SQL logical server | `ahkflow-sql-dev` | Hosts the database | — |
| SQL database | `ahkflow-db` | Application database | Basic (5 DTU) |
| App Service plan | `ahkflow-plan-dev` | Linux compute | B1 Linux |
| App Service | `ahkflow-api-dev` | API runtime (container) | — |
| Static Web App | `ahkflow-swa-dev` | Blazor WASM frontend | Free |
| Key Vault | `ahkflow-kv-dev` | App secrets (App Insights conn string, Azure AD IDs, etc.) — **not** SQL password | Standard |
| UAMI (deployer) | `ahkflow-uami-deployer-dev` | GitHub Actions identity for provisioning + migrations | — |
| UAMI (runtime) | `ahkflow-uami-runtime-dev` | App Service identity for SQL + Key Vault | — |
| Entra security group | `ahkflow-sql-admins-dev` | SQL server Entra admin | — |

### Authentication chain

```
┌──────────────────┐   OIDC federated credential
│ GitHub Actions   │──────────────────────────────► UAMI "deployer"
│ (workflow run)   │   token from token.actions         │
└──────────────────┘   .githubusercontent.com           │
                                                        ▼
                                          ┌──────────────────────┐
                                          │  Azure (sub/RG)      │
                                          │  - Contributor on RG │
                                          │  - SQL db_owner      │
                                          └──────────────────────┘

┌──────────────────┐   assigned managed identity
│ App Service      │──────────────────────────────► UAMI "runtime"
│ (container)      │                                    │
└──────────────────┘                                    ▼
                                          ┌──────────────────────┐
                                          │  - SQL read/write    │
                                          │  - Key Vault Secrets │
                                          │    User              │
                                          └──────────────────────┘

Browser ──JWT──► Static Web App (Blazor)
          │
          └──Bearer token──► App Service API
                               │
                               └── validates with Entra ID
```

### SQL Entra-only auth model

No `sa` password, no SQL admin login. Entire auth chain uses Entra ID.

1. `01-provision-azure.md` creates the SQL server with `--external-admin-*` flags pointing to the `ahkflow-sql-admins-dev` Entra group (and adds the human operator running the script to that group so they can connect).
2. `02-configure-github-oidc.md`:
   - Adds the deployer UAMI to the `ahkflow-sql-admins-dev` group — grants full SQL admin to the CI principal.
   - Connects to SQL as the operator (`sqlcmd -G`) and runs:
     ```sql
     CREATE USER [ahkflow-uami-runtime-dev] FROM EXTERNAL PROVIDER;
     ALTER ROLE db_datareader ADD MEMBER [ahkflow-uami-runtime-dev];
     ALTER ROLE db_datawriter ADD MEMBER [ahkflow-uami-runtime-dev];
     GRANT EXECUTE TO [ahkflow-uami-runtime-dev];
     ```
     Runtime UAMI gets read/write/execute only — no DDL.
3. App Service connection string (set via the workflow or the configure script):
   ```
   Server=tcp:ahkflow-sql-dev.database.windows.net,1433;
   Database=ahkflow-db;
   Authentication=Active Directory Default;
   Encrypt=True;
   TrustServerCertificate=False;
   ```
   No password. `Active Directory Default` + `AZURE_CLIENT_ID` env var points App Service's DefaultAzureCredential chain at the runtime UAMI.
4. API code (`AppDbContext` registration) uses plain `UseSqlServer(connectionString)` — the Microsoft.Data.SqlClient driver handles Entra token acquisition via the connection-string `Authentication` keyword. **Requires `Azure.Identity` in the dependency closure.** Modern `Microsoft.Data.SqlClient` (6.x+) bundles it transitively, but the rollout section below includes a verification step to confirm — and if missing, adds an explicit `<PackageReference Include="Azure.Identity" />` to `AHKFlowApp.Infrastructure`.

### Least-privilege summary

| Principal | Scope | Role | Why |
|---|---|---|---|
| Deployer UAMI | Resource group `rg-ahkflow-dev` | `Contributor` | Needs to update App Service config + push container |
| Deployer UAMI | Static Web App | via `AZURE_STATIC_WEB_APPS_API_TOKEN` (not RBAC) | SWA deploy action takes a scoped API token |
| Deployer UAMI | SQL server | `db_owner` (via Entra admin group) | EF idempotent script may need schema changes |
| Runtime UAMI | SQL database | read/write/execute only | App Service runtime cannot alter schema |
| Runtime UAMI | Key Vault | `Key Vault Secrets User` | Read app settings at runtime via Key Vault references |
| `GITHUB_TOKEN` (ci.yml) | Repo | `contents: read` | Build + test only; no writes |
| `GITHUB_TOKEN` (deploy-api.yml) | Repo | `contents: read`, `id-token: write`, `packages: write` | OIDC to Azure + push to GHCR |
| `GITHUB_TOKEN` (deploy-frontend.yml) | Repo | `contents: read`, `id-token: write` | OIDC to Azure (for federated SWA tokens, if used) |
| `GITHUB_TOKEN` (migrate-db.yml) | Repo | `contents: read`, `id-token: write` | OIDC to Azure only |

Note: Contributor-on-RG is slightly broader than strictly needed. Tighter alternative is `Website Contributor` + `Reader` on the RG, but Contributor-on-RG is simpler to explain and audit, and scope is only the single env RG. This trade-off is called out in `02-configure-github-oidc.md`.

## Workflow files

All four files pin `actions/checkout@v4`, `actions/setup-dotnet@v4`, `azure/login@v2`, `azure/webapps-deploy@v3`, `Azure/static-web-apps-deploy@v1`, `docker/login-action@v3`, `docker/build-push-action@v6`, `docker/metadata-action@v5`. Non-first-party actions pinned by SHA.

### `ci.yml` — PR gate

```yaml
name: CI

on:
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # MinVer needs full history
      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json
      - run: dotnet restore
      - run: dotnet build --configuration Release --no-restore
      - run: dotnet test --configuration Release --no-build --verbosity normal
      - run: dotnet format --verify-no-changes
```

### `deploy-api.yml` — main → container → App Service

```yaml
name: Deploy API

on:
  push:
    branches: [main]
    paths:
      - 'src/Backend/**'
      - 'tests/**'
      - 'Directory.*.props'
      - 'global.json'
      - '.github/workflows/deploy-api.yml'
  workflow_dispatch:

permissions:
  contents: read
  id-token: write
  packages: write

env:
  IMAGE_NAME: ghcr.io/${{ github.repository_owner }}/ahkflowapp-api
  # Note: dotnet-ef version is derived at runtime from Directory.Packages.props
  # (Microsoft.EntityFrameworkCore.Design) to satisfy the "no hardcoded versions" rule.

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-dotnet@v4
        with: { global-json-file: global.json }
      - run: dotnet restore
      - run: dotnet build --configuration Release --no-restore
      - run: dotnet test --configuration Release --no-build

  build-push-image:
    needs: build-test
    runs-on: ubuntu-latest
    outputs:
      image-ref: ${{ steps.image-ref.outputs.value }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }  # MinVer-style version derivation via metadata-action
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_NAME }}
          tags: |
            type=sha,format=long
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=branch
      - id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          file: src/Backend/AHKFlowApp.API/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - id: image-ref
        # Deploy uses the immutable digest (not a mutable tag) so re-running an old workflow run
        # always deploys exactly the image that run produced — rollback by re-running works.
        run: echo "value=${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}" >> "$GITHUB_OUTPUT"

  migrate-db:
    # Sequential after image push so `deploy` has a clean linear dependency chain.
    # If migration fails, the image is still pushed to GHCR — that's fine (harmless, untagged-
    # for-deploy, garbage-collected later).
    needs: build-push-image
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-dotnet@v4
        with: { global-json-file: global.json }
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Add runner IP to SQL firewall
        id: fw
        run: |
          runner_ip=$(curl -s https://api.ipify.org)
          echo "ip=$runner_ip" >> "$GITHUB_OUTPUT"
          az sql server firewall-rule create \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}" \
            --server "${{ vars.SQL_SERVER_NAME }}" \
            --name "gh-runner-${GITHUB_RUN_ID}" \
            --start-ip-address "$runner_ip" \
            --end-ip-address "$runner_ip"
      - name: Derive EF Core version from Directory.Packages.props
        id: ef
        run: |
          ef_version=$(grep -oE 'Include="Microsoft\.EntityFrameworkCore\.Design"[[:space:]]+Version="[^"]+"' Directory.Packages.props \
            | grep -oE 'Version="[^"]+"' | head -n1 | cut -d'"' -f2)
          test -n "$ef_version" || { echo "Could not find Microsoft.EntityFrameworkCore.Design version"; exit 1; }
          echo "version=$ef_version" >> "$GITHUB_OUTPUT"
      - name: Apply migrations via dotnet ef database update
        env:
          ConnectionStrings__DefaultConnection: >-
            Server=tcp:${{ vars.SQL_SERVER_FQDN }},1433;
            Database=${{ vars.SQL_DATABASE_NAME }};
            Authentication=Active Directory Default;
            Encrypt=True;
            TrustServerCertificate=False;
            Connection Timeout=30;
          # DefaultAzureCredential picks up the az login token from azure/login@v2
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
        run: |
          dotnet tool install --global dotnet-ef --version "${{ steps.ef.outputs.version }}"
          dotnet ef database update \
            --project src/Backend/AHKFlowApp.Infrastructure \
            --startup-project src/Backend/AHKFlowApp.API
      - name: Remove runner IP from SQL firewall
        if: always()
        run: |
          az sql server firewall-rule delete \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}" \
            --server "${{ vars.SQL_SERVER_NAME }}" \
            --name "gh-runner-${GITHUB_RUN_ID}" || true

  deploy:
    needs: [build-push-image, migrate-db]
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Set container image on App Service
        run: |
          az webapp config container set \
            --name "${{ vars.APP_SERVICE_NAME }}" \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}" \
            --container-image-name "${{ needs.build-push-image.outputs.image-ref }}" \
            --container-registry-url "https://ghcr.io"
          az webapp restart \
            --name "${{ vars.APP_SERVICE_NAME }}" \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}"
      - name: Health check
        # 12 attempts × 15s = 3 minutes. Covers Entra group-membership propagation (up to ~5 min)
        # plus container cold start. Health endpoint hits SQL via AddDbContextCheck<AppDbContext>.
        run: |
          url="https://${{ vars.APP_SERVICE_NAME }}.azurewebsites.net/health"
          for i in $(seq 1 12); do
            if curl -fsS "$url"; then exit 0; fi
            echo "Attempt $i/12 failed, retrying in 15s..."
            sleep 15
          done
          echo "Health check failed after 3 minutes. Check App Service logs: az webapp log tail ..."
          exit 1
```

### `deploy-frontend.yml` — main → Static Web Apps

```yaml
name: Deploy Frontend

on:
  push:
    branches: [main]
    paths:
      - 'src/Frontend/**'
      - '.github/workflows/deploy-frontend.yml'
  workflow_dispatch:

permissions:
  contents: read
  id-token: write
  pull-requests: write  # SWA action comments on PRs for preview envs (future)

jobs:
  build-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-dotnet@v4
        with: { global-json-file: global.json }
      - uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          action: upload
          app_location: src/Frontend/AHKFlowApp.UI.Blazor
          output_location: wwwroot
```

### `migrate-db.yml` — manual trigger

Identical steps to the `migrate-db` job in `deploy-api.yml`, but standalone for ad-hoc use (e.g., applying a migration without a code deploy, or recovery after a failed deploy).

```yaml
name: Migrate Database (Manual)

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type "migrate" to confirm'
        required: true

permissions:
  contents: read
  id-token: write

jobs:
  migrate:
    if: inputs.confirm == 'migrate'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-dotnet@v4
        with: { global-json-file: global.json }
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Add runner IP to SQL firewall
        run: |
          runner_ip=$(curl -s https://api.ipify.org)
          az sql server firewall-rule create \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}" \
            --server "${{ vars.SQL_SERVER_NAME }}" \
            --name "gh-runner-${GITHUB_RUN_ID}" \
            --start-ip-address "$runner_ip" \
            --end-ip-address "$runner_ip"
      - name: Derive EF Core version from Directory.Packages.props
        id: ef
        run: |
          ef_version=$(grep -oE 'Include="Microsoft\.EntityFrameworkCore\.Design"[[:space:]]+Version="[^"]+"' Directory.Packages.props \
            | grep -oE 'Version="[^"]+"' | head -n1 | cut -d'"' -f2)
          test -n "$ef_version" || { echo "Could not find Microsoft.EntityFrameworkCore.Design version"; exit 1; }
          echo "version=$ef_version" >> "$GITHUB_OUTPUT"
      - name: Apply migrations
        env:
          ConnectionStrings__DefaultConnection: >-
            Server=tcp:${{ vars.SQL_SERVER_FQDN }},1433;
            Database=${{ vars.SQL_DATABASE_NAME }};
            Authentication=Active Directory Default;
            Encrypt=True;
            TrustServerCertificate=False;
            Connection Timeout=30;
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
        run: |
          dotnet tool install --global dotnet-ef --version "${{ steps.ef.outputs.version }}"
          dotnet ef database update \
            --project src/Backend/AHKFlowApp.Infrastructure \
            --startup-project src/Backend/AHKFlowApp.API
      - name: Remove runner IP from SQL firewall
        if: always()
        run: |
          az sql server firewall-rule delete \
            --resource-group "${{ vars.AZURE_RESOURCE_GROUP }}" \
            --server "${{ vars.SQL_SERVER_NAME }}" \
            --name "gh-runner-${GITHUB_RUN_ID}" || true
```

## Provisioning scripts (`scripts/azure/`)

Four markdown files. Each file has a `## Variables` section at the top the reader copy-pastes into their shell, then numbered bash code blocks the reader runs in order. All `az X create` calls are preceded by `az X show ... || az X create ...` for idempotency.

### `00-prerequisites.md`

- Lists required local tools: `az` CLI ≥ 2.60, `gh` CLI, Docker Desktop, `dotnet` SDK 10 (used by script 02 for the SQL user creation step via `sqlcmd` OR by running a throwaway `dotnet-ef` command — final choice documented in script 02).
- `az login` + `az account set --subscription <SUB_ID>`.
- `gh auth login` (needed by script 02 for `gh secret set` / `gh variable set`).
- Confirms current subscription has permissions to create RG, SQL, App Service, Key Vault, SWA, UAMI, role assignments.
- Confirms operator can create Entra security groups (needed for SQL admin group).
- Links to Azure Free Tier info.

### `01-provision-azure.md`

Variables block at top:

```bash
ENVIRONMENT="dev"                             # dev | prod
LOCATION="westeurope"                         # any Azure region
BASE_NAME="ahkflow"

RESOURCE_GROUP="rg-${BASE_NAME}-${ENVIRONMENT}"
SQL_SERVER_NAME="${BASE_NAME}-sql-${ENVIRONMENT}"
SQL_DATABASE_NAME="${BASE_NAME}-db"
KEY_VAULT_NAME="${BASE_NAME}-kv-${ENVIRONMENT}"
APP_SERVICE_PLAN="${BASE_NAME}-plan-${ENVIRONMENT}"
APP_SERVICE_NAME="${BASE_NAME}-api-${ENVIRONMENT}"
SWA_NAME="${BASE_NAME}-swa-${ENVIRONMENT}"
LAW_NAME="${BASE_NAME}-logs-${ENVIRONMENT}"
APP_INSIGHTS_NAME="${BASE_NAME}-insights-${ENVIRONMENT}"
UAMI_DEPLOYER_NAME="${BASE_NAME}-uami-deployer-${ENVIRONMENT}"
UAMI_RUNTIME_NAME="${BASE_NAME}-uami-runtime-${ENVIRONMENT}"
SQL_ADMIN_GROUP="${BASE_NAME}-sql-admins-${ENVIRONMENT}"
```

Numbered sections:
1. Register resource providers (`Microsoft.Web`, `Microsoft.Sql`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.ManagedIdentity`).
2. Resource group.
3. Log Analytics workspace + App Insights.
4. Entra group `ahkflow-sql-admins-dev`; add current user to it.
5. SQL server (Entra admin = group) + SQL database (Basic tier) + firewall rule to allow Azure services + firewall rule for current public IP (for the sqlcmd in script 02).
6. Key Vault (RBAC-enabled); assign current user `Key Vault Secrets Officer`.
7. App Service plan (B1 Linux).
8. UAMIs (deployer + runtime).
9. App Service (Linux, container mode). Initial container image points at `nginx:latest` as a throwaway placeholder — first real image is set by `deploy-api.yml`. Assign runtime UAMI to the App Service. Set `AZURE_CLIENT_ID` app setting to the runtime UAMI client ID (so `DefaultAzureCredential` in the API runtime picks the right identity).
10. Static Web App (Free tier).
11. Print a summary with all resource IDs the reader will need for script 02.

**Entra app registrations (API + SPA) are explicitly NOT created in script 01** — authentication/authorization wiring is deferred to backlog item 012. Script 01 only creates the infrastructure needed to build + deploy a container. The App Service will serve HTTP endpoints but have no auth enforced until item 012 lands.

### `02-configure-github-oidc.md`

Variables block (continues from 01):

```bash
GITHUB_ORG="<your-github-username-or-org>"
GITHUB_REPO="AHKFlowApp"
```

Numbered sections:
1. Add federated identity credentials to deployer UAMI, one per trigger:
   - `repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main` (deploy workflows)
   - `repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request` (future CI OIDC, not used today but costs nothing)
2. RBAC assignments:
   - Deployer UAMI: `Contributor` on the RG.
   - Runtime UAMI: `Key Vault Secrets User` on the Key Vault.
   - Add deployer UAMI to `ahkflow-sql-admins-dev` group.
3. SQL user for runtime UAMI. Run as the operator (who is a member of the SQL admin group from script 01). Two options — both documented in the script, with the simpler one as default:
   - **Default (simpler):** `sqlcmd -S <server> -d <db> -G -i create-runtime-user.sql` where the .sql file contains:
     ```sql
     CREATE USER [ahkflow-uami-runtime-dev] FROM EXTERNAL PROVIDER;
     ALTER ROLE db_datareader ADD MEMBER [ahkflow-uami-runtime-dev];
     ALTER ROLE db_datawriter ADD MEMBER [ahkflow-uami-runtime-dev];
     GRANT EXECUTE TO [ahkflow-uami-runtime-dev];
     ```
     The `-G` flag uses Entra auth from the current `az login` context. This requires `sqlcmd` locally. On Windows it ships with SSMS; on Linux/macOS install `mssql-tools18`.
   - **Alternative (no sqlcmd needed):** use the Azure Portal "Query editor" blade on the SQL database and paste the SQL. Slower but zero-install.
4. Set GitHub secrets (via `gh secret set`):
   - `AZURE_CLIENT_ID` — deployer UAMI client ID
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_STATIC_WEB_APPS_API_TOKEN` — from `az staticwebapp secrets list --name "$SWA_NAME" --query "properties.apiKey" -o tsv`
5. Set GitHub variables (via `gh variable set`):
   - `AZURE_RESOURCE_GROUP`
   - `APP_SERVICE_NAME`
   - `SQL_SERVER_NAME` (short name, for firewall rule management)
   - `SQL_SERVER_FQDN` (e.g., `ahkflow-sql-dev.database.windows.net`)
   - `SQL_DATABASE_NAME`
6. Configure App Service env vars + connection string:
   - Env vars (minimal set — auth-related vars deferred to item 012):
     - `ASPNETCORE_ENVIRONMENT=Production`
     - `AZURE_CLIENT_ID=<runtime UAMI client ID>` — picked up by `DefaultAzureCredential` to select the right managed identity when multiple are assigned.
     - `APPLICATIONINSIGHTS_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=...)` — Key Vault reference.
     - `WEBSITES_PORT=8080` — matches Dockerfile `EXPOSE 8080`.
   - Connection string (`az webapp config connection-string set --connection-string-type SQLAzure`):
     ```
     Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
     ```
7. Configure CORS on the App Service:
   ```bash
   SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --query "defaultHostname" -o tsv)
   az webapp cors add \
     --name "$APP_SERVICE_NAME" \
     --resource-group "$RESOURCE_GROUP" \
     --allowed-origins "https://${SWA_HOSTNAME}"
   ```
8. Make the GHCR package public so App Service can pull anonymously:
   - First push must happen before the package exists. Script 02 closes with a reminder: after the first successful `deploy-api.yml` run, go to `https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/pkgs/container/ahkflowapp-api/settings` and set visibility to `Public`. Or via CLI: `gh api -X PATCH /user/packages/container/ahkflowapp-api/visibility -f visibility=public` (requires an extra PAT scope; manual UI is simpler).

### `99-teardown.md`

Single `az group delete --name "$RESOURCE_GROUP" --yes --no-wait` + Entra cleanup (delete group, UAMIs already in RG, app registrations). Includes safety prompt.

## GitHub secrets & variables (summary)

Set by script 02. Everything here exists because it can't be derived at runtime.

**Secrets (sensitive, `gh secret set`):**
- `AZURE_CLIENT_ID` — deployer UAMI client ID (not strictly secret, but stored as secret per MS recommendation)
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_STATIC_WEB_APPS_API_TOKEN`

**Variables (non-sensitive, `gh variable set`):**
- `AZURE_RESOURCE_GROUP`
- `APP_SERVICE_NAME`
- `SQL_SERVER_FQDN`
- `SQL_DATABASE_NAME`

## Rollout / execution order (for the implementation plan)

1. **Verify `Azure.Identity` is in the runtime dependency closure:**
   ```bash
   dotnet list src/Backend/AHKFlowApp.Infrastructure package --include-transitive | grep -i azure.identity
   ```
   If the grep is empty, add `<PackageReference Include="Azure.Identity" />` to `Directory.Packages.props` and reference it from `AHKFlowApp.Infrastructure.csproj`. Modern `Microsoft.Data.SqlClient` (6.x+) bundles it transitively, so this is usually a no-op — but we must verify, not assume.
2. **Run `dotnet format` locally** and commit any whitespace/style fixes so `ci.yml` passes on the PR.
3. **Implement in repo:** workflows + scripts on the current feature branch. PRs will not yet have any Azure resources, so CI runs on the PR but deploy workflows only trigger after merge.
4. **Human runs `scripts/azure/00-prerequisites.md`** — installs tools, logs in.
5. **Human runs `scripts/azure/01-provision-azure.md`** — creates Azure resources. Idempotent.
6. **Human runs `scripts/azure/02-configure-github-oidc.md`** — creates UAMIs + federated credentials + SQL users + GitHub secrets/vars.
7. **Open PR with the workflows** — CI workflow should succeed (no Azure needed, just build + test + format check).
8. **Merge PR to main** — `deploy-api.yml` and `deploy-frontend.yml` trigger.
9. **First `deploy-api.yml` run pushes the image to GHCR (private by default).** The deploy step will fail because App Service can't pull a private image without credentials.
10. **Set GHCR package visibility to Public** (UI or `gh api` — see script 02 step 8), then re-run the `deploy` job.
11. **Verify** — `curl https://ahkflow-api-dev.azurewebsites.net/health`, load the SWA URL in a browser.
12. **If something breaks** — re-run failed job (rollback = re-run the previous successful workflow run; image digest in that run is immutable).

## Risks / edge cases

- **First-ever deploy race**: `deploy-api.yml` assumes the App Service exists. If script 01 hasn't been run, `az webapp config container set` fails. Mitigated by documenting script order in `02-configure-github-oidc.md`'s closing section and in the rollout section of this spec.
- **GHCR package visibility on first push**: GHCR defaults new packages to `private`. App Service for Linux cannot pull from a private GHCR package without credentials. The first `deploy-api.yml` run WILL push the image successfully but the `deploy` job WILL fail on `az webapp config container set`. Expected — the rollout instructs the human to flip visibility to public after the first push, then re-run the `deploy` job. Documented loudly in both the rollout section and script 02.
- **Image digest vs tag in deploy**: `deploy` uses the immutable digest (`ghcr.io/.../ahkflowapp-api@sha256:...`), not a mutable tag like `latest`. This means re-running an OLD workflow run redeploys the exact image that run produced — true rollback by workflow re-run.
- **MinVer in Docker build**: 009's Dockerfile uses `/p:MinVerSkip=true` because `.git/` is `.dockerignore`'d. The image's internal assembly version is therefore `0.0.0-alpha.0`. The OCI label `org.opencontainers.image.version` on the image (set by `docker/metadata-action`) reflects the actual git-derived version because the metadata action reads `.git/` from the host workspace, which IS checked out. Acceptable for item 010; can revisit in a future "version stamp in container" item if needed.
- **Entra auth propagation delay**: newly-created group memberships can take 1–5 minutes to propagate. Script 02 sleeps 30s after adding UAMIs to the admin group and prints a warning. Health check in `deploy-api.yml` retries for 3 minutes to cover any residual delay at first-deploy time.
- **Runner IP add/remove dance on SQL firewall**: safer than allowing all Azure services, but creates a transient firewall rule named `gh-runner-<run-id>`. The `if: always()` cleanup step removes it even on failure; leftover rules from killed runners can accumulate. Document a periodic cleanup command in script 02 or 99.
- **EF tools install in CI**: `dotnet tool install --global dotnet-ef --version <derived>` each run adds ~10s. Acceptable; could cache `~/.dotnet/tools` in a future optimization.
- **EF tool version is derived at runtime** from `Directory.Packages.props` (anchored on `Microsoft.EntityFrameworkCore.Design` — that package's version IS the dotnet-ef tool version we need). Satisfies AGENTS.md "never hardcode package versions" rule; zero drift risk.
- **GHCR token scope**: `packages: write` is a per-workflow permission; does NOT require a PAT.
- **`dotnet format --verify-no-changes` gate**: the project may currently have uncommitted formatting violations. Rollout step 2 instructs running `dotnet format` locally first.
- **Connection string YAML multi-line parsing**: the `>-` folded style in `deploy-api.yml` strips newlines and trailing newline. The resulting value must not contain ambiguous characters. Verified safe for the Entra-ID connection string format.

## Testing / verification plan

No unit tests for workflows themselves (GitHub Actions doesn't have a great story for this). Verification is done by the `ci.yml` workflow running on the PR that introduces these files, plus manual validation after merge.

- `ci.yml` must pass on the PR introducing this spec's implementation.
- After merge + `01` + `02` executed: `deploy-api.yml` must reach `deploy` job successfully, health check must return 200.
- After `deploy-frontend.yml`: SWA default URL must serve the Blazor app.
- `act` local runner is not used — GitHub's hosted runners are the source of truth.

## Files created / modified

**New:**
- `.github/workflows/ci.yml`
- `.github/workflows/deploy-api.yml`
- `.github/workflows/deploy-frontend.yml`
- `.github/workflows/migrate-db.yml`
- `scripts/azure/00-prerequisites.md`
- `scripts/azure/01-provision-azure.md`
- `scripts/azure/02-configure-github-oidc.md`
- `scripts/azure/99-teardown.md`

**Modified:**
- `.claude/backlog/010-create-ci-cd-pipeline.md` — mark complete on merge.

No source code changes. No config changes to `src/Backend/AHKFlowApp.API/appsettings*.json` (production settings will be set as App Service env vars by script 02).

## Future improvements (non-blocking, not in this spec)

- Add `prod` environment by re-running scripts with `ENVIRONMENT=prod` + adding a second federated credential for a `production` GitHub Environment with required reviewers.
- Convert `01-provision-azure.md` to a Bicep template.
- Replace GHCR with ACR if the image needs to go private (App Service can pull from ACR via managed identity — no secrets).
- Add Blue/green via App Service deployment slots (requires Standard tier plan).
- Add CodeQL / dependency scanning workflows.
- Add PR preview environments via Static Web Apps staging slots (automatic for SWA on PRs).
- Cache `~/.dotnet/tools` to speed up `dotnet-ef` install.
- Extract the migrate-db job into a reusable workflow (`workflow_call`) shared between `deploy-api.yml` and `migrate-db.yml` to avoid drift.
- Use `GitHubActionsTestLogger` for nicer PR test annotations.
- Wire Entra app registrations and auth enforcement (deferred to backlog item 012).

## Open questions

None — all user questions answered. Defaults applied: GHCR (Q2), single `dev` env first (Q3).
