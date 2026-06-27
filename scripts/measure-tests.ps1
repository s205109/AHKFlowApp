#Requires -Version 5.1
<#
.SYNOPSIS
  Measure test project, class, test, and SQL fixture setup timings.
.DESCRIPTION
  Runs selected test projects with TRX logging and records wall-clock timings.
  SQL fixture setup timings are captured when test fixtures honor
  AHKFLOW_TEST_TIMING=1 and write JSONL entries under TestResults.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string[]]$Project,
    [string]$Filter,
    [int]$Top = 10
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot 'tests'
$resultsRoot = Join-Path $repoRoot 'TestResults\measure-tests'
$summaryPath = Join-Path $resultsRoot 'summary.json'
$sharedSqlScript = Join-Path $PSScriptRoot 'test-sql-container.common.ps1'
. $sharedSqlScript

$sharedSqlTestProjects = @(
    'AHKFlowApp.API.Tests',
    'AHKFlowApp.Application.Tests',
    'AHKFlowApp.CLI.Tests',
    'AHKFlowApp.Infrastructure.Tests'
)

function Resolve-TestProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $candidate = $Value
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $repoRoot $candidate
    }

    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $projectFile = Get-ChildItem -LiteralPath $candidate -Filter '*.csproj' | Select-Object -First 1
        if (-not $projectFile) {
            throw "No .csproj file found in $candidate."
        }

        return $projectFile.FullName
    }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "Project path not found: $Value"
}

function Get-DefaultTestProjects {
    Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.csproj' |
        Where-Object { $_.BaseName.EndsWith('.Tests', [System.StringComparison]::Ordinal) } |
        Sort-Object FullName |
        ForEach-Object { $_.FullName }
}

function Test-UsesSharedSqlFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProjectPaths
    )

    foreach ($projectPath in $ProjectPaths) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)
        if ($sharedSqlTestProjects -contains $projectName) {
            return $true
        }
    }

    return $false
}

function Get-BuildArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    $projectDirectory = Split-Path -Parent $ProjectPath
    $outputRoot = Join-Path $projectDirectory "bin\$Configuration"
    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $outputRoot -Recurse -Filter "$ProjectName.dll" -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        Select-Object -First 1
}

function Convert-TrxDuration {
    param(
        [string]$Duration
    )

    if ([string]::IsNullOrWhiteSpace($Duration)) {
        return 0.0
    }

    return [System.TimeSpan]::Parse($Duration, [System.Globalization.CultureInfo]::InvariantCulture).TotalMilliseconds
}

function Read-TrxResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw
    $unitTests = $trx.GetElementsByTagName('UnitTest')
    $unitTestResults = $trx.GetElementsByTagName('UnitTestResult')
    $testClassesById = @{}

    foreach ($unitTest in $unitTests) {
        $testId = $unitTest.id
        $testMethod = $unitTest.GetElementsByTagName('TestMethod') | Select-Object -First 1
        if ($testId -and $testMethod) {
            $testClassesById[$testId] = $testMethod.className
        }
    }

    $results = @()
    foreach ($result in $unitTestResults) {
        $className = $testClassesById[$result.testId]
        if ([string]::IsNullOrWhiteSpace($className)) {
            $className = '(unknown)'
        }

        $results += [pscustomobject]@{
            Project = $ProjectName
            Class = $className
            Test = $result.testName
            Outcome = $result.outcome
            DurationMilliseconds = [math]::Round((Convert-TrxDuration -Duration $result.duration), 3)
        }
    }

    return $results
}

function Read-FixtureTimingEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FixtureTimingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    if (-not (Test-Path -LiteralPath $FixtureTimingDirectory -PathType Container)) {
        return @()
    }

    $entries = @()
    $timingFiles = Get-ChildItem -LiteralPath $FixtureTimingDirectory -Filter 'fixture-timings-*.jsonl' -ErrorAction SilentlyContinue
    foreach ($timingFile in $timingFiles) {
        foreach ($line in Get-Content -LiteralPath $timingFile.FullName) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $entry = $line | ConvertFrom-Json
            $entries += [pscustomobject]@{
                Project = $ProjectName
                TestAssembly = $entry.testAssembly
                Component = $entry.component
                Fixture = $entry.fixture
                Operation = $entry.operation
                ElapsedMilliseconds = [math]::Round([double]$entry.elapsedMilliseconds, 3)
                TimestampUtc = $entry.timestampUtc
            }
        }
    }

    return $entries
}

