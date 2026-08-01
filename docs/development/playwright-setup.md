# Playwright CLI Setup

Used for browser automation, UI health checks, and interactive debugging via Claude Code's `playwright-cli` skill.

## Installation

```bash
# Install the Playwright CLI globally
npm install -g @playwright/cli

# Install the Chromium browser
npx playwright install chromium

# Install the Claude Code skill (makes playwright-cli available in Claude sessions)
playwright-cli install --skills
```

## Usage with Claude Code

Once installed, Claude Code can drive the browser during a session. Common uses in this project:

- **Health checks** — navigate to `/health` and verify API + database status
- **Headed mode** — run with a visible browser so you can watch what Claude is doing
- **Screenshots** — capture UI state for debugging or documentation

### Example prompts

```
"Open the health page in headed mode so I can see it"
"Take a screenshot of the home page"
"Read this worktree's launchSettings.json for the frontend port, then check the UI loads"
```

## Ports

These are the **main checkout** ports only:

| Service | URL |
|---------|-----|
| Blazor UI | http://localhost:5601 |
| API | http://localhost:5600 |

**In an agent worktree these are the wrong ports.** Each worktree gets its own offset pair (e.g. API 5602 / frontend 5603) so it can run alongside the main checkout — read the worktree's own `launchSettings.json` rather than assuming. Driving 5601 from a worktree hits the main checkout or a dead port, and the failure looks like a broken app rather than a wrong URL.

Worktrees also run no-auth automatically (`Auth:UseTestProvider=true`, always signed in as "Test User"), so a browser drive gets full CRUD with no login.

**In the main checkout, start the frontend signed in as the test user with:**

```powershell
pwsh .\scripts\run-frontend.ps1 -NoAuth
```

This builds with `WasmApplicationEnvironmentName=NoAuth`, so `wwwroot/appsettings.NoAuth.json` loads
and the app skips MSAL. Run the script with no switch for the normal MSAL path.

## Notes

- The browser opens headless by default. Add `--headed` to see the browser window.
- The Blazor app reads `ApiHttpClient:BaseAddress` directly from `appsettings.json` (single URL, no probing). If the API is not running, health checks will fail with `ERR_CONNECTION_REFUSED`.
- Ensure the API is running before navigating to `/health`: `dotnet run --project src/Backend/AHKFlowApp.API`
