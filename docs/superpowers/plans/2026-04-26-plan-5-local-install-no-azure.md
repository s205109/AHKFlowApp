# Plan 5 — Local-install path, no Azure

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute this plan task-by-task. Steps use `- [ ]` checkbox syntax for tracking.
>
> **On execution start:** copy this file to `docs/superpowers/plans/2026-04-26-plan-5-local-install-no-azure.md` and work from that path (this draft lives outside the repo because plan mode only permits one writable file).

## Context

`docker compose up` from a clean checkout currently cannot reach `[Authorize]` endpoints — the API hard-wires `AddMicrosoftIdentityWebApi` against an empty `AzureAd` config, and the Blazor frontend isn't in compose at all. The frontend already has an `Auth:UseTestProvider` toggle that swaps MSAL for a synthetic provider; this plan adds the symmetric backend toggle, containerises the Blazor app, and documents the homelab/trusted-LAN flow. Trust model: single-user, no real auth — the README must say so plainly.

This is plan 5 of the codebase-simplification roadmap (`docs/superpowers/specs/2026-04-21-codebase-simplification-roadmap-design.md`). Plan-1 audit already landed.

## Architecture

- New `TestAuthenticationHandler` in `src/Backend/AHKFlowApp.API/Auth/` — internal, hardcoded synthetic user, injects both `scp` and the long-form scope URI claim so `[RequiredScope("access_as_user")]` passes.
- `Program.cs` branches on `Auth:UseTestProvider` (matches the existing frontend flag exactly): when `true`, register the test scheme as default; when `false`, the existing `AddMicrosoftIdentityWebApi` path is unchanged.
- Blazor WASM gets a new Dockerfile (publish → nginx static). nginx sets `Blazor-Environment: Local` so the WASM client loads a new `appsettings.Local.json` with `Auth:UseTestProvider=true`.
- nginx **also reverse-proxies `/api/` to the API container** — single browser origin, so `ApiBaseUrl` stays `/` (matches the existing E2E pattern) and no CORS is involved at all.
- `docker-compose.yml` adds the Blazor service, sets `Auth__UseTestProvider=true` on the API service, and exposes 5601 → 8080 for the frontend. The API's host port (5600) stays mapped for direct curl/swagger access during debugging, but the browser only ever talks to 5601.
- Existing test auth handlers in `tests/AHKFlowApp.TestUtilities/Auth/` and `tests/AHKFlowApp.E2E.Tests/Fixtures/` are **left in place** — the new prod handler is independent. Tests stay green without churn.

## Tech stack

ASP.NET Core auth (`AuthenticationHandler<AuthenticationSchemeOptions>`), Microsoft.Identity.Web (existing prod path), Blazor WebAssembly, nginx (static host), Docker Compose, xUnit + WebApplicationFactory.

## Critical files

| Path | Action |
|---|---|
| `src/Backend/AHKFlowApp.API/Auth/TestAuthenticationHandler.cs` | Create |
| `src/Backend/AHKFlowApp.API/Program.cs` | Modify (lines ~105-109 today) |
| `src/Backend/AHKFlowApp.API/appsettings.json` | Modify (add `Auth` section default) |
| `tests/AHKFlowApp.API.Tests/Auth/TestAuthProviderToggleTests.cs` | Create |
| `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Local.json` | Create |
| `src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile` | Create |
| `src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf` | Create |
| `docker-compose.yml` | Modify |
| `README.md` | Modify (add new section under "Local Development") |

---

## Task 1 — Promote `TestAuthenticationHandler` into the API project

**Files:**
- Create: `src/Backend/AHKFlowApp.API/Auth/TestAuthenticationHandler.cs`

- [ ] **Step 1.1: Create the handler**

```csharp
namespace AHKFlowApp.API.Auth;

using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

internal sealed class TestAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "TestAuth";

    private const string SyntheticOid = "11111111-1111-1111-1111-111111111111";
    private const string SyntheticEmail = "local@homelab.invalid";
    private const string SyntheticName = "Local User";
    private const string Scope = "access_as_user";
    private const string ScopeClaimUri = "http://schemas.microsoft.com/identity/claims/scope";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        Claim[] claims =
        [
            new("oid", SyntheticOid),
            new("preferred_username", SyntheticEmail),
            new(ClaimTypes.Name, SyntheticName),
            new("scp", Scope),
            new(ScopeClaimUri, Scope),
        ];

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
```

