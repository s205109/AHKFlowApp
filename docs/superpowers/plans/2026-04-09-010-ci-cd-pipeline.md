# 010 — CI/CD Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship first real CI/CD for AHKFlowApp — CI on PRs, containerised API deploy to Azure App Service for Linux via GHCR, Blazor frontend deploy to Azure Static Web Apps, and a one-run Azure bootstrap that a brand-new contributor can execute from zero. Supports three environments: **DEV** (local development), **TEST** (Azure pre-production), and **PROD** (Azure production).

**Architecture:** Four GitHub Actions workflows (`ci`, `deploy-api`, `deploy-frontend`, `migrate-db`) authenticating to Azure via user-assigned managed identity + OIDC federated credentials (no long-lived secrets). API deploys as a container (GHCR → App Service for Linux). SQL uses Entra-only auth — no passwords. EF Core migrations run from CI via `dotnet ef database update` with a temporary firewall rule for the runner's IP. Four markdown provisioning runbooks in `scripts/azure/` stand up the whole Azure environment idempotently for each environment (TEST/PROD).

**Environment Configuration:**
- **DEV:** Local machine (`ASPNETCORE_ENVIRONMENT=Development`), LocalDB or Docker SQL Server
- **TEST:** Azure deployment (`ASPNETCORE_ENVIRONMENT=Test`), Azure SQL Database, deployed from `main` branch
- **PROD:** Azure deployment (`ASPNETCORE_ENVIRONMENT=Production`), Azure SQL Database, deployed via manual workflow trigger with approval

**Tech Stack:** GitHub Actions, Azure CLI, Azure App Service for Linux (containers), Azure Static Web Apps (Free), Azure SQL Database, Azure Key Vault, Entra ID (security groups + UAMI + federated credentials), GHCR, Docker Buildx, EF Core 10 tools.

**Spec:** [`docs/superpowers/specs/2026-04-09-010-ci-cd-pipeline-design.md`](../specs/2026-04-09-010-ci-cd-pipeline-design.md) — read this first for the full design rationale.

**Branch:** `feature/009-docker-development-setup` (per user instruction — will be merged to `main` soon, then this work continues from `main`). **If 009 has already merged when you start this plan, branch from `main` instead as `feature/010-ci-cd-pipeline`.**

**Backlog item:** [`.claude/backlog/010-create-ci-cd-pipeline.md`](../../../.claude/backlog/010-create-ci-cd-pipeline.md)

---

## File Structure

| File | Purpose | Action |
|---|---|---|
| `.github/workflows/ci.yml` | PR gate: build + test + format | Create |
| `.github/workflows/deploy-api.yml` | main → build container → push GHCR → migrate DB → deploy to App Service | Create |
| `.github/workflows/deploy-frontend.yml` | main → build Blazor wasm → deploy to SWA | Create |
| `.github/workflows/migrate-db.yml` | Manual DB migration via `workflow_dispatch` | Create |
| `scripts/azure/00-prerequisites.md` | Tool install + `az login` + `gh auth login` | Create |
| `scripts/azure/01-provision-azure.md` | Idempotent Azure resource bootstrap | Create |
| `scripts/azure/02-configure-github-oidc.md` | UAMIs + federated credentials + SQL users + `gh secret set` | Create |
| `scripts/azure/99-teardown.md` | Delete the resource group | Create |
| `Directory.Packages.props` | Add `Azure.Identity` if missing (Task 1) | Possibly modify |
| `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj` | Add `Azure.Identity` reference if missing (Task 1) | Possibly modify |
| `.claude/backlog/010-create-ci-cd-pipeline.md` | Mark complete at end of rollout | Modify |

**No application source code changes** beyond the optional `Azure.Identity` package add. No config changes to `appsettings*.json` — production settings are set at runtime by the provisioning scripts as App Service env vars.

**Validation approach:** There is nothing to TDD for YAML workflow files or bash runbooks. Each task's "verify" step is one of: a `grep` structural sanity check for top-level YAML keys (full YAML parse validation happens when CI runs), `dotnet build` + `dotnet test` when touching C# project files, and human runbook execution for the Azure bootstrap phase. The real YAML gate is Task 11 Step 6 — if any workflow file is malformed, GitHub Actions will fail to parse it and `gh pr checks --watch` will surface the error.

---

## Phase 1 — Pre-flight

### Task 1: Verify `Azure.Identity` is in the runtime dependency closure

**Files:**
- Possibly modify: `Directory.Packages.props`
- Possibly modify: `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj`

**Why this exists:** The API runtime uses `Authentication=Active Directory Default` in the SQL connection string. `Microsoft.Data.SqlClient` needs `Azure.Identity` in its dependency closure to run the full `DefaultAzureCredential` chain (which includes `ManagedIdentityCredential`). Modern `Microsoft.Data.SqlClient` 6.x bundles `Azure.Identity` transitively — but we must verify, not assume. If missing, the first production run will explode with "Unable to load type 'Azure.Identity.DefaultAzureCredential'" at connection time.

- [ ] **Step 1: Check if `Azure.Identity` is already in the transitive closure**

```bash
dotnet list src/Backend/AHKFlowApp.Infrastructure package --include-transitive | grep -i "azure\.identity"
```

**Expected (happy path):** a line like `> Azure.Identity <version>` (transitive via `Microsoft.Data.SqlClient`). If you see output, skip to Step 5.

