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

  Backlog 150. That is true about compilation and was never the whole story. A run taken soon
  after a build is much slower for reasons that have nothing to do with the tests, and the same
  tree measured 88.40 s and 55.05 s about an hour apart with no code change. Two mechanisms answer
  that, because the record holds two separate effects.

  -WarmUpRuns runs are taken first and thrown away. That removes the decay inside one measurement
  window, where the first runs are slow and the later ones settle.

  -SettleSeconds holds the counted runs back until the tree has been built that long. That removes
  the other effect, a window that is slow from end to end and never decays at all. Warm-up runs
  fill the wait, and -MaxWarmUpRuns caps how many of them there may be. The cap never shortens the
  wait: a Mode whose runs are short cannot fill the target with runs, so the script waits out the
  rest instead. Every discarded run is printed, so the reader can see the decay and judge it.

  The spread line says how far to trust the median. It cannot say whether the tree was cold: in
  that record the cold window spread 12.1 percent and the settled window spread 31.9 percent. The
  build age is printed beside it for exactly that reason.

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

    # Runs taken before the counted ones and thrown away. Backlog 150: the runs right after a
    # build are much slower for reasons that have nothing to do with the tests, and a median that
    # counts them reads far too high. Two is what the evidence supports. In that item's record the
    # first two runs of a decaying window sat above the settled band and the third was inside it.
    [ValidateRange(0, 100)]
    [int]$WarmUpRuns = 2,

    # The counted runs do not start until the tree has been built this many seconds ago. Warm-up
    # runs fill the wait, so the time buys something. Backlog 150 measured a whole five-run window
    # right after a build that was flat and 60 percent slow: no number of discarded runs fixes
    # that window, because it never decays. 0 turns the clock off.
    [ValidateRange(0, 7200)]
    [int]$SettleSeconds = 600,

    # The ceiling on warm-up runs, so the settle clock cannot run forever on a slow Mode.
    [ValidateRange(1, 100)]
    [int]$MaxWarmUpRuns = 12,

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

function Invoke-TimedRun {
    <#
      One timed run of a Mode, printed and returned in seconds.

      Warm-up runs and counted runs are the same work, so they go through one function. Two copies
      of the timing block would drift, and backlog 150 turns on the two kinds of run being measured
      identically and only counted differently.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Configuration,
        [Parameter(Mandatory = $true)][string]$ScriptRoot
    )

    Write-Host ''
    Write-Host "=== $Mode $Label ===" -ForegroundColor Cyan
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    # test-fast.ps1 throws on a failing slice, and $ErrorActionPreference is 'Stop' here, so a
    # failure ends this script. Checking $LASTEXITCODE as well would read a stale value from the
    # build above. $PSNativeCommandUseErrorActionPreference does not weaken this: it governs
    # native commands, and test-fast.ps1 is a PowerShell script whose throw propagates either way.
    & (Join-Path $ScriptRoot 'test-fast.ps1') -Mode $Mode -Configuration $Configuration -NoBuild | Out-Host
    $stopwatch.Stop()

    $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    Write-Host ("{0}: {1:N2} s" -f $Label, $elapsed) -ForegroundColor Green
    return $elapsed
}

