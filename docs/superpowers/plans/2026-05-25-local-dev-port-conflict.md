# Local Dev Port Conflict Mitigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configure-only launcher that allocates unused localhost port pairs per worktree so multiple AHKFlowApp dev stacks (humans + AI agents) can run in parallel without colliding on 5600/5601.

**Architecture:** A single PowerShell launcher (`scripts/start-local-stack.ps1`) acquires a machine-wide lock, scans for the lowest free port pair from 5600/5601 stepping +2/+2, patches the worktree's gitignored frontend `appsettings.Development.json` and backend `appsettings.Development.json`, writes a per-worktree manifest (`scripts/.env.local`), and prints `dotnet run -- --urls ...` commands that keep the launch profile (so dev env vars and the Docker SQL connection string survive) while overriding the fixed profile ports via command-line configuration. The launcher does not start processes. Entra registers a single port-less localhost SPA redirect for dev only; test/prod registrations keep their existing redirect behavior.

**Tech Stack:** PowerShell 5.1, .NET 10 (ASP.NET Core Kestrel URL overrides via `dotnet run -- --urls`), Blazor WebAssembly (`wwwroot/appsettings.Development.json`), xUnit + FluentAssertions for the one new C# test, Microsoft Entra ID (`az ad app` + Graph PATCH).

**Spec:** `docs/superpowers/specs/2026-05-25-local-dev-port-conflict-design.md`

**Review adjustments:** This plan intentionally refines the spec's launcher command shape. Use `dotnet run -- --urls ...` instead of `ASPNETCORE_URLS` because the preserved launch profiles set fixed `applicationUrl` values, and use launcher-managed API `appsettings.Development.json` for CORS instead of array-index environment overrides so stale origins cannot survive.

---

## File map

**New:**
- `scripts/start-local-stack.ps1` — launcher

**Modified:**
- `scripts/setup-dev-entra.ps1` — preserve existing API base URL when patching frontend config
- `scripts/setup-entra-app.ps1` — dev branch registers a single port-less localhost redirect
- `scripts/kill-dev-ports.ps1` — read manifest, verify process ownership before killing
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example` — note that launcher overwrites the file
- `src/Backend/AHKFlowApp.API/appsettings.Development.json.example` — note that launcher owns local CORS origins
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor` — remove fixed-port CORS troubleshooting guidance
- `tests/AHKFlowApp.UI.Blazor.Tests/Auth/AuthConfigurationValidatorTests.cs` — add port-agnostic regression test
- `README.md`, `docs/development/configuration-strategy.md`, `docs/development/playwright-setup.md`, `docs/development/docker-setup.md`, `docs/architecture/authentication.md` — reference launcher / manifest instead of 5600/5601

**Explicitly NOT modified:**
- `src/Backend/AHKFlowApp.API/Program.cs` — `dotnet run -- --urls` override works without code changes
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/AuthConfigurationValidator.cs` — already port-agnostic (test added to lock that in)
- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`, `src/Frontend/AHKFlowApp.UI.Blazor/Properties/launchSettings.json` — preserved so VS F5 still works; launcher commands use `-- --urls` when dynamic ports are needed
- `docker-compose.yml`, `scripts/deploy.ps1` — out of scope

---

### Task 1: Lock in port-agnostic validator behavior with a regression test

**Files:**
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Auth/AuthConfigurationValidatorTests.cs`

Not strict TDD — the validator is already port-agnostic. This test pins that contract so future "helpful" hardcoding triggers a red build.

- [ ] **Step 1: Add the test**

Open `tests/AHKFlowApp.UI.Blazor.Tests/Auth/AuthConfigurationValidatorTests.cs`. After the existing `ValidateForMsal_WhenValuesArePresent_DoesNotThrow` test (currently ends at line 97), add:

```csharp
[Theory]
[InlineData("http://localhost:5600")]
[InlineData("http://localhost:5604")]
[InlineData("http://localhost:5698")]
public void ValidateForMsal_AcceptsAnyLocalhostPort_ForApiBaseAddress(string baseAddress)
{
    // Arrange
    IConfiguration configuration = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ApiHttpClient:BaseAddress"] = baseAddress,
            ["AzureAd:Authority"] = "https://login.microsoftonline.com/tenant-id",
            ["AzureAd:ClientId"] = "11111111-1111-1111-1111-111111111111",
            ["AzureAd:DefaultScope"] = "api://11111111-1111-1111-1111-111111111111/access_as_user"
        })
        .Build();

    // Act
    Action act = () => AuthConfigurationValidator.ValidateForMsal(configuration);

    // Assert
    act.Should().NotThrow();
}
```

- [ ] **Step 2: Run the test, expect pass**

```
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~ValidateForMsal_AcceptsAnyLocalhostPort_ForApiBaseAddress" --verbosity normal
```

Expected: 3 passing test cases (one per `InlineData`).

- [ ] **Step 3: Run the full test project to confirm no regressions**

```
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --verbosity normal
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```
git add tests/AHKFlowApp.UI.Blazor.Tests/Auth/AuthConfigurationValidatorTests.cs
git commit -m "test: pin AuthConfigurationValidator port-agnostic contract"
```

