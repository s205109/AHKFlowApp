#Requires -Version 5.1
<#
.SYNOPSIS
Tests for scripts/run-powershell-suites.ps1, the script that runs every PowerShell suite in CI.

.DESCRIPTION
That script decides whether the powershell-suites job is honest, so it needs its own proof.
Each case builds a disposable folder of tiny fake suites under the system temp directory and runs
the driver against it with -SuiteRoot. No case touches the repository's real tests folder.

The fake suites cover both endings the real suites use: an explicit 'exit', and a throw or a plain
run off the end. One fake suite leaves $LASTEXITCODE dirty on its success path, which is the trap
that makes an in-process exit-code check report a passing suite as failed.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.4 turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is 'Stop'. Every case here runs the driver and reads its exit code, and
# a failing driver run is the expected result in most of them, so opt out.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:DriverPath = Join-Path $repoRoot 'scripts\run-powershell-suites.ps1'
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

function New-SuiteFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'markers') -Force | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
}

function Remove-SuiteFixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Writes a fake suite that drops a marker file first, so a case can prove the suite really ran,
# and then ends in the requested way.
function Add-FakeSuite {
    param(
        [string] $Root,
        [string] $Name,

        # pass      - writes the marker, prints, runs off the end (no exit)
        # exit-zero - writes the marker, then 'exit 0'
        # dirty     - writes the marker, runs a native command that exits 1, then runs off the end
        # exit-one  - writes the marker, then 'exit 1'
        # throw     - writes the marker, then throws
        [ValidateSet('pass', 'exit-zero', 'dirty', 'exit-one', 'throw')]
        [string] $Ending
    )

    $markerPath = Join-Path (Join-Path $Root 'markers') $Name
    $body = New-Object System.Collections.Generic.List[string]
    $body.Add("Set-Content -LiteralPath '$markerPath' -Value 'ran' -Encoding ascii")
    $body.Add("Write-Host 'ran $Name'")

    switch ($Ending) {
        'pass' { }
        'exit-zero' { $body.Add('exit 0') }
        'dirty' {
            # The real WorktreeBaseRef suite ends like this: a native command leaves $LASTEXITCODE
            # at 1, and the suite still passes.
            $body.Add('& cmd /c exit 1')
            $body.Add("Write-Host 'suite passed'")
        }
        'exit-one' { $body.Add('exit 1') }
        'throw' { $body.Add("throw 'deliberate failure'") }
    }

    Set-Content -LiteralPath (Join-Path $Root $Name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
}

function Test-MarkerExists {
    param([string] $Root, [string] $Name)
    return Test-Path -LiteralPath (Join-Path (Join-Path $Root 'markers') $Name)
}

# Runs the driver as its own process and returns its exit code, everything it printed, and the
# job summary it wrote. The child process is the point: it is exactly what the CI step measures.
#
# The child inherits this process's environment. Under CI that includes GITHUB_STEP_SUMMARY, so
# without the redirect below every fake suite table here would be appended to the real
# powershell-suites job summary — including the deliberate failures. Point the child at a scratch
# file instead. Redirecting rather than clearing keeps the driver's summary-writing branch covered.
function Invoke-Driver {
    param([string] $SuiteRoot, [string[]] $Exclude = @())

    $excludeLiteral = if ($Exclude.Count -eq 0) {
        '@()'
    } else {
        '@(' + (($Exclude | ForEach-Object { "'$_'" }) -join ',') + ')'
    }

    $summaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-summary-' + [guid]::NewGuid().ToString('N') + '.md')
    $previousSummary = $env:GITHUB_STEP_SUMMARY
    $env:GITHUB_STEP_SUMMARY = $summaryPath

    try {
        $command = "& '$script:DriverPath' -SuiteRoot '$SuiteRoot' -Exclude $excludeLiteral; exit `$LASTEXITCODE"
        $output = & $script:HostExe -NoProfile -Command $command 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $summary = if (Test-Path -LiteralPath $summaryPath) {
            Get-Content -LiteralPath $summaryPath -Raw
        } else {
            ''
        }
    } finally {
        $env:GITHUB_STEP_SUMMARY = $previousSummary
        Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Summary  = $summary
    }
}

Write-Host "Testing $script:DriverPath"
Assert-True (Test-Path -LiteralPath $script:DriverPath) "Driver script not found at $script:DriverPath."

Invoke-TestCase 'All suites pass -> exit code 0' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-exit-zero.Tests.ps1' -Ending 'exit-zero'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'All 2 suite\(s\) passed\.') "Expected the all-passed summary line. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'The driver prints a progress line per suite and saves no timings for a fixture run' {
    $root = New-SuiteFixture
    $timingsPath = Join-Path $repoRoot 'TestResults\progress\run-powershell-suites.json'
    $before = if (Test-Path -LiteralPath $timingsPath) { (Get-Item -LiteralPath $timingsPath).LastWriteTimeUtc } else { $null }

    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'

        $result = Invoke-Driver -SuiteRoot $root

        Assert-True ($result.Output -match '\[1/2\] 01-pass\.Tests\.ps1') "Expected a progress line for the first suite. Output: $($result.Output)"
        Assert-True ($result.Output -match '\[2/2\] 02-pass\.Tests\.ps1') "Expected a progress line for the second suite. Output: $($result.Output)"

        # A fixture run reads no history, so it can only report the time left as unknown. That is
        # also what proves it did not reach the real store.
        Assert-True ($result.Output -match 'remaining unknown') "A fixture run must report the remaining time as unknown. Output: $($result.Output)"

        $after = if (Test-Path -LiteralPath $timingsPath) { (Get-Item -LiteralPath $timingsPath).LastWriteTimeUtc } else { $null }
        Assert-True ($before -eq $after) 'A run over fake suites must not write the real timings file.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite that exits 1 fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-fail.Tests.ps1' -Ending 'exit-one'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '02-fail\.Tests\.ps1 \| failed') "The summary must mark 02-fail as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite that throws fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-throw.Tests.ps1' -Ending 'throw'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '01-throw\.Tests\.ps1 \| failed') "The summary must mark 01-throw as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# The regression test for the trap named in backlog item 066. A passing suite that leaves
