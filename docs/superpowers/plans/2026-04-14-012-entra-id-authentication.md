# Backlog 012 — Entra ID authentication (UI + API)

## Context

Backlog item `012-add-authentication-authorization` adds auth across UI, API, and CLI. Nothing exists today: no MSAL packages, no auth config, a dangling `app.UseAuthorization()` on `Program.cs:162` with no `AddAuthentication()` before it. The frontend has no auth UI and no token-attached HttpClient. The goal of this change is to land the **UI + API** halves so subsequent backlog items (013 hotstrings API CRUD, 014 hotstrings UI CRUD) can add `[Authorize]` endpoints and user-owned data without re-doing plumbing.

## Scope decisions (locked)

1. **CLI deferred.** Backlog 012 amended to drop the CLI acceptance criterion. New item `029-cli-authentication.md` created as a placeholder; implement alongside / after `017-scaffold-cli-project`.
2. **Single-tenant** Entra ID. `AzureAd:TenantId` is a fixed Segocom GUID; authority `https://login.microsoftonline.com/{tenantId}`.
3. **Tokens only, no DB persistence.** Introduce `ICurrentUser` abstraction in `AHKFlowApp.Application`. Implementation lives in **API project** (composition root), reading `IHttpContextAccessor` — keeps `AHKFlowApp.Infrastructure` free of ASP.NET Core references.
4. **Approach A — single app registration per environment.** SPA is the client AND exposes an `access_as_user` scope. Matches `dotnet new blazorwasm --auth SingleOrg` pattern. Future CLI registers as an additional public client for the same scope.

## Critical files

- `src/Backend/AHKFlowApp.API/Program.cs` — register auth, middleware ordering
- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` — Swagger security
- `src/Backend/AHKFlowApp.Application/Abstractions/ICurrentUser.cs` — new interface
- `src/Backend/AHKFlowApp.API/Auth/HttpContextCurrentUser.cs` — new implementation
- `src/Backend/AHKFlowApp.API/Controllers/WhoAmIController.cs` — new protected endpoint for e2e verification
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` — `AddMsalAuthentication`, typed HttpClient handler chain
- `src/Frontend/AHKFlowApp.UI.Blazor/App.razor`, `_Imports.razor`, `wwwroot/index.html`
- `src/Frontend/AHKFlowApp.UI.Blazor/Layout/MainLayout.razor` — add `<LoginDisplay>`
- `src/Frontend/AHKFlowApp.UI.Blazor/Shared/LoginDisplay.razor`, `Shared/RedirectToLogin.razor` (new)
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Authentication.razor` (new)
- `src/Frontend/AHKFlowApp.UI.Blazor/staticwebapp.config.json` — add `navigationFallback` only (no tight CSP). NOTE: lives outside `wwwroot/` since commit `9892c58`, copied on publish via MSBuild target.
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/service-worker.published.js` — `/authentication/*` passthrough
- `Directory.Packages.props` — add new `PackageVersion` entries (CPM)
- `tests/AHKFlowApp.TestUtilities/Auth/TestAuthHandler.cs`, `TestUserBuilder.cs`, factory extension (new)
- `tests/AHKFlowApp.API.Tests/Auth/AuthenticationTests.cs` (new)
- `infra/modules/web.bicep`, `infra/main.bicep`, `infra/main.bicepparam`
- `.github/workflows/deploy-api.yml`, `deploy-frontend.yml`
- `scripts/setup-entra-app.ps1` (new)
- `docs/deployment/entra-setup.md`, `docs/architecture/authentication.md` (new)
- `.claude/backlog/012-add-authentication-authorization.md` (amend), `.claude/backlog/029-cli-authentication.md` (new)

## Packages (run `dotnet add package`, no `--version`, then move to `Directory.Packages.props`)

- **API** (`src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`):
  - `Microsoft.Identity.Web`
  - `Microsoft.AspNetCore.Authentication.JwtBearer` (explicit for CPM pinning)