**Expected (unhappy path):** empty output. Proceed to Step 2.

- [ ] **Step 2: Resolve the latest stable version, then add to Central Package Management**

Per AGENTS.md: never hardcode package versions from memory. Resolve the latest first:

```bash
# Temporarily add to the Infrastructure project to make NuGet pick the latest stable, then copy the version:
dotnet add src/Backend/AHKFlowApp.Infrastructure package Azure.Identity
# Note the version that got written into the .csproj, then remove the unversioned reference:
dotnet remove src/Backend/AHKFlowApp.Infrastructure package Azure.Identity
```

Alternatively, inspect `https://www.nuget.org/packages/Azure.Identity` and copy the latest stable version string.

Edit `Directory.Packages.props`. Find the `<ItemGroup>` containing package versions and add (in alphabetical order):

```xml
<PackageVersion Include="Azure.Identity" Version="<resolved-version>" />
```

- [ ] **Step 3: Reference the package from the Infrastructure project**

Edit `src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj`. Find the `<ItemGroup>` with `<PackageReference>` entries and add:

```xml
<PackageReference Include="Azure.Identity" />
```

(No `Version=` — CPM supplies it.)

- [ ] **Step 4: Verify build still passes**

Run:

```bash
dotnet build --configuration Release
```

**Expected:** `Build succeeded. 0 Warning(s). 0 Error(s).`

- [ ] **Step 5: Commit (if Step 2–4 executed)**

```bash
git add Directory.Packages.props src/Backend/AHKFlowApp.Infrastructure/AHKFlowApp.Infrastructure.csproj
git commit -m "chore: add Azure.Identity for Entra SQL auth in prod"
```

If Step 1 confirmed it was already transitive, no commit — skip.

---

### Task 2: Run `dotnet format` locally and commit fixes

**Why this exists:** The new `ci.yml` gates PRs on `dotnet format --verify-no-changes`. If the current tree has accumulated whitespace or style drift, the PR introducing `ci.yml` will fail the very check it just introduced. Fix first.

- [ ] **Step 1: Run format**

```bash
dotnet format
```

**Expected:** exit 0. Any files modified will show in `git status`.

- [ ] **Step 2: Verify the fix sticks**

```bash
dotnet format --verify-no-changes
```

**Expected:** exit 0 with no output. If this fails, run Step 1 again and investigate.

- [ ] **Step 3: Commit (if Step 1 modified anything)**

```bash
git status  # inspect scope first
git diff --stat  # how many files?
```

- **Small diff (< ~10 files, whitespace/using-ordering only):** commit in this branch.

  ```bash
  git add -A
  git commit -m "style: apply dotnet format"
  ```

- **Large diff (many files, or touches logic-adjacent lines like braces/indentation on real code):** STOP and report back. A big format churn should land as its own PR on `main` first, before this feature branch, so 010's diff stays focused. Do not bundle it.

---

## Phase 2 — Workflow files

### Task 3: Create `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

**Why this exists:** Closes backlog AC #1 ("CI runs on pull requests: build + unit tests"). Triggers on any PR targeting `main`. Scope is tight: `contents: read` only.

- [ ] **Step 1: Create the directory if it doesn't exist**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write the workflow file**

Create `.github/workflows/ci.yml` with exactly this content:

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
          fetch-depth: 0  # MinVer needs full history for version derivation
      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json
      - run: dotnet restore
      - run: dotnet build --configuration Release --no-restore
      - run: dotnet test --configuration Release --no-build --verbosity normal
      - run: dotnet format --verify-no-changes
```

- [ ] **Step 3: Sanity-check the file has the expected top-level keys**

```bash
grep -q "^name:" .github/workflows/ci.yml && grep -q "^on:" .github/workflows/ci.yml && grep -q "^jobs:" .github/workflows/ci.yml && echo "structure OK"
```

**Expected:** `structure OK`. Full YAML parse validation happens on PR push — CI flags syntax errors in Task 11.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add PR build/test/format gate"
```

---

### Task 4: Create `.github/workflows/deploy-api.yml`

**Files:**
- Create: `.github/workflows/deploy-api.yml`

**Why this exists:** Closes backlog AC #2 and #4. Four sequential jobs: `build-test → build-push-image → migrate-db → deploy`. Image is pushed to GHCR by digest (immutable); deploy uses the digest, not a mutable tag. Migration opens a transient SQL firewall rule for the runner's IP and tears it down in `if: always()`. Health check retries 12×15s to cover Entra propagation on first deploy.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/deploy-api.yml` with exactly this content (see spec section "deploy-api.yml — main → container → App Service" for rationale on each block):

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
        with: { fetch-depth: 0 }
      - uses: docker/setup-buildx-action@v3  # Required for type=gha cache backend below
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
      - name: Verify digest is set
        run: |
          digest="${{ steps.build.outputs.digest }}"
          test -n "$digest" || { echo "docker/build-push-action produced an empty digest — deploy would deploy a stale image"; exit 1; }
          echo "Digest: $digest"
      - id: image-ref
        # Deploy uses the immutable digest so re-running an old workflow run redeploys
        # exactly that run's image — true rollback by re-run.
        run: echo "value=${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}" >> "$GITHUB_OUTPUT"

  migrate-db:
    # Sequential after image push so `deploy` has a clean linear dependency chain.
    # If migration fails, the image is still in GHCR (harmless, garbage-collected later).
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
          # Extract the Microsoft.EntityFrameworkCore pinned version so dotnet-ef matches the runtime EF Core.
          # Microsoft.EntityFrameworkCore.Design version === dotnet-ef tool version we need.
          ef_version=$(grep -oE 'Include="Microsoft\.EntityFrameworkCore\.Design"[[:space:]]+Version="[^"]+"' Directory.Packages.props \
            | grep -oE 'Version="[^"]+"' | head -n1 | cut -d'"' -f2)
          test -n "$ef_version" || { echo "Could not find Microsoft.EntityFrameworkCore version in Directory.Packages.props"; exit 1; }
          echo "version=$ef_version" >> "$GITHUB_OUTPUT"
          echo "Using dotnet-ef $ef_version"
      - name: Apply migrations via dotnet ef database update
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
        # 12 x 15s = 3 minutes. Covers Entra propagation + container cold start.
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

