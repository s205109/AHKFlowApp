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

  The soak starts one SQL container and every repetition uses it. Backlog 133 made every
  SQL-backed test drop the database it needs empty before it builds, so run two meets a warm
  server the way a real second Integration run does. That is the state worth soaking. A container
  start cost about 11 s, so a thirty-run soak used to spend roughly five and a half minutes on
  starts alone.

  The container is left running when the soak ends, the same way scripts/test-fast.ps1 leaves it.

  Backlog 188. -Mode Gate times the five steps of the Gate instead of one test Mode: the build,
  the format check, the PowerShell Mode, the Coverage Mode, and git diff --check. Every run builds,
  because the Gate builds, so Gate Mode does no build up front and has no settle clock. It takes 1
  warm-up and 3 counted runs unless the caller says otherwise. -BaseRef sets the base for the
  coverage step and for git diff --check. The measurement passes HEAD, so the branch's own diff
  never decides whether coverage runs.

  -Change measures the first Gate after one fixed change. One preparation run on the unchanged tree
  saves the evidence folder. Before each warm-up and counted run, the script puts that evidence
  back, appends one line to the change's file, runs the Gate, and then writes the file's original
  bytes back. -NoEvidenceReuse sets AHKFLOW_GATE_REUSE=off around each run, so it measures a full
  Gate. Each session writes record.json with the revision and the median of each step.

  tests/MeasureTestModes.Tests.ps1 covers the orchestration: argument routing, the median, the
  run lock, environment restoration, one container for the whole soak, the zero-test guard, and
  what happens when a run fails. It stubs dotnet and replaces the SQL helper, so it costs seconds
  and needs no Docker. It deliberately covers no timing: the numbers this script reports are
  evidence gathered by running it for real, and no stub can stand in for that.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Integration', 'E2E', 'Gate')]
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

    # Backlog 140. Keep the build inside every counted run, because the spec's headline figure is
    # the command a developer types and that command builds. -NoBuild still governs the one build
    # up front; this governs what each run is asked to do.
    [switch]$KeepBuildInRun,

    # Soak mode. The path to one test project, for example
    # 'tests/AHKFlowApp.Infrastructure.Tests'. -Mode is ignored when this is given.
    [string]$Soak,

    # Gate Mode only. The fixed changes to measure, from Docs, Script and Code. A comma list in one
    # value works too, because 'pwsh -File' passes 'Docs,Script,Code' as a single string.
    [string[]]$Change,

    # Gate Mode only. Turns evidence reuse off for every run, so each run is a full Gate.
    [switch]$NoEvidenceReuse,

    # Gate Mode only. The base for the coverage step and for git diff --check. Empty means the
    # Gate's own base, as Resolve-AhkFlowGateBaseRef finds it.
    [string]$BaseRef
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\test-sql-container.common.ps1"
. "$PSScriptRoot\test-run-lock.common.ps1"
. "$PSScriptRoot\test-results.common.ps1"
. "$PSScriptRoot\test-lanes.common.ps1"
. "$PSScriptRoot\code-change-filter.common.ps1"

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