---

### Task 2: Neutralize the appsettings examples

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example`
- Modify: `src/Backend/AHKFlowApp.API/appsettings.Development.json.example`

- [ ] **Step 1: Replace the frontend example file**

Open `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example` and replace its contents with:

```json
{
  "_note": "Run scripts/start-local-stack.ps1 from the repo root — it overwrites ApiHttpClient.BaseAddress with the port allocated for this worktree.",
  "ApiHttpClient": {
    "BaseAddress": "http://localhost:5600"
  },
  "AzureAd": {
    "Authority": "https://login.microsoftonline.com/<your-tenant-id>",
    "ClientId": "<your-client-id>",
    "ValidateAuthority": true,
    "DefaultScope": "api://<your-client-id>/access_as_user"
  }
}
```

The `_note` key is ignored by `IConfiguration` (unknown keys are simply not bound) and serves as inline documentation. `5600` stays as the example default — it's what the first worktree's launcher run produces anyway.

- [ ] **Step 2: Replace the API example file**

Open `src/Backend/AHKFlowApp.API/appsettings.Development.json.example` and replace its contents with:

```json
{
  "_note": "Run scripts/start-local-stack.ps1 from the repo root — it overwrites Cors.AllowedOrigins with the UI port allocated for this worktree.",
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "AHKFlowApp": "Debug",
        "Microsoft.EntityFrameworkCore": "Information",
        "Microsoft.Hosting.Lifetime": "Information",
        "Microsoft": "Warning",
        "Microsoft.AspNetCore": "Warning",
        "System": "Warning"
      }
    }
  },
  "Cors": {
    "AllowedOrigins": [
      "http://localhost:5601"
    ]
  },
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "",
    "ClientId": ""
  }
}
```

The single CORS origin is only the first-worktree example. The launcher rewrites the gitignored real API `appsettings.Development.json` to exactly one origin for the selected UI port, preventing stale array entries from keeping an old worktree origin allowed.

- [ ] **Step 3: Verify both example files are valid JSON**

```powershell
powershell -NoProfile -Command "Get-Content src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example -Raw | ConvertFrom-Json | Out-Null; Get-Content src/Backend/AHKFlowApp.API/appsettings.Development.json.example -Raw | ConvertFrom-Json | Out-Null; Write-Host 'OK'"
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```
git add src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json.example src/Backend/AHKFlowApp.API/appsettings.Development.json.example
git commit -m "docs: note launcher owns local dev appsettings"
```

---

### Task 3: Add the launcher

**Files:**
- Create: `scripts/start-local-stack.ps1`

The launcher dot-sources `scripts/Common.ps1` (existing `Write-Step` / `Write-Success` / `Write-Warn` helpers). All other logic is inline — no new helper module.

- [ ] **Step 1: Create the launcher**

Create `scripts/start-local-stack.ps1` with this exact content:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Allocates a free localhost port pair, patches frontend/API dev config, writes a per-worktree manifest, and prints the dotnet run commands needed to start the API + UI for this worktree.

.DESCRIPTION
    Configure-only — does not start dotnet processes. Run it once per worktree before you `dotnet run`. The first worktree on the machine lands on 5600/5601; subsequent worktrees step +2/+2 to the next free pair.

.PARAMETER ApiPort
    Force a specific API port. If the port is in use the launcher errors out (no fallback).

.PARAMETER UiPort
    Force a specific UI port. If omitted but -ApiPort is given, UiPort defaults to ApiPort + 1.

.EXAMPLE
    .\start-local-stack.ps1

.EXAMPLE
    .\start-local-stack.ps1 -ApiPort 5610 -UiPort 5611
#>
[CmdletBinding()]
param(
    [int] $ApiPort,
    [int] $UiPort
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$FrontendSettings = Join-Path $RepoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$BackendSettings = Join-Path $RepoRoot 'src/Backend/AHKFlowApp.API/appsettings.Development.json'
$ManifestPath = Join-Path $PSScriptRoot '.env.local'
$LockPath = Join-Path $env:TEMP 'ahkflow-port-alloc.lock'

function Test-PortFree([int] $Port) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return -not $listener
}