- [ ] **Step 2: Sanity-check structure**

```bash
grep -q "^name:" .github/workflows/deploy-api.yml && grep -q "^jobs:" .github/workflows/deploy-api.yml && grep -q "deploy:" .github/workflows/deploy-api.yml && echo "structure OK"
```

**Expected:** `structure OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy-api.yml
git commit -m "ci: add API container deploy to App Service via GHCR"
```

---

### Task 5: Create `.github/workflows/deploy-frontend.yml`

**Files:**
- Create: `.github/workflows/deploy-frontend.yml`

**Why this exists:** Closes backlog AC #3. Builds the Blazor WASM project and deploys to Azure Static Web Apps via the official action. Triggered on `main` when frontend paths change, plus `workflow_dispatch` for manual redeploy.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/deploy-frontend.yml` with exactly this content:

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

- [ ] **Step 2: Sanity-check structure**

```bash
grep -q "^name:" .github/workflows/deploy-frontend.yml && grep -q "^jobs:" .github/workflows/deploy-frontend.yml && echo "structure OK"
```

**Expected:** `structure OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy-frontend.yml
git commit -m "ci: add Blazor WASM deploy to Static Web Apps"
```

---

### Task 6: Create `.github/workflows/migrate-db.yml`

**Files:**
- Create: `.github/workflows/migrate-db.yml`

**Why this exists:** Manual DB migration entry point — for ad-hoc migrations outside a full deploy, or recovery after a failed deploy. Gated by a typed confirmation input to prevent accidental triggering.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/migrate-db.yml` with exactly this content:

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
          # Microsoft.EntityFrameworkCore.Design version === dotnet-ef tool version we need.
          ef_version=$(grep -oE 'Include="Microsoft\.EntityFrameworkCore\.Design"[[:space:]]+Version="[^"]+"' Directory.Packages.props \
            | grep -oE 'Version="[^"]+"' | head -n1 | cut -d'"' -f2)
          test -n "$ef_version" || { echo "Could not find Microsoft.EntityFrameworkCore version in Directory.Packages.props"; exit 1; }
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

- [ ] **Step 2: Sanity-check structure**

```bash
grep -q "^name:" .github/workflows/migrate-db.yml && grep -q "workflow_dispatch:" .github/workflows/migrate-db.yml && echo "structure OK"
```

**Expected:** `structure OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/migrate-db.yml
git commit -m "ci: add manual database migration workflow"
```

---

## Phase 3 — Azure provisioning runbooks

These are markdown runbooks with bash code blocks at the top containing `Variables`, then numbered sections. Every `az X create` call is preceded by `az X show ... || az X create ...` for idempotency.

### Task 7: Create `scripts/azure/00-prerequisites.md`

**Files:**
- Create: `scripts/azure/00-prerequisites.md`

**Why this exists:** First stop for a new contributor. Documents required local tools, `az login`, `gh auth login`, and a permissions sanity check. Very short — 50-ish lines.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p scripts/azure
```

- [ ] **Step 2: Write the file**

Create `scripts/azure/00-prerequisites.md` with exactly this content:

````markdown
# 00 — Prerequisites

Read this first. Install the required local tools, log into Azure and GitHub, and sanity-check your permissions. Once you are done here, continue to [`01-provision-azure.md`](./01-provision-azure.md).

## Required tools

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI | 2.60+ | https://learn.microsoft.com/cli/azure/install-azure-cli |
| GitHub CLI (`gh`) | 2.40+ | https://cli.github.com/ |
| .NET SDK | 10.0 (match `global.json`) | https://dotnet.microsoft.com/download |
| Docker Desktop (optional, for local image testing) | recent | https://www.docker.com/products/docker-desktop/ |
| `sqlcmd` or SQL Server Management Studio (for the SQL user creation step in script 02) | any | Windows: bundled with SSMS. macOS/Linux: `mssql-tools18` |

## Log in

```bash
az login
az account set --subscription "<your-subscription-id>"
az account show  # verify

gh auth login  # pick GitHub.com, HTTPS, web browser
gh auth status  # verify
```

## Permissions sanity check

You need these permissions in the target Azure subscription:

- Create resource groups, SQL servers, App Service plans, Key Vaults, Static Web Apps, user-assigned managed identities.
- Assign RBAC roles at resource-group scope (`Owner` or `User Access Administrator`).
- Create Entra ID security groups (Groups Administrator or higher in the tenant).