Why oid `11111111-...`: matches the frontend's `TestAuthenticationProvider` so the WhoAmI/owner-scoped queries see the same identity on both sides.

- [ ] **Step 1.2: Build and verify**

```bash
dotnet build src/Backend/AHKFlowApp.API --configuration Release --no-restore
```

Expected: succeeds. Handler compiles but is not yet wired anywhere.

- [ ] **Step 1.3: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Auth/TestAuthenticationHandler.cs
git commit -m "feat(api): add TestAuthenticationHandler for local-install toggle"
```

---

## Task 2 — Add `Auth:UseTestProvider` toggle in API `Program.cs`

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Program.cs` (current auth block lines 105-109)

- [ ] **Step 2.1: Replace the auth registration block**

Find:
```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
builder.Services.AddAuthorization();
```

Replace with:
```csharp
bool useTestAuth = builder.Configuration.GetValue<bool>("Auth:UseTestProvider");

if (useTestAuth)
{
    builder.Services
        .AddAuthentication(TestAuthenticationHandler.SchemeName)
        .AddScheme<AuthenticationSchemeOptions, TestAuthenticationHandler>(
            TestAuthenticationHandler.SchemeName, _ => { });
}
else
{
    builder.Services
        .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
}

builder.Services.AddAuthorization();
```

Add `using AHKFlowApp.API.Auth;` if not already present.

- [ ] **Step 2.2: Add startup log when test auth is active**

Right after the `if (useTestAuth)` registration block, inside the `if`:

```csharp
    Log.Warning("Auth:UseTestProvider=true — synthetic auth active. Single-user / trusted-LAN only.");
```

(The codebase uses Serilog static `Log` in Program.cs — confirm by reading lines around the auth block before applying.)

- [ ] **Step 2.3: Default the toggle to false in `appsettings.json`**

Modify `src/Backend/AHKFlowApp.API/appsettings.json` — add at the root (next to existing `AzureAd`):

```json
"Auth": {
  "UseTestProvider": false
}
```

- [ ] **Step 2.4: Build**

```bash
dotnet build src/Backend/AHKFlowApp.API --configuration Release --no-restore
```

Expected: succeeds.

- [ ] **Step 2.5: Run existing API tests to confirm no regression**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Expected: all green. Existing tests use `CustomWebApplicationFactory.WithTestAuth()` which overrides DI directly — they don't go through the new toggle.

- [ ] **Step 2.6: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Program.cs src/Backend/AHKFlowApp.API/appsettings.json
git commit -m "feat(api): wire Auth:UseTestProvider toggle"
```

---

## Task 3 — Integration test: toggle reaches `[Authorize]` endpoint with no Azure config

**Files:**
- Create: `tests/AHKFlowApp.API.Tests/Auth/TestAuthProviderToggleTests.cs`

- [ ] **Step 3.1: Write the failing test**

The test must exercise the *real* `Program.cs` auth wiring (not `CustomWebApplicationFactory.WithTestAuth()`, which bypasses it via DI override) **and** still satisfy DB-startup wiring. Inherit from `CustomWebApplicationFactory` to inherit Testcontainers SQL, then override config to flip the toggle and don't call `WithTestAuth()`.

```csharp
namespace AHKFlowApp.API.Tests.Auth;

using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

public sealed class TestAuthProviderToggleTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly WebApplicationFactory<Program> _factory;

    public TestAuthProviderToggleTests(CustomWebApplicationFactory factory)
    {
        _factory = factory.WithWebHostBuilder(b => b.ConfigureAppConfiguration(c =>
        {
            c.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:UseTestProvider"] = "true",
                ["AzureAd:Instance"] = "",
                ["AzureAd:TenantId"] = "",
                ["AzureAd:ClientId"] = "",
            });
        }));
    }

    [Fact]
    public async Task WhoAmI_WithToggleOn_Returns200_WithSyntheticUser()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("local@homelab.invalid");
    }
}
```

WhoAmI just reads claims — no DB query — so it isolates the auth-pipeline behaviour.

**Read first:**
- `tests/AHKFlowApp.TestUtilities/Fixtures/CustomWebApplicationFactory.cs` — confirm the class signature, Testcontainers wiring, and that overriding `ConfigureAppConfiguration` doesn't conflict with its own setup. If the factory itself sets `Auth:UseTestProvider=false` or registers the test scheme via `WithTestAuth()` unconditionally, neutralise that path before the in-memory override (e.g., construct a fresh inheriting class with a clean `ConfigureWebHost`).
- `src/Backend/AHKFlowApp.API/Controllers/WhoAmIController.cs` — confirm endpoint route is `/api/v1/whoami` (the controller name auto-routes per `[Route("api/v1/[controller]")]`).

- [ ] **Step 3.2: Run — expect failure first if you forgot the toggle, success otherwise**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~TestAuthProviderToggleTests" --verbosity normal
```

