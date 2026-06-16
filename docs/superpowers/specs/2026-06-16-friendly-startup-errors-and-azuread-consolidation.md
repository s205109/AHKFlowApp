# Friendly startup errors + Azure AD config consolidation

## Context

Fresh clones omit both `appsettings.Development.json` files (gitignored). Today this produces a **blank page** with errors only in the browser console, in three onboarding scenarios:

1. **Frontend config missing** — falls back to committed `appsettings.json` (empty `AzureAd`); `AuthConfigurationValidator.ValidateForMsal` throws in `Program.cs` *before* `Build().RunAsync()`, so Blazor never renders.
2. **Frontend config present but unconfigured** — Azure AD still holds `<placeholder>` values; same throw, same blank page.
3. **Frontend configured, backend dev config missing** — API falls back to empty `Cors:AllowedOrigins` (so `app.UseCors` is skipped) → browser blocks cross-origin calls → CORS error + blank page.

Goal: replace blank pages with friendly, in-browser guidance, and a clear API-side startup warning. Also **consolidate the Azure AD config schema** so the frontend and API use an identical block (the user fills the same 3 values in both), removing a class of misconfiguration.

Prior art to reuse: `Pages/Health.razor:96-112` already renders a friendly "Unable to reach the API" message with the exact CORS/example-file remediation.

## Decisions (confirmed)

