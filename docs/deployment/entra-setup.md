# Entra ID App Registration Setup

AHKFlowApp uses one Entra ID app registration per environment (`AHKFlowApp-dev`, `AHKFlowApp-test`, `AHKFlowApp-prod`). The SPA is both the client and the resource — it exposes an `access_as_user` scope and pre-authorizes itself.

Setup is automated. Dev has its own helper; test/prod run as part of `deploy.ps1`.

## Prerequisites

- Azure CLI with `az login` completed
- Contributor or Application Administrator role in the target tenant

## Dev

```powershell
.\scripts\setup-dev-entra.ps1
```

Creates or repairs `AHKFlowApp-dev`, waits for the service principal, redirect URIs, scope, and pre-authorization wiring to become visible, sets backend user-secrets, and writes `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json`. Idempotent — safe to re-run.

If the Microsoft-hosted sign-in page shows `AADSTS500011`, rerun `.\scripts\setup-dev-entra.ps1` and try the sign-in again. That failure page is rendered on `login.microsoftonline.com`, so the SPA cannot replace it before Entra redirects back.

## Test / Prod

Handled automatically by the full provisioning script:

```powershell
.\scripts\deploy.ps1 -Environment test
.\scripts\deploy.ps1 -Environment prod
```

Phase 3 sets up or updates the per-env app registration via `setup-entra-app.ps1` before Bicep runs. Later in the deployment, the script re-runs that setup only to refresh redirect URIs and write all three `AZURE_AD_*_{TEST|PROD}` GitHub Variables once the final app endpoints are known. The deploy workflows substitute these into `appsettings.{Test|Production}.json` at build time and inject them into App Service configuration on every deploy.

After `deploy.ps1` finishes, retrigger the API and frontend deploy workflows (they don't auto-run on `scripts/**` changes):

```powershell
gh workflow run deploy-api.yml --ref main -f environment=test
gh workflow run deploy-frontend.yml --ref main -f environment=test
```

### Manual fallback

If you only need to refresh the app registration without re-running Bicep (e.g. to add a custom domain redirect URI), call the underlying script directly:

```powershell
.\scripts\setup-entra-app.ps1 -Environment test
```

It prints the resulting `ClientId`, `TenantId`, and `DefaultScope`. Update the three `AZURE_AD_*_TEST` GitHub Variables manually via `gh variable set`.

## What's public vs secret

All `AzureAd:*` values are **public** — they appear in the compiled Blazor WASM bundle served to the browser. Stored as GitHub **Variables** (not Secrets).

`AZURE_STATIC_WEB_APPS_API_TOKEN_*` and `AZURE_API_BASE_URL_*` remain in GitHub **Secrets**.

## Adding a custom domain later

When a custom domain is added to the SWA, re-run `setup-entra-app.ps1 -Environment <env> -SwaHostname <custom-domain>` to add the custom-domain redirect URIs to the app registration. Also extend `Cors:AllowedOrigins` in bicep.