# Backlog 188. The fixed changes Gate Mode can measure. Each appends one line to one file.
$gateChanges = [ordered]@{
    # Docs only, so the coverage step still skips.
    Docs = @{ File = 'docs/development/testing-workflow.md'; Line = '<!-- gate-measure -->' }
    # A script a Suite loads, through tests/WatchTask.Tests.ps1.
    Script = @{ File = 'scripts/watch-task.ps1'; Line = '# gate-measure' }
    # A .cs file, so the build and the coverage step both run.
    Code = @{ File = 'src/Backend/AHKFlowApp.Domain/Entities/Category.cs'; Line = '// gate-measure' }
}
$changeNames = @($Change | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($Mode -eq 'Gate') {
    # Refuse before any work starts, so a wrong call costs nothing.
    $refused = @()
    if ($isSoak) { $refused += '-Soak' }
    if ($NoBuild) { $refused += '-NoBuild' }
    if ($KeepBuildInRun) { $refused += '-KeepBuildInRun' }
    if ($PSBoundParameters.ContainsKey('SettleSeconds') -and $SettleSeconds -gt 0) { $refused += '-SettleSeconds' }
    if ($refused.Count -gt 0) {
        throw ("Gate Mode does not take {0}. Every Gate run builds, so there is no build up front to skip, " +
            "and the tree never ages, so a settle clock would only add warm-up runs up to the ceiling. " +
            "A soak runs one test project, not the Gate.") -f ($refused -join ', ')
    }

    foreach ($name in $changeNames) {
        if (-not $gateChanges.Contains($name)) {
            throw "Unknown -Change value '$name'. Use Docs, Script or Code."
        }
    }
    if ($changeNames.Count -gt 0 -and $NoEvidenceReuse) {
        throw '-Change measures the first Gate after a change, with evidence reuse on. Do not combine it with -NoEvidenceReuse.'
    }
    if ($changeNames.Count -gt 0 -and $PSBoundParameters.ContainsKey('WarmUpRuns') -and $WarmUpRuns -eq 0) {
        throw '-Change needs at least one warm-up run on each changed tree. Drop -WarmUpRuns 0.'
    }

    if (-not $PSBoundParameters.ContainsKey('Runs')) { $Runs = 3 }
    if (-not $PSBoundParameters.ContainsKey('WarmUpRuns')) { $WarmUpRuns = 1 }
}
elseif ($changeNames.Count -gt 0 -or $NoEvidenceReuse -or $PSBoundParameters.ContainsKey('BaseRef')) {
    throw '-Change, -NoEvidenceReuse and -BaseRef work only with -Mode Gate.'
}

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
        [Parameter(Mandatory = $true)][string]$ScriptRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [switch]$KeepBuildInRun
    )

    Write-Host ''
    Write-Host "=== $Mode $Label ===" -ForegroundColor Cyan

    # A hashtable, not an array. Splatting an array binds its elements by position, so '-Mode'
    # would arrive as the value of the first positional parameter rather than as a name.
    $testFastArguments = @{ Mode = $Mode; Configuration = $Configuration }
    if (-not $KeepBuildInRun) {
        $testFastArguments['NoBuild'] = $true
    }

    # Backlog 140. The recorder reads these two at the moment a step runs, so they are set around
    # the call and restored after it. Each run writes its own timing files, beside its own TRX.
    $timingDirectory = Join-Path $RunDirectory 'fixture-timing'
    New-Item -ItemType Directory -Path $timingDirectory -Force | Out-Null
    $previousTiming = $env:AHKFLOW_TEST_TIMING
    $previousTimingDirectory = $env:AHKFLOW_TEST_TIMING_DIR
    $env:AHKFLOW_TEST_TIMING = '1'
    $env:AHKFLOW_TEST_TIMING_DIR = $timingDirectory

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # test-fast.ps1 throws on a failing slice, and $ErrorActionPreference is 'Stop' here, so a
        # failure ends this script. Checking $LASTEXITCODE as well would read a stale value from the
        # build above. $PSNativeCommandUseErrorActionPreference does not weaken this: it governs
        # native commands, and test-fast.ps1 is a PowerShell script whose throw propagates either way.
        & (Join-Path $ScriptRoot 'test-fast.ps1') @testFastArguments | Out-Host
        $stopwatch.Stop()
    }
    finally {
        $env:AHKFLOW_TEST_TIMING = $previousTiming
        $env:AHKFLOW_TEST_TIMING_DIR = $previousTimingDirectory
    }

    $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

    # test-fast.ps1 writes into one fixed folder and clears it at the start of every run, so the
    # TRX has to be copied out here or run five overwrites run four.
    $sharedResults = Join-Path $RepoRoot "TestResults\test-fast\$Mode"
    foreach ($trx in @(Get-ChildItem -LiteralPath $sharedResults -Recurse -Filter '*.trx' -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $trx.FullName -Destination (Join-Path $RunDirectory $trx.Name) -Force
    }

    # The command boundary, written beside the run's own artifacts. Only this function knows it,
    # and the report must not need a human to retype a number the driver already measured.
    [pscustomobject]@{ Label = $Label; ElapsedSeconds = $elapsed } |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'run.json') -Encoding utf8

    Write-Host ("{0}: {1:N2} s" -f $Label, $elapsed) -ForegroundColor Green
    return $elapsed
}

