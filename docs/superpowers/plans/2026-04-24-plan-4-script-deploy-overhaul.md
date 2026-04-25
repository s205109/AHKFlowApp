# Plan 4 — Script + deploy.ps1 Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate all scripts into `/scripts/`, make every script Windows PowerShell 5.1-compatible, harden `deploy.ps1` with a preflight block and `-SkipPrereqCheck`, and auto-trigger the full deployment sequence (API → health probe → frontend) at the end of provisioning.

**Architecture:** Four independent changes committed separately: file consolidation, PS 5.1 sweep, `deploy.ps1` preflight additions, and `deploy.ps1` Phase 9 post-provision trigger. No production C# code changes. Scripts run against Azure/GitHub — cannot be unit-tested in CI — so each task validates by syntax-parsing the modified script under Windows PowerShell 5.1 (`powershell.exe`).

**Tech Stack:** Windows PowerShell 5.1, PowerShell 7, Azure CLI (`az`), GitHub CLI (`gh`), Bicep.

**Branch:** `feature/plan-4-script-deploy-overhaul` (create fresh from `main`).

**Audit reference:** `docs/superpowers/audits/2026-04-21-baseline-audit.md` — Plan 4 section has no security findings. Note: `scripts/.env.<env>` files written by `deploy.ps1` are gitignored and contain resource names/URLs; scripts must read from those files, not hardcode resource names.

---

## Phase structure of deploy.ps1 (locked in for this plan)

`deploy.ps1` already has eight phases. This plan keeps them and adds one:

| Phase | What |
|---|---|
| 1 | Prerequisites ← **enhanced** (Bicep, jq warn, dotnet 10, PS version, `-SkipPrereqCheck`) |
| 2 | Gather configuration |
| 3 | Provision Azure Resources (Bicep) |
| 4 | Entra & OIDC configuration |
| 5 | SQL user setup |
| 6 | GitHub Secrets & Variables |
| 7 | App Service configuration |
| 8 | Save config + summary |
| 9 | **NEW** — Trigger initial deployment sequence: `deploy-api.yml` → health probe → `deploy-frontend.yml` |

---

## File Structure

**Moved files:**
- `docs/scripts/create-github-issues.ps1` → `scripts/create-github-issues.ps1` (via `git mv`)

**Modified files:**
- `scripts/deploy.ps1` — add `#Requires -Version 5.1`; extend Phase 1 with Bicep/dotnet-version/PS-version checks and `-SkipPrereqCheck`; add Phase 9
- `scripts/setup-entra-app.ps1` — `#Requires -Version 7` → `#Requires -Version 5.1`
- `scripts/setup-dev-entra.ps1` — `#Requires -Version 7` → `#Requires -Version 5.1`
- `scripts/run-coverage.ps1` — `#Requires -Version 7.0` → `#Requires -Version 5.1`
- `scripts/update.ps1` — add `#Requires -Version 5.1` (currently has no `#Requires`)
- `scripts/teardown.ps1` — add `#Requires -Version 5.1` (currently has no `#Requires`)
- `.claude/backlog/001-create-backlog-in-github.md` — update `docs/scripts/` reference to `scripts/`
- `docs/development/github-setup.md` — update link and path reference

**Not modified:**
- `scripts/kill-dev-ports.ps1` — already `#Requires -Version 5.1`
- `scripts/setup-copilot-symlinks.ps1` — already `#Requires -Version 5.1`
- `scripts/check-coverage-thresholds.py` — Python, not PowerShell

---

## Task 1: Move `create-github-issues.ps1` and update references

**Files:**
- Move: `docs/scripts/create-github-issues.ps1` → `scripts/create-github-issues.ps1`
- Modify: `.claude/backlog/001-create-backlog-in-github.md`
- Modify: `docs/development/github-setup.md`

- [ ] **Step 1.1: Move the file with git**

Run from the repo root:
```bash
git mv docs/scripts/create-github-issues.ps1 scripts/create-github-issues.ps1
```

