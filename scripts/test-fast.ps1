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
. "$PSScriptRoot\progress.common.ps1"
. "$PSScriptRoot\test-results.common.ps1"

function Get-ProgressUnitLabel {
    param([Parameter(Mandatory = $true)][object]$TestRun)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($TestRun.Project)
    if (-not [string]::IsNullOrWhiteSpace($TestRun.Filter)) {
        return "$name[$($TestRun.Filter)]"
    }

    return $name
}

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
        # Get-FastAssembly reads this list and turns each project into its built assembly, so
        # this stays the only place the Fast project list is written down.
        #
        # Every entry states its filter, including the three that never needed one. The combined
        # call applies a single filter to all five assemblies, and 'Category!=Integration' keeps
        # a test carrying no Category trait, so those three lose nothing: the combined run still
        # found all 2939 tests. Writing it out is what lets Get-FastAssembly refuse a project
        # that disagrees, instead of quietly extending one project's filter over another's tests.
        'Fast' {
            return @(
                New-TestRun -Project 'tests\AHKFlowApp.Domain.Tests\AHKFlowApp.Domain.Tests.csproj' -Filter 'Category!=Integration'
                New-TestRun -Project 'tests\AHKFlowApp.TestUtilities.Tests\AHKFlowApp.TestUtilities.Tests.csproj' -Filter 'Category!=Integration'
                New-TestRun -Project 'tests\AHKFlowApp.UI.Blazor.Tests\AHKFlowApp.UI.Blazor.Tests.csproj' -Filter 'Category!=Integration'
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

function Get-FastAssembly {
    <#
      The Fast assemblies and the one filter the combined call applies to all of them.

      The project list is not repeated here. It comes from Get-TestRuns, which stays the single
      place that records which projects Fast covers and what filter each one takes. This function
      only turns each .csproj path into the .dll the build produced from it.

      All five Fast entries now carry 'Category!=Integration' explicitly, and Step 2b is what puts
      it on the three that had no filter before. Applying it to them is safe, and that was checked
      rather than assumed: the filter keeps a test carrying no Category trait at all, and a
      combined run over these five returned 2939 tests, the same total the five separate calls
      found.

      Writing it out on all five is what makes the throw below a real guard. An earlier draft
      dropped the empty filters before checking, so a project with no filter silently inherited
      another project's filter and only a second *non-empty* filter was caught. Now every entry
      must say what it means, and any disagreement stops the run.

      'net10.0' is written out rather than read from Directory.Build.props. A framework bump is a
      once-a-year edit that already touches that file and global.json, and a grep for 'net10.0'
      finds this line. Reading the XML here would mean parsing it under PowerShell 5.1, which this
      script still supports. The failure is loud either way: the caller names the missing path.
    #>
    $testRuns = @(Get-TestRuns)

    $missing = @($testRuns | Where-Object { [string]::IsNullOrWhiteSpace($_.Filter) })
    if ($missing.Count -gt 0) {
        $names = @($missing | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Project) })
        throw "Every Fast project must state its filter, these do not: $($names -join ', ')"
    }

    $filters = @($testRuns | ForEach-Object { $_.Filter } | Sort-Object -Unique)
    if ($filters.Count -ne 1) {
        throw "The combined Fast call needs exactly one filter, found $($filters.Count): $($filters -join ', ')"
    }

    $assembly = @($testRuns | ForEach-Object {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Project)
        Join-Path (Split-Path -Parent $_.Project) "bin\$Configuration\net10.0\$name.dll"
    })

    return [pscustomobject]@{
        Assembly = $assembly
        Filter = $filters[0]
    }
}

function Get-TestCountByAssembly {
    <#
      Splits one combined TRX into per-assembly result counts.

      A combined run writes one TRX for every assembly it ran. The assembly name is not on the
      result: it is on the TestMethod element inside TestDefinitions, as the 'codeBase'
      attribute. Counting TestDefinitions is not the same as counting results, because theory
      rows with the same display name collapse into one definition. So this joins each
      UnitTestResult to its definition through the test id, and counts results.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath
    )

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw

    $assemblyByTestId = @{}
    foreach ($unitTest in $trx.GetElementsByTagName('UnitTest')) {
        $testMethod = $unitTest.GetElementsByTagName('TestMethod') | Select-Object -First 1
        if (-not $testMethod) { continue }
        $codeBase = $testMethod.codeBase
        if ([string]::IsNullOrWhiteSpace($codeBase)) { continue }
        $assemblyByTestId[$unitTest.id] = [System.IO.Path]::GetFileNameWithoutExtension($codeBase)
    }

    $counts = @{}
    foreach ($result in $trx.GetElementsByTagName('UnitTestResult')) {
        $name = $assemblyByTestId[$result.testId]
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (-not $counts.ContainsKey($name)) { $counts[$name] = 0 }
        $counts[$name]++
    }

    return $counts
}

