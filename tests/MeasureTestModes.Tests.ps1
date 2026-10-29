#Requires -Version 7.0

# Backlog 128. scripts/measure-test-modes.ps1 times a test Mode several times and reports the
# median, or soaks one test project and reports how many runs passed.
#
# This suite covers the orchestration: argument routing, the median, the run lock, the
# connection-string restore, one SQL container for the whole soak, the zero-test guard, what
# happens when a run fails, and what happens when a run leaves a TRX nobody can parse. It stubs
# 'dotnet', stubs scripts/test-fast.ps1, and replaces the SQL container helper with a
# two-function fake that logs instead of calling Docker, so it costs seconds and needs no Docker.
#
# One case is not orchestration: it calls Get-AhkFlowMedian with fixed values. The median is the
# number every performance claim in backlog 128 rests on, and driving it through the harness can
# only check it against wall-clock timings.
#
# It deliberately covers no timing. The numbers the harness reports are evidence gathered by
# running it for real against the repository, and no stub can stand in for that.
#
# Run it by hand with:  pwsh ./tests/MeasureTestModes.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from the child harness is data here, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

# The real file, not the fixture copy. The median case calls Get-AhkFlowMedian with fixed values,
# which is the only way to test the arithmetic with no wall clock in the assertion. It defines
# functions and nothing else, so dot-sourcing it here has no side effect.
. (Join-Path $repoRoot 'scripts\test-results.common.ps1')
. (Join-Path $repoRoot 'scripts\test-lanes.common.ps1')
. (Join-Path $PSScriptRoot 'LanePool.Common.ps1')

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

function New-HarnessFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('measure-test-modes-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'stub') -Force | Out-Null

    # The soak's -Soak argument names a folder, and the harness throws when it is missing. One
    # empty folder is enough: the dotnet stub never reads it.
    New-Item -ItemType Directory -Path (Join-Path $root 'tests\FakeProject') -Force | Out-Null

    # Copy the real harness, checkout lock, TRX reader, and Lane helpers.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\measure-test-modes.ps1') `
        -Destination (Join-Path $root 'scripts\measure-test-modes.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\test-run-lock.common.ps1') `
        -Destination (Join-Path $root 'scripts\test-run-lock.common.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\test-results.common.ps1') `
        -Destination (Join-Path $root 'scripts\test-results.common.ps1')
    foreach ($helper in @('test-lanes.common.ps1', 'suite-worker-count.common.ps1', 'code-change-filter.common.ps1')) {
        Copy-Item (Join-Path $repoRoot "scripts/$helper") (Join-Path $root "scripts/$helper")
    }
    Copy-Item (Join-Path $PSScriptRoot 'LanePool.Common.ps1') (Join-Path $root 'scripts/LanePool.Common.ps1')
    # Observe real failed admission before allowing the next attempt.
    Add-Content (Join-Path $root 'scripts/test-lanes.common.ps1') @'
function Wait-AhkFlowLaneRetry {
    param($Run)
    . (Join-Path $PSScriptRoot 'LanePool.Common.ps1')
    $stub = Join-Path (Split-Path $PSScriptRoot -Parent) 'stub'
    Publish-LaneSignal (Join-Path $stub 'waiting')
    Wait-LanePath (Join-Path $stub 'retry') 30 | Out-Null
}
'@
    Set-Content (Join-Path $root 'scripts/lane-observation.ps1') @'
param([string]$Label)
. (Join-Path $PSScriptRoot 'test-lanes.common.ps1')
. (Join-Path $PSScriptRoot 'LanePool.Common.ps1')
$stub = Join-Path (Split-Path $PSScriptRoot -Parent) 'stub'
if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_ROOT)) {
    $held = (Get-AhkFlowHeldLaneCount $env:AHKFLOW_TEST_LANES_ROOT) - 1
    $line = "$Label held=$held holder=$env:AHKFLOW_TEST_LANES_HOLDER"
    Add-Content (Join-Path $stub 'lanes.txt') $line
    if (Test-Path (Join-Path $stub 'gated')) {
        Publish-LaneSignal (Join-Path $stub "$Label.ready") $line
        Wait-LanePath (Join-Path $stub "$Label.release") 30 | Out-Null
    }
}
'@

    # Pause the copied harness at the parent-to-delegate boundary. Production has no test gate.
    Set-Content (Join-Path $root 'scripts/checkout-handoff.ps1') @'
. (Join-Path $PSScriptRoot 'LanePool.Common.ps1')
$stub = Join-Path (Split-Path $PSScriptRoot -Parent) 'stub'
if (Test-Path (Join-Path $stub 'handoff-enabled')) {
    Publish-LaneSignal (Join-Path $stub 'handoff.ready') $env:AHKFLOW_TEST_LANES_HOLDER
    Wait-LanePath (Join-Path $stub 'handoff.release') 30 | Out-Null
}
'@
    $harnessPath = Join-Path $root 'scripts/measure-test-modes.ps1'
    $harness = Get-Content -LiteralPath $harnessPath -Raw
    $handoffPoint = '    # Timing mode, with the lock released above.'
    Assert-True ($harness.Contains($handoffPoint)) 'Fixture must find the checkout handoff boundary.'
    $handoffGate = '    & (Join-Path $PSScriptRoot ''checkout-handoff.ps1'')'
    Set-Content -LiteralPath $harnessPath -Value ($harness.Replace($handoffPoint, "$handoffGate`n$handoffPoint"))

    Set-Content -LiteralPath (Join-Path $root 'scripts\test-sql-container.common.ps1') -Encoding utf8 -Value @'
# Fake. tests/MeasureTestModes.Tests.ps1 covers the harness's orchestration, not the container
# helper, and the real helper shells out to Docker. Each call appends one line, so a case can
# count starts and stops and check they pair up.
$script:FakeSqlLog = Join-Path (Split-Path -Parent $PSScriptRoot) 'sql-calls.txt'

function Start-AhkFlowTestSqlContainer {
    param([switch]$Fresh, [switch]$Ephemeral, [string]$RepoRoot)

    $name = "fake-sql-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    Add-Content -LiteralPath $script:FakeSqlLog -Value "start $name"
    [pscustomobject]@{
        ContainerName = $name
        ContainerId = "fakeid-$name"
        Reused = $false
        ConnectionString = "Server=127.0.0.1,14333;Database=master;User Id=sa;Password=fake;TrustServerCertificate=True"
        ElapsedMilliseconds = 0
        StartedAtUtc = [DateTimeOffset]::UtcNow
    }
}

function Stop-AhkFlowTestSqlContainer {
    param([string]$ContainerName)
    Add-Content -LiteralPath $script:FakeSqlLog -Value "stop $ContainerName"
}
'@

    Set-Content -LiteralPath (Join-Path $root 'stub\dotnet.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $stubFolder
$callsPath = Join-Path $stubFolder 'calls.txt'
Add-Content -LiteralPath $callsPath -Value ($args -join ' ')
# One log shared with the test-fast and git stubs, so the Gate cases can read the step order.
Add-Content -LiteralPath (Join-Path $stubFolder 'steps.txt') -Value ('dotnet ' + ($args -join ' '))

# The owner file, not .test-run.lock. The release step deletes the owner file and deliberately
# leaves the lock file behind, so the lock file's presence says nothing about who holds it.
$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') `
    -Value ("{0} owner={1} conn={2}" -f $args[0], $owner, $env:AHKFLOW_TEST_SQL_CONNECTION_STRING)

if ($args[0] -eq 'format') {
    Write-Output 'stub dotnet format'
    exit 0
}

if ($args[0] -eq 'build') {
    & (Join-Path $repoRoot 'scripts/lane-observation.ps1') 'build'
    if (Test-Path (Join-Path $stubFolder 'fail-build')) { exit 1 }
    Write-Output 'stub dotnet build'
    exit 0
}

# Which test run is this? The soak cases name a run number in a marker file.
$run = @(Get-Content -LiteralPath $callsPath | Where-Object { $_ -like 'test *' }).Count
& (Join-Path $repoRoot 'scripts/lane-observation.ps1') "soak-$run"

$resultsDirectory = $null
$logFileName = 'stub.trx'
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '--results-directory' -and $i + 1 -lt $args.Count) { $resultsDirectory = $args[$i + 1] }
    if ($args[$i] -eq '--logger' -and $i + 1 -lt $args.Count -and $args[$i + 1] -match 'LogFileName=(.+)$') {
        $logFileName = $Matches[1]
    }
}

