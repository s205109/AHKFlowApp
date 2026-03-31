# Post-edit hook: auto-format changed .cs files
# Runs dotnet format on specific files after Claude edits them.
#
# Usage:
#   Called automatically by Claude Code PostToolUse hook after Edit/Write on .cs files.
#   Accepts file path via:
#     1. First argument ($args[0])
#     2. CLAUDE_EDITED_FILE env var
#     3. PostToolUse stdin JSON ({"tool_input":{"file_path":"..."}})

$ErrorActionPreference = 'Stop'

# --- Log file setup ---
$logDir  = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "post-edit-format.log"

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

# Convert to relative path (dotnet format --include requires relative paths)
$file = [System.IO.Path]::GetFullPath($file)
$cwd  = [System.IO.Path]::GetFullPath((Get-Location).Path)
if ($file.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
    $file = $file.Substring($cwd.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
}

# Only format C# files
if (-not $file.EndsWith('.cs', [System.StringComparison]::OrdinalIgnoreCase)) { Write-Log "Not a .cs file ($file), skipping."; exit 0 }

# Skip if file doesn't exist (deleted)
if (-not (Test-Path $file)) { Write-Log "File not found ($file), skipping."; exit 0 }

# Find the nearest .csproj or .sln to scope the format
$dir     = Split-Path -Parent $file
$project = $null

while ($dir -and $dir -ne (Split-Path -Parent $dir)) {
    $csproj = Get-ChildItem -Path $dir -Filter '*.csproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csproj) { $project = $csproj.FullName; break }

    $sln = Get-ChildItem -Path $dir -Filter '*.sln' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sln) { $project = $sln.FullName; break }

    $dir = Split-Path -Parent $dir
}

if ($project) {
    Write-Log "Formatting $file (project: $project)"
    dotnet format $project --include $file 2>$null
    Write-Log "Format complete. (exit $LASTEXITCODE)"
} else {
    Write-Log "No .csproj or .sln found for $file, skipping format" -Err
}