function Invoke-GateRun {
    <#
      One timed run of the five Gate steps, printed and returned with each step's seconds.

      The native steps check $LASTEXITCODE, because this script turns the native-command throw off.
      test-fast.ps1 throws on a failure, so its two steps catch the throw and name the step.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Configuration,
        [Parameter(Mandatory = $true)][string]$ScriptRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$BaseRef,
        [switch]$NoEvidenceReuse
    )

    Write-Host ''
    Write-Host "=== Gate $Label ===" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null

    $testFast = Join-Path $ScriptRoot 'test-fast.ps1'
    $steps = [ordered]@{}
    $previousReuse = $env:AHKFLOW_GATE_REUSE
    if ($NoEvidenceReuse) { $env:AHKFLOW_GATE_REUSE = 'off' }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($step in @(
            @{ Name = 'build'; Native = $true; Body = { & dotnet build AHKFlowApp.slnx --configuration $Configuration | Out-Host } },
            @{ Name = 'format'; Native = $true; Body = { & dotnet format AHKFlowApp.slnx --verify-no-changes | Out-Host } },
            @{ Name = 'powershell'; Native = $false; Body = { & $testFast -Mode PowerShell | Out-Host } },
            @{ Name = 'coverage'; Native = $false; Body = { & $testFast -Mode Coverage -BaseRef $BaseRef | Out-Host } },
            @{ Name = 'diff-check'; Native = $true; Body = { & git diff --check "$BaseRef...HEAD" | Out-Host } }
        )) {
            $stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                & $step.Body
            }
            catch {
                throw "Gate step '$($step.Name)' failed during $Label. $($_.Exception.Message)"
            }
            if ($step.Native -and $LASTEXITCODE -ne 0) {
                throw "Gate step '$($step.Name)' failed during $Label with exit code $LASTEXITCODE."
            }
            $steps[$step.Name] = [Math]::Round($stepWatch.Elapsed.TotalSeconds, 2)
        }
        $stopwatch.Stop()
    }
    finally {
        $env:AHKFLOW_GATE_REUSE = $previousReuse
    }

    $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

    # The runner keeps one per-Suite timing file and rewrites it every run, so each run keeps a copy.
    $suiteTimes = Join-Path $RepoRoot 'TestResults\progress\run-powershell-suites.json'
    if (Test-Path -LiteralPath $suiteTimes) {
        Copy-Item -LiteralPath $suiteTimes -Destination (Join-Path $RunDirectory 'run-powershell-suites.json') -Force
    }

    [pscustomobject]@{ Label = $Label; ElapsedSeconds = $elapsed; Steps = $steps } |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'run.json') -Encoding utf8

    Write-Host ("{0}: {1:N2} s ({2})" -f $Label, $elapsed,
        (($steps.Keys | ForEach-Object { '{0} {1:N2}' -f $_, $steps[$_] }) -join ', ')) -ForegroundColor Green
    return [pscustomobject]@{ ElapsedSeconds = $elapsed; Steps = $steps }
}

function Restore-GateEvidence {
    <#
      Puts the evidence folder back to the state the preparation run left. A timed run must start
      from that state, or it measures a second Gate instead of the first Gate after a change.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceRoot,
        [Parameter(Mandatory = $true)][string]$SavedEvidence
    )

    Remove-Item -LiteralPath $EvidenceRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $SavedEvidence) {
        Copy-Item -LiteralPath $SavedEvidence -Destination $EvidenceRoot -Recurse -Force
    }
}