- **Blazor** (`src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj`):
  - `Microsoft.Authentication.WebAssembly.Msal` (brings `Microsoft.AspNetCore.Components.WebAssembly.Authentication`)
- **TestUtilities**: add `Microsoft.AspNetCore.Authentication` only if `TestAuthHandler` can't resolve `AuthenticationHandler<>` via existing `Microsoft.AspNetCore.Mvc.Testing` transitive graph.

## API implementation

### `Program.cs`

- After line 79 (`AddControllers()`), before line 98 (`builder.Build()`):
  - `builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));`
  - `builder.Services.AddAuthorization();` (explicit — currently implicit)
  - `builder.Services.AddHttpContextAccessor();`
  - `builder.Services.AddScoped<ICurrentUser, HttpContextCurrentUser>();`
- Pipeline order (replacing current line 162 area): `UseHttpsRedirection` → `UseCors` (conditional) → **`UseAuthentication` (new)** → `UseAuthorization`.
- Optionally encapsulate in a new `Extensions/AuthenticationExtensions.cs` (`AddEntraIdAuthentication`) for symmetry with `AddSwaggerDocs` / `AddConfiguredCors`.

### `Extensions/ApiExtensions.cs` — extend `AddSwaggerDocs`

- `AddSecurityDefinition("Bearer", new OpenApiSecurityScheme { Scheme = "bearer", BearerFormat = "JWT", In = ParameterLocation.Header, Type = SecuritySchemeType.Http })`
- Matching `AddSecurityRequirement`.

### `Application/Abstractions/ICurrentUser.cs` (new)

```csharp
public interface ICurrentUser
{
    Guid? Oid { get; }
    string? Email { get; }
    string? Name { get; }
    bool IsAuthenticated { get; }
}
```

Pure primitives — no ASP.NET Core types. Keeps `AHKFlowApp.Application` framework-free.

### `API/Auth/HttpContextCurrentUser.cs` (new)

- Primary constructor takes `IHttpContextAccessor`.
- Reads Oid from `http://schemas.microsoft.com/identity/claims/objectidentifier` or `"oid"`.
- Email from `"preferred_username"` / `ClaimTypes.Email`.
- Name from `ClaimTypes.Name` / `"name"`.
- `IsAuthenticated` from `User?.Identity?.IsAuthenticated ?? false`.

### `API/Controllers/WhoAmIController.cs` (new)

- `[ApiController] [Route("api/v1/[controller]")] [Authorize] [RequiredScope("access_as_user")]`
- Primary constructor `(ICurrentUser currentUser)`
- `GET` returns a `WhoAmIResponse(Guid? Oid, string? Email, string? Name, bool IsAuthenticated)` record (defined alongside the controller).
- Purpose: end-to-end verification target; exercises Authorize + scope + ICurrentUser in one call.

### `HealthController` / `VersionController`

No changes — both already `[AllowAnonymous]`. Confirmed.

### `appsettings.json`

Add the public skeleton:

```json
"AzureAd": {
  "Instance": "https://login.microsoftonline.com/",
  "TenantId": "",
  "ClientId": ""
}
```

Scope enforcement lives on the controller via `[RequiredScope("access_as_user")]` — no `Scopes` config key needed (`AddMicrosoftIdentityWebApi` does not consume one).

### `appsettings.Development.json`

Do **not** commit real GUIDs. Document that developers set `AzureAd:TenantId` and `AzureAd:ClientId` via `dotnet user-secrets`. `Microsoft.Identity.Web` will throw at startup if these are missing — flag in PR description + `entra-setup.md`.

### `appsettings.Test.json`, `appsettings.Production.json`

Extend with the same skeleton. Leave blank placeholders — App Service `appSettings` (set by bicep / workflow) override file-based config. File-level placeholders serve as documentation of the expected shape.

## Frontend implementation

### `AHKFlowApp.UI.Blazor.csproj`

