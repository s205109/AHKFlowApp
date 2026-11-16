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
    [switch]$SkipThresholdCheck,

    # Backlog 204. How many coverage Slices run at once: a whole number of at least 1, or Budget.
    # The value never goes above the Lanes this run holds. 1 keeps the projects in sequence.
    [string]$SlicesAtOnce = '1',

    # Backlog 204. Runs the E2E project alone, after every other Slice has ended.
    [switch]$E2ELast
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
. "$PSScriptRoot\test-lanes.common.ps1"
. "$PSScriptRoot\coverage-inputs.common.ps1"
. "$PSScriptRoot\progress.common.ps1"
. "$PSScriptRoot\test-results.common.ps1"
. "$PSScriptRoot\progress.parallel.ps1"
. "$PSScriptRoot\slice-runner.common.ps1"

$laneRun = $null
$testRunLock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode 'Coverage'
Push-Location $repoRoot
try {
    $laneRun = Enter-AhkFlowLaneRun -Mode 'Coverage' -Checkout $repoRoot -Share Half
    $sliceCount = Resolve-AhkFlowSlicesAtOnce -Requested $SlicesAtOnce -Budget (Get-AhkFlowSliceBudget -LaneRun $laneRun)
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

    # The old results are gone, and this run holds the lock. So a measured run can tell that the
    # results it finds afterwards are its own (backlog 204).
    New-Item -ItemType Directory -Path $coverageResultsRoot -Force | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_RUN_ATTEMPT)) {
        [System.IO.File]::WriteAllText((Join-Path $coverageResultsRoot 'attempt.txt'), $env:AHKFLOW_RUN_ATTEMPT)
    }

    # Read before any work starts, because the progress tracker below needs the whole unit list
    # up front. The read runs 'dotnet sln list' and reads each .csproj as text, so it needs
    # neither the restore nor the build. Reading it here also fails a solution with nothing to
    # measure before the run spends minutes on a restore, a build, and a container.
    $coverageProject = Get-AhkFlowCoverageProject -RepoRoot $repoRoot
    if ($coverageProject.Count -eq 0) {
        throw "No test project in the solution references coverlet.collector. A coverage run with nothing to measure must not look green."
    }

    $e2eProjectName = 'AHKFlowApp.E2E.Tests'
    if ($E2ELast -and @($coverageProject | Where-Object { $_.Name -eq $e2eProjectName }).Count -eq 0) {
        throw "-E2ELast needs the $e2eProjectName project, and the solution has no such coverage project."
    }

    $expectedProjectName = @($coverageProject | ForEach-Object { $_.Name })

    # A mixed unit list: three fixed phases, one unit per coverage project, then one fixed phase.
    # The project part is read at run time, so adding a test project adds a unit by itself.
    $progressUnit = @('restore', 'build', 'sql container') + $expectedProjectName + @('report')
    $progress = New-ProgressTracker -RunnerKey 'run-coverage' -RepoRoot $repoRoot -Unit $progressUnit

    Start-ProgressUnit -Tracker $progress -Name 'restore'
    dotnet restore
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
    Stop-ProgressUnit -Tracker $progress

    Start-ProgressUnit -Tracker $progress -Name 'build'
    dotnet build --configuration $Configuration `
        --disable-build-servers `
        --no-restore `
        -p:UseSharedCompilation=false
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
    Stop-ProgressUnit -Tracker $progress

    # The unit covers the start only, and on a reused container that is a fraction of a second.
    # The container stays up for the whole project loop and past the end of this run: coverage
    # shares one container per checkout with scripts/test-fast.ps1, and both hold the test-run
    # lock, so they never prepare it at the same time.
    Start-ProgressUnit -Tracker $progress -Name 'sql container'
    $sharedSqlContainer = Start-AhkFlowTestSqlContainer -RepoRoot $repoRoot
    Stop-ProgressUnit -Tracker $progress

    $previousSharedSqlConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING
    $sliceResult = @()
    try {
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $sharedSqlContainer.ConnectionString
        Write-Success ("Shared SQL test container ready in {0} ms." -f $sharedSqlContainer.ElapsedMilliseconds)

        # One Slice per project. The working directory is the repository root, because
        # coverlet.runsettings is a relative path and a child process does not follow Push-Location.
        $slices = @(foreach ($project in $coverageProject) {
                $projectResultsDirectory = Join-Path $coverageResultsRoot $project.Name
                New-AhkFlowSlice -Name $project.Name -Command 'dotnet' -LogPath (Join-Path $projectResultsDirectory "$($project.Name).log") -Argument @(
                    'test', $project.Path,
                    '--configuration', $Configuration,
                    '--disable-build-servers',
                    '--no-build',
                    '--no-restore',
                    '--collect:XPlat Code Coverage',
                    '--results-directory', $projectResultsDirectory,
                    '--settings', 'coverlet.runsettings',
                    '--logger', "trx;LogFileName=$($project.Name).trx")
            })
        $ordered = @(Get-AhkFlowSliceOrder -Slice $slices -History $progress.History -SlicesAtOnce $sliceCount)

        # Every Slice runs to the end, whatever another one's exit code. With -E2ELast the E2E
        # Slice runs alone, after the others.
        $groups = @(, $ordered)
        if ($E2ELast) {
            $groups = @(
                , @($ordered | Where-Object { $_.Name -ne $e2eProjectName })
                , @($ordered | Where-Object { $_.Name -eq $e2eProjectName }))
        }
        $atOnce = $sliceCount
        foreach ($group in $groups) {
            if (@($group).Count -gt 0) {
                $sliceResult += @(Invoke-AhkFlowSliceSet -Slice $group -SlicesAtOnce $atOnce -WorkingDirectory $repoRoot -Tracker $progress)
            }
            $atOnce = 1
        }
    }
    finally {
        # Left running on purpose, the same way scripts/test-fast.ps1 leaves it.
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousSharedSqlConnectionString
    }

    # Saved before any check below can throw, so a measured run can read every Slice's result.
    Save-AhkFlowSliceResult -Result $sliceResult -Path (Join-Path $coverageResultsRoot 'slices.json')

    # Every problem is collected first, in this order, and thrown together (D16). A failing test
    # still gets the missing-input check and, when every input is there, the report.
    $problem = New-Object System.Collections.Generic.List[string]
    $failingSlice = @($sliceResult | Where-Object { $_.ExitCode -ne 0 })
    if ($failingSlice.Count -gt 0) {
        $problem.Add("dotnet test failed for: $(($failingSlice | ForEach-Object { $_.Name }) -join ', ').")
    }
    $emptySlice = @($sliceResult | Where-Object {
            $_.ExitCode -eq 0 -and (Get-AhkFlowTestCountFromResults -ResultsDirectory (Split-Path -Parent $_.LogPath)) -lt 1
        })
    foreach ($slice in $emptySlice) {
        $problem.Add("$($slice.Name) discovered zero tests. Either no test ran, or its TRX file could not be read.")
    }

    $missingCoverageInput = Get-AhkFlowMissingCoverageInput `
        -ResultsRoot $coverageResultsRoot `
        -ExpectedProjectName $expectedProjectName
    if ($missingCoverageInput.Count -gt 0) {
        Write-Fail 'Coverage input is incomplete. This run measured nothing for these test projects:'
        foreach ($name in $missingCoverageInput) { Write-Host "  - $name" -ForegroundColor Red }
        $problem.Add(@"
$($missingCoverageInput.Count) test project(s) produced no coverage.cobertura.xml.
This is missing input, not a coverage regression. Do not read the numbers from this run.

The usual cause is a second test run in the same repository. coverlet instruments every
assembly in a test project's output folder, so another run holding one of those files makes
instrumentation fail while dotnet test still exits 0.

Make sure no other test run is active, then run this script again.
"@)
    }
    else {
        Start-ProgressUnit -Tracker $progress -Name 'report'
        reportgenerator `
            -reports:"$coverageResultsRoot/**/coverage.cobertura.xml" `
            -targetdir:"CoverageReport" `
            -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary;Cobertura"
        if ($LASTEXITCODE -ne 0) { $problem.Add('reportgenerator failed') }
        Stop-ProgressUnit -Tracker $progress
    }

    # The logs of the failing and empty Slices are printed, then every problem is thrown. The
    # timing save, the summary footer and the threshold check do not run (D16).
    if ($problem.Count -gt 0) {
        Write-AhkFlowSliceLog -Result @($failingSlice + $emptySlice)
        throw ($problem.ToArray() -join [Environment]::NewLine)
    }

    # Saved here, not at the very end. The threshold gate below can fail the run, and the seconds
    # this run measured are still true when it does. -KnownUnit drops a stored project that the
    # solution no longer has.
    Save-ProgressTimings -Tracker $progress -KnownUnit $progressUnit

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
    Exit-AhkFlowLaneRun -State $laneRun
    Exit-AhkFlowTestRunLock -Handle $testRunLock
}