Quick check:

```bash
# Can you create resource groups in the target subscription?
az group list -o table

# Can you create Entra groups?
az ad group list --query "[0].displayName" -o tsv  # if this returns a name, you can read at minimum
```

If either fails, contact your tenant admin before proceeding.

## Azure Free Tier

Azure Free Tier covers most resources this setup creates. Notable cost items:

- **App Service Plan B1 Linux**: ~$13/month.
- **Azure SQL Basic**: ~$5/month (can downgrade to Free tier offer while available).
- **Everything else** (Key Vault, App Insights, SWA, UAMI, Log Analytics): free or sub-$1/month at dev volumes.

Budget ~$20/month for a single dev environment. Run `scripts/azure/99-teardown.md` to stop the meter when you're done.

---

**Next:** [`01-provision-azure.md`](./01-provision-azure.md)
````

- [ ] **Step 3: Verify the markdown renders**

No tooling — just `cat scripts/azure/00-prerequisites.md` and eyeball it.

- [ ] **Step 4: Commit**

```bash
git add scripts/azure/00-prerequisites.md
git commit -m "docs: add Azure prerequisites runbook"
```

---

### Task 8: Create `scripts/azure/01-provision-azure.md`

**Files:**
- Create: `scripts/azure/01-provision-azure.md`

**Why this exists:** The main provisioning runbook. Creates all Azure resources idempotently. Reader runs each bash block in sequence. No Entra app registrations (deferred to item 012 per spec).

- [ ] **Step 1: Write the file**

Create `scripts/azure/01-provision-azure.md` with exactly this content:

````markdown
# 01 — Provision Azure resources

This runbook stands up the full Azure environment for a single environment (default: `dev`). All `az X create` calls are idempotent (preceded by `az X show ...`). Re-running a section is safe.

Prerequisite: you have completed [`00-prerequisites.md`](./00-prerequisites.md) and run `az login`.

## Variables

Set these once at the top of your shell. Re-export them if you open a new terminal. To provision a `prod` environment later, set `ENVIRONMENT=prod` and re-run everything.

```bash
ENVIRONMENT="dev"                                      # dev | prod
LOCATION="westeurope"                                  # any Azure region
BASE_NAME="ahkflow"                                    # project prefix

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

## 1. Register resource providers

```bash
for ns in Microsoft.Web Microsoft.Sql Microsoft.KeyVault \
          Microsoft.OperationalInsights Microsoft.Insights \
          Microsoft.ManagedIdentity; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)
  if [ "$state" != "Registered" ]; then
    echo "Registering $ns..."
    az provider register --namespace "$ns" >/dev/null
  else
    echo "$ns already registered"
  fi
done
```

## 2. Resource group

```bash
az group show --name "$RESOURCE_GROUP" &>/dev/null || \
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
```

## 3. Log Analytics workspace + Application Insights

```bash
az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" --workspace-name "$LAW_NAME" &>/dev/null || \
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LAW_NAME" \
  --location "$LOCATION"

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" --workspace-name "$LAW_NAME" --query id -o tsv)

az monitor app-insights component show \
  --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az monitor app-insights component create \
  --app "$APP_INSIGHTS_NAME" \
  --location "$LOCATION" \
  --resource-group "$RESOURCE_GROUP" \
  --workspace "$LAW_ID"
```

## 4. Entra security group for SQL admin

```bash
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv 2>/dev/null)
if [ -z "$GROUP_ID" ]; then
  GROUP_ID=$(az ad group create \
    --display-name "$SQL_ADMIN_GROUP" \
    --mail-nickname "$SQL_ADMIN_GROUP" \
    --query id -o tsv)
  echo "Created group $SQL_ADMIN_GROUP ($GROUP_ID)"
fi

# Add yourself so you can create SQL users in script 02
ME_ID=$(az ad signed-in-user show --query id -o tsv)
az ad group member check --group "$GROUP_ID" --member-id "$ME_ID" --query value -o tsv | grep -qi true || \
  az ad group member add --group "$GROUP_ID" --member-id "$ME_ID"
```

## 5. Azure SQL server + database (Entra-only auth)

```bash
az sql server show --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az sql server create \
  --name "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "$SQL_ADMIN_GROUP" \
  --external-admin-sid "$GROUP_ID"

az sql db show \
  --name "$SQL_DATABASE_NAME" \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az sql db create \
  --name "$SQL_DATABASE_NAME" \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --service-objective Basic \
  --backup-storage-redundancy Local

# Allow Azure services (required for App Service to reach SQL via Active Directory Default)
az sql server firewall-rule show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowAllAzureServices &>/dev/null || \
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowAllAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Allow your current IP so you can create SQL users in script 02
MY_IP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name "operator-${USER}-$(date +%s)" \
  --start-ip-address "$MY_IP" \
  --end-ip-address "$MY_IP"
```

## 6. Key Vault

```bash
az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az keyvault create \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku standard \
  --enable-rbac-authorization true

# Assign yourself Secrets Officer so you can manage secrets
KV_SCOPE=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$ME_ID" \
  --scope "$KV_SCOPE" 2>/dev/null || echo "Role already assigned"
```

## 7. App Service plan (Linux B1)

```bash
az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku B1 \
  --is-linux
```

## 8. User-assigned managed identities

```bash
az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az identity create \
  --name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az identity create \
  --name "$UAMI_RUNTIME_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