Add `<PackageReference Include="Microsoft.Authentication.WebAssembly.Msal" />` (no `Version=` under CPM).

### `Program.cs`

- `AddMsalAuthentication` registers `BaseAddressAuthorizationMessageHandler` transiently — do **not** register it explicitly (lifetime conflict).
- Change typed HttpClient chain to attach auth **before** resilience:

```csharp
builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
    {
        client.BaseAddress = new Uri(apiBaseUrl);
        client.Timeout = TimeSpan.FromSeconds(30);
    })
    .AddHttpMessageHandler<BaseAddressAuthorizationMessageHandler>()
    .AddStandardResilienceHandler();
```

- Add MSAL:

```csharp
builder.Services.AddMsalAuthentication(options =>
{
    builder.Configuration.Bind("AzureAd", options.ProviderOptions.Authentication);
    options.ProviderOptions.DefaultAccessTokenScopes.Add(builder.Configuration["AzureAd:DefaultScope"]!);
});
```

- Preserve existing `ApiBaseUrlResolver` logic — do not reorder it.

### `wwwroot/appsettings.json`

All MSAL-related keys live inside the `AzureAd` section (matches `Program.cs` which reads `builder.Configuration["AzureAd:DefaultScope"]`):

```json
"AzureAd": {
  "Authority": "",
  "ClientId": "",
  "ValidateAuthority": true,
  "DefaultScope": ""
}
```

### `wwwroot/appsettings.Development.json`

Commit dev values (ClientId and tenant ID are public — MSAL SPA apps ship them in the browser anyway). `Authority` = `https://login.microsoftonline.com/{dev-tenant-guid}`, `DefaultScope` = `api://{dev-clientId}/access_as_user`. File is not gitignored.

### `wwwroot/appsettings.Test.json`, `appsettings.Production.json`

Add placeholders matching existing `#{AZURE_API_BASE_URL}#` convention, keeping everything inside `AzureAd`:

```json
"AzureAd": {
  "Authority": "https://login.microsoftonline.com/#{AZURE_AD_TENANT_ID}#",
  "ClientId": "#{AZURE_AD_CLIENT_ID}#",
  "ValidateAuthority": true,
  "DefaultScope": "#{AZURE_AD_DEFAULT_SCOPE}#"
}
```

`Authority` written as a full assembled string with an embedded placeholder — simpler substitution than splitting into `Instance` + `TenantId`.

### `App.razor`

Wrap existing router in `<CascadingAuthenticationState>`; swap `RouteView` for `AuthorizeRouteView` with `NotAuthorized` → `<RedirectToLogin>`.

### `Shared/RedirectToLogin.razor` (new)

`NavigationManager.NavigateToLogin("authentication/login")` on first render. New `Shared/` folder.

### `Pages/Authentication.razor` (new)

```razor
@page "/authentication/{action}"
<RemoteAuthenticatorView Action="@Action" />
@code { [Parameter] public string? Action { get; set; } }
```

### `Layout/MainLayout.razor`

Add `<MudSpacer />` + `<LoginDisplay />` inside the existing `<MudAppBar>`. MudBlazor-only per frontend `CLAUDE.md`.

### `Shared/LoginDisplay.razor` (new)

`<AuthorizeView>`:
- `<Authorized>`: `MudText` showing `context.User.Identity!.Name`, `MudButton` "Log out" → `SignOutManager.SetSignOutState()` + `NavigateTo("authentication/logout")`.
- `<NotAuthorized>`: `MudButton` "Log in" → `NavigateTo("authentication/login")`.

### `Layout/NavMenu.razor`

No change in this PR. Home and Health remain anonymous. Future pages wrap in `<AuthorizeView>`.

### `_Imports.razor`

Add:
- `@using Microsoft.AspNetCore.Components.Authorization`
- `@using Microsoft.AspNetCore.Components.WebAssembly.Authentication`
- `@using AHKFlowApp.UI.Blazor.Shared`

