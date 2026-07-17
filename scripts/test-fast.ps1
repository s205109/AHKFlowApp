#Requires -Version 5.1
<#
.SYNOPSIS
  Run explicit local test slices for fast, integration, E2E, or coverage workflows.
.DESCRIPTION
  Fast mode runs whole-project fast suites plus non-integration slices from mixed projects.
  Integration mode runs integration slices from mixed projects plus whole-project SQL/API suites.
  Each selected test project must discover at least one test.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Integration', 'E2E', 'Coverage')]
    [string]$Mode = 'Fast',

    [string]$Configuration = 'Release',

    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$resultsRoot = Join-Path $repoRoot "TestResults\test-fast\$Mode"
$sharedSqlScript = Join-Path $PSScriptRoot 'test-sql-container.common.ps1'
. $sharedSqlScript
. "$PSScriptRoot\Common.ps1"

function New-TestRun {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,

        [string]$Filter
    )

    [pscustomobject]@{
        Project = Join-Path $repoRoot $Project
        Filter = $Filter
    }
}

function Get-TestRuns {
    switch ($Mode) {
        'Fast' {
            return @(
                New-TestRun -Project 'tests\AHKFlowApp.Domain.Tests\AHKFlowApp.Domain.Tests.csproj'
                New-TestRun -Project 'tests\AHKFlowApp.TestUtilities.Tests\AHKFlowApp.TestUtilities.Tests.csproj'
                New-TestRun -Project 'tests\AHKFlowApp.UI.Blazor.Tests\AHKFlowApp.UI.Blazor.Tests.csproj'
                New-TestRun -Project 'tests\AHKFlowApp.Application.Tests\AHKFlowApp.Application.Tests.csproj' -Filter 'Category!=Integration'
                New-TestRun -Project 'tests\AHKFlowApp.CLI.Tests\AHKFlowApp.CLI.Tests.csproj' -Filter 'Category!=Integration'
            )
        }
        'Integration' {
            return @(
                New-TestRun -Project 'tests\AHKFlowApp.Application.Tests\AHKFlowApp.Application.Tests.csproj' -Filter 'Category=Integration'
                New-TestRun -Project 'tests\AHKFlowApp.CLI.Tests\AHKFlowApp.CLI.Tests.csproj' -Filter 'Category=Integration'
                New-TestRun -Project 'tests\AHKFlowApp.API.Tests\AHKFlowApp.API.Tests.csproj'
                New-TestRun -Project 'tests\AHKFlowApp.Infrastructure.Tests\AHKFlowApp.Infrastructure.Tests.csproj'
            )
        }
        'E2E' {
            return @(
                New-TestRun -Project 'tests\AHKFlowApp.E2E.Tests\AHKFlowApp.E2E.Tests.csproj'
            )
        }
        default {
            throw "Unsupported mode: $Mode"
        }
    }
}

function Read-TestCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath
    )

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw
    $counters = $trx.GetElementsByTagName('Counters') | Select-Object -First 1
    if (-not $counters) {
        return 0
    }

    return [int]$counters.total
}

function Invoke-TestRun {
    param(
        [Parameter(Mandatory = $true)]
        [object]$TestRun
    )

    if (-not (Test-Path -LiteralPath $TestRun.Project -PathType Leaf)) {
        throw "Test project not found: $($TestRun.Project)"
    }

    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($TestRun.Project)
    $projectResultsDirectory = Join-Path $resultsRoot $projectName
    New-Item -ItemType Directory -Path $projectResultsDirectory -Force | Out-Null

    $arguments = @(
        'test',
        $TestRun.Project,
        '--configuration',
        $Configuration,
        '--logger',
        "trx;LogFileName=$projectName.trx",
        '--results-directory',
        $projectResultsDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($TestRun.Filter)) {
        $arguments += @('--filter', $TestRun.Filter)
    }

    if ($NoBuild) {
        $arguments += '--no-build'
    }

    $filterText = if ([string]::IsNullOrWhiteSpace($TestRun.Filter)) { 'all tests' } else { $TestRun.Filter }
    Write-Step "Running $projectName ($filterText)"
    & dotnet @arguments 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "dotnet test failed for $projectName."
    }

    $trxFile = Get-ChildItem -LiteralPath $projectResultsDirectory -Recurse -Filter '*.trx' |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $trxFile) {
        throw "No TRX file was produced for $projectName."
    }

    $testCount = Read-TestCount -TrxPath $trxFile.FullName
    if ($testCount -lt 1) {
        throw "$projectName discovered zero tests for filter '$filterText'."
    }

    [pscustomobject]@{
        Project = $projectName
        Filter = $filterText
        Tests = $testCount
        TrxPath = $trxFile.FullName
    }
}

$sharedSqlContainer = $null
$previousSharedSqlConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING

Push-Location $repoRoot
try {
    if ($Mode -eq 'Coverage') {
        & (Join-Path $PSScriptRoot 'run-coverage.ps1') -Configuration $Configuration
        if ($LASTEXITCODE -ne 0) {
            throw 'Coverage mode failed.'
        }

        return
    }

    if ($Mode -eq 'Integration' -or $Mode -eq 'E2E') {
        Write-Step 'Starting shared SQL test container'
        $sharedSqlContainer = Start-AhkFlowTestSqlContainer
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $sharedSqlContainer.ConnectionString
        Write-Success ("Shared SQL test container ready in {0} ms." -f $sharedSqlContainer.ElapsedMilliseconds)
    }

    if (Test-Path -LiteralPath $resultsRoot) {
        Remove-Item -LiteralPath $resultsRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null

    $summaries = @()
    foreach ($testRun in Get-TestRuns) {
        $summaries += Invoke-TestRun -TestRun $testRun
    }

    Write-Success "$Mode test slice completed."
    $summaries | Format-Table -AutoSize
}
finally {
    $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousSharedSqlConnectionString
    if ($sharedSqlContainer) {
        Stop-AhkFlowTestSqlContainer -ContainerName $sharedSqlContainer.ContainerName
    }

    Pop-Location
}