Expected: no error. The `docs/scripts/` directory becomes empty.

- [ ] **Step 1.2: Verify the file is in the right place**

Run:
```bash
ls scripts/create-github-issues.ps1
```

Expected: file is present.

- [ ] **Step 1.3: Update `.claude/backlog/001-create-backlog-in-github.md`**

Read the file and find line 30:
```
- Use `docs/scripts/create-github-issues.ps1` to batch-create issues from backlog files via `gh` CLI.
```

Replace with:
```
- Use `scripts/create-github-issues.ps1` to batch-create issues from backlog files via `gh` CLI.
```

- [ ] **Step 1.4: Update `docs/development/github-setup.md`**

Read the file. Find line 146:
```markdown
See [`docs/scripts/create-github-issues.ps1`](../scripts/create-github-issues.ps1) — reads backlog files...
```

Replace with:
```markdown
See [`scripts/create-github-issues.ps1`](../../scripts/create-github-issues.ps1) — reads backlog files...
```

(The path `../../scripts/` navigates from `docs/development/` up two levels to repo root then into `scripts/`.)

- [ ] **Step 1.5: Confirm no remaining references to `docs/scripts/`**

Run:
```bash
grep -r "docs/scripts" . --include="*.md" --include="*.ps1" --include="*.json" --include="*.yml" | grep -v ".worktrees" | grep -v "docs/superpowers"
```

Expected: no matches (the superpowers specs/plans/audits may mention the old path in historical records — those are fine to keep).

- [ ] **Step 1.6: Commit**

```bash
git add scripts/create-github-issues.ps1 .claude/backlog/001-create-backlog-in-github.md docs/development/github-setup.md
git commit -m "chore: consolidate docs/scripts into scripts/ (plan 4)"
```

---

## Task 2: PowerShell 5.1 compatibility sweep

**Files:**
- Modify: `scripts/setup-entra-app.ps1` (line 1)
- Modify: `scripts/setup-dev-entra.ps1` (line 1)
- Modify: `scripts/run-coverage.ps1` (line 1)
- Modify: `scripts/update.ps1` (add line 1)
- Modify: `scripts/teardown.ps1` (add line 1)

**Context:** The spec bans null-coalescing (`??`), ternary (`? :`), and pipeline chain operators (`&&`, `||`) — all PS7-only. Grep confirmed none are present. The only PS7-specific things are three `#Requires -Version 7` directives and two scripts with no requirement at all.

- [ ] **Step 2.1: Scan for any PS7 syntax patterns (verification step)**

Run:
```bash
grep -n "#Requires" scripts/*.ps1
```

Expected output (current state):
```
scripts/kill-dev-ports.ps1:1:#Requires -Version 5.1
scripts/run-coverage.ps1:1:#Requires -Version 7.0
scripts/setup-copilot-symlinks.ps1:1:#Requires -Version 5.1
scripts/setup-dev-entra.ps1:1:#Requires -Version 7
scripts/setup-entra-app.ps1:1:#Requires -Version 7
```