### `wwwroot/index.html`

After `blazor.webassembly.js`:

```html
<script src="_content/Microsoft.Authentication.WebAssembly.Msal/AuthenticationService.js"></script>
```

### `staticwebapp.config.json` (sibling of `wwwroot/`, not inside it)

Currently `{}`. Add `navigationFallback` so SWA serves `index.html` for SPA routes (incl. `/authentication/login-callback`):

```json
{
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/css/*", "/lib/*", "/_framework/*", "/_content/*", "*.{png,ico,js,css,wasm,json,webmanifest}"]
  }
}
```

**Do not** add `globalHeaders` with a strict CSP — the known MSAL `unsafe-eval` upstream warning (`aspnetcore#64952`) would fire. Leave CSP alone.

### `wwwroot/service-worker.published.js`

Add passthrough so the SW does not intercept MSAL redirect:

```js
if (event.request.url.includes('/authentication/')) {
  return;
}
```

## Infrastructure + deployment

### `infra/modules/web.bicep`

Add params `azureAdTenantId`, `azureAdClientId`, `azureAdInstance` (default `https://login.microsoftonline.com/`). Append App Service `appSettings`:
- `AzureAd__Instance`
- `AzureAd__TenantId`
- `AzureAd__ClientId`

### `infra/main.bicep` + `main.bicepparam`

Add params `azureAdTenantId`, `azureAdClientId`, plumb to `web` module. No defaults. Comment pointing at `setup-entra-app.ps1`.

### `.github/workflows/deploy-api.yml`

Add `az webapp config appsettings set` step after the container image update, sourcing from `vars.AZURE_AD_TENANT_ID_{TEST|PROD}` / `vars.AZURE_AD_CLIENT_ID_{TEST|PROD}`. Use GitHub **Variables** (not Secrets) — these values are public. Ensures auth config flows on every deploy, not only during manual `provision.yml`.

### `.github/workflows/deploy-frontend.yml`

Extend the existing placeholder substitution step (already handles `#{AZURE_API_BASE_URL}#`) to also replace `#{AZURE_AD_TENANT_ID}#`, `#{AZURE_AD_CLIENT_ID}#`, `#{AZURE_AD_DEFAULT_SCOPE}#` in `wwwroot/appsettings.{env}.json`.

### `scripts/setup-entra-app.ps1` (new)

Idempotent `az ad app` script:
- `az ad app list --display-name "AHKFlowApp-{env}"` → create if missing, else update.
- SPA redirect URIs: `https://localhost:7601/authentication/login-callback`, `https://{swaHostname}/authentication/login-callback`, plus matching `/authentication/logout-callback` entries.
- `az ad app update --identifier-uris api://{appId}`.
- Add `oauth2PermissionScopes` → `access_as_user` (admin + user consent enabled).
- Pre-authorize the SPA (same appId) for its own scope.
- Output `ClientId`, `TenantId` for piping into `dotnet user-secrets` and `gh variable set`.
- Parameters: `-Environment dev|test|prod`, `-SwaHostname` (falls back to `az staticwebapp show` for the corresponding env).

### `docs/deployment/entra-setup.md` (new)

Short guide:
1. Run `scripts/setup-entra-app.ps1 -Environment dev` → receive `ClientId`, `TenantId`.
2. `dotnet user-secrets set "AzureAd:TenantId" <value> --project src/Backend/AHKFlowApp.API`, same for `ClientId`.
3. Write matching values into `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json`.
4. For TEST/PROD: `gh variable set AZURE_AD_CLIENT_ID_TEST --body <value>` etc.
5. Section: "what's public vs secret" — all `AzureAd:*` values are public.

### `docs/architecture/authentication.md` (new)

One-page flow: browser → MSAL popup → Entra → code → token → API Bearer call → `AddMicrosoftIdentityWebApi` validation → `[RequiredScope("access_as_user")]` → `ICurrentUser` in handler.