# $LASTEXITCODE at 1 must still be reported as passed, which is only true because the driver runs
# each suite in its own process.
Invoke-TestCase 'A passing suite with a dirty $LASTEXITCODE still passes' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-dirty.Tests.ps1' -Ending 'dirty'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '01-dirty\.Tests\.ps1 \| passed') "The summary must mark 01-dirty as passed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Every suite runs even when the first one fails' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '02-throw.Tests.ps1' -Ending 'throw'
        Add-FakeSuite -Root $root -Name '03-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '04-dirty.Tests.ps1' -Ending 'dirty'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"

        foreach ($name in @('01-fail.Tests.ps1', '02-throw.Tests.ps1', '03-pass.Tests.ps1', '04-dirty.Tests.ps1')) {
            Assert-True (Test-MarkerExists -Root $root -Name $name) "Suite $name must still have run. Output: $($result.Output)"
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'The summary names every failed suite and no passing one' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '03-throw.Tests.ps1' -Ending 'throw'
        Add-FakeSuite -Root $root -Name '04-pass.Tests.ps1' -Ending 'exit-zero'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '2 of 4 suite\(s\) failed') "Expected a 2 of 4 failure count. Output: $($result.Output)"
        Assert-True ($result.Output -match '01-fail\.Tests\.ps1') "The failure list must name 01-fail. Output: $($result.Output)"
        Assert-True ($result.Output -match '03-throw\.Tests\.ps1') "The failure list must name 03-throw. Output: $($result.Output)"
        Assert-True ($result.Output -match '02-pass\.Tests\.ps1 \| passed') "02-pass must be listed as passed. Output: $($result.Output)"
        Assert-True ($result.Output -match '04-pass\.Tests\.ps1 \| passed') "04-pass must be listed as passed. Output: $($result.Output)"
        Assert-True (-not ($result.Output -match '02-pass\.Tests\.ps1 \| failed')) "02-pass must not be listed as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# The job summary is how a failure is read in the GitHub UI, and it goes to the file named by
# GITHUB_STEP_SUMMARY. This case also proves the redirect in Invoke-Driver works, which is what
# keeps these fake tables out of the real job summary.
Invoke-TestCase 'The driver writes its table to the GITHUB_STEP_SUMMARY file' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-fail.Tests.ps1' -Ending 'exit-one'

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.Summary -match '### PowerShell suites') "The summary file must hold the table heading. Summary: $($result.Summary)"
        Assert-True ($result.Summary -match '02-fail\.Tests\.ps1 \| failed') "The summary file must mark 02-fail as failed. Summary: $($result.Summary)"
        Assert-True ($result.Summary -match '1 of 2 suite\(s\) failed') "The summary file must hold the failure count. Summary: $($result.Summary)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# A run that finds nothing must not look green. A broken glob would otherwise hide every suite.
Invoke-TestCase 'A folder with no suites fails the run' {
    $root = New-SuiteFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'notes.txt') -Value 'not a suite' -Encoding utf8

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'No test suites found') "Expected the empty-folder message. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A missing suite folder fails the run' {
    $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-missing-' + [guid]::NewGuid().ToString('N'))

    $result = Invoke-Driver -SuiteRoot $missing
    Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'Suite folder not found') "Expected the missing-folder message. Output: $($result.Output)"
}

# An exclusion naming a file that no longer exists is a rename nobody finished. Left alone, the
# excluded suite would stop running everywhere and nothing would say so.
Invoke-TestCase 'An exclusion that names no file fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'

        $result = Invoke-Driver -SuiteRoot $root -Exclude @('NotThere.Tests.ps1')
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'NotThere\.Tests\.ps1') "The message must name the stale exclusion. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'An excluded suite does not run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-skip.Tests.ps1' -Ending 'exit-one'

        $result = Invoke-Driver -SuiteRoot $root -Exclude @('02-skip.Tests.ps1')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True (Test-MarkerExists -Root $root -Name '01-pass.Tests.ps1') "The included suite must have run. Output: $($result.Output)"
        Assert-True (-not (Test-MarkerExists -Root $root -Name '02-skip.Tests.ps1')) "The excluded suite must not have run. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# The default exclusion list is the only place a real suite can be dropped from CI by name, so it
# is checked against the real tests folder.
Invoke-TestCase 'Every default exclusion names a real suite file' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:DriverPath, [ref] $null, [ref] $null)
    $excludeParam = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Exclude' })
    Assert-True ($excludeParam.Count -eq 1) 'The driver must declare exactly one -Exclude parameter.'

    $defaults = @($excludeParam[0].DefaultValue.SafeGetValue())
    Assert-True ($defaults.Count -gt 0) 'The default exclusion list must not be empty.'

    foreach ($name in $defaults) {
        Assert-True (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name)) "Default exclusion '$name' does not exist in tests/."
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'CI PowerShell suite runner tests passed.' -ForegroundColor Green
exit 0
