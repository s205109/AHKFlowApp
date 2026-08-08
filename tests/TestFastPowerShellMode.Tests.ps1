#Requires -Version 5.1
<#
.SYNOPSIS
Tests for the PowerShell mode of scripts/test-fast.ps1.

.DESCRIPTION
The mode hands every tests/*.Tests.ps1 suite to scripts/run-powershell-suites.ps1. Each case here
builds a disposable folder of tiny fake suites under the system temp directory and points the mode
at it with -SuiteRoot. No case runs the mode against the repository's real tests folder.

That last rule is not a style preference, and a comment alone would not enforce it. The defect these
cases exist to catch is a -SuiteRoot passthrough that does not work. When the passthrough is broken
the runner falls back to its own default of tests/, finds this very file, and starts it again -
forever. So Invoke-Wrapper sets AHKFLOW_TESTFAST_MODE_TEST, and the guard at the top of this file
turns that runaway into one failed suite with a message that names the cause.
#>
[CmdletBinding()]
param()

# Recursion guard. Read the description above before removing it.
if ($env:AHKFLOW_TESTFAST_MODE_TEST -eq '1') {
    Write-Host 'Recursion guard hit: test-fast.ps1 did not forward -SuiteRoot.' -ForegroundColor Red
    exit 9
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.4 turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is 'Stop'. Most cases here expect a failing child run, so opt out.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:WrapperPath = Join-Path $repoRoot 'scripts\test-fast.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

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

# The runner rejects an exclusion that names a file it cannot find, and it checks that before it
# runs anything (scripts/run-powershell-suites.ps1:60-65). Its default exclusion is
# CodexSkillsHashParity.Tests.ps1. The wrapper exposes no -Exclude, so every fixture must contain a
# file with that name or the runner exits 1 before a single fake suite starts. The file is excluded,
# so it never runs.
function New-SuiteFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-testfast-mode-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'CodexSkillsHashParity.Tests.ps1') `
        -Value '# Placeholder so the runner default exclusion matches a real file. Never runs.' `
        -Encoding utf8
    return (Resolve-Path -LiteralPath $root).Path
}

function Remove-SuiteFixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Add-FakeSuite {
    param(
        [string] $Root,
        [string] $Name,

        # pass     - prints and runs off the end (no exit)
        # exit-one - prints, then 'exit 1'
        # throw    - prints, then throws
        [ValidateSet('pass', 'exit-one', 'throw')]
        [string] $Ending
    )

    $body = New-Object System.Collections.Generic.List[string]
    $body.Add("Write-Host 'ran $Name'")

    switch ($Ending) {
        'pass' { }
        'exit-one' { $body.Add('exit 1') }
        'throw' { $body.Add("throw 'deliberate failure'") }
    }

    Set-Content -LiteralPath (Join-Path $Root $Name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
}

# Runs the wrapper as its own process and returns its exit code and everything it printed.
#
# Two environment variables are handled here. AHKFLOW_TESTFAST_MODE_TEST arms the recursion guard at
# the top of this file. GITHUB_STEP_SUMMARY is redirected because the child inherits it: under CI the
# runner would otherwise append these fake tables, deliberate failures included, to the real
# powershell-suites job summary (scripts/run-powershell-suites.ps1:128-131).
function Invoke-Wrapper {
    param([string] $SuiteRoot)

    $summaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-testfast-mode-summary-' + [guid]::NewGuid().ToString('N') + '.md')
    $previousSummary = $env:GITHUB_STEP_SUMMARY
    $previousGuard = $env:AHKFLOW_TESTFAST_MODE_TEST
    $env:GITHUB_STEP_SUMMARY = $summaryPath
    $env:AHKFLOW_TESTFAST_MODE_TEST = '1'

    try {
        $output = & $script:HostExe -NoProfile -File $script:WrapperPath `
            -Mode PowerShell -SuiteRoot $SuiteRoot 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:GITHUB_STEP_SUMMARY = $previousSummary
        $env:AHKFLOW_TESTFAST_MODE_TEST = $previousGuard
        Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

Write-Host "Testing $script:WrapperPath"
Assert-True (Test-Path -LiteralPath $script:WrapperPath) "Wrapper script not found at $script:WrapperPath."

Invoke-TestCase 'All suites pass -> exit code 0' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'

        $result = Invoke-Wrapper -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'All 2 suite\(s\) passed\.') "Expected the all-passed summary line. Output: $($result.Output)"
    }
    finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite that exits 1 fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-exit-one.Tests.ps1' -Ending 'exit-one'

        $result = Invoke-Wrapper -SuiteRoot $root
        Assert-True ($result.ExitCode -ne 0) "Expected a non-zero exit code. Output: $($result.Output)"
        Assert-True ($result.Output -match '02-exit-one\.Tests\.ps1') "Expected the failing suite to be named. Output: $($result.Output)"
    }
    finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite that throws fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-throw.Tests.ps1' -Ending 'throw'

        $result = Invoke-Wrapper -SuiteRoot $root
        Assert-True ($result.ExitCode -ne 0) "Expected a non-zero exit code. Output: $($result.Output)"
        Assert-True ($result.Output -match '02-throw\.Tests\.ps1') "Expected the failing suite to be named. Output: $($result.Output)"
    }
    finally {
        Remove-SuiteFixture -Root $root
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'test-fast PowerShell mode tests passed.' -ForegroundColor Green
exit 0
