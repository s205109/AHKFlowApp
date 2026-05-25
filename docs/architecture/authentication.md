# Authentication Architecture

AHKFlowApp uses single-tenant Entra ID (Azure AD) via MSAL for the Blazor WASM frontend and `Microsoft.Identity.Web` JWT validation on the ASP.NET Core API.

## Flow

```
Browser
  │  user clicks "Log in" → NavigateTo("authentication/login")
  │
  ▼
MSAL (Microsoft.Authentication.WebAssembly.Msal)
  │  redirects to https://login.microsoftonline.com/{tenantId}
  │  Entra issues authorization code
  │  MSAL exchanges code → access token (Bearer JWT)
  │
  ▼
BaseAddressAuthorizationMessageHandler
  │  attaches Bearer token to every HttpClient request to the API base address
  │
  ▼
ASP.NET Core API (UseAuthentication → UseAuthorization)
  │  AddMicrosoftIdentityWebApi validates JWT signature, audience, issuer
  │  [Authorize] enforces authenticated principal
  │  [RequiredScope("access_as_user")] enforces scp claim
  │
  ▼
ICurrentUser (HttpContextCurrentUser)
  │  reads oid / preferred_username / name claims from token
  │  injected into controllers and handlers via DI
  │
  ▼
Handler / Controller returns response
```

## Key components

| Component | Location | Purpose |
|---|---|---|
| `AddMsalAuthentication` | `UI.Blazor/Program.cs` | MSAL browser auth, token cache, scopes |
| `BaseAddressAuthorizationMessageHandler` | `UI.Blazor/Program.cs` | Auto-attaches Bearer token |
| `LoginDisplay.razor` | `UI.Blazor/Shared/` | Login/logout buttons in app bar |
| `Authentication.razor` | `UI.Blazor/Pages/` | MSAL redirect/callback page |
| `RedirectToLogin.razor` | `UI.Blazor/Shared/` | Unauthenticated route guard |
| `AddMicrosoftIdentityWebApi` | `API/Program.cs` | JWT validation via `AzureAd` config |
| `ICurrentUser` | `Application/Abstractions/` | Framework-free user identity interface |
| `HttpContextCurrentUser` | `API/Auth/` | Reads claims from `IHttpContextAccessor` |
| `WhoAmIController` | `API/Controllers/` | Auth verification endpoint (`GET /api/v1/whoami`) |

## App registration

One Entra app registration per environment. The SPA is both the client (SPA redirect URIs) and the resource (exposes `access_as_user` scope, pre-authorizes itself).

- **Scope**: `api://{clientId}/access_as_user`
- **Authority**: `https://login.microsoftonline.com/{tenantId}`
- **Setup**: `scripts/setup-entra-app.ps1` — see `docs/deployment/entra-setup.md`

### Dev redirect URI

For the dev app registration, `setup-entra-app.ps1` registers a single SPA redirect: `http://localhost/authentication/login-callback` (no port). Entra ignores the port for localhost redirects ([Microsoft Learn](https://learn.microsoft.com/entra/identity-platform/reply-url#localhost-exceptions)), so a UI running on any port reachable from `localhost` is accepted. This is what makes the per-worktree dynamic port allocation work without re-registering URIs.

Test and prod registrations are unchanged - they keep the existing fixed local troubleshooting redirect and register the SWA hostname via `setup-entra-app.ps1` as before.

If Entra fails on its own hosted sign-in page before redirecting back to the SPA (for example `AADSTS500011`), that error stays on the Microsoft page. The app can only show friendly guidance for failures that actually return to `Authentication.razor`.

## Auth verification endpoint

`GET /api/v1/whoami` — requires `[Authorize]` + `[RequiredScope("access_as_user")]`. Returns `WhoAmIResponse` with `Oid`, `Email`, `Name`, `IsAuthenticated`. Use this endpoint to verify auth is wired correctly end-to-end.

## Scope enforcement

`[RequiredScope("access_as_user")]` on each protected controller. No global auth filter — every controller must declare `[Authorize]` or `[AllowAnonymous]` explicitly (per AGENTS.md security rules).

## CLI authentication

The `ahkflow` CLI uses MSAL.NET device-code flow against the same per-environment Entra app registration as the Blazor frontend.

- **Commands**: `ahkflow login`, `ahkflow logout`
- **Scope**: `api://{clientId}/access_as_user`
- **Client type**: public client with redirect URI `http://localhost`
- **Token cache**: MSAL persisted user cache at `LocalApplicationData/AHKFlowApp/msal-cache.bin3`

`ahkflow login` tries silent token acquisition first. If the cache is empty or the refresh token requires interaction, the CLI prints the device-code URL and user code to stderr. API commands use `BearerTokenHandler`, which calls `IAuthTokenProvider.GetTokenAsync()` and attaches the cached access token.

Run `scripts/setup-entra-app.ps1 -Environment dev`, `scripts/setup-entra-app.ps1 -Environment test`, or `scripts/setup-entra-app.ps1 -Environment prod` to ensure the app registration has `publicClient.redirectUris` containing `http://localhost` and `isFallbackPublicClient=true`.