UAMI_RUNTIME_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
UAMI_RUNTIME_CLIENT_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
```

## 9. App Service (Linux container)

```bash
az webapp show --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az webapp create \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --container-image-name "nginx:latest"
# ^ nginx is a throwaway placeholder. deploy-api.yml sets the real image on first deploy.

# Attach the runtime UAMI
az webapp identity assign \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --identities "$UAMI_RUNTIME_ID"

# Tell DefaultAzureCredential which identity to use
az webapp config appsettings set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "AZURE_CLIENT_ID=$UAMI_RUNTIME_CLIENT_ID" \
    "WEBSITES_PORT=8080" \
    "ASPNETCORE_ENVIRONMENT=Production"
```

## 10. Static Web App (Free tier)

```bash
az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az staticwebapp create \
  --name "$SWA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Free
# Note: Static Web Apps Free tier is only available in a limited set of regions.
# If this fails with "location not supported", retry with one of:
#   westeurope, westus2, centralus, eastus2, eastasia
# The Free tier is content-only, so the region mainly affects cold-start latency.
# Full list: https://learn.microsoft.com/azure/static-web-apps/overview#regions
```

## 11. Summary — copy these for script 02

```bash
echo ""
echo "=== Provisioning complete. Save these for script 02: ==="
echo "RESOURCE_GROUP=$RESOURCE_GROUP"
echo "SQL_SERVER_NAME=$SQL_SERVER_NAME"
echo "SQL_SERVER_FQDN=${SQL_SERVER_NAME}.database.windows.net"
echo "SQL_DATABASE_NAME=$SQL_DATABASE_NAME"
echo "KEY_VAULT_NAME=$KEY_VAULT_NAME"
echo "APP_SERVICE_NAME=$APP_SERVICE_NAME"
echo "SWA_NAME=$SWA_NAME"
echo "UAMI_DEPLOYER_NAME=$UAMI_DEPLOYER_NAME"
echo "UAMI_RUNTIME_NAME=$UAMI_RUNTIME_NAME"
echo "SQL_ADMIN_GROUP=$SQL_ADMIN_GROUP"
echo ""
echo "Tenant ID: $(az account show --query tenantId -o tsv)"
echo "Subscription ID: $(az account show --query id -o tsv)"
```

> **Entra app registrations are NOT created here.** The API runs without auth enforcement until backlog item 012 wires up Entra ID authentication. This runbook only builds the infrastructure needed to deploy a container.

---

**Next:** [`02-configure-github-oidc.md`](./02-configure-github-oidc.md)
````

- [ ] **Step 2: Verify the file parses as valid markdown and the bash blocks have no syntax errors**

No automated check needed — the bash runs inside markdown code fences. Visually inspect the file.

- [ ] **Step 3: Commit**

```bash
git add scripts/azure/01-provision-azure.md
git commit -m "docs: add Azure provisioning runbook"
```

---

### Task 9: Create `scripts/azure/02-configure-github-oidc.md`

**Files:**
- Create: `scripts/azure/02-configure-github-oidc.md`

**Why this exists:** Configures the OIDC trust, RBAC, SQL users, GitHub secrets/variables, App Service settings, and CORS. Ends with GHCR visibility toggle instructions.

- [ ] **Step 1: Write the file**

Create `scripts/azure/02-configure-github-oidc.md` with exactly this content:

````markdown
# 02 — Configure GitHub OIDC + Azure

Wires up the OIDC trust between GitHub Actions and Azure. After this, the 4 workflows in `.github/workflows/` will be able to log into Azure with zero long-lived secrets.

Prerequisite: you have completed [`01-provision-azure.md`](./01-provision-azure.md) and still have the environment variables set.

## Variables (continues from 01)

```bash
# Add these on top of the variables already set in script 01:
GITHUB_ORG="<your-github-username-or-org>"
GITHUB_REPO="AHKFlowApp"

UAMI_DEPLOYER_CLIENT_ID=$(az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
UAMI_DEPLOYER_PRINCIPAL_ID=$(az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
UAMI_RUNTIME_PRINCIPAL_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE=$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)
KV_SCOPE=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
SQL_SERVER_FQDN="${SQL_SERVER_NAME}.database.windows.net"
```

## 1. Federated identity credentials on the deployer UAMI

One credential per GitHub trigger. The subject claim scopes each credential to an exact repo + branch/event combination.

```bash
az identity federated-credential create \
  --name "gh-${GITHUB_REPO}-main" \
  --identity-name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange" 2>/dev/null || echo "main credential exists"

az identity federated-credential create \
  --name "gh-${GITHUB_REPO}-pull-request" \
  --identity-name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request" \
  --audiences "api://AzureADTokenExchange" 2>/dev/null || echo "PR credential exists"
```

## 2. RBAC role assignments

The deployer UAMI gets `Contributor` on the resource group only — not the subscription. The runtime UAMI gets `Key Vault Secrets User` on the vault only. Deployer is added to the SQL admin group so it can alter schema.

```bash
# Deployer: Contributor on the resource group
az role assignment create \
  --role "Contributor" \
  --assignee-object-id "$UAMI_DEPLOYER_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$RG_SCOPE" 2>/dev/null || echo "Deployer role already assigned"

# Runtime: Key Vault Secrets User on the Key Vault
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$UAMI_RUNTIME_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$KV_SCOPE" 2>/dev/null || echo "Runtime KV role already assigned"

# Deployer: add to SQL admin group (gets full SQL admin via group membership)
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv)
az ad group member check --group "$GROUP_ID" --member-id "$UAMI_DEPLOYER_PRINCIPAL_ID" --query value -o tsv | grep -qi true || \
  az ad group member add --group "$GROUP_ID" --member-id "$UAMI_DEPLOYER_PRINCIPAL_ID"

