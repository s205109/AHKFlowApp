# Plan: Automate Per-Environment Entra App Registration in deploy.ps1 + Add Dev Helper

## Context

Currently the repo has one shared Entra app registration (`AHKFlowApp-dev`, ClientId `3c417788-b12a-46d2-9ad4-1282244e5d26`) that is misused across environments — TEST points at it, PROD doesn't exist yet, DEV uses it informally. The deploy just failed because the frontend deploys substituted empty `#{AZURE_AD_*}#` placeholders; the missing GitHub variables (`AZURE_AD_TENANT_ID_TEST`, `AZURE_AD_CLIENT_ID_TEST`, `AZURE_AD_DEFAULT_SCOPE_TEST`) had never been set.

An idempotent `scripts/setup-entra-app.ps1` already exists that creates/updates `AHKFlowApp-{dev|test|prod}` correctly (redirect URIs, `access_as_user` scope, SPA pre-authorization). It just isn't wired into `scripts/deploy.ps1`, so running `deploy.ps1 -Environment test` does Bicep + OIDC + GitHub secrets but leaves app registration + `AZURE_AD_*` variables as a manual followup. Intent: make `deploy.ps1` a single idempotent entrypoint for test/prod that includes Entra, and add a separate one-shot dev helper.

Outcome: `.\scripts\deploy.ps1 -Environment test` (or `prod`) provisions everything including a per-env Entra app and all three `AZURE_AD_*` variables. `.\scripts\setup-dev-entra.ps1` handles local dev (user-secrets + `appsettings.Development.json`).

## Changes

### 1. `scripts/setup-entra-app.ps1` — emit result object

Currently the script communicates everything via `Write-Host`. Callers can't consume the values programmatically. Refactor so the script is both user-friendly interactively and programmatically callable:

- At end of script, after the "Next steps" block, emit a result object on the success stream:
  ```powershell
  [PSCustomObject]@{
      ClientId     = $appId
      TenantId     = $tenantId
      DefaultScope = $defaultScope
  }
  ```
- Audit stray success-stream output that would pollute the return:
  - Line 90–92: `az ad app update --id ... --identifier-uris ...` — pipe to `| Out-Null`.
  - Line 125: `az ad app show --query 'api.oauth2PermissionScopes[].value'` — already captured into `$currentScopes`, fine.
  - Line 131: `az ad app show --query '...' -o tsv` — captured, fine.
  - Line 57: `az ad app create` — captured, fine.
  - Line 50: `az ad app list` — captured, fine.
- `Write-Host` stays everywhere else (info stream, does not affect captured return).

### 2. `scripts/deploy.ps1` — integrate Entra setup into Phase 6

Existing Phase 6 title: "Configuring GitHub secrets and variables..." — extend it. Minimal diff, no phase renumbering. Insert this block **after** the existing env-specific secrets (line 434) and **before** the env-specific variables (line 437):

```powershell
# Entra app registration (per-environment: AHKFlowApp-{env})
Write-Host "  Creating/updating Entra app registration..."
$entraScript = Join-Path $PSScriptRoot 'setup-entra-app.ps1'
$entraInfo = & $entraScript -Environment $Environment -SwaHostname $SwaHostname
if (-not $entraInfo -or -not $entraInfo.ClientId) {
    throw "setup-entra-app.ps1 did not return a ClientId"
}
Set-GhVariable "AZURE_AD_TENANT_ID_${EnvSuffix}"     $entraInfo.TenantId
Set-GhVariable "AZURE_AD_CLIENT_ID_${EnvSuffix}"     $entraInfo.ClientId
Set-GhVariable "AZURE_AD_DEFAULT_SCOPE_${EnvSuffix}" $entraInfo.DefaultScope
```

`$SwaHostname` is already in scope (set from Bicep outputs at line 239). Script is idempotent, so re-running `deploy.ps1` is safe.

Also add the three Entra values to the `.env.${Environment}` snapshot written in Phase 8 (purely for operator reference):
```powershell
AZURE_AD_CLIENT_ID=$($entraInfo.ClientId)
AZURE_AD_DEFAULT_SCOPE=$($entraInfo.DefaultScope)
```
(TenantId is already written on line 498.)

### 3. `scripts/setup-dev-entra.ps1` — new manual dev helper

Dev has no Azure footprint (no SWA, no App Service), so it does not belong in `deploy.ps1`. New dedicated script — idempotent, safe to re-run:

