# Local Dev Port Conflict Mitigation — Design

**Status:** Approved 2026-05-25. Implementation plan added in `docs/superpowers/plans/2026-05-25-local-dev-port-conflict.md`.

## Goal

Let multiple AHKFlowApp worktrees and AI-agent sessions run the API and Blazor UI concurrently on one machine without localhost port collisions, while keeping MSAL auth, CORS, Swagger, and Playwright workflows usable.

## Non-goals

- Docker Compose multi-instance support
- HTTPS localhost dynamic-port workflow
- Reverse-proxying `/api` through the UI host
- New PowerShell test tooling (e.g., Pester)

## Primary scenarios

1. Human dev has the stack running on `5600/5601`; an AI agent in another worktree starts its own stack.
2. Two or more AI agents work in parallel worktrees, each needing an isolated stack.

## Architecture

One launcher, one manifest per worktree, one Entra redirect URI.

`scripts/start-local-stack.ps1` is **configure-only** — it does not start processes. Per invocation it:

1. Acquires a machine-wide lock at `$env:TEMP\ahkflow-port-alloc.lock` (created/opened exclusively, held for the duration of allocation + manifest write). Narrows the launcher-vs-launcher race to the time between two `dotnet run` invocations, which `dotnet run` itself will report loudly as "address in use" if it happens.
2. Scans for the lowest free port-pair starting at `5600/5601`, stepping `+2/+2` up to `5698/5699`. First pair where both ports are free wins.
3. Rewrites `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json` so `ApiHttpClient:BaseAddress` matches the chosen API port. Preserves `AzureAd` section.
4. Writes a manifest at `scripts/.env.local` (gitignored by existing `scripts/.env.*` rule) containing the API URL, UI URL, chosen ports, and the absolute worktree path. `kill-dev-ports.ps1` uses the recorded path to detect stale/copied manifests, but verifies process ownership against the current worktree path.
5. Prints the exact `dotnet run` commands for API and UI. Commands **keep the launch profile** (so `ASPNETCORE_ENVIRONMENT`, `AHKFLOW_START_DOCKER_SQL`, and the dev `ConnectionStrings__DefaultConnection` come from `launchSettings.json` for free) and pass `-- --urls http://localhost:<port>` to override the fixed profile ports at run time. CORS is updated by rewriting the API's gitignored `appsettings.Development.json` so `Cors.AllowedOrigins` contains the selected UI origin.

**Residual races acknowledged:** even with the lock, another agent can grab the chosen pair after the launcher exits but before `dotnet run` binds. This is rare in practice, and `dotnet run` fails with a loud, debuggable error. The lock only closes the narrow allocator-vs-allocator window.

The launcher owns no processes, no PIDs, no log capture. The worktree boundary is the isolation boundary — each worktree has its own `wwwroot/appsettings.Development.json` and `scripts/.env.local`.

The first worktree run lands on `5600/5601`, so historical addresses still work without a separate legacy code path.

## Entra strategy

**Scope: dev only.** Only the `-Environment dev` branch of `scripts/setup-entra-app.ps1` changes. The `test` and `prod` branches — including SWA hostname registration consumed by `scripts/deploy.ps1` — are not touched.

In the dev branch: register a single SPA redirect URI `http://localhost/authentication/login-callback` (no port). Rely on Entra's documented localhost port-ignoring behavior ([Microsoft Learn — localhost exceptions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url#localhost-exceptions)). Microsoft explicitly warns against registering multiple localhost URIs that differ only by port, so port enumeration is **not** an acceptable fallback.

**If verification (Task 5 of the implementation plan) shows MSAL.js / Blazor WASM does not honor port-ignoring for SPA flows:** the multi-worktree-UI use case is blocked by Entra design, not by anything this spec can fix with redirect-URI tricks. Document the limitation and ship a reduced design: only one worktree can run the UI at a time, but multiple APIs can still run in parallel for backend work. Investigating alternatives (reverse-proxy through a single fixed-port UI host, distinguishable callback paths via Blazor MSAL config) is deferred to a follow-up spec.

## Components

### New

- `scripts/start-local-stack.ps1` — launcher described above. Dot-sources `Common.ps1` for logging. Accepts `-ApiPort` and `-UiPort` overrides; otherwise auto-allocates. Accepts `-ApiLaunchProfile` for the printed API command, defaulting to `Docker SQL (Recommended)` with `LocalDB SQL` available for LocalDB workflows.

### Modified

