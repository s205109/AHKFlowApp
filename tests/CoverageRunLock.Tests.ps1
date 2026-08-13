#Requires -Version 5.1
<#
.SYNOPSIS
Tests for the shared test-run lock in scripts/test-run-lock.common.ps1.

.DESCRIPTION
The lock stops two local test runs from building and instrumenting the same output folders at
the same time. Backlog 082 recorded what happens without it: coverlet fails to instrument a
locked module, writes no coverage file for that project, and dotnet test still exits 0.

Every case uses a disposable folder under the system temp directory as the repository root.
No case takes the lock in the real repository root.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\test-run-lock.common.ps1')

$script:Failures = New-Object System.Collections.Generic.List[string]

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

function New-FakeRepoRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-lock-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
}

function Remove-FakeRepoRoot {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'A second run cannot take the lock' {
    $root = New-FakeRepoRoot
    $first = $null
    try {
        $first = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Coverage'
        $threw = $false
        $message = ''
        try { Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Fast' }
        catch { $threw = $true; $message = $_.Exception.Message }
        Assert-True $threw 'Expected the second acquisition to throw.'
        Assert-True ($message -match 'Coverage') "Expected the holder's mode in the message. Got: $message"
        Assert-True ($message -match [regex]::Escape($PID)) "Expected the holder's process id. Got: $message"
    }
    finally {
        if ($first) { Exit-AhkFlowTestRunLock -Handle $first }
        Remove-FakeRepoRoot -Root $root
    }
}

Invoke-TestCase 'Releasing the lock lets the next run take it' {
    $root = New-FakeRepoRoot
    try {
        $first = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Fast'
        Exit-AhkFlowTestRunLock -Handle $first
        $second = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Coverage'
        Assert-True ($null -ne $second) 'Expected the second acquisition to succeed.'
        Exit-AhkFlowTestRunLock -Handle $second
    }
    finally {
        Remove-FakeRepoRoot -Root $root
    }
}

Invoke-TestCase 'A stale owner file alone does not block a run' {
    $root = New-FakeRepoRoot
    try {
        Set-Content -LiteralPath (Join-Path $root '.test-run.lock.owner') `
            -Value 'Mode=Coverage; ProcessId=999999; Started=2026-01-01T00:00:00Z' -Encoding utf8
        $handle = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Fast'
        Assert-True ($null -ne $handle) 'Expected the run to take the lock despite a stale owner file.'
        $owner = Get-Content -LiteralPath $handle.OwnerPath -Raw
        Assert-True ($owner -match 'Mode=Fast') "Expected the owner file to be overwritten. Got: $owner"
        Exit-AhkFlowTestRunLock -Handle $handle
    }
    finally {
        Remove-FakeRepoRoot -Root $root
    }
}

# The lock file is never deleted, so every run after the first one meets a file that is already
# there. Only a live handle blocks. This case proves the error message tells the truth when it
# says a lock file left behind by an earlier run does not block.
Invoke-TestCase 'A leftover lock file with no open handle does not block a run' {
    $root = New-FakeRepoRoot
    try {
        Set-Content -LiteralPath (Join-Path $root '.test-run.lock') -Value 'leftover' -Encoding utf8
        $handle = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Fast'
        Assert-True ($null -ne $handle) 'Expected the run to take the lock despite a leftover lock file.'
        Exit-AhkFlowTestRunLock -Handle $handle
    }
    finally {
        Remove-FakeRepoRoot -Root $root
    }
}

Invoke-TestCase 'Releasing the lock deletes the owner file' {
    $root = New-FakeRepoRoot
    try {
        $handle = Enter-AhkFlowTestRunLock -RepoRoot $root -Mode 'Fast'
        $ownerPath = $handle.OwnerPath
        Exit-AhkFlowTestRunLock -Handle $handle
        Assert-True (-not (Test-Path -LiteralPath $ownerPath)) 'Expected the owner file to be deleted.'
    }
    finally {
        Remove-FakeRepoRoot -Root $root
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Test-run lock tests passed.' -ForegroundColor Green
exit 0