Expected: PASS once Tasks 1+2 are wired. If FAIL, debug auth pipeline (most likely: scope claim mismatch or scheme not registered).

- [ ] **Step 3.3: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/Auth/TestAuthProviderToggleTests.cs
git commit -m "test(api): cover Auth:UseTestProvider toggle"
```

---

## Task 4 — Blazor `appsettings.Local.json`

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Local.json`

- [ ] **Step 4.1: Create file**

```json
{
  "Auth": {
    "UseTestProvider": true
  },
  "ApiHttpClient": {
    "BaseAddress": "/"
  },
  "ApiBaseUrl": "/"
}
```

Same-origin: nginx (Task 5) reverse-proxies `/api/` to the API container, so `ApiBaseUrl="/"` is correct and the browser never makes a cross-origin request. This mirrors the existing `appsettings.E2E.json` pattern.

Read `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` lines 22-37 before applying — confirm both `IAhkFlowAppApiHttpClient` and `IHotstringsApiClient` derive their base address from `ApiBaseUrl`. If a client uses `ApiHttpClient:BaseAddress` from a separate config key, set it to `/` too (already covered above).

- [ ] **Step 4.2: Verify the publish copies wwwroot/appsettings.Local.json**

```bash
dotnet publish src/Frontend/AHKFlowApp.UI.Blazor --configuration Release -o /tmp/blazor-publish
ls /tmp/blazor-publish/wwwroot/appsettings.Local.json
```

Expected: file present.

- [ ] **Step 4.3: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Local.json
git commit -m "feat(ui): add appsettings.Local.json for docker-compose path"
```

---

## Task 5 — Blazor Dockerfile + nginx config

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf`

- [ ] **Step 5.1: Create nginx config**

`src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf`:
```nginx
server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Blazor WASM environment selector — picks appsettings.Local.json
    add_header Blazor-Environment "Local" always;

    # Reverse-proxy API calls to the api container (same-origin, no CORS)
    location /api/ {
        proxy_pass http://ahkflowapp-api:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # /health and /swagger pass through too (handy for in-browser debugging)
    location /health  { proxy_pass http://ahkflowapp-api:8080; }
    location /swagger { proxy_pass http://ahkflowapp-api:8080; }

    # SPA fallback (must come last for path-routing)
    location / {
        try_files $uri $uri/ /index.html =404;
    }

    # Long-cache for fingerprinted assets
    location ~* \.(?:js|css|wasm|dat|woff2)$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    # Brotli/gzip already pre-compressed by Blazor publish
    location ~ \.(?:js|css|wasm|dat)\.br$ {
        add_header Content-Encoding br;
        default_type application/octet-stream;
    }
}
```

> **Verification gate during execution.** The `Blazor-Environment` header is the documented mechanism for selecting `appsettings.{Env}.json` in standalone Blazor WASM. If after Task 7 step 7.4 the browser network tab shows it loading `appsettings.json` instead of `appsettings.Local.json`, the mechanism has changed in the .NET 10 host. Fallback: bake the local config into `appsettings.json` directly inside the Dockerfile via a `RUN cp wwwroot/appsettings.Local.json wwwroot/appsettings.json` step on the published output. Don't merge the PR until the network tab confirms `appsettings.Local.json` is the active config.

- [ ] **Step 5.2: Create Dockerfile**

`src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile`:
```dockerfile
# syntax=docker/dockerfile:1
ARG DOTNET_SDK=10.0
ARG NGINX=1.27-alpine

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK} AS build
WORKDIR /src
COPY . .
RUN dotnet restore src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj
RUN dotnet publish src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj \
    -c Release -o /app/publish --no-restore

FROM nginx:${NGINX} AS final
COPY --from=build /app/publish/wwwroot /usr/share/nginx/html
COPY src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
```

