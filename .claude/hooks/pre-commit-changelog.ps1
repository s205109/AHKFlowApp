# Pre-commit hook: verify the generated changelog asset matches CHANGELOG.md
# Safety net for edits the post-edit-changelog hook didn't see (e.g. CHANGELOG.md
# edited outside Claude Code's Edit/Write tools). Mirrors the CI check exactly
# (ci.yml "Verify changelog asset" step) so drift is caught before push, not after.
# Reads the incoming Bash command from stdin to fast-exit on non-commit commands.
#
# Exit codes:
#   0 — Changelog asset current (or not a commit command)
#   2 — Changelog asset stale, commit blocked

$ErrorActionPreference = 'Stop'

# --- Log file setup ---
$logDir  = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "pre-commit-changelog.log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log($message, [switch]$Err) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Err) { [Console]::Error.WriteLine($message) } else { Write-Host $message }
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- Read the incoming command from stdin (Claude Code passes JSON tool input) ---
$toolCommand = $null
try {
    if ([Console]::IsInputRedirected) {
        $rawInput = [Console]::In.ReadToEnd()
        if ($rawInput) {
            $parsed = $rawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
            $toolCommand = $parsed.tool_input.command
        }
    }
} catch { }

# Fast-exit if hook-invoked with a non-commit command; no stdin = manual run, proceed
if ($toolCommand -and $toolCommand -notmatch 'git\s+commit') {
    exit 0
}

Write-Log "Checking changelog asset is current..."

$repoRoot = Join-Path $PSScriptRoot "..\.."
$generatorScript = Join-Path $repoRoot "scripts\ci\generate-changelog-json.ps1"

pwsh -NoProfile -File $generatorScript -Check 2>&1 | ForEach-Object { Write-Log $_ }
if ($LASTEXITCODE -eq 0) {
    Write-Log "Changelog asset check passed. (exit 0)"
} else {
    Write-Log "Changelog asset is stale. Run 'pwsh ./scripts/ci/generate-changelog-json.ps1' to fix. (exit $LASTEXITCODE)" -Err
    exit 2
}