(`deploy.ps1`, `update.ps1`, `teardown.ps1` have no `#Requires` — they'll get one added.)

Also scan for PS7-specific syntax:
```bash
grep -n "?\?[^?]" scripts/*.ps1  # null-coalescing ??
grep -n "&&" scripts/*.ps1        # pipeline chain
grep -rn " \? " scripts/*.ps1     # ternary (rough)
```

Expected: no matches. If any match is found, stop and report it before continuing.

- [ ] **Step 2.2: Fix `scripts/setup-entra-app.ps1`**

Read `scripts/setup-entra-app.ps1`. Line 1 is:
```powershell
#Requires -Version 7
```

Replace with:
```powershell
#Requires -Version 5.1
```

- [ ] **Step 2.3: Fix `scripts/setup-dev-entra.ps1`**

Read `scripts/setup-dev-entra.ps1`. Line 1 is:
```powershell
#Requires -Version 7
```

Replace with:
```powershell
#Requires -Version 5.1
```

- [ ] **Step 2.4: Fix `scripts/run-coverage.ps1`**

Read `scripts/run-coverage.ps1`. Line 1 is:
```powershell
#Requires -Version 7.0
```

Replace with:
```powershell
#Requires -Version 5.1
```

- [ ] **Step 2.5: Add `#Requires` to `scripts/update.ps1`**

Read `scripts/update.ps1`. Line 1 is the `<#` start of the doc comment block. Insert a new first line **before** the `<#`:

The new first two lines of the file should be:
```powershell
#Requires -Version 5.1
<#
```

- [ ] **Step 2.6: Add `#Requires` to `scripts/teardown.ps1`**

Same approach as Step 2.5 for `scripts/teardown.ps1`. Insert `#Requires -Version 5.1` as the new first line, before the `<#` doc comment.

- [ ] **Step 2.7: Syntax-parse every changed script under PowerShell 5.1**

Run in a PowerShell 5.1 session (`powershell.exe`, not `pwsh`):
```powershell
$scripts = @(
    'scripts\setup-entra-app.ps1',
    'scripts\setup-dev-entra.ps1',
    'scripts\run-coverage.ps1',
    'scripts\update.ps1',
    'scripts\teardown.ps1'
)
foreach ($s in $scripts) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $s),
        [ref]$null,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host "PARSE ERRORS in $s" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "OK: $s" -ForegroundColor Green
    }
}
```

Expected: all five lines show `OK: scripts\...`. If any show parse errors, fix before committing.

From bash (Claude Code runs bash):
```bash
powershell.exe -NonInteractive -NoProfile -Command "
\$scripts = @('scripts\\setup-entra-app.ps1','scripts\\setup-dev-entra.ps1','scripts\\run-coverage.ps1','scripts\\update.ps1','scripts\\teardown.ps1')
foreach (\$s in \$scripts) {
    \$errors = \$null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path \$s),[ref]\$null,[ref]\$errors) | Out-Null
    if (\$errors.Count -gt 0) { Write-Host \"FAIL: \$s\" -ForegroundColor Red; \$errors | ForEach-Object { Write-Host \"  \$_\" } }
    else { Write-Host \"OK: \$s\" -ForegroundColor Green }
}
"
```

Expected: all OK.

- [ ] **Step 2.8: Verify all #Requires are now 5.1**

```bash
grep -n "#Requires" scripts/*.ps1
```

Expected: every line shows `5.1`, and `deploy.ps1`, `update.ps1`, `teardown.ps1`, `setup-entra-app.ps1`, `setup-dev-entra.ps1`, `run-coverage.ps1` are all covered.

- [ ] **Step 2.9: Commit**

```bash
git add scripts/setup-entra-app.ps1 scripts/setup-dev-entra.ps1 scripts/run-coverage.ps1 scripts/update.ps1 scripts/teardown.ps1
git commit -m "chore: PS 5.1 compatibility sweep — fix #Requires directives (plan 4)"
```

---

## Task 3: `deploy.ps1` Phase 1 — preflight enhancements

**Files:**
- Modify: `scripts/deploy.ps1`

**Context:** The current Phase 1 checks that `az`, `gh`, and `dotnet` commands exist, verifies Azure login, and verifies GitHub CLI auth. It does not check Bicep, the .NET SDK major version, PowerShell version, or support skipping. The script currently has no `#Requires` directive.

**Proposed Phase 1 additions:**
- New param: `[switch]$SkipPrereqCheck`
- New `#Requires -Version 5.1` header (first line)
- Bicep: `az bicep version` — fail if not present (Bicep is required for Phase 3)
- jq: warn-only (`Write-Warn`) if not found — not used by any current script but useful for debugging
- .NET SDK: parse `dotnet --version`, require major version 10
- PowerShell version: require `$PSVersionTable.PSVersion.Major -ge 5`

- [ ] **Step 3.1: Read the current deploy.ps1 param block and Phase 1**

Read `scripts/deploy.ps1` lines 1-142 to understand the exact current param block and Phase 1 structure before making changes.

- [ ] **Step 3.2: Add `#Requires -Version 5.1` and `-SkipPrereqCheck` to deploy.ps1**

The file currently starts with `<#`. Insert `#Requires -Version 5.1` as the new first line, then leave the existing `<#` doc comment. Modify the `param` block (currently ends around line 25) to add the new switch parameter:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions an AHKFlowApp Azure environment and configures CI/CD.

.DESCRIPTION
    Single entrypoint that provisions all Azure resources via Bicep, configures
    Entra ID, OIDC federation, SQL access, and GitHub secrets/variables.

    Run this once per environment (test or prod). It is idempotent — safe to re-run.

.PARAMETER Environment
    Target environment: 'test' or 'prod'. Prompts interactively if not provided.

.PARAMETER SkipPrereqCheck
    Skip Phase 1 prerequisite checks. Use when you know your environment is correct
    and want to skip the checks to save time on re-runs.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Environment test
    .\deploy.ps1 -Environment test -SkipPrereqCheck
#>
[CmdletBinding()]
param(
    [ValidateSet('test', 'prod')]
    [string]$Environment,

    [ValidateRange(1, 240)]
    [int]$MaxWaitMinutes = 45,

    [switch]$SkipPrereqCheck
)
```

- [ ] **Step 3.3: Replace the Phase 1 block**

Find the current Phase 1 section. It starts with:
```powershell
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  AHKFlowApp — Azure Provisioning Script" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Step "Phase 1: Checking prerequisites..."
```

Replace the entire Phase 1 section (everything from the banner through the `$hasSqlcmd` block, ending just before `# Phase 2`) with:

```powershell
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  AHKFlowApp — Azure Provisioning Script" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Phase 1: Prerequisites
# ---------------------------------------------------------------------------

if ($SkipPrereqCheck) {
    Write-Host "`n  Skipping prerequisite checks (-SkipPrereqCheck)" -ForegroundColor Yellow
} else {
    Write-Step "Phase 1: Checking prerequisites..."

    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Fail "PowerShell 5.1 or later required (found $($PSVersionTable.PSVersion))."
        Write-Host "    Install from: https://aka.ms/powershell" -ForegroundColor Yellow
        throw "Insufficient PowerShell version"
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    # .NET 10 SDK
    $dotnetVersion = dotnet --version 2>&1
    if ($LASTEXITCODE -ne 0 -or $dotnetVersion -notmatch '^10\.') {
        Write-Fail ".NET 10 SDK required (found: $dotnetVersion)."
        Write-Host "    Install from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        throw "Missing or incorrect .NET SDK version"
    }
    Write-Success ".NET SDK $dotnetVersion"

    Confirm-Command 'az'  'https://learn.microsoft.com/cli/azure/install-azure-cli'
    Confirm-Command 'gh'  'https://cli.github.com/'

    # Bicep (installed as az extension)
    $bicepOut = az bicep version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Bicep CLI not found. Run: az bicep install"
        throw "Missing prerequisite: Bicep"
    }
    Write-Success "Bicep: $($bicepOut -join ' ')"

    # jq — optional, warn only (not required by this script; useful for debugging)
    if (-not (Get-Command 'jq' -ErrorAction SilentlyContinue)) {
        Write-Warn "jq not found — not required by this script, but useful for JSON debugging."
        Write-Warn "Install: https://jqlang.github.io/jq/download/"
    } else {
        Write-Success "jq found"
    }

    # Verify az login
    try {
        $account = Invoke-Az-Json account show
        Write-Success "Logged into Azure as $($account.user.name) (subscription: $($account.name))"
    } catch {
        Write-Fail "Not logged into Azure. Run: az login"
        throw
    }

    # Verify gh auth
    $ghStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "GitHub CLI not authenticated. Run: gh auth login"
        throw "GitHub CLI not authenticated"
    }
    Write-Success "GitHub CLI authenticated"

    # Verify sqlcmd (optional — we fall back to portal instructions)
    $hasSqlcmd = [bool](Get-Command 'sqlcmd' -ErrorAction SilentlyContinue)
    if ($hasSqlcmd) {
        Write-Success "sqlcmd found (will use for SQL user creation)"
    } else {
        Write-Warn "sqlcmd not found — SQL user creation step will print manual instructions"
        Write-Warn "Install: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility"
    }
}

