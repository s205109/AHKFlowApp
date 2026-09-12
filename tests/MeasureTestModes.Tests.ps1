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

    # Three real files, copied. The harness under test, the lock helper - the two lock cases test
    # that behaviour - and the TRX reader the zero-test guard goes through. All three are pure
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

# The owner file, not .test-run.lock. The release step deletes the owner file and deliberately
# leaves the lock file behind, so the lock file's presence says nothing about who holds it.
$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') `
    -Value ("{0} owner={1} conn={2}" -f $args[0], $owner, $env:AHKFLOW_TEST_SQL_CONNECTION_STRING)

if ($args[0] -eq 'build') {
    Write-Output 'stub dotnet build'
    exit 0
}

# Which test run is this? The soak cases name a run number in a marker file.
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
param([string]$Mode, [string]$Configuration, [switch]$NoBuild)
$repoRoot = Split-Path -Parent $PSScriptRoot
$stubFolder = Join-Path $repoRoot 'stub'
$callsPath = Join-Path $stubFolder 'testfast-calls.txt'
Add-Content -LiteralPath $callsPath -Value "Mode=$Mode NoBuild=$NoBuild"

$owner = Test-Path -LiteralPath (Join-Path $repoRoot '.test-run.lock.owner')
Add-Content -LiteralPath (Join-Path $stubFolder 'signals.txt') -Value "test-fast owner=$owner"

# Runs of different lengths, so the reported-median case sees a median and a mean that differ.
# 1st longest, 3rd middle. Sorted they are 0.10 / 0.30 / 0.90 s: median 0.30 s, mean 0.43 s.
#
# That case asserts each printed number against the runs the harness itself printed, so no
# threshold here has to survive machine load. It once compared the mean against the median with
# a fixed 0.05 s margin, which a slow run could close by accident. The fixed-value case above
# owns that comparison now, where the numbers are constants and nothing can move them.
$run = @(Get-Content -LiteralPath $callsPath).Count

# The sleeps this fixture uses, in milliseconds, one per run. A case writes 'sleeps.txt' to
# choose them, which is how the warm-up cases get a slow head and a flat tail. The fallback is
# the original cycle, which the median and mean cases above rely on.
$sleepsPath = Join-Path $stubFolder 'sleeps.txt'
if (Test-Path -LiteralPath $sleepsPath) {
    $sleeps = @((Get-Content -LiteralPath $sleepsPath -Raw).Trim() -split ',' | ForEach-Object { [int]$_.Trim() })
}
else {
    $sleeps = @(900, 100, 300)
}
$sleep = $sleeps[($run - 1) % $sleeps.Count]
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
        # -WarmUpRuns 0 because this case counts calls. The default of 2 would add two more.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '3', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 3) "Expected 3 test-fast.ps1 calls, got $($calls.Count)."
        Assert-True (@($calls | Where-Object { $_ -match 'NoBuild=True' }).Count -eq 3) `
            "Every timing run must pass -NoBuild. Calls: $($calls -join ' | ')"
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
        # -WarmUpRuns 0 because this case counts calls. The default of 2 would add two more.
        $result = Invoke-Harness -Root $root -Arguments @('-Mode', 'Fast', '-Runs', '3', '-WarmUpRuns', '0', '-SettleSeconds', '0', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

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
        # Three slow runs then two flat ones. The median of all five is 0.90 s. The median of the
        # counted tail is 0.10 s. A harness that forgot to discard cannot land near 0.10 s by
        # accident, so no threshold here has to survive machine load.
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '900,900,900,100,100' -Encoding utf8

        $result = Invoke-Harness -Root $root -Arguments @(
            '-Mode', 'Fast', '-Runs', '2', '-WarmUpRuns', '3', '-NoBuild')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\testfast-calls.txt'))
        Assert-True ($calls.Count -eq 5) "Expected 3 warm-up plus 2 counted runs, got $($calls.Count)."

        $text = $result.Output -join "`n"
        Assert-True ($text -match 'median\s+:\s+([\d.,]+)') "No median line. Output: $text"
        $median = [double]($Matches[1] -replace ',', '.')
        Assert-True ($median -lt 0.5) `
            "The median must come from the flat tail near 0.10 s, not the whole list near 0.90 s. Got $median."
    }
    finally { Remove-HarnessFixture -Root $root }
}

Invoke-TestCase 'The discarded runs are printed, with how many there were' {
    $root = New-HarnessFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '900,900,100,100,100' -Encoding utf8

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
        Set-Content -LiteralPath (Join-Path $root 'stub\sleeps.txt') -Value '100,300,900' -Encoding utf8

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
