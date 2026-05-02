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
$thresholdScriptPath = Join-Path $repoRoot 'scripts' 'check-coverage-thresholds.py'

Push-Location $repoRoot
try {
    if (-not (Get-Command reportgenerator -ErrorAction SilentlyContinue)) {
        throw "reportgenerator command not found. Install it with: dotnet tool install -g dotnet-reportgenerator-globaltool"
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $SkipThresholdCheck -and -not $pythonCommand) {
        throw "python command not found. Install Python or rerun with -SkipThresholdCheck if you only need the HTML report."
    }

    if (Test-Path TestResults)   { Remove-Item -Recurse -Force TestResults }
    if (Test-Path $coverageReportDirectory) { Remove-Item -Recurse -Force $coverageReportDirectory }

    dotnet test --configuration $Configuration `
        --disable-build-servers `
        --collect:"XPlat Code Coverage" `
        --results-directory TestResults `
        -p:UseSharedCompilation=false `
        --settings coverlet.runsettings
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

    reportgenerator `
        -reports:"TestResults/**/coverage.cobertura.xml" `
        -targetdir:"CoverageReport" `
        -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary;Cobertura"
    if ($LASTEXITCODE -ne 0) { throw "reportgenerator failed" }

    if ($pythonCommand) {
        $summaryFooter = & python $thresholdScriptPath --github-summary-footer
        if ($LASTEXITCODE -ne 0) { throw "Failed to generate the coverage summary footer." }

        Add-Content -Path $summaryGithubPath -Value $summaryFooter
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
}
finally {
    Pop-Location
}
