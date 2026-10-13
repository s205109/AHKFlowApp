#Requires -Version 7.0
<#
.SYNOPSIS
Tests the Claude Code UserPromptExpansion hook that blocks the upstream mattpocock-skills forks.

.DESCRIPTION
The repository keeps adapted forks of some upstream mattpocock-skills skills, named mp-*. The
hook .claude/hooks/block-upstream-mp-forks.ps1 blocks the typed upstream slash command. Each
script case writes a hook input under the temp folder, then runs the hook as its own process,
the way Claude Code runs it. Exit code 2 blocks the expansion.

Run it by hand with:  pwsh ./tests/BlockUpstreamMpForksHook.Tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:HookPath = Join-Path $repoRoot '.claude/hooks/block-upstream-mp-forks.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-mpblock-' + [guid]::NewGuid().ToString('N'))
$script:Failures = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# Runs the hook exactly as Claude Code does: its own process, the input on stdin.
function Invoke-Hook {
    param([string] $Stdin)
    $id = [guid]::NewGuid().ToString('N')
    $stdinFile = Join-Path $script:TempRoot "stdin-$id.json"
    $stdoutFile = Join-Path $script:TempRoot "stdout-$id.txt"
    $stderrFile = Join-Path $script:TempRoot "stderr-$id.txt"
    [System.IO.File]::WriteAllText($stdinFile, $Stdin, [System.Text.UTF8Encoding]::new($false))
    $proc = Start-Process -FilePath $script:HostExe `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "`"$script:HookPath`"") `
        -RedirectStandardInput $stdinFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stderr   = [System.IO.File]::ReadAllText($stderrFile)
    }
}

try {
    # --- The hook as Claude Code runs it ---

    Invoke-TestCase 'A payload with command_name is blocked and names the mp- fork' {
        $result = Invoke-Hook '{"hook_event_name":"UserPromptExpansion","command_name":"mattpocock-skills:grilling"}'
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('/mp-grilling')) "The message must name /mp-grilling. Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'A payload with no command_name is blocked by the text search' {
        $result = Invoke-Hook '{"hook_event_name":"UserPromptExpansion","prompt":"/mattpocock-skills:research"}'
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('/mp-research')) "The message must name /mp-research. Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'An empty payload is still blocked' {
        $result = Invoke-Hook ''
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('Use the mp- version instead.')) "The message must point at the mp- version. Stderr: $($result.Stderr)"
    }
}
finally {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All upstream mp block hook tests passed.' -ForegroundColor Green
exit 0