Build context note: this Dockerfile is built from the **repo root** so `COPY . .` sees the whole solution. Ensure compose `build.context` is `.`.

- [ ] **Step 5.3: Local build smoke**

```bash
docker build -f src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile -t ahkflowapp-ui:local .
```

Expected: succeeds.

- [ ] **Step 5.4: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf
git commit -m "feat(ui): add Dockerfile + nginx config for blazor wasm"
```

---

## Task 6 — Wire Blazor + auth toggle in `docker-compose.yml`

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 6.1: Add `Auth__UseTestProvider=true` to `ahkflowapp-api`**

Under the existing `ahkflowapp-api.environment` block (currently has `ASPNETCORE_ENVIRONMENT=Development`, `ASPNETCORE_HTTP_PORTS=8080`, `ConnectionStrings__DefaultConnection=...`), add:

```yaml
      - Auth__UseTestProvider=true
```

- [ ] **Step 6.2: Add the `ahkflowapp-ui` service**

Append a new service block:

```yaml
  ahkflowapp-ui:
    build:
      context: .
      dockerfile: src/Frontend/AHKFlowApp.UI.Blazor/Dockerfile
    container_name: ahkflowapp-ui
    ports:
      - "5601:8080"
    depends_on:
      ahkflowapp-api:
        condition: service_started
    networks:
      - ahkflowapp-network
```

(`Auth__UseTestProvider` is **not** an env var on the UI service — Blazor WASM is static-served and reads `appsettings.Local.json` chosen via the `Blazor-Environment: Local` response header set in nginx. The env-var pattern in the design spec doesn't apply to a WASM static deploy; documenting this in the README is part of Task 8.)

- [ ] **Step 6.3: `docker compose config` smoke**

```bash
docker compose config
```

Expected: prints merged config with no errors; both services present; ports 5600 and 5601 mapped.

- [ ] **Step 6.4: Commit**

```bash
git add docker-compose.yml
git commit -m "chore(compose): add blazor service and Auth__UseTestProvider on api"
```

---

## Task 7 — End-to-end verification on a clean checkout

This task produces no commit; it is a verification gate before the README claims it works.

- [ ] **Step 7.1: Tear down and rebuild**

```bash
docker compose down -v
docker compose up --build -d
```

- [ ] **Step 7.2: Wait for health, then probe API anonymous health**

```bash
curl -fsS http://localhost:5600/health
```

Expected: `Healthy`.

- [ ] **Step 7.3: Probe `[Authorize]` endpoint without auth header — should 200 (test auth handles it)**

```bash
curl -fsS -i http://localhost:5600/api/v1/whoami
```

Expected: `HTTP/1.1 200 OK`, body contains `local@homelab.invalid`.

- [ ] **Step 7.4: Open the Blazor UI in a browser**

Browse `http://localhost:5601`. Expected: app loads, no MSAL redirect, navigates as `Local User`. Hotstrings page reachable.

**Open DevTools → Network tab.** Confirm:
- `appsettings.Local.json` is fetched (200), `appsettings.json` is also fetched but Local overrides.
- API calls go to `http://localhost:5601/api/v1/...` (same-origin via the nginx proxy), return 200, and **no CORS preflight** is visible.

If `appsettings.Local.json` is **not** fetched, the `Blazor-Environment` header mechanism has changed in .NET 10 — apply the Dockerfile fallback called out in Task 5's verification gate before continuing.

- [ ] **Step 7.5: Seed and list hotstrings**

```bash
curl -fsS -X POST http://localhost:5600/api/v1/dev/hotstrings/seed
curl -fsS http://localhost:5600/api/v1/hotstrings
```

Expected: 3 hotstrings (`btw`, `fyi`, `brb`).

- [ ] **Step 7.6: Tear down**

```bash
docker compose down -v
```

If any step fails, stop and debug before Task 8 — the README must not document a broken path.

---

## Task 8 — README "Run locally without Azure" section

**Files:**
- Modify: `README.md`

- [ ] **Step 8.1: Add a new subsection under `## Local Development` → `### Running Locally`**

After the existing "Option 2 — Docker Compose (recommended)" line, append:

