#Requires -Version 7.0
<#
.SYNOPSIS
  Times one test Mode several times and reports the median, or soaks one test project.
.DESCRIPTION
  Backlog 128. Every performance claim about the test suite is the median of five warm runs, and
  a single run is not evidence: the Fast Mode's observed spread was 7.12 s across five runs, a
  fifth of the whole Mode.

  It builds once, then runs the Mode with -NoBuild each time, so the numbers measure test
  execution and not compilation.

  -Soak runs one test project many times instead, and reports how many runs passed. Five runs fix
  a median but say little about a race that fires one run in fifty, so a reshaped project earns
  its "no new flake" claim here rather than from the timing runs.

  A soak repetition passes only when it exits zero AND its TRX counts at least one test. Counting
  the exit code alone would let thirty empty runs report "30 of 30", which is the worst kind of
  wrong answer: it looks like proof. scripts/test-fast.ps1 refuses a zero-test run for the same
  reason.

  The soak starts and removes a SQL container per repetition. Reusing one across repetitions
  would be cheaper and wrong: the migration tests migrate fixed database names from scratch and
  nothing drops them afterwards, so run two would meet an already-migrated schema and fail for a
  reason the code under test did not cause. A container start costs about 11 s, so a thirty-run
  soak spends roughly five and a half minutes on container starts.

  tests/MeasureTestModes.Tests.ps1 covers the orchestration: argument routing, the median, the
  run lock, environment restoration, one container per repetition, the zero-test guard, and what
  happens when a run fails. It stubs dotnet and replaces the SQL helper, so it costs seconds and
  needs no Docker. It deliberately covers no timing: the numbers this script reports are evidence
  gathered by running it for real, and no stub can stand in for that.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Integration', 'E2E')]
    [string]$Mode = 'Fast',

    [ValidateRange(1, 100)]
    [int]$Runs = 5,

    [string]$Configuration = 'Release',

    # Skip the one build up front. Pass it when the tree is already built.
    [switch]$NoBuild,

    # Soak mode. The path to one test project, for example
    # 'tests/AHKFlowApp.Infrastructure.Tests'. -Mode is ignored when this is given.
    [string]$Soak
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\test-sql-container.common.ps1"
. "$PSScriptRoot\test-run-lock.common.ps1"
. "$PSScriptRoot\test-results.common.ps1"

# A failing 'dotnet test' must be counted, not thrown. PowerShell turns a non-zero exit code from
# a native command into a terminating error while $ErrorActionPreference is 'Stop' and this
# preference is $true, which would end the soak at its first failure and report nothing. That is
# the opposite of what a soak is for: the answer wanted here is "2 of 30", not "it stopped".
# scripts/test-fast.ps1 opts out the same way, for the same reason.
#
# The default varies by PowerShell version and by profile, so this is written out rather than
# assumed. Measured on 2026-09-04 under pwsh 7.6.5 -NoProfile it is already $false.
#
# No test covers this line, and none can: tests/MeasureTestModes.Tests.ps1 stubs dotnet with a
# PowerShell script, and this preference governs native commands only. Sixteen scripts in this
# repository set it the same way, scripts/test-fast.ps1 among them.
#
# Both native calls below check $LASTEXITCODE for themselves, so nothing depends on the throw.
$PSNativeCommandUseErrorActionPreference = $false

$isSoak = -not [string]::IsNullOrWhiteSpace($Soak)

