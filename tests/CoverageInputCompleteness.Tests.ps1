#Requires -Version 5.1
<#
.SYNOPSIS
Tests the coverage-input completeness check in scripts/coverage-inputs.common.ps1.

.DESCRIPTION
Backlog 082: when coverlet cannot instrument a locked assembly it writes no coverage file for
that test project, and dotnet test still exits 0. The coverage gate then blames coverage for
missing input. These cases prove the run notices the missing file first.

The cases build a fake results tree under the system temp directory. No case runs dotnet.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\coverage-inputs.common.ps1')

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

# Builds <root>\<project>\<guid>\coverage.cobertura.xml for each named project, which is the
# shape coverlet produces under a per-project results directory.
function New-ResultsFixture {
    param([string[]] $ProjectName)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-coverage-' + [guid]::NewGuid().ToString('N'))
    foreach ($name in $ProjectName) {
        $folder = Join-Path (Join-Path $root $name) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'coverage.cobertura.xml') `
            -Value '<coverage><packages /></coverage>' -Encoding utf8
    }

    return (Resolve-Path -LiteralPath $root).Path
}

function Remove-ResultsFixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Writes a merged Cobertura report holding every threshold assembly except the excluded one.
# Rates are set high so nothing fails on its numbers, which keeps the case about missing input.
function New-MergedCobertura {
    param([string] $ExcludeAssembly)

    $assemblies = @(
        'AHKFlowApp.Domain', 'AHKFlowApp.Application', 'AHKFlowApp.Infrastructure',
        'AHKFlowApp.API', 'AHKFlowApp.UI.Blazor'
    ) | Where-Object { $_ -ne $ExcludeAssembly }

    $packages = ($assemblies | ForEach-Object {
        "    <package name=`"$_`" line-rate=`"0.99`" branch-rate=`"0.99`" />"
    }) -join [Environment]::NewLine

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-cobertura-' + [guid]::NewGuid().ToString('N') + '.xml')
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<coverage line-rate="0.99" branch-rate="0.99">
  <packages>
$packages
  </packages>
</coverage>
"@
    Set-Content -LiteralPath $path -Value $xml -Encoding utf8
    return $path
}

Invoke-TestCase 'A complete result set reports nothing missing' {
    $expected = @('AHKFlowApp.Domain.Tests', 'AHKFlowApp.UI.Blazor.Tests')
    $root = New-ResultsFixture -ProjectName $expected
    try {
        $missing = @(Get-AhkFlowMissingCoverageInput -ResultsRoot $root -ExpectedProjectName $expected)
        Assert-True ($missing.Count -eq 0) "Expected nothing missing, got: $($missing -join ', ')"
    }
    finally {
        Remove-ResultsFixture -Root $root
    }
}

Invoke-TestCase 'Removing one expected coverage file names that project' {
    $expected = @('AHKFlowApp.Domain.Tests', 'AHKFlowApp.UI.Blazor.Tests')
    $root = New-ResultsFixture -ProjectName $expected
    try {
        Get-ChildItem -LiteralPath (Join-Path $root 'AHKFlowApp.UI.Blazor.Tests') -Recurse -Filter 'coverage.cobertura.xml' |
            Remove-Item -Force

        $missing = @(Get-AhkFlowMissingCoverageInput -ResultsRoot $root -ExpectedProjectName $expected)
        Assert-True ($missing.Count -eq 1) "Expected exactly one missing project, got: $($missing -join ', ')"
        Assert-True ($missing[0] -eq 'AHKFlowApp.UI.Blazor.Tests') "Expected the UI project, got: $($missing[0])"
    }
    finally {
        Remove-ResultsFixture -Root $root
    }
}

Invoke-TestCase 'A project folder that was never created counts as missing' {
    $expected = @('AHKFlowApp.Domain.Tests', 'AHKFlowApp.CLI.Tests')
    $root = New-ResultsFixture -ProjectName @('AHKFlowApp.Domain.Tests')
    try {
        $missing = @(Get-AhkFlowMissingCoverageInput -ResultsRoot $root -ExpectedProjectName $expected)
        Assert-True ($missing.Count -eq 1) "Expected exactly one missing project, got: $($missing -join ', ')"
        Assert-True ($missing[0] -eq 'AHKFlowApp.CLI.Tests') "Expected the CLI project, got: $($missing[0])"
    }
    finally {
        Remove-ResultsFixture -Root $root
    }
}

Invoke-TestCase 'Coverage cleanup preserves progress history' {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-coverage-cleanup-' + [guid]::NewGuid().ToString('N'))
    try {
        $coverageResults = Join-Path $root 'TestResults\coverage'
        $progressResults = Join-Path $root 'TestResults\progress'
        $coverageReport = Join-Path $root 'CoverageReport'
        New-Item -ItemType Directory -Path $coverageResults -Force | Out-Null
        New-Item -ItemType Directory -Path $progressResults -Force | Out-Null
        New-Item -ItemType Directory -Path $coverageReport -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $coverageResults 'old.xml') -Value '<coverage />' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $progressResults 'test-fast.Fast.json') -Value '{"a":1}' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $coverageReport 'old.html') -Value '<html />' -Encoding utf8

        Remove-AhkFlowCoverageArtifacts `
            -CoverageResultsRoot $coverageResults `
            -CoverageReportDirectory $coverageReport

        Assert-True (-not (Test-Path -LiteralPath $coverageResults)) 'Expected stale coverage inputs to be removed.'
        Assert-True (-not (Test-Path -LiteralPath $coverageReport)) 'Expected the stale coverage report to be removed.'
        Assert-True (Test-Path -LiteralPath (Join-Path $progressResults 'test-fast.Fast.json')) `
            'Expected coverage cleanup to preserve progress history.'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-TestCase 'ReportGenerator reads only the current coverage result folder' {
    $runCoverage = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\run-coverage.ps1') -Raw
    $reportLines = @($runCoverage -split "`r?`n" | Where-Object { $_ -match '^\s*-reports:' })

    Assert-True ($reportLines.Count -eq 1) "Expected one ReportGenerator input, got: $($reportLines -join ' | ')"
    Assert-True ($reportLines[0] -match '\$coverageResultsRoot') `
        "Expected ReportGenerator input under the cleaned coverage folder. Got: $($reportLines[0])"
    Assert-True ($reportLines[0] -notmatch 'TestResults/\*\*/') `
        "A broad TestResults glob can merge stale reports outside coverage. Got: $($reportLines[0])"
}

Invoke-TestCase 'The expected project list comes from the solution and coverlet' {
    $projects = @(Get-AhkFlowCoverageProject -RepoRoot $repoRoot)
    $names = @($projects | ForEach-Object { $_.Name })
    Assert-True ($names.Count -ge 1) 'Expected at least one coverage-producing test project.'
    Assert-True ($names -contains 'AHKFlowApp.UI.Blazor.Tests') "Expected the UI test project. Got: $($names -join ', ')"
    Assert-True ($names -notcontains 'AHKFlowApp.TestUtilities') 'TestUtilities is a library, not a test project.'

    foreach ($project in $projects) {
        Assert-True (Test-Path -LiteralPath $project.Path -PathType Leaf) "Project path does not exist: $($project.Path)"
    }
}

Invoke-TestCase 'The gate calls a missing assembly incomplete input, not a threshold failure' {
    $cobertura = New-MergedCobertura -ExcludeAssembly 'AHKFlowApp.UI.Blazor'
    try {
        $gate = Join-Path $repoRoot 'scripts\ci\check-coverage-thresholds.py'
        $output = & python $gate --cobertura-path $cobertura 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        Assert-True ($exitCode -ne 0) "Expected a non-zero exit code. Output: $output"
        Assert-True ($output -match 'Coverage input incomplete') `
            "Expected the incomplete-input error title. Output: $output"
        Assert-True ($output -match 'AHKFlowApp\.UI\.Blazor') `
            "Expected the missing assembly to be named. Output: $output"
        Assert-True ($output -notmatch 'failed per-assembly coverage thresholds') `
            "Missing input must not be reported as a threshold failure. Output: $output"
    }
    finally {
        Remove-Item -LiteralPath $cobertura -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Coverage input completeness tests passed.' -ForegroundColor Green
exit 0