function Write-Ranking {
    param(
        [string]$Title,
        [object[]]$Rows,
        [string[]]$Property
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host '  (none)'
        return
    }

    $Rows | Select-Object -First $Top -Property $Property | Format-Table -AutoSize
}

$sharedSqlContainer = $null
$sharedSqlTiming = $null
$previousSharedSqlConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING

Push-Location $repoRoot
try {
    if ($Top -lt 1) {
        throw '-Top must be 1 or greater.'
    }

    if ($Project -and $Project.Count -gt 0) {
        $projectPaths = $Project | ForEach-Object { Resolve-TestProjectPath -Value $_ }
    }
    else {
        $projectPaths = Get-DefaultTestProjects
    }

    if (-not $projectPaths -or $projectPaths.Count -eq 0) {
        throw 'No test projects selected.'
    }

    if (Test-Path -LiteralPath $resultsRoot) {
        Remove-Item -LiteralPath $resultsRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $resultsRoot | Out-Null

    $warnings = @()
    $projectSummaries = @()
    $testResults = @()
    $fixtureTimings = @()

    if (Test-UsesSharedSqlFixture -ProjectPaths $projectPaths) {
        Write-Host 'Starting shared SQL test container...' -ForegroundColor Cyan
        $sharedSqlContainer = Start-AhkFlowTestSqlContainer
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $sharedSqlContainer.ConnectionString
        $sharedSqlTiming = [pscustomobject]@{
            Project = '(shared)'
            TestAssembly = $null
            Component = 'SharedSqlContainer'
            Fixture = 'scripts/test-sql-container.common.ps1'
            Operation = 'StartAsync'
            ElapsedMilliseconds = $sharedSqlContainer.ElapsedMilliseconds
            TimestampUtc = $sharedSqlContainer.StartedAtUtc
        }
        $fixtureTimings += $sharedSqlTiming
        Write-Host ("Shared SQL test container ready in {0} ms." -f $sharedSqlContainer.ElapsedMilliseconds) -ForegroundColor Cyan
    }

    foreach ($projectPath in $projectPaths) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)
        $projectResultsDirectory = Join-Path $resultsRoot $projectName
        $fixtureTimingDirectory = Join-Path $projectResultsDirectory 'fixture-timing'

        New-Item -ItemType Directory -Path $projectResultsDirectory | Out-Null

        $artifact = Get-BuildArtifact -ProjectPath $projectPath -ProjectName $projectName
        if (-not $artifact) {
            $warnings += "Missing build artifact for $projectName. Run: dotnet build $projectPath --configuration $Configuration"
            continue
        }

        Write-Host "Measuring $projectName..." -ForegroundColor Cyan

        $previousTiming = $env:AHKFLOW_TEST_TIMING
        $previousTimingDirectory = $env:AHKFLOW_TEST_TIMING_DIR
        $env:AHKFLOW_TEST_TIMING = '1'
        $env:AHKFLOW_TEST_TIMING_DIR = $fixtureTimingDirectory

        $arguments = @(
            'test',
            $projectPath,
            '--configuration',
            $Configuration,
            '--no-build',
            '--no-restore',
            '--logger',
            "trx;LogFileName=$projectName.trx",
            '--results-directory',
            $projectResultsDirectory
        )

        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $arguments += @('--filter', $Filter)
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & dotnet @arguments
            $exitCode = $LASTEXITCODE
        }
        finally {
            $stopwatch.Stop()
            $env:AHKFLOW_TEST_TIMING = $previousTiming
            $env:AHKFLOW_TEST_TIMING_DIR = $previousTimingDirectory
        }

        if ($exitCode -ne 0) {
            throw "dotnet test failed for $projectName with exit code $exitCode."
        }

        $trxFile = Get-ChildItem -LiteralPath $projectResultsDirectory -Recurse -Filter '*.trx' |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1

        if (-not $trxFile) {
            throw "No TRX file was produced for $projectName."
        }

        $projectTestResults = @(Read-TrxResults -TrxPath $trxFile.FullName -ProjectName $projectName)
        $projectFixtureTimings = @(Read-FixtureTimingEntries -FixtureTimingDirectory $fixtureTimingDirectory -ProjectName $projectName)
        $summedTestMilliseconds = ($projectTestResults | Measure-Object -Property DurationMilliseconds -Sum).Sum
        if ($null -eq $summedTestMilliseconds) {
            $summedTestMilliseconds = 0
        }

        if ($projectTestResults.Count -eq 0) {
            $warnings += "Zero tests were discovered for $projectName."
        }

        $testResults += $projectTestResults
        $fixtureTimings += $projectFixtureTimings

        $projectSummaries += [pscustomobject]@{
            Project = $projectName
            Tests = $projectTestResults.Count
            WallClockMilliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            SummedTestMilliseconds = [math]::Round([double]$summedTestMilliseconds, 3)
            UnattributedSetupMilliseconds = [math]::Round(($stopwatch.Elapsed.TotalMilliseconds - [double]$summedTestMilliseconds), 3)
            FixtureTimingEntries = $projectFixtureTimings.Count
            TrxPath = $trxFile.FullName
        }
    }

    $classRankings = @(
        $testResults |
            Group-Object Project, Class |
            ForEach-Object {
                $first = $_.Group | Select-Object -First 1
                [pscustomobject]@{
                    Project = $first.Project
                    Class = $first.Class
                    Tests = $_.Count
                    DurationMilliseconds = [math]::Round(($_.Group | Measure-Object -Property DurationMilliseconds -Sum).Sum, 3)
                }
            } |
            Sort-Object DurationMilliseconds -Descending
    )

    $slowTests = @($testResults | Sort-Object DurationMilliseconds -Descending)
    $slowFixtures = @($fixtureTimings | Sort-Object ElapsedMilliseconds -Descending)

    $sharedSqlStartupMilliseconds = $null
    if ($sharedSqlTiming) {
        $sharedSqlStartupMilliseconds = $sharedSqlTiming.ElapsedMilliseconds
    }

    $summary = [pscustomobject]@{
        GeneratedAtUtc = [DateTimeOffset]::UtcNow
        Configuration = $Configuration
        Filter = $Filter
        SharedSqlStartupMilliseconds = $sharedSqlStartupMilliseconds
        Projects = $projectSummaries
        SlowClasses = $classRankings | Select-Object -First $Top
        SlowTests = $slowTests | Select-Object -First $Top
        FixtureTimings = $slowFixtures | Select-Object -First $Top
        Warnings = $warnings
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

    Write-Ranking -Title 'Project wall-clock timings' -Rows ($projectSummaries | Sort-Object WallClockMilliseconds -Descending) -Property @(
        'Project',
        'Tests',
        'WallClockMilliseconds',
        'SummedTestMilliseconds',
        'UnattributedSetupMilliseconds',
        'FixtureTimingEntries'
    )

    Write-Ranking -Title 'Slowest classes by summed TRX duration' -Rows $classRankings -Property @(
        'Project',
        'Class',
        'Tests',
        'DurationMilliseconds'
    )

    Write-Ranking -Title 'Slowest tests by TRX duration' -Rows $slowTests -Property @(
        'Project',
        'Class',
        'Test',
        'Outcome',
        'DurationMilliseconds'
    )

    Write-Ranking -Title 'Slowest fixture/setup timings' -Rows $slowFixtures -Property @(
        'Project',
        'Component',
        'Fixture',
        'Operation',
        'ElapsedMilliseconds'
    )

    if ($warnings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Warnings' -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }

        throw "Measurement completed with $($warnings.Count) warning(s)."
    }

    Write-Host ''
    Write-Host "Summary written to $summaryPath" -ForegroundColor Cyan
}
finally {
    $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousSharedSqlConnectionString
    if ($sharedSqlContainer) {
        Stop-AhkFlowTestSqlContainer -ContainerName $sharedSqlContainer.ContainerName
    }

    Pop-Location
}