function Invoke-GateCase {
    <#
      The warm-up and counted runs of one Gate case. With a change, each run starts from the saved
      evidence, appends the change's line, and puts the file's original bytes back in a finally
      block. It never restores through git, which would also drop any other edit in the tree.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][int]$WarmUpRuns,
        [Parameter(Mandatory = $true)][int]$Runs,
        [Parameter(Mandatory = $true)][hashtable]$RunArguments,
        [string]$ChangeName,
        [string]$ChangeFile,
        [string]$ChangePath,
        [string]$ChangeLine,
        [string]$EvidenceRoot,
        [string]$SavedEvidence
    )

    $warmUps = @()
    $counted = @()
    $labelPrefix = if ($ChangeName) { "$ChangeName " } else { '' }
    $total = $WarmUpRuns + $Runs
    for ($index = 1; $index -le $total; $index++) {
        $isWarmUp = $index -le $WarmUpRuns
        $number = if ($isWarmUp) { $index } else { $index - $WarmUpRuns }
        $label = if ($isWarmUp) { "${labelPrefix}warm-up $number" } else { "${labelPrefix}run $number of $Runs" }
        $folder = Join-Path $CaseRoot $(if ($isWarmUp) { "warmup-$number" } else { "run-$number" })

        if ($ChangeName) {
            Restore-GateEvidence -EvidenceRoot $EvidenceRoot -SavedEvidence $SavedEvidence
            $original = [System.IO.File]::ReadAllBytes($ChangePath)
            try {
                # One line with the file's own line ending, after a line ending if the file lacks one.
                $text = [System.Text.Encoding]::UTF8.GetString($original)
                $lineEnding = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
                $prefix = if ($text.EndsWith("`n")) { '' } else { $lineEnding }
                [System.IO.File]::WriteAllBytes($ChangePath,
                    [byte[]]($original + [System.Text.Encoding]::UTF8.GetBytes("$prefix$ChangeLine$lineEnding")))
                $result = Invoke-GateRun -Label $label -RunDirectory $folder @RunArguments
            }
            finally {
                [System.IO.File]::WriteAllBytes($ChangePath, $original)
            }
        }
        else {
            $result = Invoke-GateRun -Label $label -RunDirectory $folder @RunArguments
        }

        if ($isWarmUp) { $warmUps += $result } else { $counted += $result }
    }

    $stepMedians = [ordered]@{}
    foreach ($name in $counted[0].Steps.Keys) {
        $stepMedians[$name] = Get-AhkFlowMedian -Values @($counted | ForEach-Object { $_.Steps[$name] })
    }
    $runSeconds = @($counted | ForEach-Object { $_.ElapsedSeconds })

    return [pscustomobject][ordered]@{
        Change = if ($ChangeName) { $ChangeName } else { $null }
        File = if ($ChangeName) { $ChangeFile } else { $null }
        WarmUpSeconds = @($warmUps | ForEach-Object { $_.ElapsedSeconds })
        RunSeconds = $runSeconds
        MedianSeconds = Get-AhkFlowMedian -Values $runSeconds
        SpreadPercent = [Math]::Round((Get-AhkFlowRelativeSpread -Values $runSeconds), 1)
        StepMedians = $stepMedians
    }
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

