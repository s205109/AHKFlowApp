# 047 - Make no-auth frontend startup work in the main checkout

## Metadata

- **Epic**: Developer experience
- **Type**: Fix
- **Interfaces**: UI

## Summary

Starting the frontend for no-auth no longer produces a signed-in frontend in the main checkout. The app still boots into MSAL, so a local browser drive stops at the login screen and every Add button stays disabled.

## User story

As a developer, I want the no-auth frontend start command to sign me in as the test user, so that I can drive the local UI without an Azure AD login.

## Evidence

- Started the frontend with `--launch-profile "http (No Auth)"`: the app rendered **LOG IN** and `button.add-hotkey` was `disabled`.
- Started it again with `ASPNETCORE_ENVIRONMENT=NoAuth` set directly. The host log confirmed `Hosting environment: NoAuth`, and the app still rendered **LOG IN**.
- The cause is already written down in this repository, at `tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs:27-33`: in .NET 10 the Blazor WebAssembly boot configuration is baked into `_framework/dotnet.js` at build time. The dev server's environment does not change which `appsettings.{Environment}.json` the WebAssembly app loads, so `wwwroot/appsettings.NoAuth.json` is never read.
- `Program.cs:27` reads `Auth:UseTestProvider` from configuration, so a file that never loads leaves the flag false.

## Acceptance criteria

- [ ] The documented no-auth command signs the browser in as the test user
- [ ] `button.add-hotkey` is enabled after running the documented no-auth command
- [ ] `AGENTS.md`, `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`, `docs/development/playwright-setup.md`, and `.agents/playwright-cli/SKILL.md` describe what actually works
- [ ] The E2E fixture keeps working unchanged — it already solves this by intercepting every `appsettings*.json` request

## Out of scope

- Changing how agent worktrees get no-auth. `setup-worktree-local-dev.ps1` writes `appsettings.Development.json`, which does load, so worktrees are unaffected.
- Any change to production authentication.

## Notes / dependencies

- Two candidate fixes: write the flag into `wwwroot/appsettings.Development.json` from a script, the way the worktree setup already does; or set `WasmApplicationEnvironmentName` at build time for a no-auth build.
- Found while driving the hotkey shortcut warnings feature in the main checkout on 2026-07-29. Worked around for that session by intercepting `**/appsettings*.json` in Playwright.