function Find-FreePair([int] $StartApi = 5600, [int] $EndApi = 5698) {
    for ($api = $StartApi; $api -le $EndApi; $api += 2) {
        $ui = $api + 1
        if ((Test-PortFree -Port $api) -and (Test-PortFree -Port $ui)) {
            return @{ Api = $api; Ui = $ui }
        }
    }
    throw "No free port pair found in $StartApi-$($EndApi + 1)."
}

function Update-FrontendBaseAddress([string] $Path, [string] $NewBaseAddress) {
    if (Test-Path $Path) {
        $json = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $json.PSObject.Properties['ApiHttpClient']) {
            $json | Add-Member -NotePropertyName ApiHttpClient -NotePropertyValue ([pscustomobject]@{ BaseAddress = $NewBaseAddress })
        } elseif (-not $json.ApiHttpClient) {
            $json.ApiHttpClient = [pscustomobject]@{ BaseAddress = $NewBaseAddress }
        } else {
            $json.ApiHttpClient | Add-Member -NotePropertyName BaseAddress -NotePropertyValue $NewBaseAddress -Force
        }
    } else {
        Write-Warn "Frontend appsettings.Development.json not found — writing ApiHttpClient only."
        Write-Warn "Run scripts/setup-dev-entra.ps1 to populate the AzureAd section before starting the UI."
        $json = [pscustomobject]@{
            ApiHttpClient = [pscustomobject]@{ BaseAddress = $NewBaseAddress }
        }
    }
    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Update-BackendCorsAllowedOrigin([string] $Path, [string] $AllowedOrigin) {
    if (Test-Path $Path) {
        $json = Get-Content $Path -Raw | ConvertFrom-Json
    } else {
        Write-Warn "Backend appsettings.Development.json not found — writing Cors only."
        $json = [pscustomobject]@{}
    }

    if (-not $json.PSObject.Properties['Cors']) {
        $json | Add-Member -NotePropertyName Cors -NotePropertyValue ([pscustomobject]@{})
    } elseif (-not $json.Cors) {
        $json.Cors = [pscustomobject]@{}
    }

    $json.Cors | Add-Member -NotePropertyName AllowedOrigins -NotePropertyValue @($AllowedOrigin) -Force
    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Write-Manifest([string] $Path, [int] $ApiPort, [int] $UiPort, [string] $WorktreePath) {
    $content = @(
        "# Generated by scripts/start-local-stack.ps1 - do not commit",
        "AHKFLOW_API_URL=http://localhost:$ApiPort",
        "AHKFLOW_UI_URL=http://localhost:$UiPort",
        "AHKFLOW_API_PORT=$ApiPort",
        "AHKFLOW_UI_PORT=$UiPort",
        "AHKFLOW_WORKTREE_PATH=$WorktreePath"
    ) -join "`r`n"
    Set-Content -Path $Path -Value $content -Encoding UTF8
}

# Acquire machine-wide allocation lock. FileMode.CreateNew fails atomically if the file already exists.
$lockHandle = $null
$attempt = 0
while ($attempt -lt 50) {
    try {
        $lockHandle = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        break
    } catch {
        $attempt++
        Start-Sleep -Milliseconds 100
    }
}
if (-not $lockHandle) {
    throw "Could not acquire allocation lock at $LockPath after 5 seconds. If no other launcher is running, delete the file manually."
}

try {
    Write-Step 'Allocating port pair'

    if ($ApiPort) {
        if (-not $UiPort) { $UiPort = $ApiPort + 1 }
        if (-not (Test-PortFree -Port $ApiPort)) { throw "Requested API port $ApiPort is in use." }
        if (-not (Test-PortFree -Port $UiPort)) { throw "Requested UI port $UiPort is in use." }
        Write-Success "$ApiPort/$UiPort free (explicit)"
        $pair = @{ Api = $ApiPort; Ui = $UiPort }
    } else {
        $pair = Find-FreePair
        Write-Success "$($pair.Api)/$($pair.Ui) free"
    }

    Write-Step 'Configuring frontend'
    Update-FrontendBaseAddress -Path $FrontendSettings -NewBaseAddress "http://localhost:$($pair.Api)"
    Write-Success $FrontendSettings

    Write-Step 'Configuring API CORS'
    Update-BackendCorsAllowedOrigin -Path $BackendSettings -AllowedOrigin "http://localhost:$($pair.Ui)"
    Write-Success $BackendSettings

    Write-Step 'Writing manifest'
    Write-Manifest -Path $ManifestPath -ApiPort $pair.Api -UiPort $pair.Ui -WorktreePath $RepoRoot
    Write-Success $ManifestPath
} finally {
    if ($lockHandle) {
        $lockHandle.Close()
        $lockHandle.Dispose()
        Remove-Item $LockPath -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Run these in two terminals:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  dotnet run --project src/Backend/AHKFlowApp.API --launch-profile `"Docker SQL (Recommended)`" -- --urls `"http://localhost:$($pair.Api)`""
Write-Host ""
Write-Host "  dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor --launch-profile `"http`" -- --urls `"http://localhost:$($pair.Ui)`""
Write-Host ""
Write-Host "API:  http://localhost:$($pair.Api)" -ForegroundColor Green
Write-Host "UI:   http://localhost:$($pair.Ui)" -ForegroundColor Green
```

- [ ] **Step 2: Smoke-test the launcher (no processes running)**

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1
```

Expected output (assuming 5600/5601 are free):
```
==> Allocating port pair
  + 5600/5601 free
==> Configuring frontend
  + ...wwwroot/appsettings.Development.json
==> Configuring API CORS
  + ...AHKFlowApp.API/appsettings.Development.json
==> Writing manifest
  + ...scripts/.env.local

Run these in two terminals:
  dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)" -- --urls "http://localhost:5600"
  ...
API:  http://localhost:5600
UI:   http://localhost:5601
```

Then verify the side effects:
```
powershell -NoProfile -Command "Get-Content scripts/.env.local"
powershell -NoProfile -Command "Get-Content src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json | ConvertFrom-Json | Select-Object -ExpandProperty ApiHttpClient"
powershell -NoProfile -Command "Get-Content src/Backend/AHKFlowApp.API/appsettings.Development.json | ConvertFrom-Json | Select-Object -ExpandProperty Cors | Select-Object -ExpandProperty AllowedOrigins"
```

Expected: manifest contains `AHKFLOW_API_URL=http://localhost:5600`; frontend JSON shows `BaseAddress = http://localhost:5600`; backend JSON prints exactly `http://localhost:5601`.

- [ ] **Step 3: Smoke-test conflict avoidance**

Manually occupy 5600 in another terminal:
```
powershell -NoProfile -Command '$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 5600); $l.Start(); Read-Host "Press Enter to release"'
```

Re-run the launcher in the original terminal:
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1
```

Expected: launcher reports `5602/5603 free`. Stop the placeholder listener.

- [ ] **Step 4: Smoke-test explicit port + collision error**

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1 -ApiPort 5610 -UiPort 5611
```

Expected: prints `5610/5611 free (explicit)`.

Start the placeholder listener again on 5600:
```
powershell -NoProfile -Command '$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 5600); $l.Start(); Read-Host "Press Enter to release"'
```

Then in the original terminal:
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1 -ApiPort 5600
```

Expected: errors out with `Requested API port 5600 is in use.`

- [ ] **Step 5: Commit**

```
git add scripts/start-local-stack.ps1
git commit -m "feat: add start-local-stack.ps1 worktree launcher"
```

---

### Task 4: Stop hardcoding 5600 in setup-dev-entra.ps1

**Files:**
- Modify: `scripts/setup-dev-entra.ps1`

- [ ] **Step 1: Replace the JSON-writing block**

Open `scripts/setup-dev-entra.ps1`. Replace lines 40-52 (the block from `# Frontend: appsettings.Development.json (gitignored)` through `Write-Host "  Frontend appsettings.Development.json written"`) with:

```powershell
# Frontend: appsettings.Development.json (gitignored)
# Preserve any existing ApiHttpClient:BaseAddress (set by start-local-stack.ps1).
$feSettings = Join-Path $RepoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$existingBaseAddress = 'http://localhost:5600'
if (Test-Path $feSettings) {
    $existing = Get-Content $feSettings -Raw | ConvertFrom-Json
    if ($existing.ApiHttpClient -and $existing.ApiHttpClient.BaseAddress) {
        $existingBaseAddress = $existing.ApiHttpClient.BaseAddress
    }
}

$json = [ordered]@{
    ApiHttpClient = [ordered]@{ BaseAddress = $existingBaseAddress }
    AzureAd = [ordered]@{
        Authority         = "https://login.microsoftonline.com/$($entra.TenantId)"
        ClientId          = $entra.ClientId
        ValidateAuthority = $true
        DefaultScope      = $entra.DefaultScope
    }
}
$json | ConvertTo-Json -Depth 5 | Set-Content -Path $feSettings -Encoding UTF8
Write-Host "  Frontend appsettings.Development.json written (ApiHttpClient.BaseAddress = $existingBaseAddress)"
```

- [ ] **Step 2: Smoke-test preservation (no live Entra call needed for the JSON path)**

Create a stub frontend config with a non-5600 base, then verify `setup-dev-entra.ps1` would preserve it. Easiest check is to dry-run the script's JSON logic in isolation:

```
powershell -NoProfile -Command @"
  `$feSettings = 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
  `$existing = Get-Content `$feSettings -Raw | ConvertFrom-Json
  Write-Host (`$existing.ApiHttpClient.BaseAddress)
"@
```

Expected: prints whatever the launcher last wrote (e.g., `http://localhost:5604` if you ran the launcher in a busy worktree). Confirms the read-path the script will use.

(Re-running the full `setup-dev-entra.ps1` against live Entra is not needed for this task — the change is mechanical and verified by inspection.)

- [ ] **Step 3: Commit**

```
git add scripts/setup-dev-entra.ps1
git commit -m "fix: preserve existing ApiHttpClient.BaseAddress in setup-dev-entra"
```

---

### Task 5: Dev-only port-less Entra redirect

**Files:**
- Modify: `scripts/setup-entra-app.ps1`

Change only the dev redirect behavior. Test/prod keep their existing fixed local troubleshooting redirect, and the SWA append logic stays unchanged so `deploy.ps1` does not regress.

- [ ] **Step 1: Patch the redirect-URI block**

Open `scripts/setup-entra-app.ps1`. Replace lines 122-126 (the block starting with `# Build redirect URI lists` through the second `if` that adds the https localhost URI) with:

```powershell
# ---------------------------------------------------------------------------
# Build redirect URI lists
# ---------------------------------------------------------------------------
if ($Environment -eq 'dev') {
    # Register one port-less localhost redirect and rely on Entra's
    # localhost port-ignoring (https://learn.microsoft.com/entra/identity-platform/reply-url#localhost-exceptions).
    # Microsoft warns against enumerating multiple localhost URIs that differ only by port,
    # so per-worktree port-specific entries are deliberately avoided.
    $redirectUris = @('http://localhost/authentication/login-callback')
} else {
    # Preserve existing test/prod behavior: a fixed local troubleshooting redirect plus
    # the SWA hostname appended below when available.
    $redirectUris = @('http://localhost:5601/authentication/login-callback')
}
```

Lines 127-129 (the `if ($SwaHostname)` block that appends the SWA hostname) remain unchanged — they still run for test/prod.

- [ ] **Step 2: Update the dev "Next steps" instructions (lines ~283-290)**

Replace the dev branch of the final `if ($Environment -eq 'dev') { ... } else { ... }` block (currently around lines 283-290) with:

```powershell
if ($Environment -eq 'dev') {
    Write-Host "Run from the repo root:"
    Write-Host "  dotnet user-secrets set 'AzureAd:TenantId' '$tenantId' --project src/Backend/AHKFlowApp.API"
    Write-Host "  dotnet user-secrets set 'AzureAd:ClientId' '$appId' --project src/Backend/AHKFlowApp.API"
    Write-Host "Then run scripts/start-local-stack.ps1 to allocate ports and patch frontend config."
    Write-Host "If you need to populate AzureAd settings manually:"
    Write-Host "  Authority    = https://login.microsoftonline.com/$tenantId"
    Write-Host "  ClientId     = $appId"
    Write-Host "  DefaultScope = $defaultScope"
}
```

- [ ] **Step 3: Static parse check**

```
powershell -NoProfile -Command "& { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/setup-entra-app.ps1'),[ref]$null,[ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host \"  $_\" }; exit 1 } else { Write-Host 'OK' } }"
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```
git add scripts/setup-entra-app.ps1
git commit -m "fix: dev-only port-less localhost SPA redirect in entra setup"
```

---

### Task 6: Ownership-checked kill-dev-ports.ps1

**Files:**
- Modify: `scripts/kill-dev-ports.ps1`

- [ ] **Step 1: Replace the entire file**

Overwrite `scripts/kill-dev-ports.ps1` with:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Frees ports used by this worktree's AHKFlowApp dev stack.

.DESCRIPTION
    If scripts/.env.local exists (written by start-local-stack.ps1), kills processes on the manifest's ports — but only if the owning process's command line references this worktree's path. Otherwise falls back to 5600/5601 with the same ownership check.
    Refuses to kill processes whose command line does not reference this worktree.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ManifestPath = Join-Path $PSScriptRoot '.env.local'

function Read-ManifestValue([string] $Path, [string] $Key) {
    foreach ($line in Get-Content $Path) {
        if ($line -match "^$Key=(.*)$") { return $Matches[1].Trim() }
    }
    return $null
}

$ports = @()
$worktreePath = $RepoRoot
if (Test-Path $ManifestPath) {
    $apiPort = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_API_PORT'
    $uiPort = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_UI_PORT'
    $manifestWorktree = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_WORKTREE_PATH'
    if ($apiPort) { $ports += [int]$apiPort }
    if ($uiPort) { $ports += [int]$uiPort }
    if ($manifestWorktree) { $worktreePath = $manifestWorktree }
    Write-Host "Using manifest ports: $($ports -join ', ') (worktree: $worktreePath)"
} else {
    $ports = @(5600, 5601)
    Write-Host "No manifest found — falling back to fixed ports 5600, 5601 (worktree: $worktreePath)"
}

foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        $procId = $conn.OwningProcess
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $proc) { continue }

        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
        $commandLine = if ($cim) { $cim.CommandLine } else { '' }

        if ($commandLine -and $commandLine.IndexOf($worktreePath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "Killing $($proc.Name) (PID $procId) on port $port"
            Stop-Process -Id $procId -Force
        } else {
            Write-Warning "Refusing to kill PID $procId on port $port — command line does not reference $worktreePath."
            Write-Warning "  Command: $commandLine"
        }
    }
}

Write-Host "Done."
```

- [ ] **Step 2: Static parse check**

```
powershell -NoProfile -Command "& { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/kill-dev-ports.ps1'),[ref]$null,[ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host \"  $_\" }; exit 1 } else { Write-Host 'OK' } }"
```

Expected: `OK`.

- [ ] **Step 3: Smoke-test the refuse-foreign path**

In one terminal, occupy port 5600 with a non-ahkflow process:
```
powershell -NoProfile -Command '$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 5600); $l.Start(); Read-Host "Press Enter to release"'
```

In another terminal, delete any manifest then run the kill script:
```
powershell -NoProfile -Command "Remove-Item scripts/.env.local -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\kill-dev-ports.ps1
```

Expected: prints a `WARNING: Refusing to kill PID …` line for the listener. The listener is still running (verify by checking that the Read-Host prompt is still active).

Release the listener (press Enter in its terminal).

- [ ] **Step 4: Commit**

```
git add scripts/kill-dev-ports.ps1
git commit -m "feat: kill-dev-ports verifies process ownership via worktree path"
```

---

### Task 7: Update docs to reference the launcher

**Files:**
- Modify: `README.md`
- Modify: `docs/development/configuration-strategy.md`
- Modify: `docs/development/playwright-setup.md`
- Modify: `docs/development/docker-setup.md`
- Modify: `docs/architecture/authentication.md`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor`

- [ ] **Step 1: README — replace the "run the dev stack" instructions**

In `README.md`, locate the section that documents running the API + UI locally (look for `dotnet run --project src/Backend/AHKFlowApp.API` or `localhost:5600`). Replace the run-instructions block with:

```markdown
### Local dev stack

```powershell
# From the repo root, in any worktree:
.\scripts\start-local-stack.ps1
```

The launcher allocates a free localhost port pair (starting at 5600/5601, stepping +2/+2 for each additional concurrent worktree), patches the frontend API base URL and backend CORS origin in gitignored `appsettings.Development.json` files, and prints the two `dotnet run` commands to paste into separate terminals. Active URLs are also written to `scripts/.env.local`.

To free the ports later:

```powershell
.\scripts\kill-dev-ports.ps1
```
```

Leave the EF migration / `dotnet ef` instructions intact.

- [ ] **Step 2: playwright-setup.md — replace the Ports table**

In `docs/development/playwright-setup.md`, replace the `## Ports` section (currently lines 34-40) with:

```markdown
## URLs

Each worktree's active URLs live in `scripts/.env.local` (written by `start-local-stack.ps1`):

```powershell
# Read the active UI URL into a variable
$ui = (Get-Content scripts\.env.local | Select-String '^AHKFLOW_UI_URL=' | ForEach-Object { ($_ -split '=', 2)[1] })
```

When prompting Playwright to navigate, reference the manifest instead of hardcoding `5601`. Example: *"Open the URL from `AHKFLOW_UI_URL` in `scripts/.env.local`."*
```

Also update the example prompt block (around line 31) — replace `localhost:7601` with `the URL in scripts/.env.local`.

- [ ] **Step 3: configuration-strategy.md — add launcher section**

Open `docs/development/configuration-strategy.md`. After the section describing `appsettings.Development.json`, add a new subsection:

```markdown
### Local port allocation

`scripts/start-local-stack.ps1` is the recommended way to start the dev stack. It scans for a free port pair (5600/5601, then 5602/5603, …), patches the frontend `wwwroot/appsettings.Development.json` so `ApiHttpClient.BaseAddress` matches, patches the API `appsettings.Development.json` so `Cors.AllowedOrigins` contains only the selected UI origin, and writes the active URLs to `scripts/.env.local`.

`scripts/.env.local` is gitignored (matches the existing `scripts/.env.*` pattern). It is per-worktree — each worktree maintains its own copy.

Visual Studio's F5 still works against the fixed-port launch profiles for ad-hoc single-instance debugging.
```

- [ ] **Step 4: docker-setup.md — add a note**

At the top of `docs/development/docker-setup.md`, add this paragraph after the first heading:

```markdown
> For non-Docker local dev (the common path), use `scripts/start-local-stack.ps1` instead. Docker Compose is a separate workflow that runs on its own fixed ports and does not coordinate with the launcher.
```

- [ ] **Step 5: authentication.md — document the Entra redirect change**

In `docs/architecture/authentication.md`, find the section describing the Entra app registration's redirect URIs. Add:

```markdown
### Dev redirect URI

For the dev app registration, `setup-entra-app.ps1` registers a single SPA redirect: `http://localhost/authentication/login-callback` (no port). Entra ignores the port for localhost redirects ([Microsoft Learn](https://learn.microsoft.com/entra/identity-platform/reply-url#localhost-exceptions)), so a UI running on any port reachable from `localhost` is accepted. This is what makes the per-worktree dynamic port allocation work without re-registering URIs.

Test and prod registrations are unchanged — they keep the existing fixed local troubleshooting redirect and register the SWA hostname via `setup-entra-app.ps1` as before.
```

- [ ] **Step 6: Health.razor — remove fixed-port CORS advice**

In `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor`, replace the second bullet in the "Possible causes" list:

```razor
<li>CORS is misconfigured — copy <code>appsettings.Development.json.example</code> to <code>appsettings.Development.json</code> in the API project and ensure <code>http://localhost:5601</code> is in <code>Cors:AllowedOrigins</code>.</li>
```

with:

```razor
<li>CORS is misconfigured — run <code>scripts/start-local-stack.ps1</code> from the repo root to refresh the API's local <code>Cors:AllowedOrigins</code> setting for this worktree.</li>
```

- [ ] **Step 7: Commit**

```
git add README.md docs/development/configuration-strategy.md docs/development/playwright-setup.md docs/development/docker-setup.md docs/architecture/authentication.md src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor
git commit -m "docs: point local dev docs at start-local-stack launcher"
```

---

### Task 8: End-to-end verification matrix

No code changes. This task runs the spec's manual verification matrix and records the results in the PR description.

**Prerequisites:**
- Two worktrees of this repo on the same machine (e.g., main + `.worktrees/feature/foo`).
- Both have run `dotnet build --configuration Release` successfully.
- Both have frontend `wwwroot/appsettings.Development.json` populated (run `scripts/setup-dev-entra.ps1` once per worktree if needed).
- Both have run `scripts/start-local-stack.ps1` after any manual edits to API/frontend local config so frontend `ApiHttpClient.BaseAddress` and API `Cors.AllowedOrigins` match the allocated ports.
- `setup-entra-app.ps1 -Environment dev` has been re-run since Task 5 so the Entra app has the new port-less redirect.

- [ ] **Step 1: Legacy single-instance path (worktree A)**

```
powershell -NoProfile -Command "Remove-Item scripts/.env.local -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1
```

Expected: lands on 5600/5601. Paste the printed commands into two terminals. Then:

```
powershell -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:5600/health' -UseBasicParsing).StatusCode"
```

Expected: `200`. Open `http://localhost:5601` in a browser and complete an MSAL login. Expected: login succeeds.

- [ ] **Step 2: Two concurrent worktrees**

Keep worktree A's stack running. In worktree B (`cd .worktrees/feature/foo` or your second tree), run:

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-local-stack.ps1
```

Expected: lands on 5602/5603. Paste the commands into two more terminals.

```
powershell -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:5602/health' -UseBasicParsing).StatusCode"
```

Expected: `200`. Open both UIs in different browser tabs. CORS sanity check — from the browser dev console on worktree A's UI (`http://localhost:5601`), run:

```javascript
fetch('http://localhost:5602/health').then(r => console.log(r.status)).catch(e => console.log('blocked', e))
```

Expected: blocked by CORS (worktree B's API only allows `http://localhost:5603`).

- [ ] **Step 3: Entra port-ignore verification (highest risk)**

From worktree B's UI (`http://localhost:5603`), complete a full MSAL login flow. **This is the gate.**

- **If login succeeds**: the design ships as written. Note "Entra port-ignore confirmed working for SPA on port 5603" in the PR description.
- **If login fails with redirect-URI mismatch**: stop and execute the reduced design — revert worktree B's UI (kill it), document in README + authentication.md that only one worktree can run the UI concurrently while multiple APIs can run, and update the PR description to record the reduced mode. Do not attempt port enumeration.

- [ ] **Step 4: Manifest discoverability**

From a fresh PowerShell session in worktree B:
```
powershell -NoProfile -Command "Get-Content scripts/.env.local"
```

Expected: prints the 5602/5603 URLs and the worktree path. Then use the Playwright skill (or just `Invoke-WebRequest`) to hit the UI URL read from the manifest — confirm no port was hardcoded anywhere in the consumer.

- [ ] **Step 5: Kill-script ownership**

Keep worktree A's stack on 5600/5601 running. In worktree B, write a stale manifest by hand that claims worktree B owns 5600/5601:

```powershell
$pwd = (Get-Location).Path
$manifest = @"
AHKFLOW_API_URL=http://localhost:5600
AHKFLOW_UI_URL=http://localhost:5601
AHKFLOW_API_PORT=5600
AHKFLOW_UI_PORT=5601
AHKFLOW_WORKTREE_PATH=$pwd
"@
Set-Content -Path scripts\.env.local -Value $manifest -Encoding UTF8

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\kill-dev-ports.ps1
```

Expected: prints `WARNING: Refusing to kill PID … — command line does not reference <worktree-B-path>`. Worktree A's stack still responds to `/health`. Restore worktree B's real manifest by re-running `start-local-stack.ps1`.

- [ ] **Step 6: Launch-profile env passing**

In worktree A, hit:
```
powershell -NoProfile -Command "(Invoke-WebRequest -Uri 'http://localhost:5600/swagger' -UseBasicParsing).StatusCode"
```

Expected: `200`. (Swagger is only served when `ASPNETCORE_ENVIRONMENT=Development`, which the launch profile sets. Confirms launch-profile env vars survived the `-- --urls` override.)

- [ ] **Step 7: TEST/PROD Entra unchanged**

Dry-run inspection (do not actually invoke `az ad app update` against the test tenant unless you're set up for it):
```
powershell -NoProfile -Command "Select-String -Path scripts/setup-entra-app.ps1 -Pattern 'SwaHostname'"
```

Expected: the `if ($SwaHostname)` block and the `Resolve-SWA-hostname` block are still present and untouched. Eyeball lines around the original 117-128 region — confirm dev uses `http://localhost/authentication/login-callback`, while test/prod still initialize `http://localhost:5601/authentication/login-callback` before appending the SWA hostname.

- [ ] **Step 8: Build + tests**

In both worktrees:
```
dotnet build --configuration Release
dotnet test --configuration Release --no-build
```

Expected: green on both.

- [ ] **Step 9: Docker Compose spot-check**

Stop the local `dotnet run` terminals for worktree A and worktree B first. Then, from each worktree, run the kill script so the fixed Docker Compose ports are clear:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\kill-dev-ports.ps1
```

After both local stacks are stopped, run the compose spot-check from one worktree:

```
docker compose up --build -d
powershell -NoProfile -Command "Start-Sleep -Seconds 30; (Invoke-WebRequest -Uri 'http://localhost:5600/health' -UseBasicParsing).StatusCode"
docker compose down
```

Expected: `200` from the compose-managed API on its fixed port.

- [ ] **Step 10: Open the PR**

Use `gh pr create`. Body must include a verification summary:

```
## Verification

- [x] Single-instance (worktree A, 5600/5601, /health 200, MSAL login OK)
- [x] Two concurrent worktrees (B on 5602/5603, CORS cross-worktree blocked)
- [x] Entra port-ignore confirmed working on SPA port 5603   <-- OR "REDUCED MODE: single-UI"
- [x] Manifest read by Playwright without hardcoded port
- [x] Kill-script refused to terminate foreign process on stale manifest
- [x] Swagger reachable on 5600/swagger (launch-profile env preserved)
- [x] setup-entra-app.ps1 test/prod redirects inspected, fixed localhost + SWA behavior unchanged
- [x] dotnet build + dotnet test green in both worktrees
- [x] docker compose up still serves /health on its fixed port
```

---

## Out of scope (do not implement)

- Docker Compose multi-instance support
- HTTPS localhost dynamic-port workflow
- Reverse-proxy UI host for multiplexed `/api`
- Pester or any new PowerShell test framework
- Changes to `src/Backend/AHKFlowApp.API/Program.cs` or `Auth/AuthConfigurationValidator.cs`
- Changes to `docker-compose.yml` or `scripts/deploy.ps1`
