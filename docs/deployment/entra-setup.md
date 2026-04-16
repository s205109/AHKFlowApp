# Entra ID App Registration Setup

AHKFlowApp uses a single Entra ID app registration per environment (dev, test, prod). The SPA is both the client and the resource — it exposes an `access_as_user` scope and pre-authorizes itself.

## Prerequisites

- Azure CLI with `az login` completed
- Contributor or Application Administrator role in the target tenant

## Step 1: Run the setup script

```bash
# Dev environment
.\scripts\setup-entra-app.ps1 -Environment dev

# Test environment (SWA hostname resolved automatically)
.\scripts\setup-entra-app.ps1 -Environment test

# Prod environment
.\scripts\setup-entra-app.ps1 -Environment prod
```

The script is idempotent — safe to re-run. It outputs the `ClientId`, `TenantId`, and `DefaultScope` values needed for the next steps.

## Step 2 (dev): Set user secrets

```bash
dotnet user-secrets set "AzureAd:TenantId" "<TenantId>" --project src/Backend/AHKFlowApp.API
dotnet user-secrets set "AzureAd:ClientId" "<ClientId>" --project src/Backend/AHKFlowApp.API
```

Then populate `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json`:

```json
"AzureAd": {
  "Authority": "https://login.microsoftonline.com/<TenantId>",
  "ClientId": "<ClientId>",
  "ValidateAuthority": true,
  "DefaultScope": "api://<ClientId>/access_as_user"
}
```

These values are public — MSAL SPA apps embed them in the browser bundle. Do not use `.gitignore` to hide them.

## Step 3 (test/prod): Set GitHub Variables

```bash
gh variable set AZURE_AD_TENANT_ID_TEST --body "<TenantId>"
gh variable set AZURE_AD_CLIENT_ID_TEST --body "<ClientId>"
gh variable set AZURE_AD_DEFAULT_SCOPE_TEST --body "api://<ClientId>/access_as_user"
```

The deploy workflows substitute these into `appsettings.Test.json` / `appsettings.Production.json` at build time and inject them into App Service configuration on every deploy.

## What's public vs secret

All `AzureAd:*` values are **public** — they appear in the compiled Blazor WASM bundle served to the browser. Use GitHub **Variables** (not Secrets) for them.

The `AZURE_STATIC_WEB_APPS_API_TOKEN_*` and `AZURE_API_BASE_URL_*` values are secrets (remain in GitHub Secrets as before).

## Adding a custom domain later

When a custom domain is added to the SWA, re-run `setup-entra-app.ps1` with `-SwaHostname <custom-domain>` to add the custom domain redirect URIs to the app registration. Also extend `Cors:AllowedOrigins` in bicep.