- `scripts/setup-dev-entra.ps1` — stop hardcoding `http://localhost:5600` as the API base. If the frontend `appsettings.Development.json` exists, preserve its existing `ApiHttpClient:BaseAddress`. If not, write `http://localhost:5600` as a placeholder; the launcher overwrites it.
- `scripts/setup-entra-app.ps1` — **dev branch only**: register a single port-less SPA redirect URI per the Entra strategy above. `test` and `prod` branches (including SWA hostname registration that `scripts/deploy.ps1` depends on) remain unchanged.
- `scripts/kill-dev-ports.ps1` — if `scripts/.env.local` is present, kill ports it names **only when the owning process is verifiably ours**: get the owning PID, read its command line via `Get-CimInstance Win32_Process`, and kill only if the command line references the current worktree's absolute path. If the manifest's recorded worktree path differs from the current worktree, warn and still use the current worktree for ownership checks. If `scripts/.env.local` is absent, fall back to the old behavior of killing whatever owns `5600/5601` (with the same ownership check applied). Refuse to kill foreign processes; print a message naming the foreign PID and command line.
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example` — neutralize the placeholder, add a one-line note that `start-local-stack.ps1` overwrites the file.
- `tests/AHKFlowApp.UI.Blazor.Tests/Auth/AuthConfigurationValidatorTests.cs` — add one case proving a non-`5600` localhost base URL passes validation.
- `README.md`, `docs/development/configuration-strategy.md`, `docs/development/playwright-setup.md`, `docs/development/docker-setup.md`, `docs/architecture/authentication.md` — replace `5600/5601` references with "run `start-local-stack.ps1`" or "read `scripts/.env.local`."

### Explicitly NOT modified

- `src/Backend/AHKFlowApp.API/Program.cs` — Kestrel's `-- --urls` command-line override is honored without code changes; no hardcoded `5600` in startup logging.
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/AuthConfigurationValidator.cs` — already port-agnostic. The validator only checks for non-empty values and `<` placeholders.
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`, `src/Frontend/AHKFlowApp.UI.Blazor/Properties/launchSettings.json` — kept so VS F5 still works for ad-hoc single-instance debugging.
- `docker-compose.yml` — out of scope.

## Data flow

### First worktree run

```
$ cd C:\Dev\segocom-github\AHKFlowApp
$ .\scripts\start-local-stack.ps1

  ==> Allocating port pair
  + 5600/5601 free
  ==> Writing manifest
  + scripts/.env.local
  ==> Configuring frontend
  + src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json

  Run these in two terminals:

    dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)" -- --urls "http://localhost:5600"

    dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor --launch-profile "http" -- --urls "http://localhost:5601"

  API:  http://localhost:5600
  UI:   http://localhost:5601
```

### Second worktree run

```
$ cd C:\Dev\segocom-github\AHKFlowApp\.worktrees\feature\foo
$ .\scripts\start-local-stack.ps1

  ==> Allocating port pair
  ! 5600/5601 in use, trying 5602/5603
  + 5602/5603 free
  ...
  API:  http://localhost:5602
  UI:   http://localhost:5603
