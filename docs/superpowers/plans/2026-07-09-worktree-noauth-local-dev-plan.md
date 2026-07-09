# Local No-Auth Mode: Default for Agent Worktrees + Launch Profile + Tests

## Context

Running `dotnet run` in this worktree shows "You are not signed in." and a disabled Add button. The branch code is innocent — the diff touches only hotstring feature files. The real cause: the no-auth toggle `Auth:UseTestProvider` lives in gitignored `appsettings.Development.json` files that worktrees don't inherit. `scripts/setup-worktree-local-dev.ps1` copies the **frontend** dev config from the main checkout (with real Azure AD IDs, no `Auth` key) but has **no backend equivalent**, so a worktree backend always runs real MSAL JWT validation while the frontend either has no signed-in user or (after hand-editing) sends no bearer tokens → 401s.

Goal: AI agents in worktrees get no-auth mode automatically (full CRUD via Playwright, no login); regular users in the main checkout keep MSAL by default with an explicit opt-in profile; tests keep both working.

Design decisions (grilled & confirmed):
- Worktrees default to no-auth, no opt-out switch (escape hatch: hand-edit generated configs).
- Script **writes** deterministic minimal configs for both tiers — stops copying MSAL values from main checkout.
- Human opt-in via new committed `NoAuth` frontend environment + backend launch profile env var.
- Protection: E2E smoke test + Pester assertions on the setup script (E2E alone wouldn't have caught this bug).

## Key mechanics (verified)

- Frontend `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs:24` — `Auth:UseTestProvider` → `TestAuthenticationProvider` (always authenticated) + all API clients `useAuth:false`; config comes from `wwwroot/appsettings.json` + `appsettings.{Environment}.json` fetched by the browser (env vars can't reach WASM).
- Backend `src/Backend/AHKFlowApp.API/Program.cs:114–135` — same key → `TestAuthenticationHandler`; guard throws if `true` outside `Development` (keep profiles in Development).
- Existing committed patterns to mirror: `wwwroot/appsettings.Local.json`, `appsettings.E2E.json` (both `UseTestProvider: true`).
- E2E fixtures `tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs` + `ApiFactory.cs` already boot the full stack in test-auth mode.
- Pester tests live in `tests/Worktree*.Tests.ps1`, run in `.github/workflows/ci.yml`.
- Worktree creation auto-runs `scripts/new-worktree.ps1` → `setup-worktree-local-dev.ps1` via the `WorktreeCreate` hook — so the script change makes no-auth fully automatic for agents.

## Changes

### 1. `scripts/setup-worktree-local-dev.ps1` — write both dev configs
- Replace `Write-FrontendWorktreeDevelopmentConfig` (copies main's file, lines ~524–552) with a deterministic write of `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json`:
  `{ "Auth": { "UseTestProvider": true }, "ApiHttpClient": { "BaseAddress": "http://localhost:<worktreeApiPort>" } }`
- Add `Write-BackendWorktreeDevelopmentConfig` writing `src/Backend/AHKFlowApp.API/appsettings.Development.json` with `{ "Auth": { "UseTestProvider": true } }` (CORS/connection string stay in the existing `Write-BackendWorktreeAppSettings` patching).
- No real Azure AD IDs ever land in worktrees; both tiers written by one script so they can't disagree.

### 2. Launch profiles for the main checkout (human opt-in)
- **Frontend:** commit `wwwroot/appsettings.NoAuth.json` — `{ "Auth": { "UseTestProvider": true }, "ApiHttpClient": { "BaseAddress": "http://localhost:5600" } }`. Add profile `"http (No Auth)"` to `src/Frontend/AHKFlowApp.UI.Blazor/Properties/launchSettings.json` with `ASPNETCORE_ENVIRONMENT=NoAuth` (WASM then loads that file; the Development cache-bust overlay at Program.cs:18 is correctly skipped).
- **Backend:** add profile `"Docker SQL (No Auth)"` to `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` — clone of "Docker SQL (Recommended)" plus `Auth__UseTestProvider=true`; stays `ASPNETCORE_ENVIRONMENT=Development` so the outside-Development guard and dev CORS keep working. Keep it **after** the existing first profile so plain `dotnet run` defaults stay unchanged (MSAL for humans).

### 3. E2E smoke test — `tests/AHKFlowApp.E2E.Tests/LocalAuthModeFlowTests.cs`
Reuse `SpaHost`/`ApiFactory` fixtures (pattern: `HotkeysMobileFlowTests.cs`):
1. Assert top bar shows "Test User" and Log out is disabled (local-install-mode signature, `Shared/LoginDisplay.razor`).
2. Hotstrings page: Add button enabled → create a hotstring → appears in the grid.

### 4. Pester test — `tests/WorktreeLocalDevSetup.Tests.ps1` (or extend an existing Worktree test file if a better fit)
- After running the setup script against a temp worktree fixture: both `appsettings.Development.json` files exist, both have `Auth.UseTestProvider = true`, frontend `BaseAddress` matches the allocated API port.
- Register the file in the `ci.yml` Pester step alongside the existing three.

### 5. Docs
- `AGENTS.md`: short note — worktrees run no-auth (test provider) by default; main checkout uses MSAL; "No Auth" launch profiles for opt-in.
- `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` Local Setup section: mention the no-auth path (currently only documents the MSAL copy-example flow).
- `scripts/README.md`: document the new backend config writer.
- Spec doc per user prefs: `docs/superpowers/specs/2026-07-09-local-noauth-mode-design.md` (this design, condensed).

### 6. Unbreak this worktree immediately
Run the updated `setup-worktree-local-dev.ps1` (or write the two dev config files directly) so `dotnet run` works here today with ports from `scripts/.env.worktree` (API 5606 / UI 5607).

## Verification

1. `dotnet build` + `dotnet test` (includes new E2E test; E2E uses Testcontainers SQL).
2. Run the new Pester test locally: `pwsh -NoProfile -File tests/WorktreeLocalDevSetup.Tests.ps1` (Invoke-Pester).
3. End-to-end in this worktree: `dotnet run` API + UI, then `playwright-cli` skill — verify signed in as "Test User", add a hotstring without login, no 401s in network log.
4. Main checkout sanity: plain `dotnet run` still boots the MSAL branch (no behavior change); `dotnet run --launch-profile "http (No Auth)"` + backend "Docker SQL (No Auth)" gives full no-login CRUD.

## Resolved

- Branch: implement in a **new worktree + branch** (e.g. `fix/worktree-noauth-local-dev`) — separate concern from `feature/hotstrings-datetime-kind`. Still write the gitignored dev configs into THIS worktree for immediate relief (step 6; gitignored, doesn't dirty the branch).
- E2E test stays focused — no sibling-page "not signed in" assertions.
