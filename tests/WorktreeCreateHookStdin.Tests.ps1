#Requires -Version 5.1
<#
.SYNOPSIS
  Get-HookInput in scripts/new-worktree.ps1 must decode its WorktreeCreate hook stdin as UTF-8.

.DESCRIPTION
  Claude Code's WorktreeCreate hook pipes a JSON payload to new-worktree.ps1 on stdin. The
  reader used [Console]::In, which decodes with the console code page (cp437 on Windows), not
  UTF-8. A leading UTF-8 byte order mark then arrived as three wrong characters and
  ConvertFrom-Json rejected the whole document, so the hook fell back to "-Name required" and
  created nothing.

  GitHub issue #356. The sibling fix for scripts/remove-worktree-local-dev.ps1 is backlog 117.

  Two behavioural tests spawn new-worktree.ps1 on its hook path with a {"name":"..."} payload,
  one with a UTF-8 byte order mark and one without, and assert the worktree is created with the
  name from the payload. Two content checks pin the reader shape and the bounded read.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# A minimal main checkout that carries the worktree tooling contract: every top-level
# scripts/*.ps1, one appsettings.json for setup-worktree-local-dev.ps1 to rewrite, and a
# solution file. Its parent directory is the throwaway root to delete.
function New-WorktreeToolingRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtcreate-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Create Hook Test' *> $null

    $repoScripts = Join-Path $repo 'scripts'
    New-Item -ItemType Directory -Path $repoScripts -Force | Out-Null
    Copy-Item -Path (Join-Path $scriptsDir '*.ps1') -Destination $repoScripts -Force

    $apiDir = Join-Path $repo 'src\Backend\AHKFlowApp.API'
    New-Item -ItemType Directory -Path $apiDir -Force | Out-Null
    $appSettings = '{ "ConnectionStrings": { "DefaultConnection": "Server=localhost;Database=AHKFlowApp;Trusted_Connection=True;" }, "Cors": { "AllowedOrigins": [] } }'
    Set-Content -LiteralPath (Join-Path $apiDir 'appsettings.json') -Value $appSettings -Encoding utf8

    Set-Content -LiteralPath (Join-Path $repo 'AHKFlowApp.slnx') -Value '<Solution />' -Encoding utf8

    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'worktree tooling') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

# Spawns new-worktree.ps1 with a hook payload on stdin, exactly as Claude's WorktreeCreate hook
# does. The payload bytes are written directly so the same suite sends the same bytes on Windows
# PowerShell 5.1 and PowerShell 7: Set-Content -Encoding utf8 adds a byte order mark under 5.1
# and none under 7.
function Invoke-CreateHook {
    param(
        [string] $RepoDir,
        [string] $Name,
        [switch] $WithByteOrderMark
    )

    $stdinFile = Join-Path (Split-Path -Parent $RepoDir) ('hook-stdin-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $payload = (@{ name = $Name } | ConvertTo-Json -Compress)
        [System.IO.File]::WriteAllText($stdinFile, $payload,
            (New-Object System.Text.UTF8Encoding($WithByteOrderMark.IsPresent)))

        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        $newWorktreeScript = Join-Path $RepoDir 'scripts\new-worktree.ps1'
        $proc = Start-Process -FilePath $psExe `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $newWorktreeScript) `
            -WorkingDirectory $RepoDir `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait

        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stdout   = (Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
            Stderr   = (Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Assert-WorktreeCreatedFromPayload {
    param([string] $RepoDir, [pscustomobject] $Result, [string] $Name)

    Assert-Equal 0 $Result.ExitCode "new-worktree.ps1 hook path should exit 0. Stderr: $($Result.Stderr)"

    $stdoutLines = @(($Result.Stdout -split "`r?`n") | Where-Object { $_.Trim() })
    Assert-Equal 1 $stdoutLines.Count "Hook stdout must be exactly one line. Got: $($Result.Stdout)"

    $expected = ([System.IO.Path]::GetFullPath((Join-Path $RepoDir ".claude\worktrees\$Name"))).TrimEnd('\', '/')
    Assert-Equal $expected ($stdoutLines[0].Trim().TrimEnd('\', '/')) 'Hook stdout must be the new worktree path built from the payload name.'
    Assert-True (Test-Path -LiteralPath $expected) "The worktree folder named by the payload must exist: $expected"
}

# --- Test: a byte order mark on the hook stdin -> worktree still created -------
$repo = New-WorktreeToolingRepo
try {
    $result = Invoke-CreateHook -RepoDir $repo -Name 'wt-bom-payload' -WithByteOrderMark
    Assert-WorktreeCreatedFromPayload -RepoDir $repo -Result $result -Name 'wt-bom-payload'
} finally {
    Remove-TempTree $repo
}

# --- Test: no byte order mark -> worktree created (harness control) -----------
$repo = New-WorktreeToolingRepo
try {
    $result = Invoke-CreateHook -RepoDir $repo -Name 'wt-plain-payload'
    Assert-WorktreeCreatedFromPayload -RepoDir $repo -Result $result -Name 'wt-plain-payload'
} finally {
    Remove-TempTree $repo
}

# --- Content check: Get-HookInput reads the raw stream, not [Console]::In ------
# [Console]::In is the console-code-page reader that caused issue #356.
$newWorktreeText = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'new-worktree.ps1')
$match = [regex]::Match($newWorktreeText, '(?s)function Get-HookInput\s*\{.*?\n\}')
Assert-True $match.Success 'Could not locate the Get-HookInput function body in new-worktree.ps1.'
$body = $match.Value
Assert-True ($body -notmatch '\[Console\]::In\.') 'Get-HookInput must not read stdin through [Console]::In (console code page).'
Assert-True ($body -match 'OpenStandardInput') 'Get-HookInput must read the raw stdin stream via [Console]::OpenStandardInput().'
Assert-True ($body -match 'UTF8Encoding') 'Get-HookInput must decode the raw stdin stream as UTF-8.'

# --- Content check: the bounded read is still there --------------------------
# A redirected-but-open stdin that never sends end of file must not hang the script.
Assert-True ($body -match 'Wait\(2000\)') 'Get-HookInput must keep the 2-second bounded read.'
Assert-True ($body -match 'No hook stdin within timeout') 'Get-HookInput must keep the timeout message.'

Write-Host 'Worktree create-hook stdin tests passed.'