```

The second worktree's `wwwroot/appsettings.Development.json` and `scripts/.env.local` are independent files in that worktree's working tree. Neither worktree touches the other.

### Manifest format

`scripts/.env.local`:

```
# Generated by scripts/start-local-stack.ps1 — do not commit
AHKFLOW_API_URL=http://localhost:5602
AHKFLOW_UI_URL=http://localhost:5603
AHKFLOW_API_PORT=5602
AHKFLOW_UI_PORT=5603
AHKFLOW_WORKTREE_PATH=C:\Dev\segocom-github\AHKFlowApp\.worktrees\feature\foo
```

`AHKFLOW_WORKTREE_PATH` lets `kill-dev-ports.ps1` detect stale or copied manifests. Process ownership is verified against the current repo root, so a stale manifest cannot make one worktree kill another worktree's processes.

`.env`-shell-style matches existing `scripts/.env.test` / `scripts/.env.prod`. Prefixed names avoid colliding with arbitrary `API_URL` env vars.

### Consumers

- Playwright skill / agents read `scripts/.env.local` to discover the active UI URL.
- `kill-dev-ports.ps1` reads it to know which ports to free.
- `setup-dev-entra.ps1` reads the frontend `appsettings.Development.json` (which already reflects the manifest) and preserves the base URL.

## Error handling

### Port allocation

- **Scan exhausted (no free pair in 5600–5699):** exit with a clear message naming the scanned range. User can pass explicit `-ApiPort`/`-UiPort` or free a port.
- **TOCTOU (port free at scan, taken before `dotnet run`):** not handled by the launcher. The `dotnet run` command itself fails with the standard "address in use" error. User reruns the launcher.
- **Explicit ports passed but in use:** launcher errors immediately, no fallback.
- **Same launcher run twice:** idempotent — overwrites `scripts/.env.local` and `wwwroot/appsettings.Development.json` with the same values, assuming nothing else grabbed the ports in between.

### Frontend config

- **`wwwroot/appsettings.Development.json` missing entirely:** launcher writes only the `ApiHttpClient` section and prints a message telling the user to run `setup-dev-entra.ps1` to populate `AzureAd`. The existing `AuthConfigurationValidator` enforces the boundary at app startup.
- **`wwwroot/appsettings.Development.json` present with real Entra values:** launcher reads the JSON, patches `ApiHttpClient:BaseAddress`, writes it back. No regex; preserves `AzureAd` exactly.

### Manifest

- **Stale `scripts/.env.local`:** overwritten on every launcher invocation. No staleness window.
- **Manifest references ports no longer in use (user killed processes manually):** the manifest is config, not liveness. Readers that care must probe. `kill-dev-ports.ps1` tolerates absent processes.

### Entra port-ignore failure

- **MSAL.js / Blazor WASM rejects ports not matching registered URI:** Task 5 verification gates this. If port-ignore fails for SPA, the spec ships in **reduced form** — only one worktree can run the UI at a time, but parallel APIs still work for backend-only tasks. PR description records which mode was confirmed. Port enumeration is explicitly **not** the fallback (violates Microsoft's localhost-exceptions guidance).

### CORS

- Launcher rewrites the API's gitignored `appsettings.Development.json` so `Cors.AllowedOrigins` contains `http://localhost:<uiPort>`. If a user manually undoes that config or starts a different worktree's API command, the request fails CORS — loud, debuggable.

## Testing

### Automated

- `AuthConfigurationValidatorTests.cs` — add one test proving a non-`5600` localhost base URL passes validation. Locks in port-agnostic behavior against future regressions.

No PowerShell test infrastructure is added. The launcher is verified manually per the matrix below.

### Manual verification matrix (gates the PR)

1. **Legacy single-instance.** Delete `scripts/.env.local`. Run launcher in the main worktree. Verify it lands on `5600/5601`, both processes start, `/health` returns 200, MSAL login succeeds.
2. **Two concurrent worktrees.** Keep the first stack running. In a second worktree, run launcher — verify it lands on `5602/5603`. Start both processes. Hit `/health` on both APIs from both UIs. Sanity-check: cross-worktree request from UI-A to API-B fails CORS.
3. **Entra port-ignore verification.** Highest-risk unknown. From the second worktree (`5603`), complete a full MSAL login. If the redirect succeeds with only `http://localhost/authentication/login-callback` registered, the design ships as-is. If it fails, ship the reduced design (single UI worktree at a time; document the limitation in README + auth docs) — port enumeration is not an option.
4. **Manifest discoverability.** From a fresh PowerShell session, read `scripts/.env.local` and confirm Playwright can navigate to the UI URL it names without any hardcoded port.
5. **Kill-script ownership.** With worktree A's stack running on `5600/5601`, run `kill-dev-ports.ps1` from worktree B (which thinks it owns `5600/5601` via a stale manifest). Verify the script refuses to kill A's processes and prints the foreign PID/command line.
6. **Launch-profile env passing.** Confirm the printed API command produces a running instance with `ASPNETCORE_ENVIRONMENT=Development`, Swagger reachable at `/swagger`, and Docker SQL auto-start working (where applicable). This proves the launch-profile env vars survive the `-- --urls` override.
7. **TEST/PROD Entra unchanged.** Run `scripts/setup-entra-app.ps1 -Environment test` against the dev tenant (or dry-run if available) and confirm SWA hostname registration logic at `scripts/setup-entra-app.ps1:123` still executes. `scripts/deploy.ps1` should not regress.
8. **Build + tests.** `dotnet build` and `dotnet test` on both worktrees before the PR (per CLAUDE.md).
9. **Docker Compose untouched.** Spot-check `docker compose up` still works on its single fixed port.

PR description records: which worktree, which ports, which step pass/fail, and which Entra-redirect path was confirmed.

## Unresolved questions

- None blocking. Step 3 of the verification matrix may force the Entra-redirect fallback; the spec already commits both paths.
