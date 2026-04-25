# Plan — Unify local-dev API on `http://localhost:5600`, delete `ApiBaseUrlResolver`

## Context

The Blazor WASM frontend resolves the API base URL at startup by probing a list of
candidates (`https://localhost:7600`, `http://localhost:5600`, `http://localhost:5602`,
`http://localhost:5604`) and picking the first one that answers `/api/v1/health`,
with a scheme-preference tiebreaker relative to the host page.

This exists because every backend launch profile binds a *different* port:

| Backend profile | URL(s) |
|---|---|
| `https + Docker SQL (Recommended)` (VS) | `https://localhost:7600;http://localhost:5600` |
| `https + LocalDB SQL` (VS) | `https://localhost:7600;http://localhost:5600` |
| `Docker Compose (No Debugging)` | `http://localhost:5602` |
| `Docker (API only …)` | `http://localhost:5604` |

The recent fix `ba8e394` (stop API container + add HTTP candidate) patched one symptom:
when a stale compose container was still listening on 5602, the resolver would silently
pick it instead of the fresh VS-hosted API. That fix works one direction only and leaves
the underlying fragility — scheme heuristics, port ambiguity, probe races — intact.

User confirmed: only one backend runs at a time, all of the stack is fair game to change,
and dev should be HTTP-only on a single port. This plan eliminates the resolver by
removing its reason to exist.

## Approach

Every local-dev backend scenario binds **exactly** `http://localhost:5600`. The frontend
reads `ApiHttpClient:BaseAddress` from configuration and uses it directly. No probing,
no candidates, no scheme heuristics. A port conflict surfaces as a clear "address in use"
error rather than a silent mis-route.

The existing `docker compose stop ahkflowapp-api` pre-step in `DevDockerSqlServer.cs`
already enforces the "one API at a time" invariant for the VS-launch case and stays as-is.

## Changes

### Frontend

1. **Delete** `src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiBaseUrlResolver.cs`.
2. **`src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`** — replace the `ApiBaseUrlResolver.ResolveAsync(...)` call with a direct configuration read:
   ```csharp
   string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]
       ?? throw new InvalidOperationException("ApiHttpClient:BaseAddress is not configured.");
   ```
   Keep the rest of the file unchanged.
3. **`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json`** — replace the `ApiHttpClient` block with:
   ```json
   "ApiHttpClient": {
     "BaseAddress": "http://localhost:5600"
   }
   ```
   Drop `BaseAddressCandidates` entirely.
4. **`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example`** — same trim; drop the `BaseAddressCandidates` array.
5. **`src/Frontend/AHKFlowApp.UI.Blazor/Properties/launchSettings.json`** — delete the `https` profile. Keep only `http` binding `http://localhost:5601`.

### Backend

6. **`src/Backend/AHKFlowApp.API/Properties/launchSettings.json`** — for every profile:
   - `"https + Docker SQL (Recommended)"` → rename to `"Docker SQL (Recommended)"`, `applicationUrl` = `http://localhost:5600`.
   - `"https + LocalDB SQL"` → rename to `"LocalDB SQL"`, `applicationUrl` = `http://localhost:5600`.
   - `"Docker Compose (No Debugging)"` → change `launchUrl` and the PowerShell `$url` from `5602` to `5600`.
   - `"Docker (API only - requires SQL on localhost:1433)"` → change `httpPort` from `5604` to `5600`, update `launchUrl`.
7. **`docker-compose.yml`** — change `ports: ["5602:8080"]` to `["5600:8080"]`.
8. **`src/Backend/AHKFlowApp.API/DevDockerSqlServer.cs`** — update the port-reference comment (currently mentions "port 5602") to say 5600. The `docker compose stop` logic stays.

### Docs / tooling

9. Search-and-replace `5602`, `5604`, and `https://localhost:7600` references in:
   - `AGENTS.md` (Environment URLs section)
   - `README.md`
   - `docs/environments.md`
   - `docs/development/configuration-strategy.md`
   - `docs/development/docker-setup.md`
   - `docs/development/playwright-setup.md`
   - `.vscode/launch.json`
   - `scripts/kill-dev-ports.ps1`

   Historical superpowers plan/spec docs under `docs/superpowers/` are snapshots — leave untouched.

### Azure AD (manual, out-of-repo)

10. Add `http://localhost:5601` to the Azure AD app registration's SPA redirect URIs (if it isn't already). Without this, MSAL sign-in from the HTTP frontend will fail with `AADSTS500113` or `redirect_uri_mismatch`. Azure AD explicitly allows `http://localhost` for SPA dev.

## Critical files to review during implementation

- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs:13-16` — resolver call site.
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json:1-10` — frontend config source.
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` — all four profiles.
- `docker-compose.yml:32-33` — port mapping.
- `src/Backend/AHKFlowApp.API/DevDockerSqlServer.cs:20-25` — "stop container" hook (kept as-is).

## Verification

1. `dotnet build --configuration Release` — must succeed.
2. `dotnet test --configuration Release --no-build` — all tests pass (no resolver tests exist today, confirmed via grep).
3. **VS profile — Docker SQL (Recommended):** F5, open `http://localhost:5601`, sign in via MSAL, exercise a page that calls the API, confirm 200 responses.
4. **VS profile — LocalDB SQL:** same as above.
5. **Docker Compose (No Debugging):** run the profile, confirm Swagger opens at `http://localhost:5600/swagger`, frontend calls succeed.
6. **Docker (API only):** run with external SQL on 1433, same check.
7. **Stale container guard:** `docker compose up -d`, then F5 the VS profile, confirm `DevDockerSqlServer` stops the container and VS binds 5600 cleanly.
8. **Port conflict fail-fast:** start two backends simultaneously, confirm the second fails with a clear "address in use" error (no silent misroute).

## Unresolved questions

- Azure AD app registration: `http://localhost:5601` already listed as redirect URI, or manual add needed?
- Any external doc/readme outside this repo (e.g., team wiki, Notion) that hardcodes `5602`/`5604`/`7600`?
- Keep superpowers historical specs/plans untouched as snapshots — confirm?
