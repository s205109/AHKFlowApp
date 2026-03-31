# Pre-commit hook: detect anti-patterns in staged and modified C# files
# Checks for common issues: DateTime.Now, new HttpClient(), async void, sync-over-async.
# For full anti-pattern detection, use the Roslyn MCP detect_antipatterns tool.
#
# Exit codes:
#   0 — No issues found (or no .cs files to check)
#   2 — Issues found, commit blocked

$ErrorActionPreference = 'Stop'

# --- Log file setup ---
$logDir  = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "pre-commit-antipattern.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log($message, [switch]$Err) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Err) { [Console]::Error.WriteLine($message) } else { Write-Host $message }
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- Get staged AND unstaged modified .cs files ---
# PreToolUse hook fires before the command runs, so "git add X && git commit"
# means X is not staged yet — check both to catch antipatterns either way.
$stagedFiles   = git diff --cached --name-only --diff-filter=ACM 2>$null | Where-Object { $_ -match '\.cs$' }
$unstagedFiles = git diff --name-only --diff-filter=ACM 2>$null           | Where-Object { $_ -match '\.cs$' }
$filesToCheck  = @($stagedFiles) + @($unstagedFiles) | Select-Object -Unique

if (-not $filesToCheck) {
    Write-Log "No modified .cs files, skipping anti-pattern check. (exit 0)"
    exit 0
}

Write-Log "Checking modified C# files for common issues..."

function Test-AntiPattern($filePath, $fileContent, $pattern, $message) {
    $hits = $fileContent | Select-String -Pattern $pattern -AllMatches
    if ($hits) {
        $lines = ($hits | ForEach-Object { $_.LineNumber }) -join ', '
        Write-Log "  ${filePath}:$lines — $message"
        return $true
    }
    return $false
}

$errors = 0

foreach ($file in $filesToCheck) {
    $fileContent = Get-Content $file

    if (Test-AntiPattern $file $fileContent 'DateTime\.(Now|UtcNow)'                    'Use TimeProvider instead of DateTime.Now/UtcNow')                   { $errors++ }
    if (Test-AntiPattern $file $fileContent 'new HttpClient\(\)'                         'Use IHttpClientFactory instead of new HttpClient()')                { $errors++ }
    if (Test-AntiPattern $file ($fileContent | Where-Object { $_ -notmatch 'EventArgs' }) 'async void' 'async void is dangerous, use async Task instead')     { $errors++ }
    if (Test-AntiPattern $file $fileContent '\.Result\b|\.GetAwaiter\(\)\.GetResult\(\)' 'Avoid sync-over-async (.Result / .GetAwaiter().GetResult())')       { $errors++ }
}

if ($errors -gt 0) {
    Write-Log "Found $errors anti-pattern issue(s) in modified files." -Err
    exit 2
}

Write-Log "No anti-patterns detected in modified files. (exit 0)"
exit 0
