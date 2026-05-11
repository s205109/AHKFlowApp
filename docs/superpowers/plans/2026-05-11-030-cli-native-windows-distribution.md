# CLI Native Windows Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship backlog 030 by producing a Windows x64 self-contained `ahkflow` zip on GitHub Releases with production configuration and install documentation.

**Architecture:** Keep the CLI runtime unchanged. Add a packaging script that publishes and zips the existing CLI, add a release workflow that injects production configuration into publish output, and add user-facing Windows install documentation copied into the zip.

**Tech Stack:** .NET 10, PowerShell, GitHub Actions, GitHub CLI, System.Text.Json-compatible appsettings, MinVer, xUnit.

---

## File Structure

Create:

- `scripts/publish-cli.ps1` - local and CI entrypoint for Windows x64 CLI packaging.
- `.github/workflows/release-cli.yml` - GitHub Release workflow for `ahkflow-win-x64.zip`.
- `docs/cli/windows-install.md` - install, uninstall, and token cache removal instructions.

Modify:

- `.claude/backlog/030-cli-native-windows-distribution.md` - mark acceptance criteria complete after implementation.

No CLI command source changes are expected. The existing `AssemblyName` already emits `ahkflow.exe`, and the existing config pipeline already reads `appsettings.json` next to the executable.

---

## Task 1: Add Windows CLI Packaging Script

**Files:**
- Create: `scripts/publish-cli.ps1`
- Test manually: generated `.tmp/cli-package-smoke/ahkflow-win-x64.zip`

- [ ] **Step 1: Create the packaging script**

Create `scripts/publish-cli.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri]$ApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [guid]$ClientId,

    [Parameter(Mandatory = $true)]
    [guid]$TenantId,

    [string]$Configuration = 'Release',

    [string]$Runtime = 'win-x64',

    [string]$OutputDirectory = '.artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ApiBaseUrl.IsAbsoluteUri -or $ApiBaseUrl.Scheme -ne 'https') {
    throw "ApiBaseUrl must be an absolute HTTPS URL."
}

if ($ClientId -eq [guid]::Empty) {
    throw "ClientId must be a non-empty GUID."
}

if ($TenantId -eq [guid]::Empty) {
    throw "TenantId must be a non-empty GUID."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$projectPath = Join-Path $repoRoot 'src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj'
$installDocPath = Join-Path $repoRoot 'docs/cli/windows-install.md'
$stagingRoot = Join-Path $repoRoot '.tmp/cli-release'
$publishDir = Join-Path $stagingRoot 'publish'
$packageDir = Join-Path $stagingRoot 'package'
$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $repoRoot $OutputDirectory
}
$zipPath = Join-Path $resolvedOutput "ahkflow-$Runtime.zip"

if (-not (Test-Path -LiteralPath $installDocPath)) {
    throw "Install documentation was not found at $installDocPath."
}

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

dotnet publish $projectPath `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    --output $publishDir

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed."
}

$settingsPath = Join-Path $publishDir 'appsettings.json'
$settings = [ordered]@{
    ApiBaseUrl = $ApiBaseUrl.AbsoluteUri.TrimEnd('/')
    ClientId = $ClientId.ToString()
    TenantId = $TenantId.ToString()
}
$settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding utf8

Copy-Item -LiteralPath (Join-Path $publishDir 'ahkflow.exe') -Destination $packageDir
Copy-Item -LiteralPath $settingsPath -Destination $packageDir
Copy-Item -LiteralPath $installDocPath -Destination (Join-Path $packageDir 'INSTALL.md')

$requiredFiles = @('ahkflow.exe', 'appsettings.json', 'INSTALL.md')
foreach ($file in $requiredFiles) {
    $path = Join-Path $packageDir $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Package validation failed: missing $file."
    }
}

$packagedSettings = Get-Content -LiteralPath (Join-Path $packageDir 'appsettings.json') -Raw | ConvertFrom-Json
if ($packagedSettings.ApiBaseUrl -match 'placeholder-prod' -or
    $packagedSettings.ClientId -eq '00000000-0000-0000-0000-000000000000' -or
    $packagedSettings.TenantId -eq '00000000-0000-0000-0000-000000000000') {
    throw "Package validation failed: appsettings.json still contains placeholder values."
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageDir, $zipPath)

