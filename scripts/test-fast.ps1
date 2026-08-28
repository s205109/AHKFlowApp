#Requires -Version 5.1
<#
.SYNOPSIS
  Run explicit local test slices for fast, integration, E2E, or coverage workflows.
.DESCRIPTION
  Fast mode runs whole-project fast suites plus non-integration slices from mixed projects.
  Integration mode runs integration slices from mixed projects plus whole-project SQL/API suites.
  PowerShell mode runs every tests/*.Tests.ps1 suite through scripts/run-powershell-suites.ps1.
  It ignores -Configuration and -NoBuild, because PowerShell suites are not built.
  Each selected test project must discover at least one test.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Integration', 'E2E', 'Coverage', 'PowerShell')]
    [string]$Mode = 'Fast',

    [string]$Configuration = 'Release',

    [switch]$NoBuild,

    # Coverage mode only. Runs the slice even when the filter excludes every changed path.
    [switch]$Force,

    # PowerShell mode only. Forwarded to run-powershell-suites.ps1 so a test can point the mode at a
    # folder of fake suites. Empty means the runner picks its own default of tests/.
    #
    # This goes last on purpose. An unattributed parameter takes an implicit position in declaration
    # order, and switches take none, so putting it here leaves $Mode at position 0 and
    # $Configuration at position 1. Put it above $Configuration instead and 'test-fast.ps1 Fast
    # Debug' silently binds Debug to $SuiteRoot while $Configuration stays Release.
    [string]$SuiteRoot,

    # Coverage mode only. The ref the changed-file check diffs against. Empty means: ask the
    # pull request for its base, then fall back to origin/main.
    #
    # This goes last for the same reason $SuiteRoot does. An unattributed parameter takes an
    # implicit position in declaration order, so putting it any earlier would silently rebind
    # 'test-fast.ps1 Fast Debug'.
    [string]$BaseRef
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$resultsRoot = Join-Path $repoRoot "TestResults\test-fast\$Mode"
$sharedSqlScript = Join-Path $PSScriptRoot 'test-sql-container.common.ps1'
. $sharedSqlScript
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\test-run-lock.common.ps1"
. "$PSScriptRoot\code-change-filter.common.ps1"

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
$testRunLock = $null
$previousSharedSqlConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING

Push-Location $repoRoot
try {
    if ($Mode -eq 'Coverage') {
        if (-not $Force) {
            # A decision that cannot be made is never a skip. Anything that goes wrong here -
            # a git failure, a missing filter file, a pattern the matcher cannot read - runs
            # the slice and prints the reason.
            $decision = $null
            try {
                $decision = Get-AhkFlowCoverageDecision -RepoRoot $repoRoot -BaseRef $BaseRef
            }
            catch {
                Write-Warn "Cannot decide whether this branch changed compiled code, so the coverage slice will run."
                Write-Warn $_.Exception.Message
            }

            if ($decision -and -not $decision.CoverageRequired) {
                Write-AhkFlowCoverageSkipReport -Decision $decision
                return
            }
        }

        & (Join-Path $PSScriptRoot 'run-coverage.ps1') -Configuration $Configuration
        if ($LASTEXITCODE -ne 0) {
            throw 'Coverage mode failed.'
        }

        return
    }

    if ($Mode -eq 'PowerShell') {
        $suiteArguments = @{}
        if (-not [string]::IsNullOrWhiteSpace($SuiteRoot)) {
            $suiteArguments['SuiteRoot'] = $SuiteRoot
        }

        & (Join-Path $PSScriptRoot 'run-powershell-suites.ps1') @suiteArguments
        if ($LASTEXITCODE -ne 0) {
            throw 'PowerShell suites failed.'
        }

        return
    }

    $testRunLock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode $Mode

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

    Exit-AhkFlowTestRunLock -Handle $testRunLock
    Pop-Location
}
