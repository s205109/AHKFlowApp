#Requires -Version 7.0

# Backlog 123. scripts/test-fast.ps1 wraps its .NET test loop in the progress module: it builds a
# tracker keyed by mode, starts and stops a unit around each project, and saves the timings when
# the loop finishes.
#
# Building trackers by hand proves the module. It does not prove the wrapper calls it. Removing
# every progress call from the Fast and Integration loops left the module suite green, so this
# suite drives scripts/test-fast.ps1 itself.
#
# The wrapper resolves its repository root from $PSScriptRoot, so it gets a repository of its own.
# Everything it dot-sources is copied in, the five Fast projects exist as empty .csproj files, and
# 'dotnet' is a stub earlier on PATH that writes the TRX file the wrapper reads. So a pass here is
# the wiring, not a real test run.
#
# Run it by hand with:  pwsh ./tests/TestFastDotnetProgress.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from the child wrapper is data here, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

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

# The five projects Fast mode runs, in the order it runs them, each with the unit label the
# wrapper builds for it. Derived from scripts/test-fast.ps1, so a change there fails this suite
# rather than quietly passing with the wrong list.
$script:FastProject = @(
    @{ Name = 'AHKFlowApp.Domain.Tests';       Label = 'AHKFlowApp.Domain.Tests' }
    @{ Name = 'AHKFlowApp.TestUtilities.Tests'; Label = 'AHKFlowApp.TestUtilities.Tests' }
    @{ Name = 'AHKFlowApp.UI.Blazor.Tests';    Label = 'AHKFlowApp.UI.Blazor.Tests' }
    @{ Name = 'AHKFlowApp.Application.Tests';  Label = 'AHKFlowApp.Application.Tests[Category!=Integration]' }
    @{ Name = 'AHKFlowApp.CLI.Tests';          Label = 'AHKFlowApp.CLI.Tests[Category!=Integration]' }
)

function New-WrapperFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('test-fast-progress-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'stub') -Force | Out-Null

    foreach ($name in @(
            'test-fast.ps1'
            'Common.ps1'
            'test-sql-container.common.ps1'
            'test-run-lock.common.ps1'
            'code-change-filter.common.ps1'
            'progress.common.ps1'
        )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\$name") -Destination (Join-Path $root "scripts\$name")
    }

    foreach ($project in $script:FastProject) {
        $folder = Join-Path (Join-Path $root 'tests') $project.Name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder "$($project.Name).csproj") `
            -Value '<Project Sdk="Microsoft.NET.Sdk" />' -Encoding utf8
    }

    # PowerShell finds a .ps1 by its bare name on PATH, and passes arguments as an array, so the
    # ';' inside the --logger value survives. A .cmd shim would split it.
    Set-Content -LiteralPath (Join-Path $root 'stub\dotnet.ps1') -Encoding utf8 -Value @'
$resultsDirectory = $null
$logFileName = 'stub.trx'
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '--results-directory' -and $i + 1 -lt $args.Count) {
        $resultsDirectory = $args[$i + 1]
    }
    if ($args[$i] -eq '--logger' -and $i + 1 -lt $args.Count -and $args[$i + 1] -match 'LogFileName=(.+)$') {
        $logFileName = $Matches[1]
    }
}

if ($resultsDirectory) {
    New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
    $trx = '<?xml version="1.0" encoding="UTF-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><ResultSummary><Counters total="1" passed="1" failed="0" /></ResultSummary></TestRun>'
    Set-Content -LiteralPath (Join-Path $resultsDirectory $logFileName) -Value $trx -Encoding utf8
}

Write-Output 'stub dotnet test'
exit 0
'@

    return $root
}

function Remove-WrapperFixture {
    param([string] $Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-FastMode {
    param([Parameter(Mandatory)][string] $Root)

    $previousPath = $env:PATH
    $env:PATH = (Join-Path $Root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
    try {
        $output = & $hostExe -NoProfile -File (Join-Path $Root 'scripts\test-fast.ps1') -Mode Fast -NoBuild 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $env:PATH = $previousPath
    }
}

Write-Host "Testing $(Join-Path $repoRoot 'scripts\test-fast.ps1')"

Invoke-TestCase 'Fast mode prints a progress line for every project it runs' {
    $root = New-WrapperFixture
    try {
        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $position = 0
        foreach ($project in $script:FastProject) {
            $position++
            $pattern = "\[$position/5\] " + [regex]::Escape($project.Label)
            Assert-True ($result.Output -match $pattern) `
                "Expected a progress line '[$position/5] $($project.Label)'. Output: $($result.Output)"
        }
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode saves its timings under the key for its own mode' {
    $root = New-WrapperFixture
    try {
        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $historyPath = Join-Path $root 'TestResults\progress\test-fast.Fast.json'
        Assert-True (Test-Path -LiteralPath $historyPath -PathType Leaf) `
            "Expected saved timings at $historyPath. Output: $($result.Output)"

        $saved = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
        foreach ($project in $script:FastProject) {
            Assert-True ($null -ne $saved.PSObject.Properties[$project.Label]) `
                "Expected saved seconds for '$($project.Label)', got: $(($saved.PSObject.Properties.Name) -join ', ')"
        }

        # The key carries the mode, so an Integration run cannot read a Fast estimate.
        $integrationPath = Join-Path $root 'TestResults\progress\test-fast.Integration.json'
        Assert-True (-not (Test-Path -LiteralPath $integrationPath)) `
            'A Fast run must not write the Integration timings file.'
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode reads last run timings back as an estimate' {
    $root = New-WrapperFixture
    try {
        Invoke-FastMode -Root $root | Out-Null
        $result = Invoke-FastMode -Root $root

        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'remaining ~') `
            "The second run must estimate the time left from the first run's timings. Output: $($result.Output)"
        Assert-True (-not ($result.Output -match 'no history')) `
            "The second run must not report missing history. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
}

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'test-fast .NET progress wiring tests passed.' -ForegroundColor Green