$laneState = $null
Push-Location $repoRoot
try {
    if ($isSoak -and -not (Test-Path -LiteralPath $Soak -PathType Container)) {
        throw "Test project folder not found: $Soak"
    }

    # Reserve before build and timing. Keep this share across warm-ups and checkout releases.
    $laneShare = if ($isSoak) { 'Half' } else { 'Whole' }
    $laneMode = if ($isSoak) { "Soak:$Soak" } else { "Measure:$Mode" }
    $laneState = Enter-AhkFlowLaneRun -Mode $laneMode -Checkout $repoRoot -Share $laneShare

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

        # Gate Mode builds inside every run, because the Gate does.
        if (-not $NoBuild -and $Mode -ne 'Gate') {
            Write-Host "Building solution ($Configuration) once before the runs..."
            & dotnet build AHKFlowApp.slnx --configuration $Configuration | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
        }

        if ($isSoak) {
            $passed = 0
            $failed = @()
            $empty = @()

            # One container for the whole soak. It also makes each repetition identical to a real
            # second Integration run, which is the thing the soak is meant to be repeating.
            $container = Start-AhkFlowTestSqlContainer -RepoRoot $repoRoot
            $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $container.ConnectionString
            Write-Host ("Soak container: {0} ({1})" -f $container.ContainerName, $container.ContainerId)

            for ($run = 1; $run -le $Runs; $run++) {
                Write-Host ''
                Write-Host "=== soak run $run of $Runs : $Soak ===" -ForegroundColor Cyan

                $resultsDirectory = Join-Path $repoRoot "TestResults\soak\run-$run"
                Remove-Item -LiteralPath $resultsDirectory -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null

                & dotnet test $Soak --configuration $Configuration --no-build `
                    --logger 'trx;LogFileName=soak.trx' --results-directory $resultsDirectory | Out-Host
                $exitCode = $LASTEXITCODE

                # Two ways to fail, and the second one is silent without this. A run that exits
                # zero having discovered nothing is not a pass. A soak that counts only the exit
                # code passes a run that discovered nothing, and a filter typo or a lost class
                # fixture is exactly how that happens: dotnet test exits zero with an empty suite.
                # Thirty of those report "30 of 30". scripts/test-fast.ps1 refuses a zero-test run
                # for the same reason, through the same helper.
                #
                # The exit code is read first, and the TRX only when the run claims success. A run
                # that died part-way is already a failure, and its half-written TRX carries no
                # answer worth asking for.
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

            Write-Host ''
            Write-Host ("Soak container at the end: {0} ({1})" -f $container.ContainerName, $container.ContainerId)

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
        # Soak mode sets this once, before its loop. Timing mode never sets it, so restoring it is
        # a no-op there. The container itself is left running, as backlog 133 requires.
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousConnectionString
        Exit-AhkFlowTestRunLock -Handle $lock
    }

    # Timing mode, with the lock released above.
    #
    # Backlog 140. One folder per run, so the report can describe the run that produced the
    # headline. Warm-up folders are named apart from counted ones, so a reader can tell the
    # discarded runs from the counted set.
    #
    # One session folder per invocation, and never a delete. Backlog 140's measurement took two
    # sessions back to back in one Mode, and an earlier version cleared the Mode's folder at the
    # start of each, so the second session erased the first before anybody reported on it. The
    # UTC timestamp keeps sessions in order; the suffix loop keeps two invocations in the same
    # second apart.
    $modeRoot = Join-Path $repoRoot "TestResults\measure-test-modes\$Mode"
    $sessionName = 'session-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $runRoot = Join-Path $modeRoot $sessionName
    $suffix = 1
    while (Test-Path -LiteralPath $runRoot) {
        $suffix++
        $runRoot = Join-Path $modeRoot "$sessionName-$suffix"
    }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    Write-Host "Session artifacts: $runRoot" -ForegroundColor Cyan

    if ($Mode -eq 'Gate') {
        # Backlog 188. Gate Mode has its own loop: no settle clock, and with -Change a preparation
        # run first. The lock is already released above, because the coverage step calls
        # test-fast.ps1, which takes the same lock.
        $gateBase = Resolve-AhkFlowGateBaseRef -RepoRoot $repoRoot -BaseRef $BaseRef
        # The same rule as Get-GateEvidenceRoot in scripts/gate-evidence.common.ps1.
        $evidenceRoot = if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_GATE_EVIDENCE_ROOT)) {
            $env:AHKFLOW_GATE_EVIDENCE_ROOT
        }
        else {
            Join-Path $repoRoot 'TestResults\gate-evidence'
        }
        Write-Host "Gate base: $gateBase" -ForegroundColor Cyan

        $runArguments = @{
            Configuration = $Configuration
            ScriptRoot = $PSScriptRoot
            RepoRoot = $repoRoot
            BaseRef = $gateBase
            NoEvidenceReuse = [bool]$NoEvidenceReuse
        }

        $preparation = $null
        $cases = @()
        if ($changeNames.Count -eq 0) {
            $cases += Invoke-GateCase -CaseRoot $runRoot -WarmUpRuns $WarmUpRuns -Runs $Runs -RunArguments $runArguments
        }
        else {
            # Only a green Gate on the unchanged tree makes the state every timed run starts from.
            $preparation = Invoke-GateRun -Label 'preparation' -RunDirectory (Join-Path $runRoot 'preparation') @runArguments
            $savedEvidence = Join-Path $runRoot 'prepared-evidence'
            if (Test-Path -LiteralPath $evidenceRoot) {
                Copy-Item -LiteralPath $evidenceRoot -Destination $savedEvidence -Recurse -Force
            }

            foreach ($name in $changeNames) {
                $cases += Invoke-GateCase -CaseRoot (Join-Path $runRoot $name) -WarmUpRuns $WarmUpRuns -Runs $Runs `
                    -RunArguments $runArguments -ChangeName $name -ChangeFile $gateChanges[$name].File `
                    -ChangePath (Join-Path $repoRoot $gateChanges[$name].File) -ChangeLine $gateChanges[$name].Line `
                    -EvidenceRoot $evidenceRoot -SavedEvidence $savedEvidence
            }
        }

        $revision = "$(& git rev-parse HEAD)".Trim()
        [pscustomobject][ordered]@{
            Revision = $revision
            Mode = 'Gate'
            BaseRef = $gateBase
            NoEvidenceReuse = [bool]$NoEvidenceReuse
            Preparation = $preparation
            Cases = $cases
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'record.json') -Encoding utf8

        Write-Host ''
        Write-Host "Gate at $revision, base $gateBase" -ForegroundColor Cyan
        if ($null -ne $preparation) {
            Write-Host ("  preparation: {0:N2} s" -f $preparation.ElapsedSeconds)
        }
        foreach ($case in $cases) {
            $name = if ($case.Change) { "change $($case.Change)" } else { 'no change' }
            Write-Host "  $name over $Runs counted runs" -ForegroundColor Cyan
            if ($case.WarmUpSeconds.Count -gt 0) {
                Write-Host ("    warm-up: {0} (discarded, {1})" -f `
                    (($case.WarmUpSeconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / '), $case.WarmUpSeconds.Count)
            }
            Write-Host ("    runs   : {0}" -f (($case.RunSeconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / '))
            Write-Host ("    median : {0:N2} s" -f $case.MedianSeconds)
            Write-Host ("    spread : {0:N1} % of the median" -f $case.SpreadPercent)
            Write-Host ("    steps  : {0}" -f (($case.StepMedians.Keys | ForEach-Object { '{0} {1:N2}' -f $_, $case.StepMedians[$_] }) -join ', '))
        }
        return
    }

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
            -Mode $Mode -Configuration $Configuration -ScriptRoot $PSScriptRoot `
            -RepoRoot $repoRoot -RunDirectory (Join-Path $runRoot ("warmup-" + ($warmUpSeconds.Count + 1))) `
            -KeepBuildInRun:$KeepBuildInRun
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
            -Mode $Mode -Configuration $Configuration -ScriptRoot $PSScriptRoot `
            -RepoRoot $repoRoot -RunDirectory (Join-Path $runRoot "run-$run") `
            -KeepBuildInRun:$KeepBuildInRun
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
    Exit-AhkFlowLaneRun -State $laneState
    Pop-Location
}