### Backlog

- **Amend** `.claude/backlog/012-add-authentication-authorization.md`:
  - Remove CLI acceptance criterion.
  - Add: "CLI deferred — see 029. Tokens validated against `access_as_user` scope; no user DB persistence (claims-only via `ICurrentUser`)."
- **Create** `.claude/backlog/029-cli-authentication.md` (next free — 028 is last): placeholder pointing at 017, MSAL.NET device-code flow, same scope, public-client registration added to existing Entra app.
- **Update** `.claude/CLAUDE.md` "Out of Scope" section: replace "Authentication implementation details — see backlog item 012" with "CLI authentication — see backlog item 029".

## Tests

### `tests/AHKFlowApp.TestUtilities/Auth/TestAuthHandler.cs` (new)

- Scheme `"Test"`.
- Produces `ClaimsPrincipal` with `oid`, `preferred_username`, `name`, and `scp` claim `access_as_user` (so `[RequiredScope]` passes).
- Reads optional `X-Test-Oid` / `X-Test-Email` headers for per-call overrides, falls back to builder defaults.

### `tests/AHKFlowApp.TestUtilities/Auth/TestUserBuilder.cs` (new)

Fluent builder per project preference (see user memory):
- `.WithOid(Guid)`, `.WithEmail(string)`, `.WithName(string)`, `.WithScope(string)`, `.WithoutScope()`.

### `tests/AHKFlowApp.TestUtilities/Fixtures/CustomWebApplicationFactory.cs` (extend)

Add opt-in builder method `.WithTestAuth(Action<TestUserBuilder>? configure = null)` returning a configured factory instance. Internally:
- `services.AddAuthentication(defaultScheme: "Test").AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => {});` — swaps default scheme so `[Authorize]` uses "Test".

Existing `HealthControllerTests` / `VersionControllerTests` stay untouched — their endpoints are `[AllowAnonymous]` so they don't trigger the scheme.

### `tests/AHKFlowApp.API.Tests/Auth/AuthenticationTests.cs` (new)

Against `WhoAmIController`:
1. `GetWhoAmI_WithoutToken_Returns401` — plain `CreateClient()` call.
2. `GetWhoAmI_WithTestUser_Returns200AndClaims` — `.WithTestAuth(u => u.WithOid(guid).WithEmail("test@example.com"))`.
3. `GetWhoAmI_WithMissingScope_Returns403` — `.WithTestAuth(u => u.WithoutScope())`.
4. `GetHealth_Anonymous_StillWorks` — sanity that `[AllowAnonymous]` is unaffected.

No changes to existing API tests.

## Build sequence (single PR, stacked commits)

Each commit must build and keep existing tests green.

1. **Packages + `ICurrentUser` interface** — `Directory.Packages.props`, `ICurrentUser.cs`. Nothing wired yet. Green.
2. **API auth plumbing + `WhoAmIController` + Swagger Bearer** — `Program.cs`, `HttpContextCurrentUser`, `WhoAmIController`, `appsettings.*.json` placeholders. **Local startup now requires user-secrets** (document in PR). Existing tests still pass — they only hit `[AllowAnonymous]` endpoints.
3. **Test auth infra + `AuthenticationTests`** — `TestAuthHandler`, `TestUserBuilder`, factory extension, `AuthenticationTests.cs`. Full `dotnet test` green.
4. **Frontend MSAL** — csproj package, `Program.cs` handler chain, `App.razor`, `Pages/Authentication.razor`, `Shared/LoginDisplay.razor`, `Shared/RedirectToLogin.razor`, `Layout/MainLayout.razor`, `_Imports.razor`, `index.html`, `appsettings.*.json`, `staticwebapp.config.json`, `service-worker.published.js`. Frontend builds. `bUnit` tests may need tweaks if any touch MainLayout — verify.
5. **Infra + docs + backlog** — `web.bicep`, `main.bicep`, `main.bicepparam`, `deploy-api.yml`, `deploy-frontend.yml`, `scripts/setup-entra-app.ps1`, `docs/deployment/entra-setup.md`, `docs/architecture/authentication.md`, amend backlog 012, create 029, update `.claude/CLAUDE.md`.

