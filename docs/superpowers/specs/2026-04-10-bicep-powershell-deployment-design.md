# Bicep + PowerShell Deployment Migration — Design Spec

## Problem

The current Azure provisioning lives in 4 bash markdown runbooks (`scripts/azure/00–03`) containing ~280 lines of `az` commands that users manually copy-paste. This project targets Windows users (AutoHotkey management tool), yet the provisioning scripts are bash-first. The process is error-prone, not idempotent in practice, and requires significant Azure/GitHub knowledge to follow.

## Goal

Replace the bash runbooks with a single-command PowerShell deployment experience backed by Bicep infrastructure-as-code. An end user with an Azure subscription should be able to run `.\deploy.ps1` and have a working AHKFlowApp instance.

## Approach

**Bicep** for declarative Azure resources. **PowerShell** for orchestration, user interaction, and imperative steps that Bicep cannot handle (Entra ID, OIDC, SQL users, GitHub secrets). **Azure CLI** as the underlying engine (designed so `azd` can be layered on later).

## Audience

- **Primary:** End users who want their own hosted AHKFlowApp instance.
- **Secondary:** Contributors/developers who fork the repo and need their own Azure environment.

## Scope

### In scope

- Bicep modules for all declarative Azure resources
- PowerShell scripts: `deploy.ps1`, `update.ps1`, `teardown.ps1`
- GitHub Actions: add Bicep lint to CI, add optional `provision.yml` workflow
- Remove old bash runbooks (`scripts/azure/00–03`)
- Documentation updates (deployment guide, AGENTS.md, README.md)

### Out of scope

- Application Insights + Log Analytics (backlog item 011)
- Key Vault (not used in code — removed from resource set)
- Azure Developer CLI (`azd`) adoption (future enhancement)
- Blue/green deployments

## Resource Set

7 Azure resources + 1 Entra resource. Simplified from the original 12+ by removing Key Vault, Application Insights, and Log Analytics.

| Resource | Managed by | Notes |
|---|---|---|
| Resource Group | `az group create` (PowerShell) | Created before Bicep runs |
| SQL Server (Entra-only auth) | Bicep (`sql.bicep`) | No SQL auth — Entra AD only |
| SQL Database (Basic tier) | Bicep (`sql.bicep`) | ~$5/month |
| App Service Plan (Linux B1) | Bicep (`web.bicep`) | ~$13/month |
| App Service (Linux container) | Bicep (`web.bicep`) | GHCR container image |
| Static Web App (Free tier) | Bicep (`swa.bicep`) | Blazor WASM frontend |
| User-Assigned Managed Identity — deployer | Bicep (`identity.bicep`) | GitHub Actions OIDC |
| User-Assigned Managed Identity — runtime | Bicep (`identity.bicep`) | App Service → SQL access |
| Entra Security Group (SQL admin) | PowerShell (imperative) | Not an ARM resource |

**Estimated monthly cost:** ~$18–20 for a single environment (Basic SQL + B1 App Service).

## Bicep Module Layout

```
infra/
  main.bicep                    # Orchestrator — imports modules, wires outputs
  main.bicepparam               # Default parameter values
  modules/
    identity.bicep              # deployer UAMI + runtime UAMI
    sql.bicep                   # SQL Server + Database + AllowAzureServices firewall rule
    web.bicep                   # App Service Plan + App Service + container config + UAMI assignment
    swa.bicep                   # Static Web App
```

### Parameters (`main.bicep`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `environment` | string | (required) | `test` or `prod` |
| `location` | string | `resourceGroup().location` | Azure region |
| `baseName` | string | `ahkflowapp` | Prefix for all resource names |
| `sqlAdminGroupId` | string | (required) | Entra security group object ID |
| `sqlAdminGroupName` | string | (required) | Entra security group display name |

### Outputs (`main.bicep`)

All resource names, IDs, FQDNs, and client IDs needed by the PowerShell imperative steps. These flow back to `deploy.ps1` so it can configure OIDC, SQL users, and GitHub secrets without re-querying Azure.

Key outputs:
- `sqlServerFqdn` — for connection strings and SQL user creation
- `sqlServerName` — for firewall rule management
- `sqlDatabaseName` — for SQL user creation
- `appServiceName` — for container deployment
- `swaName` — for SWA API token retrieval
- `swaDefaultHostname` — for CORS configuration
- `deployerUamiClientId` — for GitHub OIDC secrets
- `deployerUamiName` — for federated credential creation
- `deployerUamiPrincipalId` — for RBAC and Entra group membership
- `runtimeUamiName` — for SQL user creation
- `runtimeUamiId` — for App Service identity assignment
- `runtimeUamiClientId` — for `AZURE_CLIENT_ID` app setting

## PowerShell Script Design

### `deploy.ps1` — Single Entrypoint

Phases executed in order:

**Phase 1: Prerequisites Check**
- Verify Azure CLI installed (`az --version`)
- Verify logged in (`az account show`)
- Verify .NET SDK installed (`dotnet --version`)
- Verify GitHub CLI installed + authenticated (`gh auth status`)
- Clear error messages with install URLs if anything is missing

**Phase 2: Gather Configuration**
- Prompt: Environment (`test`/`prod`) — default: `test`
- Prompt: Azure region — default: `westeurope`
- Prompt: Base name — default: `ahkflowapp`
- Auto-detect: GitHub org/repo from `git remote get-url origin`
- Confirm summary before proceeding

**Phase 3: Provision Azure Resources (Bicep)**
- Create resource group via `az group create`
- Create Entra security group via `az ad group create` (idempotent — checks first)
- Add current user to group
- Deploy `infra/main.bicep` via `az deployment group create` passing group ID/name as parameters
- Capture all Bicep outputs into PowerShell variables