echo "Waiting 30s for Entra group membership to propagate..."
sleep 30
```

## 3. Create SQL user for the runtime UAMI

**You** (the operator, a member of `$SQL_ADMIN_GROUP`) create a contained SQL user for the runtime UAMI and grant it least-privilege access.

### Option A — sqlcmd (requires `mssql-tools18` installed)

```bash
cat > /tmp/create-runtime-user.sql <<SQL
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$UAMI_RUNTIME_NAME')
BEGIN
  CREATE USER [$UAMI_RUNTIME_NAME] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [$UAMI_RUNTIME_NAME];
ALTER ROLE db_datawriter ADD MEMBER [$UAMI_RUNTIME_NAME];
GRANT EXECUTE TO [$UAMI_RUNTIME_NAME];
SQL

sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DATABASE_NAME" -G -i /tmp/create-runtime-user.sql
rm /tmp/create-runtime-user.sql
```

### Option B — Azure Portal Query Editor (no local sqlcmd needed)

1. Go to: `https://portal.azure.com/#@/resource${RG_SCOPE}/providers/Microsoft.Sql/servers/${SQL_SERVER_NAME}/databases/${SQL_DATABASE_NAME}/queryEditor`
2. Sign in with your Entra ID (the account that's a member of the admin group).
3. Paste and run:
   ```sql
   CREATE USER [ahkflow-uami-runtime-dev] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [ahkflow-uami-runtime-dev];
   ALTER ROLE db_datawriter ADD MEMBER [ahkflow-uami-runtime-dev];
   GRANT EXECUTE TO [ahkflow-uami-runtime-dev];
   ```
   (Replace `ahkflow-uami-runtime-dev` with your actual `$UAMI_RUNTIME_NAME` if different.)

## 4. GitHub repo secrets

```bash
gh secret set AZURE_CLIENT_ID --body "$UAMI_DEPLOYER_CLIENT_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"

SWA_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --query "properties.apiKey" -o tsv)
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body "$SWA_TOKEN" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

## 5. GitHub repo variables (non-secret)

```bash
gh variable set AZURE_RESOURCE_GROUP --body "$RESOURCE_GROUP" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set APP_SERVICE_NAME --body "$APP_SERVICE_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_SERVER_NAME --body "$SQL_SERVER_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_SERVER_FQDN --body "$SQL_SERVER_FQDN" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_DATABASE_NAME --body "$SQL_DATABASE_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

## 6. Configure App Service connection string

```bash
az webapp config connection-string set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --connection-string-type SQLAzure \
  --settings "DefaultConnection=Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

## 7. Configure CORS on the App Service

```bash
SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --query "defaultHostname" -o tsv)
az webapp cors add \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --allowed-origins "https://${SWA_HOSTNAME}"
```

## 8. First deploy + GHCR visibility flip

The first `deploy-api.yml` run will successfully push an image to GHCR (private by default) but the `deploy` job will fail with "manifest unknown" or "unauthorized" because App Service can't pull a private GHCR image without credentials.

After the first push, make the package public:

1. Visit the packages tab for your account type:
   - **Personal account:** `https://github.com/<your-username>?tab=packages`
   - **Organization:** `https://github.com/orgs/<your-org>/packages`
2. Find the `ahkflowapp-api` package.
3. Click **Package settings** → **Change visibility** → **Public** → confirm.
4. Re-run the failed `deploy` job: Actions → Deploy API → failed run → Re-run failed jobs.

The next run should succeed end-to-end.

> **Tighter alternative (future improvement):** keep GHCR private and configure App Service with a PAT that has `read:packages`. Or switch to Azure Container Registry and use the runtime UAMI with AcrPull.

---

**Next:** merge your PR to `main`, watch the workflows run, flip GHCR visibility. You're done.

**Teardown (when finished):** [`99-teardown.md`](./99-teardown.md)
````

- [ ] **Step 2: Visually inspect**

```bash
cat scripts/azure/02-configure-github-oidc.md | head -80
```

- [ ] **Step 3: Commit**

```bash
git add scripts/azure/02-configure-github-oidc.md
git commit -m "docs: add GitHub OIDC + Azure configuration runbook"
```

---

### Task 10: Create `scripts/azure/99-teardown.md`

**Files:**
- Create: `scripts/azure/99-teardown.md`

**Why this exists:** One-command teardown to stop paying for dev resources when you're not using them. Includes safety confirmation.

- [ ] **Step 1: Write the file**

Create `scripts/azure/99-teardown.md` with exactly this content:

````markdown
# 99 — Teardown

Stop paying for dev resources. Deletes the entire resource group, the SQL admin Entra group, and the GitHub secrets/variables.

> **⚠️ Destructive.** This deletes **everything** created by scripts 01 and 02. Only run this on a dev environment you're finished with. There is **no undo** — including the SQL database.

## Variables