$emptyMarker = Join-Path $stubFolder 'empty-run.txt'
$total = 1
if ((Test-Path -LiteralPath $emptyMarker) -and ((Get-Content -LiteralPath $emptyMarker -Raw).Trim() -eq "$run")) {
    $total = 0
}

# A run killed part-way leaves a TRX whose XML never closes. The two malformed-TRX cases name a
# run number here to get one, because reading such a file is where a soak used to stop dead.
$malformedMarker = Join-Path $stubFolder 'malformed-run.txt'
$malformed = (Test-Path -LiteralPath $malformedMarker) -and
    ((Get-Content -LiteralPath $malformedMarker -Raw).Trim() -eq "$run")

if ($resultsDirectory) {
    New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
    if ($malformed) {
        $trx = '<?xml version="1.0" encoding="UTF-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">' +
            '<ResultSummary><Counters total='
    }
    else {
        $trx = '<?xml version="1.0" encoding="UTF-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">' +
            "<ResultSummary><Counters total=""$total"" passed=""$total"" failed=""0"" /></ResultSummary></TestRun>"
    }
    Set-Content -LiteralPath (Join-Path $resultsDirectory $logFileName) -Value $trx -Encoding utf8
}

$failMarker = Join-Path $stubFolder 'fail-run.txt'
if ((Test-Path -LiteralPath $failMarker) -and ((Get-Content -LiteralPath $failMarker -Raw).Trim() -eq "$run")) {
    Write-Output "stub dotnet test: forced failure on run $run"
    exit 1
}

Write-Output 'stub dotnet test'
exit 0
'@

    Set-Content -LiteralPath (Join-Path $root 'scripts\test-fast.ps1') -Encoding utf8 -Value @'
param([string]$Mode, [string]$Configuration, [switch]$NoBuild, [string]$BaseRef)
$repoRoot = Split-Path -Parent $PSScriptRoot
$stubFolder = Join-Path $repoRoot 'stub'
$callsPath = Join-Path $stubFolder 'testfast-calls.txt'
Add-Content -LiteralPath $callsPath -Value "Mode=$Mode NoBuild=$NoBuild Reuse=$env:AHKFLOW_GATE_REUSE"
Add-Content -LiteralPath (Join-Path $stubFolder 'steps.txt') -Value "test-fast Mode=$Mode BaseRef=$BaseRef"

# The Gate's PowerShell step. It records what the evidence folder held when it started and
# whether a fixed change was in the tree, then leaves a file of its own in the evidence folder,
# the way a real run leaves evidence. The Gate cases read that record.
if ($Mode -eq 'PowerShell') {
    $powerShellRun = @(Get-Content -LiteralPath $callsPath | Where-Object { $_ -like 'Mode=PowerShell *' }).Count
    $evidenceRoot = $env:AHKFLOW_GATE_EVIDENCE_ROOT
    $held = @(Get-ChildItem -LiteralPath $evidenceRoot -File -ErrorAction SilentlyContinue | ForEach-Object Name | Sort-Object) -join ','
    $changed = @('docs/development/testing-workflow.md', 'scripts/watch-task.ps1',
        'src/Backend/AHKFlowApp.Domain/Entities/Category.cs' |
        Where-Object { (Get-Content -LiteralPath (Join-Path $repoRoot $_) -Raw) -match 'gate-measure' }).Count -gt 0
    Add-Content -LiteralPath (Join-Path $stubFolder 'evidence-seen.txt') -Value "run=$powerShellRun held=$held changed=$changed"
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $evidenceRoot "run-$powerShellRun.txt") -Value 'evidence'
    $progressFolder = Join-Path $repoRoot 'TestResults/progress'
    New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $progressFolder 'run-powershell-suites.json') -Value "{ ""run"": $powerShellRun }"
    $failAt = Join-Path $stubFolder 'fail-powershell.txt'
    if ((Test-Path -LiteralPath $failAt) -and ((Get-Content -LiteralPath $failAt -Raw).Trim() -eq "$powerShellRun")) {
        throw 'PowerShell suites failed.'
    }
}

$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') -Value "test-fast owner=$owner"

