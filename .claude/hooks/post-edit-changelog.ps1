# Post-edit hook: keep the generated changelog asset in sync with CHANGELOG.md
# Runs generate-changelog-json.ps1 after Claude edits CHANGELOG.md, so
# src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/changelog.json never drifts (CI
# blocks on staleness via generate-changelog-json.ps1 -Check).
#
# Usage:
#   Called automatically by Claude Code PostToolUse hook after Edit/Write.
#   Accepts file path via:
#     1. First argument ($args[0])
#     2. CLAUDE_EDITED_FILE env var
#     3. PostToolUse stdin JSON ({"tool_input":{"file_path":"..."}})

$ErrorActionPreference = 'Stop'

# --- Log file setup ---
$logDir  = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "post-edit-changelog.log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log($message, [switch]$Err) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Err) { [Console]::Error.WriteLine($message) } else { Write-Host $message }
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

$file = if ($args.Count -gt 0) { $args[0] } else { $env:CLAUDE_EDITED_FILE }

# Fallback: parse file_path from PostToolUse stdin JSON
if (-not $file) {
    $stdin = $input | Out-String
    if ($stdin) {
        if ($stdin -match '"file_path"\s*:\s*"([^"]+)"') {
            $file = $Matches[1]
        }
    }
}

if (-not $file) { Write-Log "No file path provided, skipping."; exit 0 }

# Only react to the repo-root CHANGELOG.md (not nested files that happen to share the name)
$file = [System.IO.Path]::GetFullPath($file)
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$changelogPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "CHANGELOG.md"))

if ($file -ne $changelogPath) { Write-Log "Not CHANGELOG.md ($file), skipping."; exit 0 }

$generatorScript = Join-Path $repoRoot "scripts\ci\generate-changelog-json.ps1"
if (-not (Test-Path $generatorScript)) { Write-Log "Generator script not found ($generatorScript), cannot sync changelog.json." -Err; exit 2 }

Write-Log "CHANGELOG.md edited, regenerating changelog.json..."
pwsh -NoProfile -File $generatorScript 2>&1 | ForEach-Object { Write-Log $_ }
if ($LASTEXITCODE -ne 0) {
    Write-Log "Changelog regeneration failed (exit $LASTEXITCODE) — changelog.json is stale. Fix CHANGELOG.md syntax and rerun: pwsh ./scripts/ci/generate-changelog-json.ps1" -Err
    exit 2
}
Write-Log "Regeneration complete. (exit 0)"
