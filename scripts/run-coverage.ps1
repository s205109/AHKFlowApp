#Requires -Version 5.1
<#
.SYNOPSIS
  Run tests with coverage locally, generate the merged CoverageReport output, and enforce the CI coverage gate.
.DESCRIPTION
  Requires:
    dotnet tool install -g dotnet-reportgenerator-globaltool

  Output:
    TestResults/**/coverage.cobertura.xml  (per-project Cobertura)
    CoverageReport/index.html              (browsable HTML)
    CoverageReport/Cobertura.xml           (merged Cobertura read by the threshold gate)
    CoverageReport/Summary.json            (merged numeric summary)
    CoverageReport/SummaryGithub.md        (same markdown summary CI publishes)
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [switch]$SkipThresholdCheck
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$coverageReportDirectory = Join-Path $repoRoot 'CoverageReport'
$summaryJsonPath = Join-Path $coverageReportDirectory 'Summary.json'
$summaryGithubPath = Join-Path $coverageReportDirectory 'SummaryGithub.md'
$thresholdScriptPath = Join-Path $repoRoot 'scripts' 'ci' 'check-coverage-thresholds.py'
$coverageResultsRoot = Join-Path $repoRoot 'TestResults' 'coverage'
$sharedSqlScript = Join-Path $PSScriptRoot 'test-sql-container.common.ps1'
. $sharedSqlScript
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\test-run-lock.common.ps1"
. "$PSScriptRoot\coverage-inputs.common.ps1"

$testRunLock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode 'Coverage'
Push-Location $repoRoot
try {
    if (-not (Get-Command reportgenerator -ErrorAction SilentlyContinue)) {
        throw "reportgenerator command not found. Install it with: dotnet tool install -g dotnet-reportgenerator-globaltool"
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $SkipThresholdCheck -and -not $pythonCommand) {
        throw "python command not found. Install Python or rerun with -SkipThresholdCheck if you only need the HTML report."
    }

    Remove-AhkFlowCoverageArtifacts `
        -CoverageResultsRoot $coverageResultsRoot `
        -CoverageReportDirectory $coverageReportDirectory

    dotnet restore
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }

    dotnet build --configuration $Configuration `
        --disable-build-servers `
        --no-restore `
        -p:UseSharedCompilation=false
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

    Write-Step 'Starting shared SQL test container'
    $sharedSqlContainer = Start-AhkFlowTestSqlContainer
    $previousSharedSqlConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING
    $testExitCode = 0
    try {
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $sharedSqlContainer.ConnectionString
        Write-Success ("Shared SQL test container ready in {0} ms." -f $sharedSqlContainer.ElapsedMilliseconds)

        $coverageProject = Get-AhkFlowCoverageProject -RepoRoot $repoRoot
        if ($coverageProject.Count -eq 0) {
            throw "No test project in the solution references coverlet.collector. A coverage run with nothing to measure must not look green."
        }

        $expectedProjectName = @($coverageProject | ForEach-Object { $_.Name })

        foreach ($project in $coverageProject) {
            $projectName = $project.Name
            $projectResultsDirectory = Join-Path $coverageResultsRoot $projectName

            Write-Step "Collecting coverage for $projectName"
            dotnet test $project.Path --configuration $Configuration `
                --disable-build-servers `
                --no-build `
                --no-restore `
                --collect:"XPlat Code Coverage" `
                --results-directory $projectResultsDirectory `
                --settings coverlet.runsettings
            if ($LASTEXITCODE -ne 0) { $testExitCode = $LASTEXITCODE }
        }
    }
    finally {
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousSharedSqlConnectionString
        Stop-AhkFlowTestSqlContainer -ContainerName $sharedSqlContainer.ContainerName
    }

    if ($testExitCode -ne 0) { throw "dotnet test failed" }

    $missingCoverageInput = Get-AhkFlowMissingCoverageInput `
        -ResultsRoot $coverageResultsRoot `
        -ExpectedProjectName $expectedProjectName
    if ($missingCoverageInput.Count -gt 0) {
        Write-Fail 'Coverage input is incomplete. This run measured nothing for these test projects:'
        foreach ($name in $missingCoverageInput) { Write-Host "  - $name" -ForegroundColor Red }
        throw @"
$($missingCoverageInput.Count) test project(s) produced no coverage.cobertura.xml.
This is missing input, not a coverage regression. Do not read the numbers from this run.

The usual cause is a second test run in the same repository. coverlet instruments every
assembly in a test project's output folder, so another run holding one of those files makes
instrumentation fail while dotnet test still exits 0.

Make sure no other test run is active, then run this script again.
"@
    }

    reportgenerator `
        -reports:"TestResults/**/coverage.cobertura.xml" `
        -targetdir:"CoverageReport" `
        -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary;Cobertura"
    if ($LASTEXITCODE -ne 0) { throw "reportgenerator failed" }

    if ($pythonCommand) {
        $summaryFooter = & python $thresholdScriptPath --github-summary-footer
        if ($LASTEXITCODE -ne 0) { throw "Failed to generate the coverage summary footer." }

        Add-Content -Path $summaryGithubPath -Value $summaryFooter -Encoding utf8
    }

    if (-not $SkipThresholdCheck) {
        & python $thresholdScriptPath
        if ($LASTEXITCODE -ne 0) { throw "Coverage thresholds not met. See the gate output above." }
    }

    $summary = Get-Content $summaryJsonPath -Raw | ConvertFrom-Json
    Write-Host ""
    Write-Host "Line coverage   : $($summary.summary.linecoverage)%" -ForegroundColor Cyan
    Write-Host "Branch coverage : $($summary.summary.branchcoverage)%" -ForegroundColor Cyan
    Write-Host "Report          : $(Resolve-Path (Join-Path $coverageReportDirectory 'index.html'))" -ForegroundColor Cyan
    Write-Host "Cobertura       : $(Resolve-Path (Join-Path $coverageReportDirectory 'Cobertura.xml'))" -ForegroundColor Cyan
    Write-Host "Summary         : $(Resolve-Path $summaryGithubPath)" -ForegroundColor Cyan

    Write-Success 'Coverage run complete.'
}
finally {
    Pop-Location
    Exit-AhkFlowTestRunLock -Handle $testRunLock
}