# Gated Lane cases also exercise the delegated checkout reacquisition.
$delegateLock = $null
try {
if (Test-Path (Join-Path $stubFolder 'gated')) {
    . (Join-Path $PSScriptRoot 'test-run-lock.common.ps1')
    $delegateLock = Enter-AhkFlowTestRunLock -RepoRoot $repoRoot -Mode $Mode
}

# A case that does not write 'sleeps.txt' gets runs of different lengths: 1st longest, 3rd
# middle. Sorted they are 0.10 / 0.30 / 0.90 s: median 0.30 s, mean 0.43 s.
#
# The reported-median case asserts each printed number against the runs the harness itself printed, so no
# threshold here has to survive machine load. It once compared the mean against the median with
# a fixed 0.05 s margin, which a slow run could close by accident. The fixed-value case above
# owns that comparison now, where the numbers are constants and nothing can move them.
$run = @(Get-Content -LiteralPath $callsPath).Count
& (Join-Path $repoRoot 'scripts/lane-observation.ps1') "fast-$run"
if (Test-Path (Join-Path $stubFolder 'fail-fast')) { throw 'Forced timed invocation failure.' }

# The sleeps this fixture uses, in milliseconds, one per run. A case writes 'sleeps.txt' to
# choose them, which is how the warm-up cases get a slow head and a flat tail. The fallback is
# the original cycle.
$sleepsPath = Join-Path $stubFolder 'sleeps.txt'
if (Test-Path -LiteralPath $sleepsPath) {
    $sleeps = @((Get-Content -LiteralPath $sleepsPath -Raw).Trim() -split ',' | ForEach-Object { [int]$_.Trim() })
}
else {
    $sleeps = @(900, 100, 300)
}
$sleep = $sleeps[($run - 1) % $sleeps.Count]
Start-Sleep -Milliseconds $sleep
} finally {
    if ($null -ne $delegateLock) { Exit-AhkFlowTestRunLock -Handle $delegateLock }
}
'@

    # Gate Mode calls git for the revision and for 'git diff --check'. The stub logs into the
    # shared step log and answers rev-parse with a fixed commit id. The Gate cases pass -BaseRef,
    # so nothing asks gh for a pull request base.
    Set-Content -LiteralPath (Join-Path $root 'stub\git.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
Add-Content -LiteralPath (Join-Path $stubFolder 'steps.txt') -Value ('git ' + ($args -join ' '))
if ($args[0] -eq 'rev-parse') { Write-Output '0123456789abcdef0123456789abcdef01234567' }
exit 0
'@

    # The three files Gate Mode's -Change appends a line to. Each has its own line ending, and
    # the .cs file has a byte order mark, so the restore cases compare real bytes.
    $changeFiles = @{
        'docs/development/testing-workflow.md' = [Text.Encoding]::UTF8.GetBytes("# Testing`n`nText.`n")
        'scripts/watch-task.ps1' = [Text.Encoding]::UTF8.GetBytes("param()`r`nWrite-Host 'watch'`r`n")
        'src/Backend/AHKFlowApp.Domain/Entities/Category.cs' = [byte[]](0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes("namespace X;`r`n")
    }
    foreach ($relative in $changeFiles.Keys) {
        $path = Join-Path $root $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllBytes($path, $changeFiles[$relative])
    }

    return $root
}

function Remove-HarnessFixture {
    param([string] $Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Harness {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    # The stub folder goes first on PATH so 'dotnet' resolves to dotnet.ps1. PowerShell finds a
    # .ps1 by its bare name and passes arguments as an array, so the ';' inside the --logger
    # value survives; a .cmd shim would split it.
    $previousPath = $env:PATH
    $previousHolder = $env:AHKFLOW_TEST_LANES_HOLDER
    $previousEvidence = $env:AHKFLOW_GATE_EVIDENCE_ROOT
    if ([string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_ROOT) -and
        [string]::IsNullOrWhiteSpace($previousHolder)) { $env:AHKFLOW_TEST_LANES_HOLDER = "$PID" }
    $env:PATH = (Join-Path $Root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
    # Gate Mode saves and restores the evidence folder. Point it into the fixture, never at the
    # real TestResults folder of this checkout.
    $env:AHKFLOW_GATE_EVIDENCE_ROOT = Join-Path $Root 'evidence'
    try {
        $output = & $hostExe -NoProfile -File (Join-Path $Root 'scripts\measure-test-modes.ps1') @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $env:PATH = $previousPath
        $env:AHKFLOW_TEST_LANES_HOLDER = $previousHolder
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = $previousEvidence
    }
}

function New-GateFixture {
    # A harness fixture whose test-fast stub does not sleep. Gate Mode calls it twice a run.
    $root = New-HarnessFixture
    Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '0' -Encoding utf8
    return $root
}

function Get-GateStepLines {
    # The step log without the revision lookups, which are not Gate steps.
    param([string] $Root)
    @(Get-Content -LiteralPath (Join-Path $Root 'stub\steps.txt') | Where-Object { $_ -notlike 'git rev-parse*' })
}

Write-Host "Testing $(Join-Path $repoRoot 'scripts\measure-test-modes.ps1')"

Invoke-TestCase 'KeepBuildInRun leaves -NoBuild off the test-fast call' {
    $root = New-HarnessFixture
    try {
        # The case checks calls and signals, never run times, so the stub does not sleep.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '0' -Encoding utf8
        # -NoBuild here is the harness's own one-build-up-front switch. -KeepBuildInRun governs
        # what each run is asked to do, and the two are deliberately independent.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '1', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild', '-KeepBuildInRun')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 1) "Expected 1 test-fast.ps1 call, got $($calls.Count)."
        Assert-True (@($calls | Where-Object { $_ -match 'NoBuild=False' }).Count -eq 1) `
            "-KeepBuildInRun must leave -NoBuild off the call. Calls: $($calls -join ' | ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Two measurements in one Mode keep both sessions' {
    $root = New-HarnessFixture
    try {
        # The case checks calls and signals, never run times, so the stub does not sleep.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '0' -Encoding utf8
        # Backlog 140 took two sessions back to back in one Mode, and the second invocation deleted
        # the first one's artifacts. Each invocation writes its own session folder now, and never
        # removes an earlier one. The stub runs finish within a second, so the two sessions also
        # prove that two invocations in the same second do not collide.
        $first = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '2', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($first.ExitCode -eq 0) "Expected exit code 0 from the first session, got $($first.ExitCode). Output: $($first.Output)"
        $second = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '1', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($second.ExitCode -eq 0) "Expected exit code 0 from the second session, got $($second.ExitCode). Output: $($second.Output)"

        $modeRoot = Join-Path $root 'TestResults\measure-test-modes\Fast'
        $sessions = @(Get-ChildItem -LiteralPath $modeRoot -Directory -Filter 'session-*' -ErrorAction SilentlyContinue)
        Assert-True ($sessions.Count -eq 2) "Expected 2 session folders after two invocations, got $($sessions.Count)."

        if ($sessions.Count -eq 2) {
            $runCounts = @($sessions | ForEach-Object { @(Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'run-*').Count } | Sort-Object)
            Assert-True (($runCounts -join ',') -eq '1,2') "Expected one session with 2 counted runs and one with 1, got $($runCounts -join ',')."

            foreach ($session in $sessions) {
                foreach ($run in @(Get-ChildItem -LiteralPath $session.FullName -Directory -Filter 'run-*')) {
                    $recorded = Join-Path $run.FullName 'run.json'
                    Assert-True (Test-Path -LiteralPath $recorded) "Expected $recorded to hold the run's elapsed seconds."
                }
            }
        }
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Get-AhkFlowMedian is the middle sorted value, and the mean of the middle two when even' {
    # Fixed values and no wall clock at all. The case below proves the harness prints the median it
    # computed; this case proves the computation, and no amount of machine load can move it.
    Assert-True ((Get-AhkFlowMedian -Values @(0.9, 0.1, 0.3)) -eq 0.3) `
        'An odd count is the middle of the sorted values, and the input is not pre-sorted.'
    Assert-True ((Get-AhkFlowMedian -Values @(4, 1, 3, 2)) -eq 2.5) `
        'An even count is the mean of the middle two sorted values.'
    Assert-True ((Get-AhkFlowMedian -Values @(7)) -eq 7) 'One value is its own median.'

    # The discriminating case. Mean 28.75, median 5: a median that quietly became a mean fails
    # here by a wide margin, with no threshold to tune.
    Assert-True ((Get-AhkFlowMedian -Values @(5, 5, 5, 100)) -eq 5) `
        'The median ignores an outlier that moves the mean.'

    $threw = $false
    try { Get-AhkFlowMedian -Values @() } catch { $threw = $true }
    Assert-True $threw 'An empty set has no median, and silently returning zero would read as a fast run.'
}

Invoke-TestCase 'Get-AhkFlowRelativeSpread is the range as a share of the median' {
    # Fixed values, no wall clock. 20 minus 10 over a median of 15 is two thirds of the median.
    $spread = Get-AhkFlowRelativeSpread -Values @(10, 15, 20)
    Assert-True ([Math]::Abs($spread - 66.6667) -lt 0.01) "Expected 66.67 percent, got $spread."

    Assert-True ((Get-AhkFlowRelativeSpread -Values @(7, 7, 7)) -eq 0) `
        'Identical runs spread by nothing at all.'

    # The record for backlog 150. Window 1 was the coldest of the three measurements and reads as
    # the tightest, which is why the documentation says this figure does not detect a cold tree.
    $coldWindow = Get-AhkFlowRelativeSpread -Values @(91.21, 85.46, 96.13, 87.87, 88.40)
    $settledWindow = Get-AhkFlowRelativeSpread -Values @(55.64, 51.10, 53.68, 51.15, 51.53, 54.45, 56.79, 57.92, 68.64, 62.83)
    Assert-True ($coldWindow -lt $settledWindow) `
        "The record says the cold window is the tighter one: cold $coldWindow against settled $settledWindow."

    $threw = $false
    try { Get-AhkFlowRelativeSpread -Values @() } catch { $threw = $true }
    Assert-True $threw 'An empty set has no spread, and returning zero would read as a perfect measurement.'
}

Invoke-TestCase 'Get-AhkFlowTestCount returns zero for every shape of TRX nobody can read' {
    # A killed run leaves one of three things behind, and only one of them is a parse error.
    # A zero-byte file is the likeliest: the logger creates the file, then the process dies
    # before it writes anything. Get-Content -Raw returns $null for that, [xml]$null assigns
    # without throwing, and the null then throws on the first method call - past the catch.
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ('trx-unreadable-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $probe -Force | Out-Null
    try {
        $zeroByte = Join-Path $probe 'zero.trx'
        New-Item -ItemType File -Path $zeroByte -Force | Out-Null
        Assert-True ((Get-Item -LiteralPath $zeroByte).Length -eq 0) 'The probe file must really be zero bytes.'
        Assert-True ((Get-AhkFlowTestCount -TrxPath $zeroByte) -eq 0) 'A zero-byte TRX counts zero tests.'

        $whitespace = Join-Path $probe 'blank.trx'
        Set-Content -LiteralPath $whitespace -Value '   ' -Encoding utf8
        Assert-True ((Get-AhkFlowTestCount -TrxPath $whitespace) -eq 0) 'A whitespace-only TRX counts zero tests.'

        $truncated = Join-Path $probe 'cut.trx'
        Set-Content -LiteralPath $truncated -Value '<?xml version="1.0"?><TestRun><ResultSummary><Counters total=' -Encoding utf8
        Assert-True ((Get-AhkFlowTestCount -TrxPath $truncated) -eq 0) 'A truncated TRX counts zero tests.'

        Assert-True ((Get-AhkFlowTestCountFromResults -ResultsDirectory $probe) -eq 0) `
            'The directory entry point the soak calls must answer zero as well.'
    }
    finally { Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'The reported median is the middle of the sorted runs, and the mean line is the mean' {
    $root = New-HarnessFixture
    try {
        # Runs of different lengths, so the median and the mean differ: sorted 0.02 / 0.06 / 0.18 s.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '180,20,60' -Encoding utf8

        # -WarmUpRuns 0 because this case counts calls. The default of 2 would add two more.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '3', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # Timing mode calls the Mode once per run, and every run passes -NoBuild.
        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 3) "Expected 3 test-fast.ps1 calls, got $($calls.Count)."
        Assert-True (@($calls | Where-Object { $_ -match 'NoBuild=True' }).Count -eq 3) `
            "Every timing run must pass -NoBuild. Calls: $($calls -join ' | ')"

        # Every number here comes from the harness's own output, so both sides of each assertion
        # move together. Load changes what the runs are; it cannot make the median stop being the
        # middle one, nor the mean line stop being their average. The case above owns the arithmetic.
        $text = $result.Output -join "`n"
        Assert-True ($text -match 'runs\s+:\s+([\d.,/ ]+)') "No runs line. Output: $text"
        $runs = @($Matches[1] -split '/' | ForEach-Object { [double]($_.Trim() -replace ',', '.') })
        Assert-True ($text -match 'median\s+:\s+([\d.,]+)') "No median line. Output: $text"
        $median = [double]($Matches[1] -replace ',', '.')
        Assert-True ($text -match 'mean\s+:\s+([\d.,]+)') "No mean line. Output: $text"
        $mean = [double]($Matches[1] -replace ',', '.')

        $sorted = @($runs | Sort-Object)
        Assert-True ([Math]::Abs($median - $sorted[1]) -lt 0.02) `
            "Median $median must be the middle sorted run $($sorted[1]). Runs: $($runs -join ', ')"
        Assert-True ([Math]::Abs($mean - ($runs | Measure-Object -Average).Average) -lt 0.02) `
            "Mean $mean must be the average of the runs. Runs: $($runs -join ', ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A slow head is discarded and the median is the flat tail' {
    $root = New-HarnessFixture
    try {
        # Three slow runs then two flat ones. The median of all five is 0.60 s. The median of the
        # counted tail is near 0 s. A harness that forgot to discard cannot land near 0 s by
        # accident, and 0.30 s of margin on each side survives machine load.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '600,600,600,0,0' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '2', '-WarmUpRuns', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 5) "Expected 3 warm-up plus 2 counted runs, got $($calls.Count)."

        $text = $result.Output -join "`n"
        Assert-True ($text -match 'median\s+:\s+([\d.,]+)') "No median line. Output: $text"
        $median = [double]($Matches[1] -replace ',', '.')
        Assert-True ($median -lt 0.3) `
            "The median must come from the flat tail near 0 s, not the whole list near 0.60 s. Got $median."
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The discarded runs are printed, with how many there were' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '0' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '3', '-WarmUpRuns', '2', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # The reader has to see the decay to judge it. A bare count of 2 cannot be judged at all.
        $text = $result.Output -join "`n"
        Assert-True ($text -match 'warm-up\s*:\s+([\d.,/ ]+)\(discarded, (\d+)\)') `
            "No warm-up line naming the discarded runs and their count. Output: $text"
        $discarded = @($Matches[1] -split '/' | ForEach-Object { [double]($_.Trim() -replace ',', '.') })
        Assert-True ($discarded.Count -eq 2) "Expected two discarded runs printed, got $($discarded.Count)."
        Assert-True ([int]$Matches[2] -eq 2) "The printed count must be 2, got $($Matches[2])."
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The warm-up ceiling caps the runs and never the wait' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '300' -Encoding utf8

        # A build output file written just now, so the settle clock is not satisfied.
        $binFolder = Join-Path $root 'tests\FakeProject\bin\Release\net10.0'
        New-Item -ItemType Directory -Path $binFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $binFolder 'Fake.dll') -Value 'not a real assembly' -Encoding utf8

        # Four warm-up runs at 300 ms cannot fill a 5 s target, so the ceiling is reached first.
        # Backlog 188 tried 100 ms and 3 s. On a GitHub runner three warm-ups filled 3 s, so the
        # ceiling never ran: start-up costs about a second a run there. Keep the 5 s margin.
        # That is the shape of a real short Mode: the Fast Mode measured 13.5 to 16.1 s a run, and
        # a 600 s target would need more than forty runs to fill. The ceiling must cap the runs
        # without ever letting the counted runs start on a tree that is still cold.
        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '1', '-WarmUpRuns', '1',
            '-SettleSeconds', '5', '-MaxWarmUpRuns', '4', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # Warm-ups past the minimum of one, capped at four, then one counted run.
        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 5) "Expected 4 warm-up plus 1 counted run, got $($calls.Count)."

        $text = $result.Output -join "`n"
        Assert-True ($text -match 'warm-up ceiling') `
            "Reaching the ceiling must say so, or a reader reads a cold median as a settled one. Output: $text"
        Assert-True ($text -match 'Waiting') `
            "The ceiling caps the runs, not the wait. It must wait out the rest. Output: $text"

        # The assertion that proves the wait really happened. Without it the counted runs start
        # about 2 s after the build, and the build-age line reads well under the 5 s target.
        Assert-True ($text -match 'built\s+:\s+([\d.,]+)\s+s') "No build-age line. Output: $text"
        $builtAge = [double]($Matches[1] -replace '[,.]', '')
        Assert-True ($builtAge -ge 5) `
            "The counted runs must start at or after the 5 s settle target, but the build age reads $builtAge s. Output: $text"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'With no build output the settle clock is off, and it says so' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '50' -Encoding utf8

        # The fixture has tests\FakeProject but no bin folder, so nothing dates the build.
        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '1', '-WarmUpRuns', '1', '-SettleSeconds', '3600', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 2) "Expected 1 warm-up plus 1 counted run, got $($calls.Count)."

        # Silence would be the worst outcome: the clock off and nobody told.
        $text = $result.Output -join "`n"
        Assert-True ($text -match 'no build output') `
            "A settle clock that cannot find a build date must say so. Output: $text"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The report names the spread and how old the build was' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '20,60,180' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '3', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # Both sides of the assertion come from the harness's own output, so machine load moves
        # them together. The fixed-value case above owns the arithmetic.
        $text = $result.Output -join "`n"
        Assert-True ($text -match 'runs\s+:\s+([\d.,/ ]+)') "No runs line. Output: $text"
        $runs = @($Matches[1] -split '/' | ForEach-Object { [double]($_.Trim() -replace ',', '.') })
        Assert-True ($text -match 'spread\s+:\s+([\d.,]+)') "No spread line. Output: $text"
        $spread = [double]($Matches[1] -replace ',', '.')

        $expected = Get-AhkFlowRelativeSpread -Values $runs
        Assert-True ([Math]::Abs($spread - $expected) -lt 0.5) `
            "Spread $spread must match the printed runs, which give $expected. Runs: $($runs -join ', ')"

        # The fixture has no build output, so this run must say the age is unknown rather than
        # print a number it cannot have.
        Assert-True ($text -match 'built\s+:\s+unknown') "No build-age line. Output: $text"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Soak mode prepares one container for the whole soak and leaves it running' {
    $root = New-HarnessFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $sql = @(Get-Content -LiteralPath (Join-Path $root 'sql-calls.txt'))
        $started = @($sql | Where-Object { $_ -like 'start *' })
        $stopped = @($sql | Where-Object { $_ -like 'stop *' })

        # One start for three repetitions. Backlog 133: every SQL-backed test drops the database it
        # needs empty, so run two meets a warm server the way a real second run does.
        Assert-True ($started.Count -eq 1) "Expected 1 container start, got $($started.Count). Log: $($sql -join ' | ')"

        # And no stop at all. A soak that removed its container would hide the very state the
        # reuse exists to soak.
        Assert-True ($stopped.Count -eq 0) "Expected no container stop, got $($stopped.Count). Log: $($sql -join ' | ')"

        # The same run holds the lock for every repetition. Backlog 201 merged that check here.
        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $runs = @($signals | Where-Object { $_ -like 'test *' })
        Assert-True ($runs.Count -eq 3) "Expected three soak runs, got $($runs.Count)."
        Assert-True (@($runs | Where-Object { $_ -match 'owner=True' }).Count -eq 3) `
            "Soak mode calls dotnet test directly, so it holds the lock throughout. Signals: $($signals -join ' | ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A failing soak run is counted and named, and the soak still finishes' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\fail-run.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        # All three repetitions must have run. Stopping at the first failure is the defect. The
        # container starts once now, so a run count comes from the test invocations instead.
        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $testCalls = @($signals | Where-Object { $_ -like 'test *' })
        Assert-True ($testCalls.Count -eq 3) `
            "The soak must finish all 3 runs after run 2 fails. Signals: $($signals -join ' | ')"
        Assert-True ($text -match 'passed\s+:\s+2 of 3') "Expected 'passed : 2 of 3'. Output: $text"
        Assert-True ($text -match 'failed runs\s+:\s+2') "Expected run 2 named. Output: $text"
        Assert-True ($result.ExitCode -ne 0) 'A soak with a failed run must fail overall.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A soak run that exits zero with an empty TRX is not a pass' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\empty-run.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        Assert-True ($text -match 'ran zero tests\s+:\s+2') `
            "Run 2 discovered nothing and must be named. Output: $text"
        Assert-True (-not ($text -match 'passed\s+:\s+3 of 3')) `
            "An empty run must not count as passed. Output: $text"
        Assert-True ($result.ExitCode -ne 0) 'A soak with an empty run must fail overall.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A soak run that fails with a half-written TRX is counted, not thrown' {
    $root = New-HarnessFixture
    try {
        # Run 2 dies part-way: it exits non-zero AND leaves a TRX whose XML never closes. The
        # soak used to read the count before it checked the exit code, so the parse error escaped
        # the loop and run 3 never happened. A failed run is data; it must not end the soak.
        Set-Content -LiteralPath (Join-Path $root 'stub\fail-run.txt') -Value '2' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $root 'stub\malformed-run.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        # The container starts once now, so a run count comes from the test invocations instead.
        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $testCalls = @($signals | Where-Object { $_ -like 'test *' })
        Assert-True ($testCalls.Count -eq 3) `
            "The soak must finish all 3 runs after run 2 dies mid-write. Signals: $($signals -join ' | ')"
        Assert-True ($text -match 'passed\s+:\s+2 of 3') "Expected 'passed : 2 of 3'. Output: $text"
        Assert-True ($text -match 'failed runs\s+:\s+2') "Expected run 2 named as failed. Output: $text"
        Assert-True ($result.ExitCode -ne 0) 'A soak with a failed run must fail overall.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A soak run that exits zero with an unreadable TRX is not a pass' {
    $root = New-HarnessFixture
    try {
        # Exit code zero, and a TRX that will not parse. The count is unknown, so the run proved
        # nothing and belongs with the empty ones. Reading it must still not end the soak.
        Set-Content -LiteralPath (Join-Path $root 'stub\malformed-run.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        # The container starts once now, so a run count comes from the test invocations instead.
        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $testCalls = @($signals | Where-Object { $_ -like 'test *' })
        Assert-True ($testCalls.Count -eq 3) `
            "The soak must finish all 3 runs. Signals: $($signals -join ' | ')"
        Assert-True ($text -match 'ran zero tests\s+:\s+2') `
            "Run 2 wrote an unreadable TRX and must be named. Output: $text"
        Assert-True (-not ($text -match 'passed\s+:\s+3 of 3')) `
            "An unreadable TRX must not count as passed. Output: $text"
        Assert-True ($result.ExitCode -ne 0) 'A soak with an unreadable TRX must fail overall.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A soak with both an empty run and a failed run names both' {
    $root = New-HarnessFixture
    try {
        # Run 2 comes back empty, run 3 genuinely fails. The summary used to throw inside the
        # first block it matched, so the second list never printed and the reader went hunting
        # a filter typo while a real failure sat unnamed.
        Set-Content -LiteralPath (Join-Path $root 'stub\empty-run.txt') -Value '2' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $root 'stub\fail-run.txt') -Value '3' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        Assert-True ($text -match 'ran zero tests\s+:\s+2') "Run 2 must be named as empty. Output: $text"
        Assert-True ($text -match 'failed runs\s+:\s+3') "Run 3 must be named as failed. Output: $text"
        Assert-True ($text -match 'passed\s+:\s+1 of 3') "Only run 1 passed. Output: $text"
        Assert-True ($result.ExitCode -ne 0) 'A soak with either kind of trouble must fail overall.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The connection-string variable is restored in the process that changed it' {
    $root = New-HarnessFixture
    try {
        # In-process on purpose. The harness sets $env:AHKFLOW_TEST_SQL_CONNECTION_STRING inside
        # its own process, so asserting on the parent's copy after a child process exits passes
        # whatever the harness does - the child's environment was never the parent's.
        $previousPath = $env:PATH
        $previousConn = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING
        $previousHolder = $env:AHKFLOW_TEST_LANES_HOLDER
        $env:AHKFLOW_TEST_LANES_HOLDER = "$PID"
        $env:PATH = (Join-Path $root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
        $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = 'sentinel-value'
        try {
            & (Join-Path $root 'scripts\measure-test-modes.ps1') -Soak 'tests/FakeProject' -Runs 2 -NoBuild | Out-Null
            Assert-True ($env:AHKFLOW_TEST_SQL_CONNECTION_STRING -eq 'sentinel-value') `
                "Expected the sentinel back, got '$($env:AHKFLOW_TEST_SQL_CONNECTION_STRING)'."

            # And prove it was actually replaced during the run, or the assertion above is vacuous.
            $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
            $duringRun = @($signals | Where-Object { $_ -like 'test *' })
            Assert-True (@($duringRun | Where-Object { $_ -match 'conn=Server=' }).Count -eq 2) `
                "Each run must see the container's connection string. Signals: $($signals -join ' | ')"
        }
        finally {
            $env:PATH = $previousPath
            $env:AHKFLOW_TEST_SQL_CONNECTION_STRING = $previousConn
            $env:AHKFLOW_TEST_LANES_HOLDER = $previousHolder
        }
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The build runs inside the lock, and timing mode releases it before the first run' {
    $root = New-HarnessFixture
    try {
        # The case checks calls and signals, never run times, so the stub does not sleep.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '0' -Encoding utf8
        # Note the absent -NoBuild: this case is about the build.
        # -WarmUpRuns 0 because this case counts calls. The default of 2 would add two more.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '2', '-WarmUpRuns', '0', '-SettleSeconds', '0')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $build = @($signals | Where-Object { $_ -like 'build *' })
        Assert-True ($build.Count -eq 1) "Expected one build signal, got $($build.Count)."
        Assert-True ($build[0] -match 'owner=True') `
            "The build must hold the run lock. Signals: $($signals -join ' | ')"

        $modeRuns = @($signals | Where-Object { $_ -like 'test-fast *' })
        Assert-True ($modeRuns.Count -eq 2) "Expected two Mode runs, got $($modeRuns.Count)."
        Assert-True (@($modeRuns | Where-Object { $_ -match 'owner=False' }).Count -eq 2) `
            "Timing mode must release the lock before calling test-fast.ps1, which takes it itself. Signals: $($signals -join ' | ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

foreach ($scenario in @(
    @{ Name = 'Timing'; Arguments = @('-Runs', '2', '-WarmUpRuns', '1', '-SettleSeconds', '0'); Calls = @('build', 'fast-1', 'fast-2', 'fast-3'); Held = 4 },
    @{ Name = 'Soak'; Arguments = @('-Soak', 'tests/FakeProject', '-Runs', '3'); Calls = @('build', 'soak-1', 'soak-2', 'soak-3'); Held = 2 }
)) {
    Invoke-TestCase "$($scenario.Name) waits before work and holds its share across every call" {
        $root = New-HarnessFixture
        $pool = New-PinnedLanePool 4
        $child = $null; $blocker = $null
        try {
            Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root } -Body {
                $previousPath = $env:PATH
                try {
                    $env:PATH = (Join-Path $root 'stub') + [IO.Path]::PathSeparator + $previousPath
                    Set-Content (Join-Path $root 'stub/gated') 'yes'
                    Set-Content (Join-Path $root 'stub/sleeps.txt') '0'
                    # Leave only lane 0 free so both shares collect it then wait.
                    $blocker = @(1..3 | ForEach-Object { Open-AhkFlowLaneFile (Join-Path $pool.Root "lane-$_.lock") })
                    $child = Start-LaneChildProcess (@('-NoProfile', '-File', (Join-Path $root 'scripts/measure-test-modes.ps1')) + $scenario.Arguments)
                    [void](Wait-LanePath (Join-Path $root 'stub/waiting') 10 $child)
                    Assert-True (-not (Test-Path (Join-Path $root 'stub/signals.txt'))) 'No build or timed work may start before admission.'
                    Assert-True (-not (Test-Path (Join-Path $root 'TestResults/measure-test-modes'))) 'Measurement artifacts must start after admission.'
                    $blocker.Dispose(); $blocker = $null
                    Publish-LaneSignal (Join-Path $root 'stub/retry')
                    foreach ($call in $scenario.Calls) {
                        $line = Wait-LanePath (Join-Path $root "stub/$call.ready") 10 $child
                        Assert-True ($line.Trim() -eq "$call held=$($scenario.Held) holder=$($child.Process.Id)") "Unexpected Lane observation: $line"
                        Assert-True ((Get-RunLaneCount $pool) -eq $scenario.Held) 'Reservation must remain live while the call is gated.'
                        Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $root '.test-run.lock')) 'Build, delegated Fast, and soak must each hold the checkout lock.'
                        Publish-LaneSignal (Join-Path $root "stub/$call.release")
                    }
                    $result = Wait-LaneChildProcess $child 10
                    Assert-True ($result.ExitCode -eq 0) "Harness failed: $($result.Error)"
                    Assert-True ((Get-RunLaneCount $pool) -eq 0) 'Completion must release every Lane.'
                } finally {
                    Stop-LaneChildProcess $child; $child = $null
                    if ($null -ne $blocker) { $blocker.Dispose(); $blocker = $null }
                    $env:PATH = $previousPath
                }
            }
        } finally { Stop-LaneChildProcess $child; if ($null -ne $blocker) { $blocker.Dispose() }; Remove-PinnedLanePool $pool; Remove-HarnessFixture $root }
    }
}

Invoke-TestCase 'Whole blocks a competing acquirer through the parent checkout handoff' {
    $root = New-HarnessFixture; $pool = New-PinnedLanePool 4
    $child = $null; $contender = $null
    try {
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root } -Body {
            $previousPath = $env:PATH
            try {
                $env:PATH = (Join-Path $root 'stub') + [IO.Path]::PathSeparator + $previousPath
                foreach ($marker in @('gated', 'handoff-enabled')) { Set-Content (Join-Path $root "stub/$marker") 'yes' }
                Set-Content (Join-Path $root 'stub/sleeps.txt') '0'
                $child = Start-LaneChildProcess @('-NoProfile', '-File', (Join-Path $root 'scripts/measure-test-modes.ps1'), '-Runs', '1', '-WarmUpRuns', '0', '-SettleSeconds', '0')
                [void](Wait-LanePath (Join-Path $root 'stub/build.ready') 10 $child)
                Assert-True ((Get-RunLaneCount $pool) -eq 4) 'Build must hold Whole before the handoff.'
                Publish-LaneSignal (Join-Path $root 'stub/build.release')
                $holder = Wait-LanePath (Join-Path $root 'stub/handoff.ready') 10 $child
                Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $root '.test-run.lock'))) 'Parent must release checkout before the handoff gate.'

                $signals = @{
                    Acquired = Join-Path $pool.Root 'contender-acquired'
                    Release = Join-Path $pool.Root 'contender-release'
                    FailedAttempt = Join-Path $pool.Root 'contender-blocked'
                }
                $contender = Start-LaneHolder $pool.Root $signals Contender One 4
                $deadline = [Diagnostics.Stopwatch]::StartNew()
                while (-not (Test-Path "$($signals.FailedAttempt).done") -and -not (Test-Path "$($signals.Acquired).done")) {
                    Assert-True (-not $contender.Process.HasExited) 'Contender exited before attempting admission.'
                    Assert-True ($deadline.Elapsed.TotalSeconds -lt 10) 'Contender must acknowledge admission within its deadline.'
                    Start-Sleep -Milliseconds 20
                }
                Assert-True (-not (Test-Path "$($signals.Acquired).done")) 'Competing acquirer entered while the parent was handing checkout to Fast.'
                [void](Wait-LanePath $signals.FailedAttempt 10 $contender)
                Assert-True ($holder.Trim() -eq "$($child.Process.Id)") 'Handoff must retain the parent marker.'
                Assert-True ((Get-RunLaneCount $pool) -eq 4) 'Whole must remain held while the contender waits at the handoff.'

                Publish-LaneSignal (Join-Path $root 'stub/handoff.release')
                [void](Wait-LanePath (Join-Path $root 'stub/fast-1.ready') 10 $child)
                Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $root '.test-run.lock')) 'Fast must reacquire checkout while the contender waits.'
                Assert-True ((Get-RunLaneCount $pool) -eq 4) 'Fast must inherit the same Whole reservation.'
                Assert-True (-not (Test-Path "$($signals.Acquired).done")) 'Contender must stay blocked until the timing session finishes.'
                Publish-LaneSignal (Join-Path $root 'stub/fast-1.release')
                Assert-True ((Wait-LaneChildProcess $child 10).ExitCode -eq 0) 'Timing harness must complete normally.'
                [void](Wait-LanePath $signals.Acquired 10 $contender)
                Publish-LaneSignal $signals.Release
                Assert-True ((Wait-LaneChildProcess $contender 10).ExitCode -eq 0) 'Contender must acquire after the outer reservation ends.'
                Assert-True ((Get-RunLaneCount $pool) -eq 0) 'Both children must release their Lanes.'
            } finally {
                Stop-LaneChildProcess $child; $child = $null
                Stop-LaneChildProcess $contender; $contender = $null
                $env:PATH = $previousPath
            }
        }
    } finally { Stop-LaneChildProcess $child; Stop-LaneChildProcess $contender; Remove-PinnedLanePool $pool; Remove-HarnessFixture $root }
}

foreach ($soak in @($false, $true)) {
    Invoke-TestCase "Nested harness preserves its marker without adding Lanes (soak=$soak)" {
        $root = New-HarnessFixture; $pool = New-PinnedLanePool 4; $held = $null
        try {
            $held = Enter-AhkFlowLanes $pool.Root Half 4
            Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = 'inherited-owner' } -Body {
                $arguments = if ($soak) { @{ Soak = 'tests/FakeProject'; Runs = 2 } } else { @{ Runs = 2; WarmUpRuns = 1; SettleSeconds = 0 } }
                $previousPath = $env:PATH
                try {
                    $env:PATH = (Join-Path $root 'stub') + [IO.Path]::PathSeparator + $previousPath
                    & (Join-Path $root 'scripts/measure-test-modes.ps1') @arguments | Out-Null
                    Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -eq 'inherited-owner') 'Nested exit must preserve the marker in its own host.'
                } finally { $env:PATH = $previousPath }
                $lines = @(Get-Content (Join-Path $root 'stub/lanes.txt'))
                Assert-True ($lines.Count -eq $(if ($soak) { 3 } else { 4 })) 'Observe build and every delegated call.'
                foreach ($line in $lines) { Assert-True ($line -match 'held=2 holder=inherited-owner$') "Nested reservation changed: $line" }
                Assert-True ((Get-RunLaneCount $pool) -eq 2) 'Nested completion must preserve the parent reservation.'
            }
        } finally { Exit-AhkFlowLanes $held; Remove-PinnedLanePool $pool; Remove-HarnessFixture $root }
    }
}

foreach ($failure in @('fail-build', 'fail-fast', 'fail-run.txt', 'none')) {
    Invoke-TestCase "Same-host $failure restores its marker and releases its Lanes and checkout" {
        $root = New-HarnessFixture; $pool = New-PinnedLanePool 4
        try {
            Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
                $previousPath = $env:PATH
                try {
                    $env:PATH = (Join-Path $root 'stub') + [IO.Path]::PathSeparator + $previousPath
                    if ($failure -ne 'none') { Set-Content (Join-Path $root "stub/$failure") '1' }
                    Set-Content (Join-Path $root 'stub/sleeps.txt') '0'
                    $arguments = if ($failure -eq 'fail-run.txt') { @{ Soak = 'tests/FakeProject'; Runs = 2 } } else { @{ Runs = 1; WarmUpRuns = 0; SettleSeconds = 0 } }
                    $threw = $false
                    try { & (Join-Path $root 'scripts/measure-test-modes.ps1') @arguments | Out-Null } catch { $threw = $true }
                    Assert-True ($threw -eq ($failure -ne 'none')) 'Expected invocation outcome differed.'
                    $lines = @(Get-Content (Join-Path $root 'stub/lanes.txt'))
                    $expected = if ($failure -eq 'fail-run.txt') { 2 } else { 4 }
                    foreach ($line in $lines) { Assert-True ($line -match "held=$expected holder=$PID$") "Reservation missing before failure: $line" }
                    Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -eq '  ') 'Restore the exact previous marker in the same host.'
                    Assert-True ((Get-RunLaneCount $pool) -eq 0) 'Release Lanes after invocation.'
                    Assert-True (@(Get-ChildItem (Join-Path $pool.Root 'runs') -File).Count -eq 0) 'Completion must remove its advisory record.'
                    Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $root '.test-run.lock'))) 'Release checkout after invocation.'
                    $fresh = Enter-AhkFlowLaneRun Fresh $root Whole
                    try { Assert-True ($fresh.Lanes.Streams.Count -eq 4) 'Same host must acquire again.' } finally { Exit-AhkFlowLaneRun $fresh }
                } finally { $env:PATH = $previousPath }
            }
        } finally { Remove-PinnedLanePool $pool; Remove-HarnessFixture $root }
    }
}

Invoke-TestCase 'Cancelled admission cleans up in a surviving runspace before any work starts' {
    $root = New-HarnessFixture; $pool = New-PinnedLanePool 4; $blocker = $null; $worker = $null
    try {
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            try {
                $blocker = Open-AhkFlowLaneFile (Join-Path $pool.Root 'lane-1.lock')
                $worker = [PowerShell]::Create().AddScript({ param($Root); & (Join-Path $Root 'scripts/measure-test-modes.ps1') -Runs 1 -NoBuild -WarmUpRuns 0 -SettleSeconds 0 }).AddArgument($root)
                $async = $worker.BeginInvoke()
                [void](Wait-LanePath (Join-Path $root 'stub/waiting') 10)
                Assert-True ((Get-RunLaneCount $pool) -eq 4) 'Cancellation must interrupt three acquired Lanes plus the blocker.'
                Assert-True (-not (Test-Path (Join-Path $root 'stub/signals.txt'))) 'Admission must precede timed calls.'
                $stop = $worker.BeginStop($null, $null)
                Assert-True ($stop.AsyncWaitHandle.WaitOne(10000)) 'Cancellation must settle.'
                $worker.EndStop($stop)
                try { [void]$worker.EndInvoke($async) } catch [Management.Automation.PipelineStoppedException] { }
                Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -eq '  ') 'Cancelled entry must restore its marker.'
                Assert-True ((Get-RunLaneCount $pool) -eq 1) 'Cancellation must release the partial share.'
                Assert-True (@(Get-ChildItem (Join-Path $pool.Root 'runs') -File).Count -eq 0) 'Cancellation must remove its advisory record.'
                Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock'))) 'Cancellation must release admission lock.'
                Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $root '.test-run.lock'))) 'Cancellation must leave checkout available.'
                $blocker.Dispose(); $blocker = $null
                $worker.Commands.Clear()
                [void]$worker.AddScript({ param($Module, $Root); . $Module; $state = Enter-AhkFlowLaneRun Fresh $Root Whole; try { $state.Lanes.Streams.Count } finally { Exit-AhkFlowLaneRun $state } }).AddArgument((Join-Path $repoRoot 'scripts/test-lanes.common.ps1')).AddArgument($root)
                $fresh = $worker.BeginInvoke()
                Assert-True ($fresh.AsyncWaitHandle.WaitOne(10000)) 'Surviving runspace must acquire again.'
                $result = $worker.EndInvoke($fresh)
                Assert-True ($result[0] -eq 4) 'Surviving runspace must acquire Whole.'
                Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -eq '  ') 'Fresh invocation must restore marker.'
            } finally {
                if ($null -ne $worker) { $worker.Stop(); $worker.Dispose(); $worker = $null }
                if ($null -ne $blocker) { $blocker.Dispose(); $blocker = $null }
            }
        }
    } finally { Remove-PinnedLanePool $pool; Remove-HarnessFixture $root }
}

# Backlog 188. Gate Mode times the five Gate steps, so the record measures what a developer
# waits for before a pull request goes ready.

Invoke-TestCase 'Gate Mode runs the five Gate steps in order, once per run, and records their times' {
    $root = New-GateFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Gate', '-BaseRef', 'main', '-WarmUpRuns', '1', '-Runs', '2')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # The base must reach both the coverage step and git diff --check. A measurement that
        # falls back to the branch's real base counts this branch's own diff.
        $oneRun = @(
            'dotnet build AHKFlowApp.slnx --configuration Release',
            'dotnet format AHKFlowApp.slnx --verify-no-changes',
            'test-fast Mode=PowerShell BaseRef=',
            'test-fast Mode=Coverage BaseRef=main',
            'git diff --check main...HEAD')
        $expected = @($oneRun + $oneRun + $oneRun)
        $actual = Get-GateStepLines -Root $root
        Assert-True (($actual -join "`n") -eq ($expected -join "`n")) `
            "Expected the five steps three times. Got:`n$($actual -join "`n")"

        # The step times go into run.json, and their medians into record.json.

        $session = @(Get-ChildItem -LiteralPath (Join-Path $root 'TestResults\measure-test-modes\Gate') -Directory)
        Assert-True ($session.Count -eq 1) "Expected one session folder, got $($session.Count)."
        $stepNames = 'build,format,powershell,coverage,diff-check'
        foreach ($runFolder in @(Get-ChildItem -LiteralPath $session[0].FullName -Directory -Filter 'run-*')) {
            $run = Get-Content -LiteralPath (Join-Path $runFolder.FullName 'run.json') -Raw | ConvertFrom-Json
            Assert-True ((@($run.Steps.PSObject.Properties.Name) -join ',') -eq $stepNames) `
                "Expected the steps $stepNames in order, got $(@($run.Steps.PSObject.Properties.Name) -join ',')."
            $sum = (@($run.Steps.PSObject.Properties.Value) | Measure-Object -Sum).Sum
            Assert-True ($run.ElapsedSeconds -ge $sum - 0.05) "The total $($run.ElapsedSeconds) must cover the steps, which sum to $sum."
            Assert-True (Test-Path -LiteralPath (Join-Path $runFolder.FullName 'run-powershell-suites.json')) `
                "Each run must keep its own copy of the per-Suite times in $($runFolder.Name)."
        }

        $record = Get-Content -LiteralPath (Join-Path $session[0].FullName 'record.json') -Raw | ConvertFrom-Json
        Assert-True ($record.Revision -eq '0123456789abcdef0123456789abcdef01234567') "Expected the stub revision, got '$($record.Revision)'."
        Assert-True ($record.Mode -eq 'Gate') "Expected Mode Gate, got '$($record.Mode)'."
        Assert-True (@($record.Cases).Count -eq 1) "Expected one case without -Change, got $(@($record.Cases).Count)."
        Assert-True (@($record.Cases[0].RunSeconds).Count -eq 2) 'The record must keep every counted run total.'
        Assert-True ((@($record.Cases[0].StepMedians.PSObject.Properties.Name) -join ',') -eq $stepNames) `
            'The record must hold a median for each step.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Gate Mode with a change restores the changed file to its original bytes' {
    $root = New-GateFixture
    try {
        $paths = @('docs/development/testing-workflow.md', 'scripts/watch-task.ps1', 'src/Backend/AHKFlowApp.Domain/Entities/Category.cs')
        $before = @{}
        foreach ($relative in $paths) { $before[$relative] = [IO.File]::ReadAllBytes((Join-Path $root $relative)) }

        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Gate', '-BaseRef', 'main', '-Change', 'Docs,Script,Code', '-WarmUpRuns', '1', '-Runs', '1')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # The change must really have been in the tree during the timed runs, or the restore
        # assertion below proves nothing.
        $seen = @(Get-Content -LiteralPath (Join-Path $root 'stub\evidence-seen.txt'))
        Assert-True ($seen.Count -eq 7) "Expected 1 preparation and 6 timed runs, got $($seen.Count)."
        Assert-True ($seen[0] -match 'changed=False') "The preparation run must see the unchanged tree: $($seen[0])"
        Assert-True (@($seen | Select-Object -Skip 1 | Where-Object { $_ -match 'changed=True' }).Count -eq 6) `
            "Every timed run must see its change. Seen:`n$($seen -join "`n")"

        # The preparation run leaves run-1.txt. Every timed run must start with that file and
        # nothing else: the marker back, and the file the timed run before it wrote gone.
        foreach ($line in @($seen | Select-Object -Skip 1)) {
            Assert-True ($line -match 'held=run-1\.txt changed') "A timed run must start from the prepared evidence only: $line"
        }

        foreach ($relative in $paths) {
            $after = [IO.File]::ReadAllBytes((Join-Path $root $relative))
            Assert-True ([Convert]::ToBase64String($after) -eq [Convert]::ToBase64String($before[$relative])) `
                "$relative must hold its original bytes after the session."
        }
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Gate Mode with a change restores the file when a step fails' {
    $root = New-GateFixture
    try {
        $relative = 'scripts/watch-task.ps1'
        $before = [IO.File]::ReadAllBytes((Join-Path $root $relative))
        # Call 1 is the preparation run, so call 2 is the first run with the change applied.
        Set-Content -LiteralPath (Join-Path $root 'stub\fail-powershell.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Gate', '-BaseRef', 'main', '-Change', 'Script', '-WarmUpRuns', '1', '-Runs', '1')
        Assert-True ($result.ExitCode -ne 0) "A failing Gate step must fail the session. Output: $($result.Output)"
        Assert-True ($result.Output -match 'powershell') "The error must name the failing step. Output: $($result.Output)"

        $seen = @(Get-Content -LiteralPath (Join-Path $root 'stub\evidence-seen.txt'))
        Assert-True ($seen[-1] -match 'run=2 .*changed=True') "The failing run must have had the change applied: $($seen -join ' | ')"
        $after = [IO.File]::ReadAllBytes((Join-Path $root $relative))
        Assert-True ([Convert]::ToBase64String($after) -eq [Convert]::ToBase64String($before)) `
            "$relative must hold its original bytes after a failed step."
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Gate Mode with -NoEvidenceReuse sets AHKFLOW_GATE_REUSE to off and restores it' {
    $root = New-GateFixture
    # In-process, like the connection-string case: a child process's environment never reaches
    # the parent, so only an in-process run can show the variable restored.
    $previousPath = $env:PATH
    $previousReuse = $env:AHKFLOW_GATE_REUSE
    $previousHolder = $env:AHKFLOW_TEST_LANES_HOLDER
    $previousEvidence = $env:AHKFLOW_GATE_EVIDENCE_ROOT
    try {
        $env:AHKFLOW_TEST_LANES_HOLDER = "$PID"
        $env:PATH = (Join-Path $root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = Join-Path $root 'evidence'
        $env:AHKFLOW_GATE_REUSE = 'sentinel-value'
        & (Join-Path $root 'scripts\measure-test-modes.ps1') -Mode Gate -BaseRef main -NoEvidenceReuse -WarmUpRuns 1 -Runs 1 | Out-Null
        Assert-True ($env:AHKFLOW_GATE_REUSE -eq 'sentinel-value') `
            "Expected the sentinel back, got '$($env:AHKFLOW_GATE_REUSE)'."

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 4) "Expected 2 runs of 2 test-fast calls, got $($calls.Count)."
        Assert-True (@($calls | Where-Object { $_ -match 'Reuse=off$' }).Count -eq 4) `
            "Every call in every run must see reuse off. Calls: $($calls -join ' | ')"
    }
    finally {
        $env:PATH = $previousPath
        $env:AHKFLOW_GATE_REUSE = $previousReuse
        $env:AHKFLOW_TEST_LANES_HOLDER = $previousHolder
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = $previousEvidence
        Remove-HarnessFixture -Root $root
    }
}

Invoke-TestCase 'Gate Mode refuses a settle clock, -NoBuild, -KeepBuildInRun and -Soak' {
    $root = New-GateFixture
    try {
        # Every Gate run builds, so the tree never ages. A settle clock would add warm-ups up to
        # the ceiling and break the run budget. The other three describe work Gate Mode never does.
        foreach ($extra in @(@('-SettleSeconds', '5'), @('-NoBuild'), @('-KeepBuildInRun'), @('-Soak', 'tests/FakeProject'))) {
            $result = Invoke-Harness -Root $root -Arguments (@('-Mode', 'Gate', '-BaseRef', 'main') + $extra)
            Assert-True ($result.ExitCode -ne 0) "Gate Mode must refuse $($extra[0]). Output: $($result.Output)"
            Assert-True ($result.Output -match [regex]::Escape($extra[0])) "The refusal must name $($extra[0]). Output: $($result.Output)"
        }
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'stub\steps.txt'))) 'A refused session must run no step.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Gate Mode refuses -Change with -NoEvidenceReuse, and -Change with no warm-up' {
    $root = New-GateFixture
    try {
        # -Change measures the first Gate after a change, which reuse makes different from a full
        # Gate. With reuse off the two cases measure the same thing. With no warm-up there is no
        # discarded run on the changed tree.
        foreach ($extra in @(@('-NoEvidenceReuse'), @('-WarmUpRuns', '0'))) {
            $result = Invoke-Harness -Root $root -Arguments (@('-Mode', 'Gate', '-BaseRef', 'main', '-Change', 'Docs') + $extra)
            Assert-True ($result.ExitCode -ne 0) "Gate Mode must refuse -Change with $($extra[0]). Output: $($result.Output)"
            Assert-True ($result.Output -match [regex]::Escape($extra[0])) "The refusal must name $($extra[0]). Output: $($result.Output)"
        }
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'stub\steps.txt'))) 'A refused session must run no step.'
    }
    finally { Remove-HarnessFixture -Root $root }
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
Write-Host 'measure-test-modes orchestration tests passed.' -ForegroundColor Green
