#Requires -Version 7.0
<#
.SYNOPSIS
  Run tests with coverage locally and generate HTML + JSON summary matching CI.
.DESCRIPTION
  Requires: dotnet tool install -g dotnet-reportgenerator-globaltool
  Output:
    TestResults/**/coverage.cobertura.xml  (per-project Cobertura)
    coverage-report/index.html             (browsable HTML)
    coverage-report/Summary.json           (same shape CI gates on)
    coverage-report/SummaryGithub.md       (same markdown CI comments)
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (Test-Path TestResults)   { Remove-Item -Recurse -Force TestResults }
    if (Test-Path coverage-report) { Remove-Item -Recurse -Force coverage-report }

    dotnet test --configuration $Configuration `
        --collect:"XPlat Code Coverage" `
        --results-directory TestResults `
        --settings coverlet.runsettings
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

    reportgenerator `
        -reports:"TestResults/**/coverage.cobertura.xml" `
        -targetdir:"coverage-report" `
        -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary"
    if ($LASTEXITCODE -ne 0) { throw "reportgenerator failed" }

    $summary = Get-Content coverage-report/Summary.json | ConvertFrom-Json
    Write-Host ""
    Write-Host "Line coverage   : $($summary.summary.linecoverage)%" -ForegroundColor Cyan
    Write-Host "Branch coverage : $($summary.summary.branchcoverage)%" -ForegroundColor Cyan
    Write-Host "Report          : $(Resolve-Path coverage-report/index.html)" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