# When -SkipPrereqCheck is used, $account and $hasSqlcmd must still be populated
# (they're used in Phase 2 and 5). Populate them here.
if ($SkipPrereqCheck) {
    $account = Invoke-Az-Json account show
    $hasSqlcmd = [bool](Get-Command 'sqlcmd' -ErrorAction SilentlyContinue)
}
```

**IMPORTANT:** The helper functions (`Write-Step`, `Write-Success`, `Write-Warn`, `Write-Fail`, `Confirm-Command`, `Invoke-Az`, `Invoke-Az-Json`, `Try-Az`, `Try-Az-Json`) are defined between the param block and the Phase 1 section. They must remain in place — do not move or remove them. Only the Phase 1 section itself changes.

- [ ] **Step 3.4: Syntax-parse the modified deploy.ps1**

```bash
powershell.exe -NonInteractive -NoProfile -Command "
\$errors = \$null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path 'scripts\deploy.ps1'),
    [ref]\$null,
    [ref]\$errors
) | Out-Null
if (\$errors.Count -gt 0) {
    Write-Host 'PARSE ERRORS:' -ForegroundColor Red
    \$errors | ForEach-Object { Write-Host \"  \$_\" }
    exit 1
} else {
    Write-Host 'OK: scripts\deploy.ps1' -ForegroundColor Green
}
"
```

Expected: `OK: scripts\deploy.ps1`

- [ ] **Step 3.5: Spot-check `-SkipPrereqCheck` help output**

```bash
powershell.exe -NonInteractive -NoProfile -Command "Get-Help scripts\deploy.ps1 -Parameter SkipPrereqCheck"
```

Expected: help text showing `SkipPrereqCheck` parameter description.

- [ ] **Step 3.6: Commit**

```bash
git add scripts/deploy.ps1
git commit -m "feat: deploy.ps1 Phase 1 — add Bicep/dotnet-version/PS-version checks, -SkipPrereqCheck (plan 4)"
```

---

## Task 4: `deploy.ps1` Phase 9 — post-provision deployment trigger

**Files:**
- Modify: `scripts/deploy.ps1`

**Context:** After Phase 8 (save config + summary), the script currently prints "Next steps: Push to main." The spec requires it to instead automatically trigger the full deployment sequence: `deploy-api.yml` (which builds image, migrates DB, deploys API) → health probe passes → `deploy-frontend.yml`. The sequence is sequential: frontend deploy only starts after the API is healthy.

**Key workflow inputs:**
- `deploy-api.yml` input: `environment` (choice: `test` | `prod`)
- `deploy-frontend.yml` input: `environment` (choice: `test` | `prod`)

**GitHub CLI commands used:**
- `gh workflow run <workflow> --field environment=<env> --repo <org/repo>` — triggers the run
- `gh run list --workflow <workflow> --repo <org/repo> --limit 1 --json databaseId` — gets the new run ID
- `gh run watch <runId> --repo <org/repo>` — waits synchronously until run completes (pass/fail)

- [ ] **Step 4.1: Find the end of Phase 8 in deploy.ps1**

Read `scripts/deploy.ps1` from line 640 onwards. Phase 8 ends with the `Write-Host` blocks that print the summary. The last `Write-Host ""` around line 693 is the end of the current file.

- [ ] **Step 4.2: Replace the Phase 8 "Next steps" block and append Phase 9**

Find the Phase 8 "Save config + Summary" section starting around line 638. The current final block:
```powershell
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Push to 'main' to trigger GitHub Actions deploy"
Write-Host "  2. The first push will build and push the container image to GHCR."
Write-Host ""
Write-Host "  IMPORTANT: GHCR packages are private by default." -ForegroundColor Yellow
Write-Host "  After the first deploy-api.yml run, make the container image public:"
Write-Host "  https://github.com/$($GitHubOrgRepo.Split('/')[0])?tab=packages"
Write-Host "  Find 'ahkflowapp-api' -> Package settings -> Change visibility -> Public"
Write-Host "  Then re-run the failed deploy job."
Write-Host ""
Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""
```

Replace that block with:
```powershell
Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""

# ---------------------------------------------------------------------------
# Phase 9: Trigger initial deployment sequence
# ---------------------------------------------------------------------------

Write-Step "Phase 9: Triggering initial deployment sequence..."
Write-Host "  Order: API deploy (build + migrate + deploy) -> health probe -> frontend deploy" -ForegroundColor DarkGray

# Step 9a — Trigger deploy-api.yml
Write-Host ""
Write-Host "  Triggering deploy-api.yml for '$Environment'..."
gh workflow run deploy-api.yml --field environment=$Environment --repo $GitHubOrgRepo
if ($LASTEXITCODE -ne 0) { throw "Failed to trigger deploy-api.yml" }
Write-Success "deploy-api.yml triggered"

# Wait for GitHub to register the run (race window: gh run list may return the previous run)
Write-Host "  Waiting 15s for the run to register in GitHub..."
Start-Sleep -Seconds 15

# Resolve run ID
$runListJson = gh run list --workflow deploy-api.yml --repo $GitHubOrgRepo --limit 1 --json databaseId 2>&1
$runId = ($runListJson | ConvertFrom-Json)[0].databaseId
if (-not $runId) { throw "Could not resolve run ID for deploy-api.yml. Check: gh run list --workflow deploy-api.yml --repo $GitHubOrgRepo" }
Write-Host "  Watching run #$runId — this typically takes 8-15 minutes..."

gh run watch $runId --exit-status --repo $GitHubOrgRepo
if ($LASTEXITCODE -ne 0) { throw "deploy-api.yml run #$runId failed. Check: gh run view $runId --repo $GitHubOrgRepo" }
Write-Success "API deployment complete (run #$runId)"

Write-Host ""
Write-Host "  IMPORTANT: GHCR packages are private by default." -ForegroundColor Yellow
Write-Host "  If the run above failed on the push step, make the package public and re-run:" -ForegroundColor Yellow
Write-Host "  https://github.com/$($GitHubOrgRepo.Split('/')[0])?tab=packages" -ForegroundColor Yellow
Write-Host "  Find 'ahkflowapp-api' -> Package settings -> Change visibility -> Public" -ForegroundColor Yellow
Write-Host ""

# Step 9b — Poll health endpoint
$healthUrl = "https://$AppServiceHostname/health"
Write-Host "  Polling health endpoint: $healthUrl (up to 3 minutes)..."
$healthOk = $false
for ($i = 0; $i -lt 18; $i++) {
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEap
        if ($resp -and $resp.StatusCode -eq 200) {
            $healthOk = $true
            break
        }
    } catch {
        $ErrorActionPreference = $prevEap
    }
    Write-Host "  . [$($i * 10)s] not yet healthy..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
}
if (-not $healthOk) {
    Write-Warn "Health check at $healthUrl did not return 200 within 3 minutes."
    Write-Warn "The App Service may still be starting. Check manually before using the frontend."
    Write-Warn "Once healthy, trigger the frontend manually: gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo"
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host "  Provisioning complete — MANUAL STEP REQUIRED" -ForegroundColor Yellow
    Write-Host "  Trigger frontend deploy once API is healthy:" -ForegroundColor Yellow
    Write-Host "  gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    exit 0
}
Write-Success "API health check passed"