```powershell
#Requires -Version 7
# Calls setup-entra-app.ps1 -Environment dev, then wires local dev config:
#  - dotnet user-secrets for backend API
#  - writes wwwroot/appsettings.Development.json for the Blazor frontend

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

$entraScript = Join-Path $PSScriptRoot 'setup-entra-app.ps1'
$entra = & $entraScript -Environment dev
if (-not $entra -or -not $entra.ClientId) {
    throw "setup-entra-app.ps1 did not return a ClientId"
}

# Backend: user-secrets
Push-Location (Join-Path $RepoRoot 'src/Backend/AHKFlowApp.API')
try {
    dotnet user-secrets set 'AzureAd:TenantId' $entra.TenantId | Out-Null
    dotnet user-secrets set 'AzureAd:ClientId' $entra.ClientId | Out-Null
} finally { Pop-Location }

# Frontend: appsettings.Development.json (gitignored)
$feSettings = Join-Path $RepoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$json = [ordered]@{
    ApiHttpClient = [ordered]@{ BaseAddress = 'http://localhost:5600' }
    AzureAd = [ordered]@{
        Authority         = "https://login.microsoftonline.com/$($entra.TenantId)"
        ClientId          = $entra.ClientId
        ValidateAuthority = $true
        DefaultScope      = $entra.DefaultScope
    }
}
$json | ConvertTo-Json -Depth 5 | Set-Content -Path $feSettings -Encoding UTF8

Write-Host "Dev Entra setup complete." -ForegroundColor Green
```

`appsettings.Development.json` is gitignored (per frontend CLAUDE.md), so rewriting it is safe. Preserves the shape of `appsettings.Development.json.example`.

### 4. `docs/deployment/entra-setup.md` — update

Replace the three manual blocks (Steps 1–3) with:

- **Dev:** run `.\scripts\setup-dev-entra.ps1` — configures user-secrets + appsettings.Development.json automatically.
- **Test / Prod:** handled automatically by `.\scripts\deploy.ps1 -Environment <env>` (Phase 6). Keep a short "manual fallback" note pointing at `setup-entra-app.ps1` directly for troubleshooting / re-running a single env without full deploy.

Leave the "custom domain later" section as-is.

### 5. One-time state reconciliation (operator, not scripted)

After this lands, running `deploy.ps1 -Environment test` will:
- Create a new `AHKFlowApp-test` registration (separate from existing `AHKFlowApp-dev`).
- Overwrite `AZURE_AD_CLIENT_ID_TEST` / `AZURE_AD_TENANT_ID_TEST` / `AZURE_AD_DEFAULT_SCOPE_TEST` GitHub vars to point at the new app.
- Existing `AHKFlowApp-dev` (currently ClientId `3c417788-b12a-46d2-9ad4-1282244e5d26`) stays untouched — fine for local dev. Operator can optionally run `setup-dev-entra.ps1` to realign local config.

Followup: manually retrigger `deploy-frontend.yml` and `deploy-api.yml` after running `deploy.ps1 -Environment test`, because neither workflow path includes `scripts/**` triggers.

### 6. Branch

This work is independent of the in-flight `fix/auth-resilience-empty-config` branch (which adds the Program.cs guard). New branch: `feature/per-env-entra-registration`, branched from `main`. PR it separately. Merge order doesn't matter — they're orthogonal.

## Critical files

| File | Action |
|---|---|
| `scripts/setup-entra-app.ps1` | Modify: emit result object, silence stray az output |
| `scripts/deploy.ps1` | Modify: extend Phase 6 + Phase 8 |
| `scripts/setup-dev-entra.ps1` | Create |
| `docs/deployment/entra-setup.md` | Rewrite Steps 1–3 |

## Verification

1. **Idempotence of setup-entra-app.ps1 return value** — run twice manually with `-Environment dev`, capture the output both times, compare objects. Second run must return same ClientId and not create a duplicate app.
2. **deploy.ps1 end-to-end on test** — run `.\scripts\deploy.ps1 -Environment test`. Confirm:
   - `AHKFlowApp-test` exists in Entra (`az ad app list --display-name AHKFlowApp-test`).
   - `gh variable list` shows all three `AZURE_AD_*_TEST` populated with test values (not dev's `3c417788...`).
   - `scripts/.env.test` contains the new values.
3. **Redeploy + smoke** — manually trigger `deploy-api.yml` and `deploy-frontend.yml` for test. Confirm:
   - `curl -fsS https://ahkflowapp-api-test.azurewebsites.net/health` → 200.
   - Frontend loads, login redirects to `login.microsoftonline.com/<test-tenantid>`, after consent `/api/v1/whoami` returns the principal.
4. **Dev helper** — on a clean clone: run `scripts/setup-dev-entra.ps1`. Confirm:
   - User-secrets set (`dotnet user-secrets list --project src/Backend/AHKFlowApp.API`).
   - `wwwroot/appsettings.Development.json` exists with correct Authority/ClientId/DefaultScope.
   - API runs locally (`dotnet run --project src/Backend/AHKFlowApp.API`), frontend starts, login works.
5. **Re-run safety** — run `deploy.ps1 -Environment test` a second time. Must complete with no errors, no duplicate app registration, no variable churn.

## Open questions

- PROD now or later? Plan assumes test-only for first exercise; `deploy.ps1 -Environment prod` will work identically when invoked later. If you want PROD set up in the same session, just run `deploy.ps1 -Environment prod` after test passes.
- Keep old `AHKFlowApp-dev` registration or delete? Harmless to leave; cleanup is a separate Entra portal action whenever convenient.