**No global `[Authorize]` filter.** Per AGENTS.md rule, every controller (including future ones) must decorate itself explicitly. `[Authorize] [RequiredScope("access_as_user")]` applies only to `WhoAmIController` in this PR.

## Verification

### Local end-to-end

1. `scripts/setup-entra-app.ps1 -Environment dev` → note `ClientId`, `TenantId`.
2. `dotnet user-secrets set "AzureAd:TenantId" <value> --project src/Backend/AHKFlowApp.API`; same for `AzureAd:ClientId`.
3. Update `wwwroot/appsettings.Development.json` with the same values.
4. `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + Docker SQL (Recommended)"`.
5. `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor` (separate terminal).
6. Browser `https://localhost:7601` → click **Log in** → Entra consent → redirected back → `LoginDisplay` shows user name in `MudAppBar`.
7. Visit `/whoami` (or a dev-only test button calling the API) → sees 200 + claims in dev tools.
8. `curl https://localhost:7600/api/v1/whoami` → 401.
9. `curl https://localhost:7600/api/v1/health` → 200.
10. `dotnet test --configuration Release` → all green (incl. new `AuthenticationTests`).
11. `dotnet format` → clean.

### CI

- CI pipeline (`ci.yml`) builds + tests + format check + bicep lint — unchanged. Should pass.

## Risks / edge cases

- **Startup hard-fail on missing config** — `Microsoft.Identity.Web` throws if `ClientId`/`TenantId` missing. Developers pulling this branch must run `setup-entra-app.ps1` first. Call out in PR description.
- **Handler ordering** — `BaseAddressAuthorizationMessageHandler` must precede `AddStandardResilienceHandler` so retries include the token.
- **Service worker interception** — PWA SW will serve stale `/authentication/login-callback` from cache without the passthrough.
- **SWA navigation fallback** — without `navigationFallback`, a hard refresh on `/authentication/login-callback` 404s.
- **CSP upstream warning** — known `aspnetcore#64952`. Do not tighten `staticwebapp.config.json` CSP here.
- **CORS + Bearer preflight** — existing CORS has `.AllowCredentials()` and `.AllowAnyHeader()`; `fdc6d75` already wires SWA hostname. OK.
- **Clock skew** — default JWT tolerance 5 min. Fine unless proven otherwise.
- **CPM version drift** — pin `Microsoft.Identity.Web` + `Microsoft.AspNetCore.Authentication.JwtBearer` explicitly in `Directory.Packages.props`; take latest stable via `dotnet add package`.
- **SWA custom domain future** — when added (per `project_swa_custom_domain_reminder.md`), update both Entra redirect URIs AND `Cors:AllowedOrigins`.
- **`WhoAmIController` is test-only surface** — acceptable as a permanent "health check for auth" endpoint; label it in `docs/architecture/authentication.md` as the canonical auth-verification target.

## Decisions (previously open questions — closing now)

1. Commit `wwwroot/appsettings.Development.json` w/ dev ClientId + tenant ID. Public anyway in SPA.
2. Auth config for TEST/PROD flows via `deploy-api.yml` `appsettings set` step every deploy — not bicep-only. Drift-proof.
3. Don't pre-add CPM package ref to `TestUtilities`. Only add if `AuthenticationHandler<>` resolution fails in commit 3.
4. Frontend `appsettings.Test.json` / `.Production.json` write `Authority` as full assembled string w/ embedded `#{AZURE_AD_TENANT_ID}#`. No runtime assembly in `Program.cs`.
5. Keep `WhoAmIController` permanently. Doubles as an auth health-check endpoint; label as such in `docs/architecture/authentication.md`.

## Unresolved questions

None.