function Invoke-CombinedTestRun {
    <#
      Runs several built test assemblies in one 'dotnet test' call.

      One call instead of five removes four MSBuild evaluations of the whole project graph. The
      caller must have built already: passing assembly paths means dotnet builds nothing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Assembly,

        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    foreach ($path in $Assembly) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Test assembly not found: $path. Build the solution first, or drop -NoBuild."
        }
    }

    $combinedResultsDirectory = Join-Path $resultsRoot 'combined'
    New-Item -ItemType Directory -Path $combinedResultsDirectory -Force | Out-Null

    $arguments = @('test') + $Assembly + @(
        '--logger',
        'trx;LogFileName=combined.trx',
        '--results-directory',
        $combinedResultsDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        $arguments += @('--filter', $Filter)
    }

    $filterText = if ([string]::IsNullOrWhiteSpace($Filter)) { 'all tests' } else { $Filter }
    Write-Step "Running $($Assembly.Count) assemblies in one call ($filterText)"
    & dotnet @arguments 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "dotnet test failed for $Label."
    }

    $trxPath = Join-Path $combinedResultsDirectory 'combined.trx'
    if (-not (Test-Path -LiteralPath $trxPath -PathType Leaf)) {
        throw "No TRX file was produced for $Label."
    }

    # The zero-test guard, kept. One assembly discovering nothing is what catches a filter typo,
    # and a combined run would otherwise hide it behind the other four.
    $counts = Get-TestCountByAssembly -TrxPath $trxPath
    $summaries = @()
    foreach ($path in $Assembly) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $count = 0
        if ($counts.ContainsKey($name)) { $count = $counts[$name] }

        $summaries += New-AhkFlowTestSummary -Project $name -Filter $filterText -Tests $count -TrxPath $trxPath
    }

    return $summaries
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

    $trxPath = Get-AhkFlowLatestTrxPath -ResultsDirectory $projectResultsDirectory
    if (-not $trxPath) {
        throw "No TRX file was produced for $projectName."
    }

    New-AhkFlowTestSummary `
        -Project $projectName `
        -Filter $filterText `
        -Tests (Get-AhkFlowTestCount -TrxPath $trxPath) `
        -TrxPath $trxPath
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
        # The runner needs PowerShell 7, because it runs the suites through ForEach-Object
        # -Parallel. This wrapper still supports Windows PowerShell 5.1, and a '#Requires' in a
        # script called in-process is enforced against the running host. So the runner always goes
        # into a pwsh child process: calling it here would fail on 5.1 before a suite started.
        $runnerHost = if ($PSVersionTable.PSVersion.Major -ge 7) {
            [System.Diagnostics.Process]::GetCurrentProcess().Path
        }
        else {
            $found = @(Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) {
                throw 'PowerShell mode needs pwsh (PowerShell 7). Install it, or start this script with pwsh.'
            }
            $found[0].Source
        }

        $suiteArguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'run-powershell-suites.ps1'))
        if (-not [string]::IsNullOrWhiteSpace($SuiteRoot)) {
            $suiteArguments += @('-SuiteRoot', $SuiteRoot)
        }

        # PowerShell 7.4 turns a non-zero exit code from a native command into a terminating error
        # while $ErrorActionPreference is 'Stop'. The runner exits 1 for a failing suite, and that
        # is data the check below reports. The variable does not exist in 5.1, where setting it is
        # harmless. Windows PowerShell has no equivalent behaviour to opt out of.
        $PSNativeCommandUseErrorActionPreference = $false

        & $runnerHost @suiteArguments
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

    if ($Mode -eq 'Fast') {
        # Assembly paths mean dotnet builds nothing, so this script has to build. -NoBuild keeps
        # its meaning: the caller already built, as the pre-push hook does.
        #
        # The whole solution, not the five test projects. Measured on an up-to-date tree: the
        # solution's sixteen projects take 6.9 s and the biggest single test project takes 4.7 s,
        # so the eleven extra projects cost about 2.2 s. Building the five separately would be
        # five MSBuild evaluations, roughly 22 s, which is the cost this change exists to remove.
        if (-not $NoBuild) {
            Write-Step "Building solution ($Configuration)"
            & dotnet build AHKFlowApp.slnx --configuration $Configuration 2>&1 |
                ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                throw 'Build failed.'
            }
        }

        $fast = Get-FastAssembly
        $label = "Fast[$($fast.Filter)]"
        $progress = New-ProgressTracker -RunnerKey "test-fast.$Mode" -RepoRoot $repoRoot -Unit @($label)
        Start-ProgressUnit -Tracker $progress -Name $label
        $summaries = @(Invoke-CombinedTestRun `
            -Assembly $fast.Assembly `
            -Filter $fast.Filter `
            -Label $label)
        Stop-ProgressUnit -Tracker $progress
        Save-ProgressTimings -Tracker $progress
    }
    else {
        $testRuns = @(Get-TestRuns)
        $progress = New-ProgressTracker -RunnerKey "test-fast.$Mode" -RepoRoot $repoRoot -Unit @(
            $testRuns | ForEach-Object { Get-ProgressUnitLabel -TestRun $_ }
        )

        $summaries = @()
        foreach ($testRun in $testRuns) {
            Start-ProgressUnit -Tracker $progress -Name (Get-ProgressUnitLabel -TestRun $testRun)
            $summaries += Invoke-TestRun -TestRun $testRun
            Stop-ProgressUnit -Tracker $progress
        }

        Save-ProgressTimings -Tracker $progress
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
