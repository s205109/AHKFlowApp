# Pre-commit hook: verify code formatting
# Runs dotnet format in verify mode — fails if any files need formatting.
# Reads the incoming Bash command from stdin to fast-exit on non-commit commands.
#
# Exit codes:
#   0 — Format check passed (or not a commit command)
#   2 — Format check failed, commit blocked

$ErrorActionPreference = 'Stop'

# --- Log file setup ---
$logDir  = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "pre-commit-format.log"

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

Write-Log "Checking code formatting..."

dotnet format --verify-no-changes --verbosity quiet 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Log "Format check passed. (exit 0)"
} else {
    Write-Log "Format check failed. Run 'dotnet format' to fix formatting issues. (exit $LASTEXITCODE)" -Err
    exit 2
}