```bash
ENVIRONMENT="dev"
BASE_NAME="ahkflow"
RESOURCE_GROUP="rg-${BASE_NAME}-${ENVIRONMENT}"
SQL_ADMIN_GROUP="${BASE_NAME}-sql-admins-${ENVIRONMENT}"
GITHUB_ORG="<your-github-username-or-org>"
GITHUB_REPO="AHKFlowApp"
```

## 1. Confirm

```bash
echo "About to delete resource group: $RESOURCE_GROUP"
read -p "Type the RG name to confirm: " CONFIRM
[ "$CONFIRM" = "$RESOURCE_GROUP" ] || { echo "Mismatch. Aborting."; exit 1; }
```

## 2. Delete Azure resources

```bash
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Resource group deletion started (async). Check status: az group show --name $RESOURCE_GROUP"
```

## 3. Delete the SQL admin Entra group

```bash
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv 2>/dev/null)
if [ -n "$GROUP_ID" ]; then
  az ad group delete --group "$GROUP_ID"
  echo "Deleted Entra group $SQL_ADMIN_GROUP"
fi
```

## 4. Clean up GitHub secrets and variables (optional)

```bash
for s in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_STATIC_WEB_APPS_API_TOKEN; do
  gh secret delete "$s" --repo "${GITHUB_ORG}/${GITHUB_REPO}" 2>/dev/null || true
done

for v in AZURE_RESOURCE_GROUP APP_SERVICE_NAME SQL_SERVER_NAME SQL_SERVER_FQDN SQL_DATABASE_NAME; do
  gh variable delete "$v" --repo "${GITHUB_ORG}/${GITHUB_REPO}" 2>/dev/null || true
done
```

## 5. Verify

```bash
az group show --name "$RESOURCE_GROUP" 2>&1 | grep -q "could not be found" && echo "✓ RG deleted" || echo "⚠ RG still exists (deletion may be async)"
```
````

- [ ] **Step 2: Visually inspect**

- [ ] **Step 3: Commit**

```bash
git add scripts/azure/99-teardown.md
git commit -m "docs: add Azure teardown runbook"
```

---

## Phase 4 — Push and open PR

### Task 11: Push the branch and open a PR

**Why this exists:** Triggers `ci.yml` on the PR. Confirms the workflow file itself parses correctly and the build/test/format gates pass.

- [ ] **Step 1: Verify working tree is clean**

```bash
git status
```

**Expected:** `nothing to commit, working tree clean` and branch is `feature/009-docker-development-setup` (or the branch you continued from if 009 has already merged).

- [ ] **Step 2: Run the full build + tests locally one more time**

```bash
dotnet restore
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build
dotnet format --verify-no-changes
```

**Expected:** all four commands succeed, no warnings, no format diffs.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin HEAD
```

- [ ] **Step 4: Write the PR body to a temp file**

Write the following exact content to `/tmp/pr-body-010.md`:

```markdown
## Summary
- 4 GitHub Actions workflows (ci, deploy-api, deploy-frontend, migrate-db)
- 4 Azure provisioning runbooks in scripts/azure/ (OIDC + Entra-only SQL auth + GHCR + SWA)
- Closes all 4 acceptance criteria in backlog item 010

## Spec
docs/superpowers/specs/2026-04-09-010-ci-cd-pipeline-design.md

## Rollout
See rollout section in the spec. Before merge, operator must:
1. Run scripts/azure/00-prerequisites.md
2. Run scripts/azure/01-provision-azure.md
3. Run scripts/azure/02-configure-github-oidc.md

After merge, operator must flip the GHCR package visibility to public and re-run the deploy job (documented in script 02).