- Render via a **Blazor component** (plain HTML + inline styles so it renders without MudBlazor's theme provider).
- Remediation: **Azure AD setup** path (copy example → fill values / run `scripts/setup-dev-entra.ps1`).
- Scope: **frontend + API** startup messaging.
- Connectivity detection: **both** a dev-only `/health` probe gate (specific message) **and** an always-on `ErrorBoundary` (catch-all, never blank).
- Probe gate: **Development only**; `ErrorBoundary`: all environments.
- API on missing dev config: **warn + continue** (non-fatal; Swagger-only / test-auth still work).
- Token scope: **derive** `api://{ClientId}/access_as_user`, with optional `AzureAd:Scopes` override.

## Design

### A. Azure AD config consolidation
Both projects standardize on:
```json
"AzureAd": { "Instance": "https://login.microsoftonline.com/", "TenantId": "", "ClientId": "" }
```
- **API**: no code change — already binds this shape via `AddMicrosoftIdentityWebApi(GetSection("AzureAd"))`.
- **Frontend**: new pure helper `Auth/AzureAdSettings.cs` → `Resolve(IConfiguration)` returns `(Authority, ClientId, Scope, ValidateAuthority)`:
  - `Authority = $"{Instance.TrimEnd('/')}/{TenantId}"`
  - `Scope = configuration["AzureAd:Scopes"] ?? $"api://{ClientId}/access_as_user"`
  - `ValidateAuthority` from config (default `true`)
- `Program.cs` MSAL branch: replace `Configuration.Bind("AzureAd", ...Authentication)` and the `DefaultScope`/`Authority` reads with explicit assignment from `AzureAdSettings.Resolve(...)`.
- `Auth/ApiAuthorizationMessageHandler.cs:15` currently reads `AzureAd:DefaultScope` — change to `AzureAdSettings.Resolve(...).Scope`.

Assumption (true per repo examples): a single app registration serves SPA + API, so `ClientId` is shared and the scope is derivable. The optional `AzureAd:Scopes` override covers non-standard setups.

### B. Shared `StartupError` component
`Startup/StartupError.razor` — plain HTML + inline `<style>`. `[Parameter] public StartupErrorReason Reason`. Enum `StartupErrorReason`: `MissingFrontendConfig`, `PlaceholderConfig`, `BackendUnreachable`, `Unexpected`. Each reason renders title + cause + remediation + Reload/Retry. Backend/unexpected text mirrors `Health.razor`.

### C. Frontend config-error path (no exceptions for flow control)
Replace throw-based `AuthConfigurationValidator.ValidateForMsal` with result-based `Startup/StartupConfigValidator.cs` → `Check(IConfiguration)` returning `StartupErrorReason?` (`null` = ok; `MissingFrontendConfig` for empty; `PlaceholderConfig` for `<...>`). Validates `ApiHttpClient:BaseAddress`, `AzureAd:Instance`, `AzureAd:TenantId`, `AzureAd:ClientId`.

`Program.cs` (MSAL branch only): if `Check(...)` returns a reason → register `StartupErrorState(reason)` singleton + `builder.RootComponents.Add<StartupError>("#app")`, skip MSAL/API-client/`App` registration. Else configure MSAL + add `App`. `StartupError` reads the reason from the injected `StartupErrorState`. Move the unconditional `RootComponents.Add<App>("#app")` so exactly one root component binds `#app`.

### D. Frontend backend-unreachable path
- `Startup/RequireApiConnectivity.razor` gate wrapping `<Router>` in `App.razor`. Injects `IWebAssemblyHostEnvironment` + `IHttpClientFactory`. In **Development only**, `OnInitializedAsync` probes `GET /health` via a dedicated named client `"HealthProbe"` (BaseAddress = `ApiHttpClient:BaseAddress`, ~3s timeout, **no** resilience handler, **no** auth). States: probing (spinner) → ok (render `ChildContent`) / failed (render `StartupError Reason="BackendUnreachable"` + Retry). Non-dev: render `ChildContent` immediately (no probe). Gate is a parent of `Router`, so in dev it short-circuits *before* any auth redirect, avoiding the redirect-into-blank case.
- Always-on `<ErrorBoundary>` in `App.razor` wrapping the gate; `ErrorContent` renders `StartupError Reason="Unexpected"`. Safety net for any unhandled render exception.

`App.razor` shape:
```razor
<CascadingAuthenticationState>
  <ErrorBoundary>
    <ChildContent>
      <RequireApiConnectivity>
        <Router ...>...</Router>
      </RequireApiConnectivity>
    </ChildContent>
    <ErrorContent><StartupError Reason="StartupErrorReason.Unexpected" /></ErrorContent>
  </ErrorBoundary>
</CascadingAuthenticationState>
```

### E. API startup dev-config check
Add `WarnOnMissingDevConfig(IConfiguration, ILogger)` to `Extensions/ApiExtensions.cs`; call in `Program.cs` in Development when `!useTestAuth`. For each of empty `AzureAd:TenantId`, `AzureAd:ClientId`, empty `Cors:AllowedOrigins` → `Log.Warning` with remediation pointing at the API's `appsettings.Development.json.example`. Non-fatal.

### F. Examples + docs + setup script
- Frontend `wwwroot/appsettings.Development.json.example` + committed `wwwroot/appsettings.json` → consolidated shape (`Instance`/`TenantId`/`ClientId`, keep `ValidateAuthority`).
- API `appsettings.Development.json.example` already correct — align only if needed.
- **`scripts/setup-dev-entra.ps1:42-49`** writes the frontend `appsettings.Development.json` in the **old** `Authority`/`DefaultScope` shape. Update the `AzureAd` block it emits to `Instance`/`TenantId`/`ClientId` (it already has `$entra.TenantId`/`$entra.ClientId`; drop the now-derived `Authority`/`DefaultScope`). Without this, a fresh `setup-dev-entra.ps1` run produces config `AzureAdSettings.Resolve` can't read. **Critical gap — surfaced by ultraplan refinement.**
- **`docs/development/configuration-strategy.md:190-201`** documents the old frontend `AzureAd` shape — update to the consolidated shape.
- Update `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` local-setup snippet and any README "run locally" notes referencing the old keys.

## Implementation steps

1. **Consolidation** (TDD): `AzureAdSettings.Resolve` + tests (`AzureAdSettingsTests` — authority/scope derivation + override). Wire into `Program.cs` + `ApiAuthorizationMessageHandler`.
2. **Config check** (TDD): `StartupConfigValidator.Check` returning reasons; rewrite `AuthConfigurationValidatorTests` (→ `StartupConfigValidatorTests`) for new shape + result-based assertions.
3. **`StartupError` + enum + `StartupErrorState`**; bUnit `StartupErrorTests` (each reason → expected remediation text).
4. **Config-error wiring** in `Program.cs` (root-component swap).
5. **`RequireApiConnectivity` gate** + `"HealthProbe"` named client; bUnit `RequireApiConnectivityTests` (200 → child; failure → StartupError; non-dev → child, no probe).
6. **`ErrorBoundary` + gate** into `App.razor`.
7. **API `WarnOnMissingDevConfig`** + call site.
8. **Examples + docs** update.
9. **Manual repro** of all three blank-page scenarios to confirm the friendly pages render (see Verification).

## Files

**Create:**
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/AzureAdSettings.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Startup/StartupConfigValidator.cs` (+ `StartupErrorReason` enum, `StartupErrorState`)
- `src/Frontend/AHKFlowApp.UI.Blazor/Startup/StartupError.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Startup/RequireApiConnectivity.razor`
- `tests/AHKFlowApp.UI.Blazor.Tests/Auth/AzureAdSettingsTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Startup/StartupErrorTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Startup/RequireApiConnectivityTests.cs`

**Modify:**
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` (resolve AzureAd, config-error root swap, HealthProbe client)
- `src/Frontend/AHKFlowApp.UI.Blazor/App.razor` (ErrorBoundary + gate)
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/ApiAuthorizationMessageHandler.cs` (use resolved scope)
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/AuthConfigurationValidator.cs` (remove/replace) + `tests/.../Auth/AuthConfigurationValidatorTests.cs` (rewrite)
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json` + `appsettings.Development.json.example`
- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` + `src/Backend/AHKFlowApp.API/Program.cs`
- `scripts/setup-dev-entra.ps1` (frontend `AzureAd` block → consolidated shape)
- `docs/development/configuration-strategy.md` (frontend `AzureAd` doc snippet)
- `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` (+ README notes if referencing old keys)

## Verification

- `dotnet build -c Release` + `dotnet test -c Release` (new bUnit + unit tests pass; rewritten validator tests pass).
- Manual repro (use `playwright-cli` skill to confirm friendly pages, not blank):
  1. Delete frontend `appsettings.Development.json` → run frontend → expect `MissingFrontendConfig` page.
  2. Put `<placeholder>` values back → expect `PlaceholderConfig` page.
  3. Configure frontend correctly, start frontend but **not** the API (or API without dev config) → expect `BackendUnreachable` page (dev probe), and confirm the API console shows the `WarnOnMissingDevConfig` warnings.
  4. Both configured + API running → app loads normally; consolidated `Instance`/`TenantId`/`ClientId` yields a working login + authorized API call.
- `dotnet format` clean.
