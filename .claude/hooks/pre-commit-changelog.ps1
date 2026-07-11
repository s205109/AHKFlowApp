# Pre-commit hook: verify the generated changelog asset matches CHANGELOG.md
# Safety net for edits the post-edit-changelog hook didn't see (e.g. CHANGELOG.md
# edited outside Claude Code's Edit/Write tools). Mirrors the CI check
# (ci.yml "Verify changelog asset" step) so drift is caught before push, not after.
# Reads the incoming Bash command from stdin to fast-exit on non-commit commands.
#
# Two checks, both must pass:
#   1. Working tree — PreToolUse fires before the command runs, so with
#      "git add X && git commit" nothing is staged yet; this catches that path.
#   2. Index — what the commit will actually contain. Catches CHANGELOG.md
#      staged while the regenerated JSON is not (working tree looks synced,
#      but git would commit the old JSON).
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

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$generatorScript = Join-Path $repoRoot "scripts\ci\generate-changelog-json.ps1"
$jsonRelPath = 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/changelog.json'

# --- Check 1: working tree ---
Write-Log "Checking changelog asset (working tree)..."

pwsh -NoProfile -File $generatorScript -Check 2>&1 | ForEach-Object { Write-Log $_ }
if ($LASTEXITCODE -ne 0) {
    Write-Log "Changelog asset is stale in the working tree. Run 'pwsh ./scripts/ci/generate-changelog-json.ps1' to fix. (exit $LASTEXITCODE)" -Err
    exit 2
}

# --- Check 2: index (staged content = what the commit will contain) ---
Write-Log "Checking changelog asset (index)..."

# git emits UTF-8 bytes; PowerShell decodes native output with the console code
# page, which mangles non-ASCII (e.g. "…") — force UTF-8 for the capture.
$prevEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $stagedMd = & git -C $repoRoot show :CHANGELOG.md 2>$null
} finally {
    [Console]::OutputEncoding = $prevEncoding
}
if ($LASTEXITCODE -ne 0) {
    # CHANGELOG.md not in the index (e.g. fresh repo state) — nothing to compare.
    Write-Log "CHANGELOG.md not found in index, skipping index check. (exit 0)"
    exit 0
}

$jsonIndexHash = (& git -C $repoRoot ls-files -s -- $jsonRelPath) -split '\s+' | Select-Object -Skip 1 -First 1
if (-not $jsonIndexHash) {
    Write-Log "changelog.json missing from index while CHANGELOG.md is tracked. Run 'pwsh ./scripts/ci/generate-changelog-json.ps1' and stage it. (exit 2)" -Err
    exit 2
}

$tempMd   = New-TemporaryFile
$tempJson = New-TemporaryFile
try {
    # Line-join is safe: the generator parses line-by-line and trims trailing whitespace.
    [System.IO.File]::WriteAllText($tempMd.FullName, (($stagedMd -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))

    pwsh -NoProfile -File $generatorScript -InputPath $tempMd.FullName -OutputPath $tempJson.FullName 2>&1 | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Changelog generation from staged CHANGELOG.md failed (exit $LASTEXITCODE) — fix CHANGELOG.md syntax. (exit 2)" -Err
        exit 2
    }

    # Compare git blob hashes — exact byte comparison, no encoding round-trips.
    $expectedHash = (& git -C $repoRoot hash-object -- $tempJson.FullName).Trim()
    if ($expectedHash -ne $jsonIndexHash) {
        Write-Log "Staged changelog.json does not match staged CHANGELOG.md. Run 'pwsh ./scripts/ci/generate-changelog-json.ps1' and stage the result. (exit 2)" -Err
        exit 2
    }
} finally {
    Remove-Item $tempMd.FullName, $tempJson.FullName -Force -ErrorAction SilentlyContinue
}

Write-Log "Changelog asset check passed (working tree + index). (exit 0)"
