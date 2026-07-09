# Local No-Auth Mode — Design

## Problem

Agent worktrees showed "You are not signed in." with a disabled Add button. Root cause: the
no-auth toggle `Auth:UseTestProvider` lives in gitignored `appsettings.Development.json` files that
worktrees don't inherit. The setup script copied the **frontend** dev config from the main checkout
(real Azure AD IDs, no `Auth` key) and had **no backend equivalent**, so a worktree backend ran real
MSAL JWT validation → 401s.

## Goals

- Agent worktrees get no-auth mode automatically (full CRUD via Playwright, no login).
- Main checkout keeps MSAL by default, with an explicit human opt-in.
- Tests keep both paths working.

## Mechanics

- Key `Auth:UseTestProvider=true` → frontend `TestAuthenticationProvider` (always authenticated) +
  API clients `useAuth:false`; backend `TestAuthenticationHandler`. Backend guard throws if the key
  is true outside `Development`, so all no-auth profiles stay in `Development`.
- Frontend config is fetched by the browser from `wwwroot/appsettings*.json`; env vars can't reach
  WASM. The `Development` cache-bust overlay (`Program.cs`) is correctly skipped under a custom
  environment such as `NoAuth`.

## Design

1. **`setup-worktree-local-dev.ps1`** deterministically **writes** both dev configs (stops copying
   from the main checkout): frontend `{ Auth.UseTestProvider=true, ApiHttpClient.BaseAddress=<worktree
   API port> }` and backend `{ Auth.UseTestProvider=true }`. One script writes both, so they can't
   disagree, and no real Azure AD IDs ever land in a worktree. Both files are gitignored.
2. **Human opt-in (main checkout):** committed `wwwroot/appsettings.NoAuth.json`; frontend launch
   profile `http (No Auth)` (`ASPNETCORE_ENVIRONMENT=NoAuth`); backend launch profile
   `Docker SQL (No Auth)` (clone of the recommended profile + `Auth__UseTestProvider=true`, still
   `ASPNETCORE_ENVIRONMENT=Development`). The default (first) profiles are unchanged → plain
   `dotnet run` stays MSAL.
3. **Worktree SQL isolation for all Docker SQL profiles:** the setup script patches compose project,
   SQL port, and connection string on every launch profile marked `AHKFLOW_START_DOCKER_SQL=true`
   (not just the recommended one), so running `Docker SQL (No Auth)` inside a worktree can't hit
   the main checkout's SQL container on 1433.
4. **Protection:**
   - E2E `LocalAuthModeFlowTests` — app boots as "Test User", Log out disabled, create-hotstring works.
   - Pester `WorktreeLocalDevSetup.Tests.ps1` — runs the setup script against a temp worktree fixture;
     asserts both dev configs exist, both have `Auth.UseTestProvider=true`, frontend `BaseAddress`
     matches the allocated API port, both Docker SQL launch profiles get the worktree SQL port/compose
     project, and no `AzureAd` section leaks in. Registered in `ci.yml`.

## Decisions

- Worktrees default to no-auth with no opt-out switch (escape hatch: hand-edit the generated configs).
- E2E alone wouldn't have caught the original bug (its SpaHost forces test auth regardless), hence the
  Pester assertions on the script are the primary regression guard.