```markdown
**Option 3 — Docker Compose without Azure (homelab / trusted-LAN):**

Runs the full stack — SQL Server, API, and Blazor frontend — with no Azure AD sign-in. Authentication is bypassed via a synthetic `Local User` identity on every request.

> **Trust model.** The synthetic auth provider authenticates *every* request as the same fixed user. This is acceptable for **single-user homelab use on a trusted LAN only**. Do not expose this configuration to the public internet. To switch back to real Entra ID auth, set `Auth:UseTestProvider=false` (or remove the env var) and provide `AzureAd:*` config.

```bash
git clone <repo>
cd AHKFlowApp
docker compose up --build
```

Then open http://localhost:5601 in a browser. The app loads as `Local User` with no sign-in prompt.

| Service | URL |
|---|---|
| Blazor UI | http://localhost:5601 |
| API | http://localhost:5600 |
| API health | http://localhost:5600/health |
| API OpenAPI | http://localhost:5600/swagger/v1/swagger.json |
| SQL Server | localhost:1433 (sa / `Dev!LocalOnly_2026`) |

To populate sample hotstrings:

```bash
curl -X POST http://localhost:5600/api/v1/dev/hotstrings/seed
```

**How the toggle works:**
- API reads `Auth:UseTestProvider` (set in compose as `Auth__UseTestProvider=true`). When true, it registers a `TestAuthenticationHandler` that injects a fixed identity instead of validating Azure AD JWTs.
- Blazor WASM reads `appsettings.Local.json` (selected by the `Blazor-Environment: Local` header set by nginx). It bypasses MSAL and the Authorization header.

**To run with real Entra ID instead** — see [docs/architecture/authentication.md](docs/architecture/authentication.md) and clear the env override:

```bash
Auth__UseTestProvider= docker compose up
```
```

- [ ] **Step 8.2: Update the URLs table at the end of `## Local Development`**

If the existing URLs table doesn't already mention port 5601, leave it (it does — Frontend → http://localhost:5601 is already listed).

- [ ] **Step 8.3: Commit**

```bash
git add README.md
git commit -m "docs: document Run locally without Azure path"
```

---

## Verification (end-to-end)

A reviewer can verify this PR end-to-end with:

```bash
# Fresh clone
git clone <repo> /tmp/ahkflow-verify
cd /tmp/ahkflow-verify

# Backend build + tests (toggle test included)
dotnet test tests/AHKFlowApp.API.Tests \
  --filter "FullyQualifiedName~TestAuthProviderToggleTests" \
  --verbosity normal

# Compose end-to-end
docker compose up --build -d
curl -fsS http://localhost:5600/health
curl -fsS http://localhost:5600/api/v1/whoami | grep -q "local@homelab.invalid"
# Browse http://localhost:5601 — confirm no sign-in, app loads as Local User.
docker compose down -v
```

Plus full backend test suite green:
```bash
dotnet test --configuration Release --no-build --verbosity normal
```

---

## Out of scope

Per the design spec:
- Separate `run-local.ps1` / `deploy-local.ps1` script.
- New compose profile.
- Raspberry Pi-specific tuning.
- Real auth (OIDC / Keycloak / local identity).
- Consolidating the two existing test-only handlers (`tests/AHKFlowApp.TestUtilities/Auth/TestAuthHandler.cs`, `tests/AHKFlowApp.E2E.Tests/Fixtures/TestAuthHandler.cs`) — independent cleanup.

---

## Unresolved questions

- Compose UI service: build context is repo root — accept the larger Docker build context, or add `.dockerignore` updates? (Default: accept; spec is M-sized, no .dockerignore tuning.)
- Frontend port collision: 5601 is already used by `dotnet run` for local dev. Documenting both flows risks user confusion — call it out in README, or assume mutually-exclusive use? (Default: assume mutually exclusive; one paragraph in README is enough.)
- `Auth:UseTestProvider` defaulting in non-compose Development: should `appsettings.Development.json` set it to true so `dotnet run` works without Azure config too? (Spec is silent; default to false to keep the existing developer flow unchanged — devs who want it can use compose.)
- Does plan-4's `deploy.ps1` preflight check need to know about the toggle (e.g., warn if `Auth__UseTestProvider=true` is in env when deploying to Azure)? Out of scope here, flag for plan 4 follow-up.