## Test plan
- [ ] CI workflow passes on this PR (build + test + format)
- [ ] Human runs scripts/azure/00 + 01 + 02 to bootstrap Azure
- [ ] Merge triggers deploy-api.yml and deploy-frontend.yml
- [ ] First deploy-api run fails on private GHCR, operator flips visibility, re-runs
- [ ] curl https://ahkflow-api-dev.azurewebsites.net/health returns 200
- [ ] SWA default URL serves the Blazor app
```

- [ ] **Step 5: Open the PR**

```bash
gh pr create --title "feat: CI/CD pipeline (backlog 010)" --body-file /tmp/pr-body-010.md
rm /tmp/pr-body-010.md
```

- [ ] **Step 6: Watch CI**

```bash
# --watch polls until checks finish. If the run hangs for >15 minutes, Ctrl-C and investigate
# via: gh run list --branch "$(git branch --show-current)" --limit 1
gh pr checks --watch
```

**Expected:** `CI / build-test` succeeds. If it fails on `dotnet format --verify-no-changes`, go back to Task 2 and re-run locally.

---

## Phase 5 — Human operator runbook (BLOCKING — manual execution)

**These tasks require a human operator with Azure subscription privileges. A subagent cannot complete them autonomously — they involve interactive `az login`, resource creation that incurs cost, and Entra ID changes. Mark the tasks as a single checkpoint when the human reports completion.**

### Task 12: Human runs the Azure bootstrap runbooks

- [ ] **Step 1: Operator reads and executes `scripts/azure/00-prerequisites.md`** — installs `az`, `gh`, `dotnet`, logs in, confirms permissions.

- [ ] **Step 2: Operator reads and executes `scripts/azure/01-provision-azure.md`** — creates the resource group, SQL server + DB, Key Vault, App Service, SWA, Log Analytics, App Insights, UAMIs. **Budget: ~$20/month for B1 + SQL Basic.**

- [ ] **Step 3: Operator reads and executes `scripts/azure/02-configure-github-oidc.md`** — creates federated credentials, RBAC assignments, SQL users for the runtime UAMI, sets `gh secret`/`gh variable`, configures App Service connection string + CORS.

- [ ] **Step 4: Operator confirms all GitHub secrets and variables are set:**

```bash
gh secret list --repo "${GITHUB_ORG}/AHKFlowApp"
gh variable list --repo "${GITHUB_ORG}/AHKFlowApp"
```

**Expected:** secrets include `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_STATIC_WEB_APPS_API_TOKEN`. Variables include `AZURE_RESOURCE_GROUP`, `APP_SERVICE_NAME`, `SQL_SERVER_NAME`, `SQL_SERVER_FQDN`, `SQL_DATABASE_NAME`.

---

### Task 13: Merge the PR and observe the first deploy

- [ ] **Step 1: Operator merges the PR to `main`.**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 2: Watch the deploy workflows**

```bash
gh run list --workflow=deploy-api.yml --limit 1
gh run watch $(gh run list --workflow=deploy-api.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

**Expected (first-run):**
- `build-test` ✓
- `build-push-image` ✓ (image pushed to GHCR, still private)
- `migrate-db` ✓ (runs `dotnet ef database update`, creates initial schema)
- `deploy` ✗ **fails** with a registry pull error (expected on first run — GHCR is private by default)

- [ ] **Step 3: Flip GHCR package visibility to public**

Browser:
- Personal account: `https://github.com/<your-username>?tab=packages`
- Org: `https://github.com/orgs/<your-org>/packages`

Then: `ahkflowapp-api` → Package settings → Change visibility → Public → confirm.

- [ ] **Step 4: Re-run the failed `deploy` job**

```bash
gh run rerun --failed $(gh run list --workflow=deploy-api.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

**Expected:** `deploy` succeeds, health check returns 200.

- [ ] **Step 5: Verify the API is live**

```bash
curl -fsS "https://ahkflow-api-dev.azurewebsites.net/health"
```

**Expected:** plain-text `Healthy` (or JSON `{"status":"Healthy",...}` depending on the exact health check serializer).

- [ ] **Step 6: Watch the frontend deploy**

```bash
gh run list --workflow=deploy-frontend.yml --limit 1
```

**Expected:** successful deploy of the Blazor app to the SWA default URL. Open `https://<SWA_HOSTNAME>/` in a browser and confirm the Blazor app loads.

---

### Task 14: Mark backlog item 010 complete (follow-up PR)

Per memory rule "No direct commits to main", this goes through a small follow-up PR.

- [ ] **Step 1: Tick the acceptance-criteria checkboxes**

Open `.claude/backlog/010-create-ci-cd-pipeline.md`. Find the `## Acceptance criteria` section and change each `- [ ]` to `- [x]` for the 4 criteria that are now satisfied. The file has no YAML frontmatter — just checkboxes.

- [ ] **Step 2: Open follow-up PR**

```bash
git checkout main
git pull
git checkout -b chore/close-010-backlog
git add .claude/backlog/010-create-ci-cd-pipeline.md
git commit -m "chore: close backlog 010"
git push -u origin HEAD
gh pr create --title "chore: close backlog 010" --body "Marks backlog 010 done after successful rollout."
```

---

## Done

All 4 backlog acceptance criteria are closed:

| AC | Closed by |
|---|---|
| CI runs on PRs (build + unit tests) | `.github/workflows/ci.yml` (Task 3) |
| CD runs on main (build + tests + publish artifacts) | `.github/workflows/deploy-api.yml` + `deploy-frontend.yml` (Tasks 4, 5) |
| UI deploys to Azure Static Web Apps | `.github/workflows/deploy-frontend.yml` (Task 5) |
| API deploys via container to Azure | `.github/workflows/deploy-api.yml` (Task 4) — GHCR image pulled by App Service for Linux |

## Troubleshooting

- **`dotnet format --verify-no-changes` fails in CI:** run `dotnet format` locally, commit, push. Task 2 should have pre-empted this.
- **`deploy` job fails with "manifest unknown" or "unauthorized":** GHCR package is still private. Re-check Task 13 Step 3.
- **Health check fails after 3 minutes:** container may have crashed. Run `az webapp log tail --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"` to see startup logs.
- **Migration job fails with Entra auth errors:** group membership may not have propagated. Wait 5 minutes, re-run the `migrate-db` job.
- **Migration job fails with firewall errors:** the transient runner-IP firewall rule may have been left over from a previous failed run. Delete any stale `gh-runner-*` rules: `az sql server firewall-rule list --resource-group "$RG" --server "$SQL_SERVER_NAME" --query "[?starts_with(name, 'gh-runner-')].name" -o tsv | xargs -I{} az sql server firewall-rule delete --resource-group "$RG" --server "$SQL_SERVER_NAME" --name {}`.
- **`az webapp config container set` fails with "resource not found":** script 01 didn't create the webapp. Re-run section 9 of `01-provision-azure.md`.
- **SWA deploy fails with "invalid token":** `AZURE_STATIC_WEB_APPS_API_TOKEN` secret is wrong. Re-run section 4 of `02-configure-github-oidc.md`.