function Get-BuildCompletedAtUtc {
    <#
      When the test output was last written, in UTC, or $null when there is none.

      The newest write time across every test project's build output. That is the closest thing to
      a build clock this script can read without being told, and it works for a -NoBuild run, which
      is the run that most needs it.

      The framework folder is a wildcard on purpose. Pinning net10.0 here would answer $null after
      a framework bump, and a settle clock that switches itself off in silence is worse than no
      settle clock at all.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Configuration
    )

    $pattern = Join-Path $RepoRoot "tests\*\bin\$Configuration\*\*.dll"
    $newest = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $newest) { return $null }

    return $newest.LastWriteTimeUtc
}

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
            # Both lists print before either throw. Throwing inside the first block hid the
            # second one, so a soak where run 2 came back empty and run 17 genuinely failed
            # named only run 2, and the reader went looking for the wrong problem.
            if ($empty.Count -gt 0) {
                Write-Host ("  ran zero tests : {0}" -f ($empty -join ', ')) -ForegroundColor Red
            }
            if ($failed.Count -gt 0) {
                Write-Host ("  failed runs : {0}" -f ($failed -join ', ')) -ForegroundColor Red
            }

            # A run lands in $empty for two different reasons, and the message names both. Its
            # TRX said zero, or its TRX could not be read at all - a filter typo and a killed
            # run look identical from here, because the count reader answers zero for each.
            if ($empty.Count -gt 0) {
                throw "$($empty.Count) of $Runs soak runs reported no tests. Either the filter matched nothing, or the run died before it wrote a readable TRX. The soak proved nothing; check the filter, the fixture, and the TRX files under TestResults\soak."
            }
            if ($failed.Count -gt 0) {
                throw "The soak failed $($failed.Count) of $Runs runs. A new flake means the reshape is wrong."
            }

            return
        }
    }
    finally {
        Exit-AhkFlowTestRunLock -Handle $lock
    }

    # Timing mode, with the lock released above.
    $buildCompletedAtUtc = Get-BuildCompletedAtUtc -RepoRoot $repoRoot -Configuration $Configuration
    if ($null -eq $buildCompletedAtUtc) {
        Write-Host 'Found no build output, so the settle clock is off for this run.' -ForegroundColor Yellow
    }

    $secondsSinceBuild = 0
    $warmUpSeconds = @()
    while ($true) {
        if ($null -ne $buildCompletedAtUtc) {
            $secondsSinceBuild = ([DateTime]::UtcNow - $buildCompletedAtUtc).TotalSeconds
        }

        $enoughRuns = $warmUpSeconds.Count -ge $WarmUpRuns
        $settled = ($SettleSeconds -le 0) -or ($null -eq $buildCompletedAtUtc) -or
            ($secondsSinceBuild -ge $SettleSeconds)
        if ($enoughRuns -and $settled) { break }

        if ($warmUpSeconds.Count -ge $MaxWarmUpRuns) {
            # The ceiling caps the runs. It never caps the wait.
            #
            # A Mode whose runs are short cannot fill the settle target with runs alone. The Fast
            # Mode measured 13.5 to 16.1 s a run on 2026-09-12, so a 600 s target would need more
            # than forty runs. An earlier version stopped here instead of waiting, which started
            # the counted runs on a tree that was still cold and printed a median that read exactly
            # like a settled one. Waiting out the rest costs the same wall clock and no CPU.
            if (-not $settled) {
                $remaining = [Math]::Ceiling($SettleSeconds - $secondsSinceBuild)
                Write-Host ("Reached the warm-up ceiling of {0} runs. Waiting {1:N0} s more for the tree to settle." -f `
                    $MaxWarmUpRuns, $remaining) -ForegroundColor Yellow
                Start-Sleep -Seconds $remaining
            }
            elseif (-not $enoughRuns) {
                # Only reachable when -MaxWarmUpRuns is below -WarmUpRuns, which is a contradiction
                # the caller has to see rather than have silently resolved.
                Write-Host ("Reached the warm-up ceiling of {0} runs before the {1} warm-up runs asked for." -f `
                    $MaxWarmUpRuns, $WarmUpRuns) -ForegroundColor Yellow
            }
            break
        }

        $warmUpSeconds += Invoke-TimedRun -Label ("warm-up " + ($warmUpSeconds.Count + 1)) `
            -Mode $Mode -Configuration $Configuration -ScriptRoot $PSScriptRoot
    }

    # Read the clock once more, after the warm-up loop and any wait. The report calls this figure
    # the age at the first counted run, and the value the loop left behind was read before the last
    # warm-up run, not after it.
    if ($null -ne $buildCompletedAtUtc) {
        $secondsSinceBuild = ([DateTime]::UtcNow - $buildCompletedAtUtc).TotalSeconds
    }

    $seconds = @()
    for ($run = 1; $run -le $Runs; $run++) {
        $seconds += Invoke-TimedRun -Label "run $run of $Runs" `
            -Mode $Mode -Configuration $Configuration -ScriptRoot $PSScriptRoot
    }

    $median = Get-AhkFlowMedian -Values $seconds
    $mean = ($seconds | Measure-Object -Average).Average
    $max = ($seconds | Measure-Object -Maximum).Maximum

    Write-Host ''
    Write-Host "$Mode over $Runs counted runs" -ForegroundColor Cyan
    if ($warmUpSeconds.Count -gt 0) {
        # The runs themselves, not only how many there were. A reader who sees 91 / 62 falling to
        # a flat tail can judge whether the measurement settled. A bare count cannot be judged.
        Write-Host ("  warm-up: {0} (discarded, {1})" -f `
            (($warmUpSeconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / '), $warmUpSeconds.Count)
    }
    Write-Host ("  runs   : {0}" -f (($seconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / '))
    Write-Host ("  median : {0:N2} s" -f $median)
    Write-Host ("  mean   : {0:N2} s" -f $mean)
    Write-Host ("  max    : {0:N2} s" -f $max)
    Write-Host ("  spread : {0:N1} % of the median" -f (Get-AhkFlowRelativeSpread -Values $seconds))
    if ($null -eq $buildCompletedAtUtc) {
        Write-Host '  built  : unknown, found no build output'
    }
    else {
        Write-Host ("  built  : {0:N0} s before the first counted run" -f $secondsSinceBuild)
    }
}
finally {
    Pop-Location
}