# Step 9c — Trigger deploy-frontend.yml
Write-Host ""
Write-Host "  Triggering deploy-frontend.yml for '$Environment'..."
gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo
if ($LASTEXITCODE -ne 0) { throw "Failed to trigger deploy-frontend.yml" }
Write-Success "deploy-frontend.yml triggered (running asynchronously)"
Write-Host "    Monitor: gh run list --workflow deploy-frontend.yml --repo $GitHubOrgRepo" -ForegroundColor DarkGray

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  AHKFlowApp ($Environment) — Provisioning + Deploy DONE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  API health  : https://$AppServiceHostname/health"
Write-Host "  Frontend    : https://$SwaHostname"
Write-Host "  Resources   : $ResourceGroup"
Write-Host ""
Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""
```

**Note:** The existing Phase 8 summary block (`AHKFlowApp ($Environment) -- Provisioning Complete!`) should be **removed** — Phase 9's final block replaces it. The Phase 8 section should end just before the "Next steps" header (keep the `Write-Success "Config saved..."` line and the Phase 8 header block only).

- [ ] **Step 4.3: Syntax-parse the modified deploy.ps1**

```bash
powershell.exe -NonInteractive -NoProfile -Command "
\$errors = \$null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path 'scripts\deploy.ps1'),
    [ref]\$null,
    [ref]\$errors
) | Out-Null
if (\$errors.Count -gt 0) {
    Write-Host 'PARSE ERRORS:' -ForegroundColor Red
    \$errors | ForEach-Object { Write-Host \"  \$_\" }
    exit 1
} else {
    Write-Host 'OK: scripts\deploy.ps1' -ForegroundColor Green
}
"
```

Expected: `OK: scripts\deploy.ps1`

- [ ] **Step 4.4: Verify Phase 9 is present and Phase 8 summary is cleaned up**

```bash
grep -n "Phase 9\|Phase 8\|Next steps\|Provisioning Complete\|Provisioning + Deploy" scripts/deploy.ps1
```

Expected:
- One line: `Phase 8: Saving configuration...`
- One line: `Phase 9: Triggering initial deployment sequence...`
- One line: `Provisioning + Deploy DONE!`
- No line: `Provisioning Complete!`
- No line: `Next steps:`

- [ ] **Step 4.5: Commit**

```bash
git add scripts/deploy.ps1
git commit -m "feat: deploy.ps1 Phase 9 — auto-trigger API deploy, health probe, frontend deploy (plan 4)"
```

---

## Task 5: Full regression + PR

**Files:** None modified (regression only).

- [ ] **Step 5.1: Parse all modified scripts under PowerShell 5.1**

```bash
powershell.exe -NonInteractive -NoProfile -Command "
\$scripts = Get-ChildItem scripts\*.ps1 | Select-Object -ExpandProperty FullName
\$allOk = \$true
foreach (\$s in \$scripts) {
    \$errors = \$null
    [System.Management.Automation.Language.Parser]::ParseFile(\$s,[ref]\$null,[ref]\$errors) | Out-Null
    if (\$errors.Count -gt 0) {
        Write-Host \"FAIL: \$s\" -ForegroundColor Red
        \$errors | ForEach-Object { Write-Host \"  \$_\" }
        \$allOk = \$false
    } else {
        Write-Host \"OK: \$s\" -ForegroundColor Green
    }
}
if (-not \$allOk) { exit 1 }
"
```

Expected: all `OK:` lines, exit 0.

- [ ] **Step 5.2: Confirm no remaining `docs/scripts/` references in operative files**

```bash
grep -r "docs/scripts" . --include="*.md" --include="*.ps1" --include="*.json" --include="*.yml" | grep -v ".worktrees" | grep -v "docs/superpowers"
```

Expected: no matches.

- [ ] **Step 5.3: Confirm all scripts have `#Requires -Version 5.1`**

```bash
grep -n "#Requires" scripts/*.ps1
```

Expected: every `.ps1` shows `5.1`.

- [ ] **Step 5.4: Run the .NET build and test suite (no changes to C# code, just regression)**

```bash
dotnet build --configuration Release -q 2>&1 | tail -5
dotnet test --configuration Release --no-build -q 2>&1 | tail -10
```

Expected: build succeeds, all tests pass.

- [ ] **Step 5.5: Format check**

```bash
dotnet format --verify-no-changes 2>&1 | tail -5
```

Expected: no changes (PowerShell files are not touched by `dotnet format`).

- [ ] **Step 5.6: Push and open PR**

```bash
git push -u origin feature/plan-4-script-deploy-overhaul
gh pr create --title "chore: script consolidation + PS 5.1 sweep + deploy.ps1 preflight & Phase 9 (plan 4)" --body "$(cat <<'EOF'
## Summary

Plan 4 of the codebase simplification roadmap. No C# production code changes.

- **Consolidate scripts:** `docs/scripts/create-github-issues.ps1` moved to `scripts/` (single folder). References updated in backlog 001 and `docs/development/github-setup.md`.
- **PS 5.1 sweep:** All `#Requires -Version 7` / `#Requires -Version 7.0` directives changed to `5.1`. `update.ps1` and `teardown.ps1` get their first `#Requires -Version 5.1`. No PS7-specific syntax (`??`, ternary, `&&`) was present in any script.
- **deploy.ps1 Phase 1 hardened:** Adds PowerShell version check, .NET 10 SDK version check, Bicep check (fail), jq check (warn-only). Adds `-SkipPrereqCheck` switch. `$account` and `$hasSqlcmd` still populated under skip mode so later phases work correctly.
- **deploy.ps1 Phase 9 (new):** After provisioning, automatically triggers `deploy-api.yml` (build → migrate DB → deploy API), polls health endpoint (up to 3 min, 10s interval), then triggers `deploy-frontend.yml`. If health poll times out, prints a manual instruction and exits 0 rather than failing the whole provisioning run.

## Test plan
- [x] `powershell.exe` syntax-parse: all scripts in `scripts/*.ps1` — all OK
- [x] `grep "#Requires" scripts/*.ps1` — all show 5.1
- [x] `grep -r "docs/scripts" .` — no operative matches
- [x] `dotnet build --configuration Release` — passes
- [x] `dotnet test --configuration Release --no-build` — all tests pass
- [x] `dotnet format --verify-no-changes` — no changes

Closes plan 4 of the codebase simplification roadmap.
EOF
)"
```

Expected: PR URL output. CI (build-test, bicep-lint, coverage) should pass — no C# changes.

---

## Self-review

**Spec coverage:**

| Requirement | Task |
|---|---|
| Consolidate `docs/scripts/*` → `/scripts/` | Task 1 |
| PS 5.1 sweep — no null-coalescing, ternary, PS7-only syntax | Task 2 |
| `deploy.ps1` preflight: .NET 10 SDK, Azure CLI, Bicep, jq, GitHub CLI, PowerShell version | Task 3 |
| `-SkipPrereqCheck` | Task 3 |
| Phase-separated structure confirmed | Documented in plan header table |
| Auto-trigger `deploy-frontend.yml` on success | Task 4 |
| Ordering: DB migrate → API deploy → health probe → frontend | Task 4 (deploy-api.yml includes migration; health probe before frontend) |

**Placeholder scan:** No TBDs, TODOs, "similar to Task N", or "implement later". Every code block is complete.

**Type/name consistency:**
- `$SkipPrereqCheck` used consistently in param block (Task 3.2) and the conditional block (Task 3.3).
- `$GitHubOrgRepo`, `$Environment`, `$AppServiceHostname`, `$SwaHostname` are all set in Phase 2 and referenced in Phase 9 — valid.
- `Invoke-Az-Json` helper is defined before Phase 1 — available in the `$SkipPrereqCheck` fallback block.

---

## Unresolved questions

None.