Push-Location $repoRoot
try {
    if ($isSoak -and -not (Test-Path -LiteralPath $Soak -PathType Container)) {
        throw "Test project folder not found: $Soak"
    }

    # The lock covers the build, not only the runs. A build that overlaps another session's
    # coverage instrumentation measures the overlap rather than the test suite, and the first
    # build of a timing session is the one nothing else was protecting.
    # scripts/run-coverage.ps1 takes the lock before its restore and build for the same reason.
    #
    # Soak mode keeps the lock for the whole run: it calls dotnet test directly and owns a SQL
    # container for minutes. Timing mode releases it below, before its first run, because it
    # calls test-fast.ps1, which takes this same lock on every run and would deadlock against a
    # parent still holding it. That leaves a gap between the release and the first run. Another
    # session can take the lock in that gap, and then test-fast.ps1 refuses and names the run
    # holding it, which is a loud failure rather than a corrupted measurement.
    $lockMode = if ($isSoak) { "Soak:$Soak" } else { "Measure:$Mode" }
    $lock = $null
    $previousConnectionString = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING
    try {
        $lock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode $lockMode

        if (-not $NoBuild) {
            Write-Host "Building solution ($Configuration) once before the runs..."
            & dotnet build AHKFlowApp.slnx --configuration $Configuration | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
        }

        if ($isSoak) {
            $passed = 0
            $failed = @()
            $empty = @()
            for ($run = 1; $run -le $Runs; $run++) {
                Write-Host ''
                Write-Host "=== soak run $run of $Runs : $Soak ===" -ForegroundColor Cyan

                # One container per repetition, not one for the whole soak. The migration tests
                # migrate fixed database names from scratch, and no test in the repository drops
                # its database afterwards, so a reused server would leave run two facing an
                # already-migrated schema. That is exactly the blocker D7 records against reusing
                # the container between runs, and a soak that hits it reports a failure the
                # reshape did not cause.
                #
                # It also makes each repetition identical to a real Integration run, which is the
                # thing the soak is meant to be repeating.
                $resultsDirectory = Join-Path $repoRoot "TestResults\soak\run-$run"
                Remove-Item -LiteralPath $resultsDirectory -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null

                $container = $null
                try {
                    $container = Start-AhkFlowTestSqlContainer
                    $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $container.ConnectionString

                    & dotnet test $Soak --configuration $Configuration --no-build `
                        --logger 'trx;LogFileName=soak.trx' --results-directory $resultsDirectory | Out-Host
                    $exitCode = $LASTEXITCODE

                    # Two ways to fail, and the second one is silent without this. A run that
                    # exits zero having discovered nothing is not a pass.
                    # A soak that counts only the exit code passes a run that discovered
                    # nothing, and a filter typo or a lost class fixture is exactly how
                    # that happens: dotnet test exits zero with an empty suite. Thirty of
                    # those report "30 of 30". scripts/test-fast.ps1 refuses a zero-test
                    # run for the same reason, through the same helper.
                    #
                    # The exit code is read first, and the TRX only when the run claims success.
                    # A run that died part-way is already a failure, and its half-written TRX
                    # carries no answer worth asking for.
                    if ($exitCode -ne 0) {
                        $failed += $run
                    }
                    else {
                        $count = Get-AhkFlowTestCountFromResults -ResultsDirectory $resultsDirectory
                        if ($count -lt 1) {
                            Write-Host "run $run exited 0 but ran zero tests" -ForegroundColor Red
                            $empty += $run
                        }
                        else {
                            $passed++
                        }
                    }
                }
                finally {
                    $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousConnectionString
                    if ($container) { Stop-AhkFlowTestSqlContainer -ContainerName $container.ContainerName }
                }
            }

            Write-Host ''
            Write-Host "Soak of $Soak" -ForegroundColor Cyan
            Write-Host ("  passed : {0} of {1}" -f $passed, $Runs)
            if ($empty.Count -gt 0) {
                Write-Host ("  ran zero tests : {0}" -f ($empty -join ', ')) -ForegroundColor Red
                throw "$($empty.Count) of $Runs soak runs discovered zero tests. The soak proved nothing; fix the filter or the fixture first."
            }
            if ($failed.Count -gt 0) {
                Write-Host ("  failed runs : {0}" -f ($failed -join ', ')) -ForegroundColor Red
                throw "The soak failed $($failed.Count) of $Runs runs. A new flake means the reshape is wrong."
            }

            return
        }
    }
    finally {
        Exit-AhkFlowTestRunLock -Handle $lock
    }

    # Timing mode, with the lock released above.
    $seconds = @()
    for ($run = 1; $run -le $Runs; $run++) {
        Write-Host ''
        Write-Host "=== $Mode run $run of $Runs ===" -ForegroundColor Cyan
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # test-fast.ps1 throws on a failing slice, and $ErrorActionPreference is 'Stop' here, so a
        # failure ends this script. Checking $LASTEXITCODE as well would read a stale value from
        # the build above. $PSNativeCommandUseErrorActionPreference does not weaken this: it
        # governs native commands, and test-fast.ps1 is a PowerShell script whose throw
        # propagates either way.
        & (Join-Path $PSScriptRoot 'test-fast.ps1') -Mode $Mode -Configuration $Configuration -NoBuild | Out-Host
        $stopwatch.Stop()

        $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        $seconds += $elapsed
        Write-Host ("run {0}: {1:N2} s" -f $run, $elapsed) -ForegroundColor Green
    }

    $median = Get-AhkFlowMedian -Values $seconds
    $mean = ($seconds | Measure-Object -Average).Average
    $max = ($seconds | Measure-Object -Maximum).Maximum

    Write-Host ''
    Write-Host "$Mode over $Runs runs" -ForegroundColor Cyan
    Write-Host ("  runs   : {0}" -f (($seconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / '))
    Write-Host ("  median : {0:N2} s" -f $median)
    Write-Host ("  mean   : {0:N2} s" -f $mean)
    Write-Host ("  max    : {0:N2} s" -f $max)
}
finally {
    Pop-Location
}
