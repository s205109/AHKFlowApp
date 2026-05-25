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
"Check if the UI is loading correctly at the URL in scripts/.env.local"
```

## URLs

Each worktree's active URLs live in `scripts/.env.local` (written by `start-local-stack.ps1`):

```powershell
# Read the active UI URL into a variable
$ui = (Get-Content scripts\.env.local | Select-String '^AHKFLOW_UI_URL=' | ForEach-Object { ($_ -split '=', 2)[1] })
```

When prompting Playwright to navigate, reference the manifest instead of hardcoding `5601`. Example: *"Open the URL from `AHKFLOW_UI_URL` in `scripts/.env.local`."*

## Notes

- The browser opens headless by default. Add `--headed` to see the browser window.
- The Blazor app reads `ApiHttpClient:BaseAddress` directly from `appsettings.json` (single URL, no probing). If the API is not running, health checks will fail with `ERR_CONNECTION_REFUSED`.
- Ensure the API is running before navigating to `/health`: run `scripts/start-local-stack.ps1`, then start the API with the printed command.
