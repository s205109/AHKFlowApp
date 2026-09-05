#Requires -Version 7.0

# Backlog 128. scripts/measure-test-modes.ps1 times a test Mode several times and reports the
# median, or soaks one test project and reports how many runs passed.
#
# This suite covers the orchestration only: argument routing, the median, the run lock, the
# connection-string restore, one SQL container per soak repetition, the zero-test guard, and what
# happens when a run fails. It stubs 'dotnet', stubs scripts/test-fast.ps1, and replaces the SQL
# container helper with a two-function fake that logs instead of calling Docker, so it costs
# seconds and needs no Docker.
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

    # Three real files, copied. The harness under test, the lock helper - the lock behaviour is
    # what case 7 tests - and the TRX reader the zero-test guard goes through. All three are pure
    # PowerShell that dot-sources nothing.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\measure-test-modes.ps1') `
        -Destination (Join-Path $root 'scripts\measure-test-modes.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\test-run-lock.common.ps1') `
        -Destination (Join-Path $root 'scripts\test-run-lock.common.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\test-results.common.ps1') `
        -Destination (Join-Path $root 'scripts\test-results.common.ps1')

    Set-Content -LiteralPath (Join-Path $root 'scripts\test-sql-container.common.ps1') -Encoding utf8 -Value @'
# Fake. tests/MeasureTestModes.Tests.ps1 covers the harness's orchestration, not the container
# helper, and the real helper shells out to Docker. Each call appends one line, so a case can
# count starts and stops and check they pair up.
$script:FakeSqlLog = Join-Path (Split-Path -Parent $PSScriptRoot) 'sql-calls.txt'

