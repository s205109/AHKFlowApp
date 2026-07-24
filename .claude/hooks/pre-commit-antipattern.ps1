# Pre-commit hook: detect anti-patterns in lines ADDED by staged and unstaged changes to
# modified C# files (diff-scoped — pre-existing lines in a touched file are never flagged,
# only what this commit actually introduces).
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

# Anchor to the repo root: git diff paths are repo-root-relative, and the hook's
# cwd is wherever Claude Code currently runs.
Set-Location (Join-Path $PSScriptRoot "..\..")

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

Write-Log "Checking lines added by staged/unstaged changes for common issues..."

# Parses `git diff -U0` output into a list of { LineNumber, Text } for lines the diff ADDS
# in the new-file version. Deleted/context lines are skipped; hunk headers drive the running
# new-file line counter (with -U0 there should be no context lines, but unmatched lines are
# still ignored defensively rather than mis-tracking the counter).
function Get-AddedLines($file) {
    $added = @()
    $currentLine = 0

    $diffOutputs = @(
        (git diff --cached -U0 -- $file 2>$null),
        (git diff -U0 -- $file 2>$null)
    )

    foreach ($diffOutput in $diffOutputs) {
        foreach ($line in $diffOutput) {
            if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') {
                $currentLine = [int]$Matches[1]
                continue
            }
            if ($line.StartsWith('+++') -or $line.StartsWith('---')) {
                continue
            }
            if ($line.StartsWith('+')) {
                $added += [PSCustomObject]@{ LineNumber = $currentLine; Text = $line.Substring(1) }
                $currentLine++
            }
            # Lines starting with '-' are deletions: they don't exist in the new file, so the
            # new-file line counter does not advance for them.
        }
    }

    return $added
}

function Test-AntiPattern($filePath, $addedLines, $pattern, $message) {
    $hits = $addedLines | Where-Object { $_.Text -match $pattern }
    if ($hits) {
        $lines = ($hits | ForEach-Object { $_.LineNumber }) -join ', '
        Write-Log "  ${filePath}:$lines — $message"
        return $true
    }
    return $false
}

$errors = 0

foreach ($file in $filesToCheck) {
    $addedLines = Get-AddedLines $file
    if (-not $addedLines) { continue }

    if (Test-AntiPattern $file $addedLines 'DateTime\.(Now|UtcNow)'                                    'Use TimeProvider instead of DateTime.Now/UtcNow')                   { $errors++ }
    if (Test-AntiPattern $file $addedLines 'new HttpClient\(\)'                                        'Use IHttpClientFactory instead of new HttpClient()')                { $errors++ }
    if (Test-AntiPattern $file ($addedLines | Where-Object { $_.Text -notmatch 'EventArgs' }) 'async void' 'async void is dangerous, use async Task instead')                { $errors++ }
    # Polly's Outcome<T>.Result is the resilience outcome value, not a blocking Task.Result.
    # Strip only that exact expression from each line before scanning, so a real task.Result
    # sharing a line with Outcome.Result is still caught. `using Ardalis.Result;` (and any other
    # `using X.Result;` namespace import) is excluded outright — a using directive can never
    # contain a blocking .Result access, but its namespace can end in the literal text ".Result".
    # The exclusion is anchored to the import shape (`using A.B.C;` / `global using ...`, optional
    # alias) so it can NOT swallow a `using` statement or declaration: `using var x = Foo().Result;`
    # and `using (Foo().Result) { }` are real sync-over-async and must still be caught.
    $usingDirective = '^\s*(global\s+)?using\s+(static\s+)?([\w.]+\s*=\s*)?[\w.<>,\[\]\s]+;\s*$'
    $resultScan = $addedLines | Where-Object { $_.Text -notmatch $usingDirective } | ForEach-Object { [PSCustomObject]@{ LineNumber = $_.LineNumber; Text = ($_.Text -replace '\bOutcome\.Result\b', '') } }
    if (Test-AntiPattern $file $resultScan '\.Result\b|\.GetAwaiter\(\)\.GetResult\(\)' 'Avoid sync-over-async (.Result / .GetAwaiter().GetResult())') { $errors++ }
}

if ($errors -gt 0) {
    Write-Log "Found $errors anti-pattern issue(s) in added lines." -Err
    exit 2
}

Write-Log "No anti-patterns detected in added lines. (exit 0)"
exit 0