Write-Host "Created $zipPath"
```

- [ ] **Step 2: Parse-check the script**

Run:

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/publish-cli.ps1'), [ref]$null, [ref]$errors)
if ($errors) { $errors | Format-List; exit 1 }
```

Expected: no output and exit code `0`.

- [ ] **Step 3: Commit**

```powershell
git add scripts/publish-cli.ps1
git commit -m "chore(030): add CLI release packaging script"
```

---

## Task 2: Add Windows Install Documentation

**Files:**
- Create: `docs/cli/windows-install.md`

- [ ] **Step 1: Create the install doc**

Create `docs/cli/windows-install.md`:

```markdown
# Install AHKFlow CLI on Windows

## Install

1. Download `ahkflow-win-x64.zip` from the latest AHKFlowApp GitHub Release.
2. Create a stable install folder:

   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\Tools\ahkflow"
   ```

3. Extract the zip into that folder.
4. Add the folder to your user `PATH`:

   ```powershell
   $installPath = "$env:USERPROFILE\Tools\ahkflow"
   $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
   if (($currentPath -split ';') -notcontains $installPath) {
       [Environment]::SetEnvironmentVariable('Path', "$currentPath;$installPath", 'User')
   }
   ```

5. Open a new terminal and verify the install:

   ```powershell
   ahkflow --help
   ```

## Sign in and use

```powershell
ahkflow login
ahkflow hotstring list
ahkflow logout
```

`ahkflow login` uses device-code sign-in. Follow the URL and code shown in the terminal.

## Uninstall

1. Remove the install folder from your user `PATH`.
2. Delete the extracted install folder:

   ```powershell
   Remove-Item -LiteralPath "$env:USERPROFILE\Tools\ahkflow" -Recurse -Force
   ```

3. Remove the local token cache if you want to clear sign-in state:

   ```powershell
   Remove-Item -LiteralPath "$env:LOCALAPPDATA\AHKFlowApp\msal-cache.bin3" -Force -ErrorAction SilentlyContinue
   ```

If the `AHKFlowApp` local app data folder is only used for CLI auth state, you can remove the whole folder:

```powershell
Remove-Item -LiteralPath "$env:LOCALAPPDATA\AHKFlowApp" -Recurse -Force -ErrorAction SilentlyContinue
```

## Advanced overrides

The release zip includes production configuration. Normal users do not need environment variables.

For development or test environments, these variables override packaged configuration:

```powershell
$env:AHKFLOW_ApiBaseUrl = 'https://example.invalid'
$env:AHKFLOW_ClientId = '11111111-1111-1111-1111-111111111111'
$env:AHKFLOW_TenantId = '22222222-2222-2222-2222-222222222222'
```
```

- [ ] **Step 2: Commit**

```powershell
git add docs/cli/windows-install.md
git commit -m "docs(030): add Windows CLI install guide"
```

---

## Task 3: Verify Local Package Output

**Files:**
- Uses: `scripts/publish-cli.ps1`
- Uses: `docs/cli/windows-install.md`
- Produces local untracked output under `.tmp/cli-package-smoke`

- [ ] **Step 1: Run the packaging script with smoke values**

Run:

```powershell
pwsh -NoProfile -File .\scripts\publish-cli.ps1 `
  -ApiBaseUrl https://example.invalid `
  -ClientId 11111111-1111-1111-1111-111111111111 `
  -TenantId 22222222-2222-2222-2222-222222222222 `
  -OutputDirectory .tmp\cli-package-smoke
```

Expected: command succeeds and prints `Created ...ahkflow-win-x64.zip`.

- [ ] **Step 2: Verify zip contents**

Run:

```powershell
$zip = Resolve-Path '.tmp\cli-package-smoke\ahkflow-win-x64.zip'
$extract = '.tmp\cli-package-smoke\extract'
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $extract
Get-ChildItem $extract | Select-Object -ExpandProperty Name | Sort-Object
```

Expected exactly:

```text
ahkflow.exe
appsettings.json
INSTALL.md
```

- [ ] **Step 3: Verify injected config**

Run:

```powershell
Get-Content '.tmp\cli-package-smoke\extract\appsettings.json' -Raw | ConvertFrom-Json
```

Expected:

```text
ApiBaseUrl = https://example.invalid
ClientId = 11111111-1111-1111-1111-111111111111
TenantId = 22222222-2222-2222-2222-222222222222
```

- [ ] **Step 4: Verify executable help**

Run:

```powershell
.\.tmp\cli-package-smoke\extract\ahkflow.exe --help
```

Expected: exit code `0`; output includes `login`, `logout`, `hotstring`, and `download`.

---

## Task 4: Add GitHub Release Workflow

**Files:**
- Create: `.github/workflows/release-cli.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/release-cli.yml`:

```yaml
name: Release CLI

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag to package, for example v1.0.0'
        required: true
        type: string