function Start-AhkFlowTestSqlContainer {
    $name = "fake-sql-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    Add-Content -LiteralPath $script:FakeSqlLog -Value "start $name"
    [pscustomobject]@{
        ContainerName = $name
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

# The owner file, not .test-run.lock. The release step deletes the owner file and deliberately
# leaves the lock file behind, so the lock file's presence says nothing about who holds it.
$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') `
    -Value ("{0} owner={1} conn={2}" -f $args[0], $owner, $env:AHKFLOW_TEST_SQL_CONNECTION_STRING)

if ($args[0] -eq 'build') {
    Write-Output 'stub dotnet build'
    exit 0
}

# Which test run is this? Cases 4 and 5 name a run number in a marker file.
$run = @(Get-Content -LiteralPath $callsPath | Where-Object { $_ -like 'test *' }).Count

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

if ($resultsDirectory) {
    New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
    $trx = '<?xml version="1.0" encoding="UTF-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">' +
        "<ResultSummary><Counters total=""$total"" passed=""$total"" failed=""0"" /></ResultSummary></TestRun>"
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
param([string]$Mode, [string]$Configuration, [switch]$NoBuild)
$repoRoot = Split-Path -Parent $PSScriptRoot
$stubFolder = Join-Path $repoRoot 'stub'
$callsPath = Join-Path $stubFolder 'testfast-calls.txt'
Add-Content -LiteralPath $callsPath -Value "Mode=$Mode NoBuild=$NoBuild"

$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') -Value "test-fast owner=$owner"

# Runs of different lengths, so case 2 can tell a median from a mean. 1st longest, 3rd middle.
# The three numbers are chosen, not arbitrary. Sorted they are 0.10 / 0.30 / 0.90 s, so the
# median is 0.30 s and the mean is 0.43 s. Case 2 asserts the two differ by more than 0.05 s,
# and the gap here is 0.13 s - nearly three times the threshold. An earlier draft used
# 600 / 100 / 300, whose median is 0.30 s and mean 0.33 s: a gap of 0.033 s, which fails that
# assertion outright rather than flakily. Change these numbers and re-do this arithmetic.
$run = @(Get-Content -LiteralPath $callsPath).Count
$sleep = @(900, 100, 300)[($run - 1) % 3]
Start-Sleep -Milliseconds $sleep
'@

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
    $env:PATH = (Join-Path $Root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
    try {
        $output = & $hostExe -NoProfile -File (Join-Path $Root 'scripts\measure-test-modes.ps1') @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $env:PATH = $previousPath
    }
}

Write-Host "Testing $(Join-Path $repoRoot 'scripts\measure-test-modes.ps1')"

Invoke-TestCase 'Timing mode calls the Mode once per run' {
    $root = New-HarnessFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 3) "Expected 3 test-fast.ps1 calls, got $($calls.Count)."
        Assert-True (@($calls | Where-Object { $_ -match 'NoBuild=True' }).Count -eq 3) `
            "Every timing run must pass -NoBuild. Calls: $($calls -join ' | ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The reported median is the middle of the sorted runs, not the mean' {
    $root = New-HarnessFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # Assert the arithmetic against the numbers the harness itself printed, never against a
        # wall-clock value. Process start-up noise moves every run; it cannot move the ordering.
        $text = $result.Output -join "`n"
        Assert-True ($text -match 'runs\s+:\s+([\d.,/ ]+)') "No runs line. Output: $text"
        $runs = @($Matches[1] -split '/' | ForEach-Object { [double]($_.Trim() -replace ',', '.') })
        Assert-True ($text -match 'median\s+:\s+([\d.,]+)') "No median line. Output: $text"
        $median = [double]($Matches[1] -replace ',', '.')

        $sorted = @($runs | Sort-Object)
        Assert-True ([Math]::Abs($median - $sorted[1]) -lt 0.02) `
            "Median $median must be the middle sorted run $($sorted[1]). Runs: $($runs -join ', ')"

        $mean = ($runs | Measure-Object -Average).Average
        Assert-True ([Math]::Abs($mean - $sorted[1]) -gt 0.05) `
            'The stub sleeps must differ enough that the mean and the median are distinguishable.'
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'Soak mode starts and removes one container per repetition' {
    $root = New-HarnessFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $sql = @(Get-Content -LiteralPath (Join-Path $root 'sql-calls.txt'))
        $started = @($sql | Where-Object { $_ -like 'start *' } | ForEach-Object { $_.Substring(6) })
        $stopped = @($sql | Where-Object { $_ -like 'stop *' } | ForEach-Object { $_.Substring(5) })
        Assert-True ($started.Count -eq 3) "Expected 3 container starts, got $($started.Count). Log: $($sql -join ' | ')"
        Assert-True ($stopped.Count -eq 3) "Expected 3 container stops, got $($stopped.Count). Log: $($sql -join ' | ')"
        Assert-True ((@($started | Sort-Object) -join ',') -eq (@($stopped | Sort-Object) -join ',')) `
            "Every started container must be the one stopped. Log: $($sql -join ' | ')"
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'A failing soak run is counted and named, and the soak still finishes' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\fail-run.txt') -Value '2' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        $text = $result.Output -join "`n"

        # All three repetitions must have run. Stopping at the first failure is the defect.
        $sql = @(Get-Content -LiteralPath (Join-Path $root 'sql-calls.txt'))
        Assert-True (@($sql | Where-Object { $_ -like 'start *' }).Count -eq 3) `
            "The soak must finish all 3 runs after run 2 fails. Log: $($sql -join ' | ')"
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

Invoke-TestCase 'The connection-string variable is restored in the process that changed it' {
    $root = New-HarnessFixture
    try {
        # In-process on purpose. The harness sets $env:AHKFLOW_TEST_SQL_CONNECTION_STRING inside
        # its own process, so asserting on the parent's copy after a child process exits passes
        # whatever the harness does - the child's environment was never the parent's.
        $previousPath = $env:PATH
        $previousConn = $env:AHKFLOW_TEST_SQL_CONNECTION_STRING
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
        }
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The build runs inside the lock, and timing mode releases it before the first run' {
    $root = New-HarnessFixture
    try {
        # Note the absent -NoBuild: this case is about the build.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '2')
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

Invoke-TestCase 'Soak mode holds the lock for every repetition' {
    $root = New-HarnessFixture
    try {
        $result = Invoke-Harness -Root $root -Arguments @('-Soak', 'tests/FakeProject', '-Runs', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $signals = @(Get-Content -LiteralPath (Join-Path $root 'stub\signals.txt'))
        $runs = @($signals | Where-Object { $_ -like 'test *' })
        Assert-True ($runs.Count -eq 3) "Expected three soak runs, got $($runs.Count)."
        Assert-True (@($runs | Where-Object { $_ -match 'owner=True' }).Count -eq 3) `
            "Soak mode calls dotnet test directly, so it holds the lock throughout. Signals: $($signals -join ' | ')"
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