**Phase 4: Entra & OIDC Configuration**
- Create federated identity credentials on deployer UAMI (main branch + pull_request)
- Assign Contributor role on RG to deployer UAMI
- Add deployer UAMI to SQL admin Entra group
- Wait for Entra propagation (~30s)

**Phase 5: SQL User Setup**
- Add runner IP to SQL firewall (temporary)
- Create contained SQL user for runtime UAMI via `sqlcmd` or `Invoke-Sqlcmd`
- Grant `db_datareader`, `db_datawriter`, `EXECUTE`
- Remove temporary firewall rule

**Phase 6: GitHub Configuration**
- Set shared secrets: `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- Set environment-specific secrets: `AZURE_CLIENT_ID_{ENV}`, `AZURE_STATIC_WEB_APPS_API_TOKEN_{ENV}`
- Set environment-specific variables: resource group, app service name, SQL server name/FQDN, database name

**Phase 7: App Service Configuration**
- Set connection string on App Service
- Configure CORS with SWA hostname
- Set `AZURE_CLIENT_ID` and `ASPNETCORE_ENVIRONMENT` app settings

**Phase 8: Summary**
- Print all resource URLs (API, SWA, health endpoint)
- Warn: GHCR package is private by default — print instructions to make it public (required for App Service to pull the image)
- Print next steps: "Push to main to trigger first deploy via GitHub Actions"
- Save configuration to `scripts/.env.{environment}` for use by `update.ps1` and `teardown.ps1`

**Design properties:**
- **Idempotent:** Safe to re-run. Bicep is declarative. All imperative steps check before creating.
- **No SQL passwords:** Entra-only authentication throughout.
- **Config persistence:** `.env.{environment}` file stores all configuration so subsequent scripts don't re-prompt.

### `update.ps1` — Redeploy Latest Release

- Reads saved config from `.env.{environment}`
- Fetches latest GHCR image tag for the environment
- Sets it on App Service via `az webapp config container set`
- Restarts App Service
- Health-checks the `/health` endpoint
- ~30 lines

### `teardown.ps1` — Delete Everything

- Reads saved config from `.env.{environment}`
- Prompts for confirmation (type resource group name)
- Deletes: resource group (cascades all Azure resources), Entra security group, GitHub secrets/variables
- Removes local `.env.{environment}` file

## GitHub Actions Changes

### `ci.yml` — Add Bicep Lint

Add one step to validate Bicep syntax on PRs:

```yaml
- name: Lint Bicep
  run: az bicep build --file infra/main.bicep
```

No other changes to the CI workflow.

### `provision.yml` — New Optional Workflow

A `workflow_dispatch` workflow for advanced users who prefer CI-driven provisioning:

```yaml
name: Provision Azure (Manual)
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [test, prod]
```

Runs `az deployment group create` with the Bicep template. Does NOT handle imperative steps (Entra, OIDC, SQL users, GitHub secrets) — those still require `deploy.ps1` for the initial setup.

### Unchanged Workflows

- `deploy-api.yml` — container build/push/deploy stays as-is
- `deploy-frontend.yml` — SWA deploy stays as-is
- `migrate-db.yml` — EF migration stays as-is

## File Structure

```
infra/                                          # NEW — Bicep infrastructure
  main.bicep
  main.bicepparam
  modules/
    identity.bicep
    sql.bicep
    web.bicep
    swa.bicep

scripts/
  deploy.ps1                                    # NEW — single entrypoint
  update.ps1                                    # NEW — redeploy latest
  teardown.ps1                                  # NEW — delete everything
  .env.test                                     # GENERATED — saved config (gitignored)
  .env.prod                                     # GENERATED — saved config (gitignored)
  kill-dev-ports.ps1                            # KEEP — existing utility
  setup-copilot-symlinks.ps1                    # KEEP — existing utility

scripts/azure/                                  # REMOVED — old bash runbooks
  00-prerequisites.md                           # deleted
  01-provision-azure.md                         # deleted
  02-configure-github-oidc.md                   # deleted
  99-teardown.md                                # deleted

.github/workflows/
  ci.yml                                        # UPDATED — add Bicep lint
  deploy-api.yml                                # UNCHANGED
  deploy-frontend.yml                           # UNCHANGED
  migrate-db.yml                                # UNCHANGED
  provision.yml                                 # NEW — optional CI provisioning

docs/
  deployment/
    getting-started.md                          # NEW — deployment guide
```

## Error Handling

- Prerequisites check fails → clear message with install URLs, exit
- `az login` not authenticated → prompt to run `az login`, exit
- Bicep deployment fails → Azure error message displayed, exit (safe to re-run)
- SQL user creation fails → firewall rule cleanup still runs (`finally` block), error displayed
- GitHub CLI not authenticated → prompt to run `gh auth login`, exit

## Testing Strategy

- **Bicep:** `az bicep build` in CI catches syntax errors. Manual `what-if` for resource changes.
- **PowerShell:** Manual testing against a test subscription. Scripts are idempotent, so testing is re-running.
- **Integration:** Full end-to-end: run `deploy.ps1` → push to main → verify deploy → run `teardown.ps1`.

## Future Considerations

- **azd adoption:** Bicep modules are reusable by `azd`. Add `azure.yaml` + hooks when ready.
- **Application Insights + Log Analytics:** Add as Bicep modules in backlog item 011. Just add `monitoring.bicep` and wire into `main.bicep`.
- **Key Vault:** Add when secrets management is needed (e.g., backlog item 012 — authentication).
- **Multiple subscriptions:** Current design assumes one subscription. Could be extended with subscription selection.