permissions:
  contents: write

env:
  DOTNET_NOLOGO: true
  RELEASE_TAG: ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.tag || github.ref_name }}

jobs:
  package:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.tag || github.ref }}

      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --configuration Release --no-restore

      - name: Test
        run: dotnet test --configuration Release --no-build --verbosity normal

      - name: Package Windows CLI
        shell: pwsh
        env:
          API_BASE_URL: ${{ secrets.AZURE_API_BASE_URL_PROD }}
          AD_CLIENT_ID: ${{ vars.AZURE_AD_CLIENT_ID_PROD }}
          AD_TENANT_ID: ${{ vars.AZURE_AD_TENANT_ID_PROD }}
        run: |
          if ([string]::IsNullOrWhiteSpace($env:API_BASE_URL)) { throw "AZURE_API_BASE_URL_PROD is not configured." }
          if ([string]::IsNullOrWhiteSpace($env:AD_CLIENT_ID)) { throw "AZURE_AD_CLIENT_ID_PROD is not configured." }
          if ([string]::IsNullOrWhiteSpace($env:AD_TENANT_ID)) { throw "AZURE_AD_TENANT_ID_PROD is not configured." }

          .\scripts\publish-cli.ps1 `
            -ApiBaseUrl $env:API_BASE_URL `
            -ClientId $env:AD_CLIENT_ID `
            -TenantId $env:AD_TENANT_ID `
            -OutputDirectory .artifacts

      - name: Verify package
        shell: pwsh
        run: |
          $zip = Resolve-Path '.artifacts\ahkflow-win-x64.zip'
          $extract = Join-Path $env:RUNNER_TEMP 'ahkflow-cli'
          if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
          Expand-Archive -LiteralPath $zip -DestinationPath $extract

          $expected = @('ahkflow.exe', 'appsettings.json', 'INSTALL.md') | Sort-Object
          $actual = Get-ChildItem -LiteralPath $extract -File | Select-Object -ExpandProperty Name | Sort-Object
          if (($actual -join '|') -ne ($expected -join '|')) {
              throw "Unexpected zip contents: $($actual -join ', ')"
          }

          $settings = Get-Content -LiteralPath (Join-Path $extract 'appsettings.json') -Raw | ConvertFrom-Json
          if ($settings.ApiBaseUrl -match 'placeholder-prod') { throw "ApiBaseUrl was not replaced." }
          if ($settings.ClientId -eq '00000000-0000-0000-0000-000000000000') { throw "ClientId was not replaced." }
          if ($settings.TenantId -eq '00000000-0000-0000-0000-000000000000') { throw "TenantId was not replaced." }

          & (Join-Path $extract 'ahkflow.exe') --help
          if ($LASTEXITCODE -ne 0) { throw "ahkflow.exe --help failed." }

      - uses: actions/upload-artifact@v4
        with:
          name: ahkflow-win-x64
          path: .artifacts/ahkflow-win-x64.zip
          retention-days: 30

      - name: Publish GitHub Release asset
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release view $env:RELEASE_TAG 2>$null
          if ($LASTEXITCODE -ne 0) {
              gh release create $env:RELEASE_TAG `
                --title $env:RELEASE_TAG `
                --notes "AHKFlow CLI Windows x64 release." `
                .artifacts/ahkflow-win-x64.zip
              if ($LASTEXITCODE -ne 0) { throw "Failed to create GitHub Release." }
          } else {
              gh release upload $env:RELEASE_TAG .artifacts/ahkflow-win-x64.zip --clobber
              if ($LASTEXITCODE -ne 0) { throw "Failed to upload GitHub Release asset." }
          }
```

- [ ] **Step 2: Commit**

```powershell
git add .github/workflows/release-cli.yml
git commit -m "ci(030): publish Windows CLI release asset"
```

---

## Task 5: Update Backlog and Installer Follow-Up Decision

**Files:**
- Modify: `.claude/backlog/030-cli-native-windows-distribution.md`

- [ ] **Step 1: Mark acceptance criteria complete**

In `.claude/backlog/030-cli-native-windows-distribution.md`, mark each acceptance criterion as complete after Tasks 1-4 are implemented:

```markdown
- [x] CI publishes a Windows x64 self-contained `ahkflow` release artifact as a zip.
- [x] The published artifact contains an executable users can run as `ahkflow.exe`.
- [x] The published CLI includes production `ApiBaseUrl`, `ClientId`, and `TenantId` configuration so users do not need environment variables for normal use.
- [x] The zip includes minimal install instructions for adding the extracted folder to `PATH`.
- [x] `ahkflow login`, `ahkflow hotstring list`, and `ahkflow logout` work from the extracted zip against production services.
- [x] Release documentation explains the supported install path and how to uninstall or remove the local token cache.
- [x] A follow-up installer path is documented, either Winget or an MSI/MSIX installer, with the chosen direction recorded.
```

Append before `## Out of scope`:

```markdown
## Completion

**Completed:** 2026-05-11

Release channel: GitHub Releases with `ahkflow-win-x64.zip`.

Follow-up installer direction: Winget, after the zip release asset is stable.
```

- [ ] **Step 2: Commit**

```powershell
git add .claude/backlog/030-cli-native-windows-distribution.md
git commit -m "docs(030): mark CLI Windows distribution complete"
```

---

## Task 6: Full Verification

**Files:**
- Verifies all previous tasks.

- [ ] **Step 1: Format check**

Run:

```powershell
dotnet format --verify-no-changes
```

Expected: succeeds with no file changes.

- [ ] **Step 2: Build**

Run:

```powershell
dotnet build --configuration Release --no-restore
```

Expected: succeeds.

- [ ] **Step 3: Test**

Run:

```powershell
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: succeeds.

- [ ] **Step 4: Package smoke**

Run:

```powershell
pwsh -NoProfile -File .\scripts\publish-cli.ps1 `
  -ApiBaseUrl https://example.invalid `
  -ClientId 11111111-1111-1111-1111-111111111111 `
  -TenantId 22222222-2222-2222-2222-222222222222 `
  -OutputDirectory .tmp\cli-package-smoke
```

Expected: succeeds and creates `.tmp\cli-package-smoke\ahkflow-win-x64.zip`.

- [ ] **Step 5: Extracted executable smoke**

Run:

```powershell
$zip = Resolve-Path '.tmp\cli-package-smoke\ahkflow-win-x64.zip'
$extract = '.tmp\cli-package-smoke\extract-final'
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $extract
.\.tmp\cli-package-smoke\extract-final\ahkflow.exe --help
```

Expected: exit code `0`; output includes `login`, `logout`, `hotstring`, and `download`.

- [ ] **Step 6: Final Git status**

Run:

```powershell
git status --short --branch
```

Expected: clean branch `feature/030-cli-native-windows-distribution`.

---

## Manual Production Acceptance

After the release workflow publishes a real GitHub Release asset:

1. Download `ahkflow-win-x64.zip` from the GitHub Release.
2. Extract it on Windows.
3. Add the extracted folder to user `PATH`.
4. Open a new terminal.
5. Run:

```powershell
ahkflow --help
ahkflow login
ahkflow hotstring list
ahkflow logout
```

Expected:

- `ahkflow --help` succeeds.
- `login` completes device-code sign-in against production Entra configuration.
- `hotstring list` reaches production API without any `AHKFLOW_` environment variables.
- `logout` clears cached auth state.

---

## Self-Review Checklist

- Backlog criterion for a Windows x64 self-contained zip maps to Tasks 1, 3, and 4.
- Backlog criterion for `ahkflow.exe` maps to the existing project `AssemblyName` plus Tasks 1 and 3.
- Backlog criterion for production config maps to Tasks 1 and 4.
- Backlog criterion for install instructions maps to Task 2 and packaging copy in Task 1.
- Backlog criterion for login/list/logout smoke maps to Manual Production Acceptance.
- Backlog criterion for uninstall and token cache docs maps to Task 2.
- Backlog criterion for future installer direction maps to Task 5 with Winget recorded.
