#Requires -Version 7.0
<#
.SYNOPSIS
Tests for scripts/run-powershell-suites.ps1, the script that runs every PowerShell suite in CI.

.DESCRIPTION
That script decides whether the powershell-suites job is honest, so it needs its own proof.
Each case builds a disposable folder of tiny fake suites under the system temp directory and runs
the driver against it with -SuiteRoot. No case touches the repository's real tests folder.

The fake suites cover both endings the real suites use: an explicit 'exit', and a throw or a plain
run off the end. One fake suite leaves $LASTEXITCODE dirty on its success path, which is the trap
that makes an in-process exit-code check report a passing suite as failed.

This suite declares 7.0 because the driver it tests does. Each case spawns the driver with the
current host, so a 5.1 host would spawn a 5.1 child and hit the driver's own '#Requires'.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.4 turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is 'Stop'. Every case here runs the driver and reads its exit code, and
# a failing driver run is the expected result in most of them, so opt out.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:DriverPath = Join-Path $repoRoot 'scripts\run-powershell-suites.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

# The manifest functions are tested by calling them, not by spawning one child per invalid file.
. (Join-Path $repoRoot 'scripts\powershell-suites.common.ps1')

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

function New-SuiteFixture {
    param([string] $Infix = '')

    $leaf = 'ahkflow-suiterunner-' + $Infix + [guid]::NewGuid().ToString('N')
    $root = Join-Path ([System.IO.Path]::GetTempPath()) $leaf
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'markers') -Force | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
}

function ConvertTo-ScriptLiteral {
    param([string] $Value)

    # A single-quoted PowerShell literal escapes an apostrophe by doubling it. Paths here run
    # through the repository root and the temporary folder, and both run through the user profile
    # name; O'Brien is a real name. A suite name may legally carry one too. Without this the
    # generated command is a syntax error, on one person's machine only.
    return "'" + $Value.Replace("'", "''") + "'"
}

# Every run reads a manifest from its suite root, so a fixture needs one. With no -Entry the
# helper writes one plain parallel entry per fake suite already in the folder, so a case that
# does not care about the manifest can ignore it. A validation case passes -Entry instead.
function Set-FixtureManifest {
    param(
        [string] $Root,
        [object[]] $Entry
    )

    if (-not $Entry) {
        $Entry = @(Get-ChildItem -LiteralPath $Root -Filter '*.Tests.ps1' -File | Sort-Object Name | ForEach-Object {
                [ordered]@{
                    name            = $_.Name
                    jobs            = @('suites')
                    execution       = 'parallel'
                    baselineSeconds = $null
                }
            })
    }

    $payload = [ordered]@{ suites = @($Entry) }
    $json = ($payload | ConvertTo-Json -Depth 6)
    Set-Content -LiteralPath (Join-Path $Root 'powershell-suites.json') -Value $json -Encoding utf8
}

function Remove-SuiteFixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Writes a fake suite that drops a marker file first, so a case can prove the suite really ran,
# and then ends in the requested way.
function Add-FakeSuite {
    param(
        [string] $Root,
        [string] $Name,

        # pass      - writes the marker, prints, runs off the end (no exit)
        # exit-zero - writes the marker, then 'exit 0'
        # dirty     - writes the marker, runs a native command that exits 1, then runs off the end
        # exit-one  - writes the marker, then 'exit 1'
        # throw     - writes the marker, then throws
        [ValidateSet('pass', 'exit-zero', 'dirty', 'exit-one', 'throw')]
        [string] $Ending
    )

    $markerPath = Join-Path (Join-Path $Root 'markers') $Name
    $body = New-Object System.Collections.Generic.List[string]
    $body.Add("Set-Content -LiteralPath $(ConvertTo-ScriptLiteral $markerPath) -Value 'ran' -Encoding ascii")
    $body.Add("Write-Host $(ConvertTo-ScriptLiteral "ran $Name")")

    switch ($Ending) {
        'pass' { }
        'exit-zero' { $body.Add('exit 0') }
        'dirty' {
            # The real WorktreeBaseRef suite ends like this: a native command leaves $LASTEXITCODE
            # at 1, and the suite still passes.
            $body.Add('& cmd /c exit 1')
            $body.Add("Write-Host 'suite passed'")
        }
        'exit-one' { $body.Add('exit 1') }
        'throw' { $body.Add("throw 'deliberate failure'") }
    }

    Set-Content -LiteralPath (Join-Path $Root $Name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
}

function Test-MarkerExists {
    param([string] $Root, [string] $Name)
    return Test-Path -LiteralPath (Join-Path (Join-Path $Root 'markers') $Name)
}

function Add-IntervalSuite {
    param(
        [string] $Root,
        [string] $Name,
        [int] $BarrierCount = 0,
        [string] $BarrierTag = 'all',
        [int] $TimeoutSeconds = 10,
        [int] $HoldMilliseconds = 300
    )

    # Two things this helper has to get right, and an earlier draft got both wrong.
    #
    # The clock. [datetime]::UtcNow is the wall clock, and the system may correct it backwards
    # while the run is in flight, which reorders stamps taken in different processes.
    # [System.Diagnostics.Stopwatch]::GetTimestamp() reads one machine-wide monotonic counter -
    # QueryPerformanceCounter on Windows, CLOCK_MONOTONIC elsewhere - so stamps from separate
    # processes on the same machine sort correctly. The sweep compares order only, so the
    # counter's own unit never matters. The barrier's own timeout below measures elapsed time with
    # the same monotonic source, for the same reason: a backward correction would otherwise stretch
    # the wait past the point where the case still means anything.
    #
    # The overlap. A fixed sleep overlaps only if the runspace pool happens to fill inside it,
    # which nothing guarantees. So a suite signs in and then waits for the rest of its barrier
    # group before it starts its hold: the overlap is caused, not hoped for. Every member of a
    # group is released within milliseconds of the last arrival, and all of them then hold for
    # -HoldMilliseconds, so their windows must intersect. -BarrierCount 0 means "wait for nobody",
    # which is what a suite that has to run alone needs. The tag keeps one group's sign-ins from
    # releasing another group's barrier.
    $markers = Join-Path $Root 'markers'
    $stamp = Join-Path $markers ($Name + '.interval')
    $signIn = Join-Path $markers ($BarrierTag + '.' + $Name + '.arrived')

    $wait = @()
    if ($BarrierCount -gt 0) {
        # A timeout, so a runner that never parallelises fails the assertion instead of hanging.
        # The tag is ours, never a path, so only the folder needs escaping.
        $wait = @(
            "`$watch = [System.Diagnostics.Stopwatch]::StartNew()"
            "while (`$watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {"
            "    if (@(Get-ChildItem -LiteralPath $(ConvertTo-ScriptLiteral $markers) -Filter '$BarrierTag.*.arrived' -File).Count -ge $BarrierCount) { break }"
            '    Start-Sleep -Milliseconds 25'
            '}'
        )
    }

    $body = @(
        "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral $stamp) -Value ([System.Diagnostics.Stopwatch]::GetTimestamp()) -Encoding ascii"
        "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral $signIn) -Value 'here' -Encoding ascii"
    ) + $wait + @(
        "Start-Sleep -Milliseconds $HoldMilliseconds"
        "Add-Content -LiteralPath $(ConvertTo-ScriptLiteral $stamp) -Value ([System.Diagnostics.Stopwatch]::GetTimestamp()) -Encoding ascii"
    )
    Set-Content -LiteralPath (Join-Path $Root $Name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
}

function Get-PeakOverlap {
    param([string] $Root, [string[]] $Name)

    $point = [System.Collections.Generic.List[object]]::new()
    foreach ($one in $Name) {
        $ticks = @(Get-Content -LiteralPath (Join-Path (Join-Path $Root 'markers') ($one + '.interval')))
        if ($ticks.Count -ne 2) { throw "Suite $one wrote $($ticks.Count) ticks, expected 2." }
        $point.Add([pscustomobject]@{ Tick = [long] $ticks[0]; Delta = 1 })
        $point.Add([pscustomobject]@{ Tick = [long] $ticks[1]; Delta = -1 })
    }

    # Sort ends before starts at an equal tick, so touching windows do not read as an overlap.
    $live = 0
    $peak = 0
    foreach ($one in @($point | Sort-Object Tick, Delta)) {
        $live += $one.Delta
        if ($live -gt $peak) { $peak = $live }
    }
    return $peak
}

# Runs the driver as its own process and returns its exit code, everything it printed, and the
# job summary it wrote. The child process is the point: it is exactly what the CI step measures.
#
# The child inherits this process's environment. Under CI that includes GITHUB_STEP_SUMMARY, so
# without the redirect below every fake suite table here would be appended to the real
# powershell-suites job summary — including the deliberate failures. Point the child at a scratch
# file instead. Redirecting rather than clearing keeps the driver's summary-writing branch covered.
function Invoke-Driver {
    param([string] $SuiteRoot, [string[]] $Suite = @(), [string] $RawSuite, [int] $MaxParallel = 0, [hashtable] $EnvVar = @{})

    # RawSuite hands the driver a literal PowerShell expression, so a case can pass '-Suite $null'.
    # That is what an unset variable becomes, and ConvertTo-ScriptLiteral would quote it into a
    # string instead, which tests something else.
    $suiteLiteral = if ($PSBoundParameters.ContainsKey('RawSuite')) {
        " -Suite $RawSuite"
    } elseif ($Suite.Count -eq 0) {
        ''
    } else {
        ' -Suite @(' + (($Suite | ForEach-Object { ConvertTo-ScriptLiteral $_ }) -join ',') + ')'
    }

    # The binding, not the value. A case passes -MaxParallel -1 on purpose to prove the run
    # refuses it, and a '-gt 0' test would drop that argument instead of passing it on.
    $parallelLiteral = if ($PSBoundParameters.ContainsKey('MaxParallel')) { " -MaxParallel $MaxParallel" } else { '' }

    $summaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-summary-' + [guid]::NewGuid().ToString('N') + '.md')
    $previousSummary = $env:GITHUB_STEP_SUMMARY
    $env:GITHUB_STEP_SUMMARY = $summaryPath

    # Saved and restored the same way the summary path is, so one case cannot leak a value into
    # the next one.
    $previousEnv = @{}
    foreach ($name in $EnvVar.Keys) {
        $previousEnv[$name] = [System.Environment]::GetEnvironmentVariable($name)
        [System.Environment]::SetEnvironmentVariable($name, $EnvVar[$name])
    }

    try {
        $command = "& $(ConvertTo-ScriptLiteral $script:DriverPath) -SuiteRoot $(ConvertTo-ScriptLiteral $SuiteRoot)$suiteLiteral$parallelLiteral; exit `$LASTEXITCODE"
        $output = & $script:HostExe -NoProfile -Command $command 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $summary = if (Test-Path -LiteralPath $summaryPath) {
            Get-Content -LiteralPath $summaryPath -Raw
        } else {
            ''
        }
    } finally {
        $env:GITHUB_STEP_SUMMARY = $previousSummary
        foreach ($name in $previousEnv.Keys) {
            [System.Environment]::SetEnvironmentVariable($name, $previousEnv[$name])
        }
        Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Summary  = $summary
    }
}

Write-Host "Testing $script:DriverPath"
Assert-True (Test-Path -LiteralPath $script:DriverPath) "Driver script not found at $script:DriverPath."

Invoke-TestCase 'All suites pass -> exit code 0' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-exit-zero.Tests.ps1' -Ending 'exit-zero'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'All 2 suite\(s\) passed\.') "Expected the all-passed summary line. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'The driver prints a progress line per suite and saves no timings for a fixture run' {
    $root = New-SuiteFixture
    $timingsPath = Join-Path $repoRoot 'TestResults\progress\run-powershell-suites.json'
    $before = if (Test-Path -LiteralPath $timingsPath) { (Get-Item -LiteralPath $timingsPath).LastWriteTimeUtc } else { $null }

    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root

        Assert-True ($result.Output -match '\[\d/2 done\] 01-pass\.Tests\.ps1') "Expected a completion line for the first suite. Output: $($result.Output)"
        Assert-True ($result.Output -match '\[\d/2 done\] 02-pass\.Tests\.ps1') "Expected a completion line for the second suite. Output: $($result.Output)"

        # The line's position is not fixed any more, because suites finish in whatever order they
        # finish. The last-write check below is what proves the run did not reach the real store.
        $after = if (Test-Path -LiteralPath $timingsPath) { (Get-Item -LiteralPath $timingsPath).LastWriteTimeUtc } else { $null }
        Assert-True ($before -eq $after) 'A run over fake suites must not write the real timings file.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A run over the repository''s own tests folder saves its timings' {
    # A copy of the runner in a temporary tree, so the case can be a real run against "the
    # repository's own tests folder" without running the 47 real suites, and without writing
    # into the store the real runs read.
    #
    # This is the other half of the case above. That one proves a fixture run stores nothing;
    # this one proves a real run still does. The decision used to test whether -SuiteRoot was
    # passed, so naming the real folder ran the real suites and then stored nothing.
    $fakeRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterepo-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'tests') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'markers') -Force | Out-Null

        foreach ($name in @('run-powershell-suites.ps1', 'progress.common.ps1', 'progress.parallel.ps1', 'powershell-suites.common.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $fakeRepo "scripts/$name")
        }

        Add-FakeSuite -Root $fakeRepo -Name '01-pass.Tests.ps1' -Ending 'pass'
        Move-Item -LiteralPath (Join-Path $fakeRepo '01-pass.Tests.ps1') -Destination (Join-Path $fakeRepo 'tests/01-pass.Tests.ps1')
        Set-FixtureManifest -Root (Join-Path $fakeRepo 'tests')

        $driver = Join-Path $fakeRepo 'scripts/run-powershell-suites.ps1'
        $timings = Join-Path $fakeRepo 'TestResults/progress/run-powershell-suites.json'

        $noRootCommand = "& $(ConvertTo-ScriptLiteral $driver); exit `$LASTEXITCODE"
        $namedRootCommand = "& $(ConvertTo-ScriptLiteral $driver) -SuiteRoot $(ConvertTo-ScriptLiteral (Join-Path $fakeRepo 'tests')); exit `$LASTEXITCODE"

        # No -SuiteRoot at all: the runner falls back to its own tests folder.
        $out = & $script:HostExe -NoProfile -Command $noRootCommand 2>&1 | Out-String
        Assert-True (Test-Path -LiteralPath $timings) "A run with no -SuiteRoot must save its timings. Output: $out"

        Remove-Item -LiteralPath $timings -Force

        # The same folder, named explicitly. Still a real run, so it must still save.
        $out = & $script:HostExe -NoProfile -Command $namedRootCommand 2>&1 | Out-String
        Assert-True (Test-Path -LiteralPath $timings) "Naming the repository's own tests folder must still save timings. Output: $out"

        $saved = Get-Content -LiteralPath $timings -Raw | ConvertFrom-Json
        Assert-True ($null -ne $saved.'01-pass.Tests.ps1') 'The saved timings must name the suite that ran.'
    } finally {
        Remove-Item -LiteralPath $fakeRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'A suite that exits 1 fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-fail.Tests.ps1' -Ending 'exit-one'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '02-fail\.Tests\.ps1 \| failed') "The summary must mark 02-fail as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite that throws fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-throw.Tests.ps1' -Ending 'throw'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '01-throw\.Tests\.ps1 \| failed') "The summary must mark 01-throw as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# The regression test for the trap named in backlog item 066. A passing suite that leaves
# $LASTEXITCODE at 1 must still be reported as passed, which is only true because the driver runs
# each suite in its own process.
Invoke-TestCase 'A passing suite with a dirty $LASTEXITCODE still passes' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-dirty.Tests.ps1' -Ending 'dirty'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '01-dirty\.Tests\.ps1 \| passed') "The summary must mark 01-dirty as passed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Every suite runs even when the first one fails' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '02-throw.Tests.ps1' -Ending 'throw'
        Add-FakeSuite -Root $root -Name '03-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '04-dirty.Tests.ps1' -Ending 'dirty'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"

        foreach ($name in @('01-fail.Tests.ps1', '02-throw.Tests.ps1', '03-pass.Tests.ps1', '04-dirty.Tests.ps1')) {
            Assert-True (Test-MarkerExists -Root $root -Name $name) "Suite $name must still have run. Output: $($result.Output)"
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'The summary names every failed suite and no passing one' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '03-throw.Tests.ps1' -Ending 'throw'
        Add-FakeSuite -Root $root -Name '04-pass.Tests.ps1' -Ending 'exit-zero'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '2 of 4 suite\(s\) failed') "Expected a 2 of 4 failure count. Output: $($result.Output)"
        Assert-True ($result.Output -match '01-fail\.Tests\.ps1') "The failure list must name 01-fail. Output: $($result.Output)"
        Assert-True ($result.Output -match '03-throw\.Tests\.ps1') "The failure list must name 03-throw. Output: $($result.Output)"
        Assert-True ($result.Output -match '02-pass\.Tests\.ps1 \| passed') "02-pass must be listed as passed. Output: $($result.Output)"
        Assert-True ($result.Output -match '04-pass\.Tests\.ps1 \| passed') "04-pass must be listed as passed. Output: $($result.Output)"
        Assert-True (-not ($result.Output -match '02-pass\.Tests\.ps1 \| failed')) "02-pass must not be listed as failed. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# The job summary is how a failure is read in the GitHub UI, and it goes to the file named by
# GITHUB_STEP_SUMMARY. This case also proves the redirect in Invoke-Driver works, which is what
# keeps these fake tables out of the real job summary.
Invoke-TestCase 'The driver writes its table to the GITHUB_STEP_SUMMARY file' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-fail.Tests.ps1' -Ending 'exit-one'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.Summary -match '### PowerShell suites') "The summary file must hold the table heading. Summary: $($result.Summary)"
        Assert-True ($result.Summary -match '02-fail\.Tests\.ps1 \| failed') "The summary file must mark 02-fail as failed. Summary: $($result.Summary)"
        Assert-True ($result.Summary -match '1 of 2 suite\(s\) failed') "The summary file must hold the failure count. Summary: $($result.Summary)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# A run that finds nothing must not look green. A broken glob would otherwise hide every suite.
Invoke-TestCase 'A folder with no suites fails the run' {
    $root = New-SuiteFixture
    try {
        Set-Content -LiteralPath (Join-Path $root 'notes.txt') -Value 'not a suite' -Encoding utf8

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'No test suites found') "Expected the empty-folder message. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A missing suite folder fails the run' {
    $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-missing-' + [guid]::NewGuid().ToString('N'))

    $result = Invoke-Driver -SuiteRoot $missing
    Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'Suite folder not found') "Expected the missing-folder message. Output: $($result.Output)"
}

Invoke-TestCase 'A suite folder whose path contains an apostrophe still runs' {
    # The driver command, the marker lines and the generated suite bodies are all built as
    # PowerShell source text. An apostrophe that is not doubled turns that text into a syntax
    # error. Nobody sees it until somebody whose user profile carries one runs the suite, because
    # the temporary folder sits under the profile, so the fixture has to supply the apostrophe.
    $root = New-SuiteFixture -Infix "o'brien"
    try {
        Assert-True ($root.Contains("'")) "The fixture path must carry an apostrophe, got '$root'."
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name "02-o'hara.Tests.ps1" -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        foreach ($name in @('01-pass.Tests.ps1', "02-o'hara.Tests.ps1")) {
            Assert-True (Test-MarkerExists -Root $root -Name $name) "Suite $name must have run. Output: $($result.Output)"
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A missing manifest fails before any suite runs' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        # No Set-FixtureManifest on purpose.

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'powershell-suites\.json') "The message must name the manifest file. Output: $($result.Output)"
        Assert-True (-not (Test-MarkerExists -Root $root -Name '01-pass.Tests.ps1')) 'No suite may run when the manifest is missing.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite file missing from the manifest fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-orphan.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-pass.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '02-orphan\.Tests\.ps1') "The message must name the missing entry. Output: $($result.Output)"
        Assert-True (-not (Test-MarkerExists -Root $root -Name '01-pass.Tests.ps1')) 'No suite may run when the manifest is incomplete.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A manifest entry with no suite file fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-pass.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = 'NotThere.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'NotThere\.Tests\.ps1') "The message must name the stale entry. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A duplicate manifest entry fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-pass.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '01-pass.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = 2 }
        )

        $result = Invoke-Driver -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'more than once') "The message must say the name repeats. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

# Writes a manifest into a scratch folder and returns its path, so a unit case can call
# Read-SuiteManifest without building a folder of fake suites.
function New-ManifestFile {
    param([object[]] $Entry)

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
    $payload = [ordered]@{ suites = @($Entry) }
    Set-Content -LiteralPath $path -Value ($payload | ConvertTo-Json -Depth 6) -Encoding utf8
    return $path
}

Invoke-TestCase 'An unknown job value fails the manifest' {
    $path = New-ManifestFile -Entry @(
        [ordered]@{ name = 'a.Tests.ps1'; jobs = @('nonsense'); execution = 'parallel'; baselineSeconds = 1 }
    )
    try {
        $threw = $false
        $message = ''
        try { Read-SuiteManifest -Path $path -DiscoveredName @('a.Tests.ps1') } catch { $threw = $true; $message = $_.Exception.Message }
        Assert-True $threw 'An unknown job value must throw.'
        Assert-True ($message -match 'nonsense') "The message must name the bad value. Got: $message"
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'An unknown execution value fails the manifest' {
    $path = New-ManifestFile -Entry @(
        [ordered]@{ name = 'a.Tests.ps1'; jobs = @('suites'); execution = 'sometimes'; baselineSeconds = 1 }
    )
    try {
        $threw = $false
        $message = ''
        try { Read-SuiteManifest -Path $path -DiscoveredName @('a.Tests.ps1') } catch { $threw = $true; $message = $_.Exception.Message }
        Assert-True $threw 'An unknown execution value must throw.'
        Assert-True ($message -match 'sometimes') "The message must name the bad value. Got: $message"
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'An exclusive entry with no reason fails the manifest' {
    $path = New-ManifestFile -Entry @(
        [ordered]@{ name = 'a.Tests.ps1'; jobs = @('suites'); execution = 'exclusive'; baselineSeconds = 1 }
    )
    try {
        $threw = $false
        $message = ''
        try { Read-SuiteManifest -Path $path -DiscoveredName @('a.Tests.ps1') } catch { $threw = $true; $message = $_.Exception.Message }
        Assert-True $threw 'An exclusive entry with no reason must throw.'
        Assert-True ($message -match 'reason') "The message must ask for a reason. Got: $message"
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'An unusable baseline duration fails the manifest' {
    foreach ($bad in @(0, -3, 'NaN', 'Infinity', 'soon')) {
        $path = New-ManifestFile -Entry @(
            [ordered]@{ name = 'a.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $bad }
        )
        try {
            $threw = $false
            try { Read-SuiteManifest -Path $path -DiscoveredName @('a.Tests.ps1') } catch { $threw = $true }
            Assert-True $threw "baselineSeconds '$bad' must throw."
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-TestCase 'A null baseline duration is allowed' {
    $path = New-ManifestFile -Entry @(
        [ordered]@{ name = 'a.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
    )
    try {
        $entries = @(Read-SuiteManifest -Path $path -DiscoveredName @('a.Tests.ps1'))
        Assert-True ($entries.Count -eq 1) "Expected one entry, got $($entries.Count)."
        Assert-True ($null -eq $entries[0].BaselineSeconds) 'A null baseline must survive as $null.'
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'With no pattern the selection is every suite in the suites job' {
    $entries = @(
        [pscustomobject]@{ Name = 'a.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 1.0 }
        [pscustomobject]@{ Name = 'b.Tests.ps1'; Jobs = @('invariants', 'suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 2.0 }
        [pscustomobject]@{ Name = 'c.Tests.ps1'; Jobs = @('codex-parity'); Execution = 'parallel'; Reason = $null; BaselineSeconds = $null }
    )

    $selected = @(Select-SuiteEntry -Entry $entries)
    Assert-True ($selected.Count -eq 2) "Expected two suites, got $($selected.Count)."
    Assert-True (($selected.Name -join ',') -eq 'a.Tests.ps1,b.Tests.ps1') "Got: $($selected.Name -join ',')"
}

Invoke-TestCase 'The schedule puts the longest suite first and an unknown one before all of them' {
    $entries = @(
        [pscustomobject]@{ Name = 'short.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 2.0 }
        [pscustomobject]@{ Name = 'long.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 90.0 }
        [pscustomobject]@{ Name = 'new.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = $null }
    )

    $order = (Get-SuiteSchedule -Entry $entries -History @{}).Name -join ','
    Assert-True ($order -eq 'new.Tests.ps1,long.Tests.ps1,short.Tests.ps1') "Got: $order"
}

Invoke-TestCase 'Local history overrides the committed baseline' {
    $entries = @(
        [pscustomobject]@{ Name = 'a.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 90.0 }
        [pscustomobject]@{ Name = 'b.Tests.ps1'; Jobs = @('suites'); Execution = 'parallel'; Reason = $null; BaselineSeconds = 10.0 }
    )

    # History says a is now the quick one, so b must be scheduled first.
    $order = (Get-SuiteSchedule -Entry $entries -History @{ 'a.Tests.ps1' = 1.0 }).Name -join ','
    Assert-True ($order -eq 'b.Tests.ps1,a.Tests.ps1') "Got: $order"
}

Invoke-TestCase 'A -Suite wildcard runs only the suites it matches' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'Beta.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'AlphaTwo.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -Suite @('Alpha*')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True (Test-MarkerExists -Root $root -Name 'Alpha.Tests.ps1') 'Alpha must have run.'
        Assert-True (Test-MarkerExists -Root $root -Name 'AlphaTwo.Tests.ps1') 'AlphaTwo must have run.'
        Assert-True (-not (Test-MarkerExists -Root $root -Name 'Beta.Tests.ps1')) 'Beta must not have run.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Two -Suite wildcards that overlap run each suite once' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'Beta.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -Suite @('Alpha*', 'A*')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'All 1 suite\(s\) passed\.') "Alpha must be counted once. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'An unmatched -Suite wildcard fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -Suite @('Nope*')
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'Nope\*') "The message must name the wildcard. Output: $($result.Output)"
        Assert-True (-not (Test-MarkerExists -Root $root -Name 'Alpha.Tests.ps1')) 'No suite may run when the selection fails.'
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A blank -Suite wildcard fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'Beta.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        # PowerShell reads a one-element array as its element, so an empty string used to look like
        # "no selection argument" and quietly ran every suite. A caller who wants everything leaves
        # -Suite out.
        $result = Invoke-Driver -SuiteRoot $root -Suite @('')
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'blank') "The message must say the value is blank. Output: $($result.Output)"
        foreach ($name in @('Alpha.Tests.ps1', 'Beta.Tests.ps1')) {
            Assert-True (-not (Test-MarkerExists -Root $root -Name $name)) "No suite may run when the selection fails. $name ran."
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A -Suite argument that carries no value fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'Beta.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        # '-Suite $env:FILTER' with the variable unset binds $null, and '-Suite @()' binds an empty
        # array. Both ask for a subset and name none, so both must fail instead of running the lot.
        foreach ($literal in @('$null', '@()')) {
            $result = Invoke-Driver -SuiteRoot $root -RawSuite $literal
            Assert-True ($result.ExitCode -eq 1) "Expected exit code 1 for -Suite $literal, got $($result.ExitCode). Output: $($result.Output)"
            Assert-True ($result.Output -match 'no value to match') "The message must say the argument named nothing. Output: $($result.Output)"
            foreach ($name in @('Alpha.Tests.ps1', 'Beta.Tests.ps1')) {
                Assert-True (-not (Test-MarkerExists -Root $root -Name $name)) "No suite may run when -Suite $literal fails. $name ran."
            }
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A -Suite wildcard that matches only a suite outside the suites job says so' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name 'Alpha.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name 'Elsewhere.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = 'Alpha.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = 'Elsewhere.Tests.ps1'; jobs = @('codex-parity'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Driver -SuiteRoot $root -Suite @('Elsewhere*')
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'outside the suites job') "The message must explain the miss. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'test-fast PowerShell mode still reaches the full selection' {
    # The wrapper passes no selection argument, so the runner must still choose every suite in the
    # suites job. This is the whole reason scripts/test-fast.ps1 needs no edit.
    $wrapper = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/test-fast.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($wrapper, [ref] $null, [ref] $null)
    $text = $ast.Extent.Text
    Assert-True ($text -notmatch '-Suite\b') 'test-fast.ps1 must not pass a -Suite argument.'
    Assert-True ($text -match "run-powershell-suites\.ps1'\) @suiteArguments") 'test-fast.ps1 must still splat only SuiteRoot.'
}

Invoke-TestCase 'A parallel run and a sequential run reach the same verdict and the same suites' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '03-dirty.Tests.ps1' -Ending 'dirty'
        Add-FakeSuite -Root $root -Name '04-throw.Tests.ps1' -Ending 'throw'
        Set-FixtureManifest -Root $root

        $sequential = Invoke-Driver -SuiteRoot $root -MaxParallel 1
        $parallel = Invoke-Driver -SuiteRoot $root -MaxParallel 4

        Assert-True ($sequential.ExitCode -eq $parallel.ExitCode) "Verdicts differ: $($sequential.ExitCode) and $($parallel.ExitCode)."
        Assert-True ($parallel.ExitCode -eq 1) "Expected exit code 1, got $($parallel.ExitCode). Output: $($parallel.Output)"
        foreach ($name in @('01-pass', '02-fail', '03-dirty', '04-throw')) {
            Assert-True ($parallel.Output -match "$name\.Tests\.ps1 \| (passed|failed)") "The table must list $name. Output: $($parallel.Output)"
        }
        Assert-True ($parallel.Output -match '03-dirty\.Tests\.ps1 \| passed') "A dirty exit code must still pass in parallel. Output: $($parallel.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Every suite runs in parallel even after another fails' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-fail.Tests.ps1' -Ending 'exit-one'
        Add-FakeSuite -Root $root -Name '02-throw.Tests.ps1' -Ending 'throw'
        Add-FakeSuite -Root $root -Name '03-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '04-dirty.Tests.ps1' -Ending 'dirty'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 4
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        foreach ($name in @('01-fail.Tests.ps1', '02-throw.Tests.ps1', '03-pass.Tests.ps1', '04-dirty.Tests.ps1')) {
            Assert-True (Test-MarkerExists -Root $root -Name $name) "Suite $name must still have run. Output: $($result.Output)"
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A suite whose host will not start becomes that suite''s failure' {
    # The launch error itself, which no fixture run can produce: the runner always has a working
    # pwsh, and a fixture cannot withhold it from one child. Calling Invoke-SuiteChild directly
    # with a host that does not exist is what reaches the catch. PowerShell throws
    # CommandNotFoundException before any process starts, so this is the real launch failure the
    # spec asks for, not a stand-in.
    . (Join-Path $repoRoot 'scripts/powershell-suites.common.ps1')

    $result = Invoke-SuiteChild -Path (Join-Path $repoRoot 'tests/CiPowerShellSuiteRunner.Tests.ps1') -Name '01-x.Tests.ps1' -HostExe 'ahkflow-no-such-host-executable'

    Assert-True ($result.ExitCode -eq 1) "A launch failure must be exit code 1, got $($result.ExitCode)."
    Assert-True ($result.Name -eq '01-x.Tests.ps1') "The result must carry the suite name, got '$($result.Name)'."
    Assert-True ($result.Output -match 'Could not start the suite') "The output must say the suite could not start. Output: $($result.Output)"
}

Invoke-TestCase 'A suite that cannot run at all fails alone, and the rest still run' {
    $root = New-SuiteFixture
    try {
        # An unbalanced brace. pwsh -File rejects the file before it runs a single line, so this
        # suite never starts in the sense that matters: no marker, no output of its own, and a
        # non-zero exit code from the host. The case above covers a suite that runs and then fails;
        # 'exit-one' and 'throw' both execute the script first, so neither covers this shape.
        Set-Content -LiteralPath (Join-Path $root '01-nostart.Tests.ps1') -Value 'if ($true) {' -Encoding utf8
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '03-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 3
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match '01-nostart\.Tests\.ps1 \| failed') "The suite that could not run must be reported as failed. Output: $($result.Output)"
        Assert-True (-not (Test-MarkerExists -Root $root -Name '01-nostart.Tests.ps1')) 'The suite that could not run must not have run.'
        foreach ($name in @('02-pass.Tests.ps1', '03-pass.Tests.ps1')) {
            Assert-True (Test-MarkerExists -Root $root -Name $name) "Suite $name must still have run. Output: $($result.Output)"
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Two suites'' output never interleaves' {
    $root = New-SuiteFixture
    try {
        # Each suite prints a start marker, waits, then prints an end marker. Run in parallel with
        # unbuffered output the two would cross; buffered, each block prints whole.
        foreach ($name in @('01-slow.Tests.ps1', '02-slow.Tests.ps1')) {
            $tag = $name.Substring(0, 2)
            $body = @(
                "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral (Join-Path (Join-Path $root 'markers') $name)) -Value 'ran' -Encoding ascii"
                "Write-Host 'START-$tag'"
                'Start-Sleep -Milliseconds 400'
                "Write-Host 'END-$tag'"
            )
            Set-Content -LiteralPath (Join-Path $root $name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
        }
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 2
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # All four markers must be there first. Without this the sweep below runs zero times on
        # empty output, $interleaved stays false, and the case passes having read nothing.
        $order = @([regex]::Matches($result.Output, '(START|END)-(\d\d)') | ForEach-Object { $_.Value })
        foreach ($marker in @('START-01', 'END-01', 'START-02', 'END-02')) {
            Assert-True ($order -contains $marker) "Missing $marker. Output: $($result.Output)"
        }
        Assert-True ($order.Count -eq 4) "Expected exactly four markers, got $($order.Count): $($order -join ' ')"

        # Every START must be followed by its own END before the other START appears.
        $interleaved = $false
        for ($i = 0; $i -lt $order.Count - 1; $i += 2) {
            if ($order[$i] -notmatch '^START-(\d\d)$') { $interleaved = $true; break }
            if ($order[$i + 1] -ne ('END-' + $Matches[1])) { $interleaved = $true; break }
        }
        Assert-True (-not $interleaved) "Output interleaved: $($order -join ' ')"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'The final table is sorted by suite name whatever the finish order' {
    $root = New-SuiteFixture
    try {
        # The slowest suite sorts first by name, so a table in finish order would put it last.
        $slow = @(
            "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral (Join-Path (Join-Path $root 'markers') '01-slow.Tests.ps1')) -Value 'ran' -Encoding ascii"
            'Start-Sleep -Milliseconds 600'
        )
        Set-Content -LiteralPath (Join-Path $root '01-slow.Tests.ps1') -Value ($slow -join [Environment]::NewLine) -Encoding utf8
        Add-FakeSuite -Root $root -Name '02-quick.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 2
        $first = $result.Output.IndexOf('| 01-slow.Tests.ps1 |')
        $second = $result.Output.IndexOf('| 02-quick.Tests.ps1 |')
        Assert-True ($first -ge 0 -and $second -ge 0) "Both suites must be in the table. Output: $($result.Output)"
        Assert-True ($first -lt $second) "The table must be sorted by name. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'Two suites really do run at the same time' {
    $root = New-SuiteFixture
    try {
        # Barrier of two: no suite holds until a second suite is signed in beside it. A runner
        # that runs one at a time leaves the first suite waiting until its timeout, and the peak
        # then reads 1.
        $names = @('01-a.Tests.ps1', '02-b.Tests.ps1', '03-c.Tests.ps1')
        foreach ($name in $names) { Add-IntervalSuite -Root $root -Name $name -BarrierCount 2 }
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 2
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # Exactly two: below two the runner is sequential, above two it ignored -MaxParallel.
        $peak = Get-PeakOverlap -Root $root -Name $names
        Assert-True ($peak -eq 2) "Peak overlap must be 2 under -MaxParallel 2, got $peak."
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'MaxParallel 1 runs nothing at the same time' {
    $root = New-SuiteFixture
    try {
        # The same barrier as the case above, and for the same reason. Fixed 300 ms windows and no
        # barrier would let a runner that ignores -MaxParallel 1 pass: start three workers more
        # than 300 ms apart and no two windows meet, so the peak reads 1 on a broken runner.
        #
        # With the barrier the two implementations separate. One worker: the first suite waits for
        # a second sign-in that cannot arrive, times out, and holds alone; the two after it find
        # enough sign-ins already on disk and hold alone too. Peak 1. More than one worker: the
        # barrier releases them together and the peak goes above 1.
        #
        # A shorter timeout than the default here. The timeout is pure cost on the passing path in
        # this case, and it is only reached on the failing path in the case above. Five seconds is
        # still far longer than starting a second child takes.
        $names = @('01-a.Tests.ps1', '02-b.Tests.ps1', '03-c.Tests.ps1')
        foreach ($name in $names) { Add-IntervalSuite -Root $root -Name $name -BarrierCount 2 -TimeoutSeconds 5 }
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 1
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $peak = Get-PeakOverlap -Root $root -Name $names
        Assert-True ($peak -eq 1) "-MaxParallel 1 must never overlap, got $peak."
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'An exclusive suite never overlaps another suite' {
    $root = New-SuiteFixture
    try {
        # All three sign in under one tag, and the counts differ. The pair waits for two, so they
        # are released by each other and their windows must intersect. The exclusive suite waits
        # for all three, which is the assertion turned into behaviour: it holds its window open
        # until the other two are alive beside it.
        #
        # An earlier draft gave the exclusive suite no barrier and a fixed 300 ms window. A
        # scheduler that wrongly admitted it into the shared pool could then start the pair after
        # that window closed, and every assertion still passed. With the three-count barrier that
        # scheduler is caught: the pair signs in while the exclusive suite is still waiting, all
        # three release together, and the peak reads 3.
        #
        # A correct scheduler pays one timeout, and only in one of the two orders. If the exclusive
        # suite runs first it waits the full timeout, because the pair cannot start beside it, then
        # holds alone; the pair then finds three sign-ins on disk and releases at once. If the pair
        # runs first they release each other with no wait, and the exclusive suite afterwards finds
        # three sign-ins already there.
        $names = @('01-alone.Tests.ps1', '02-other.Tests.ps1', '03-other.Tests.ps1')
        Add-IntervalSuite -Root $root -Name '01-alone.Tests.ps1' -BarrierCount 3 -BarrierTag 'pair'
        Add-IntervalSuite -Root $root -Name '02-other.Tests.ps1' -BarrierCount 2 -BarrierTag 'pair'
        Add-IntervalSuite -Root $root -Name '03-other.Tests.ps1' -BarrierCount 2 -BarrierTag 'pair'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-alone.Tests.ps1'; jobs = @('suites'); execution = 'exclusive'; reason = 'The test needs one suite that may not share.'; baselineSeconds = $null }
            [ordered]@{ name = '02-other.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '03-other.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 3
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        # The two parallel suites must still overlap. Without this the case passes on a runner that
        # simply never parallelises, which is the whole failure being guarded against.
        $pair = Get-PeakOverlap -Root $root -Name @('02-other.Tests.ps1', '03-other.Tests.ps1')
        Assert-True ($pair -eq 2) "The two parallel suites must overlap each other, got $pair."

        $all = Get-PeakOverlap -Root $root -Name $names
        Assert-True ($all -eq 2) "The exclusive suite must not raise peak overlap above 2, got $all."

        $mine = @(Get-Content -LiteralPath (Join-Path (Join-Path $root 'markers') '01-alone.Tests.ps1.interval'))
        $start = [long] $mine[0]
        $end = [long] $mine[1]
        foreach ($other in @('02-other.Tests.ps1', '03-other.Tests.ps1')) {
            $theirs = @(Get-Content -LiteralPath (Join-Path (Join-Path $root 'markers') ($other + '.interval')))
            $overlaps = ([long] $theirs[0]) -lt $end -and ([long] $theirs[1]) -gt $start
            Assert-True (-not $overlaps) "$other ran inside the exclusive window."
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A blank AHKFLOW_SUITE_MAX_PARALLEL falls back to the default' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -EnvVar @{ AHKFLOW_SUITE_MAX_PARALLEL = '   ' }
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A bad AHKFLOW_SUITE_MAX_PARALLEL fails the run and names the variable' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        foreach ($bad in @('lots', '0', '-2', '2.5')) {
            $result = Invoke-Driver -SuiteRoot $root -EnvVar @{ AHKFLOW_SUITE_MAX_PARALLEL = $bad }
            Assert-True ($result.ExitCode -eq 1) "Value '$bad' must fail the run, got $($result.ExitCode). Output: $($result.Output)"
            Assert-True ($result.Output -match 'AHKFLOW_SUITE_MAX_PARALLEL') "The message must name the variable. Output: $($result.Output)"
            Assert-True ($result.Output -match [regex]::Escape($bad)) "The message must name the value. Output: $($result.Output)"
            Assert-True (-not (Test-MarkerExists -Root $root -Name '01-pass.Tests.ps1')) "No suite may run for value '$bad'."
            Remove-Item -LiteralPath (Join-Path (Join-Path $root 'markers') '*') -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'An explicit -MaxParallel wins over the environment variable' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        # The variable is unusable, so a run that read it would fail. The explicit value must win
        # before the variable is even considered.
        $result = Invoke-Driver -SuiteRoot $root -MaxParallel 2 -EnvVar @{ AHKFLOW_SUITE_MAX_PARALLEL = 'lots' }
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'An explicit -MaxParallel below one fails the run' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $result = Invoke-Driver -SuiteRoot $root -MaxParallel -1
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'MaxParallel') "The message must name the parameter. Output: $($result.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A run inside GitHub Actions wraps each suite in one pair of group markers' {
    $root = New-SuiteFixture
    try {
        Add-FakeSuite -Root $root -Name '01-pass.Tests.ps1' -Ending 'pass'
        Add-FakeSuite -Root $root -Name '02-pass.Tests.ps1' -Ending 'pass'
        Set-FixtureManifest -Root $root

        $inside = Invoke-Driver -SuiteRoot $root -EnvVar @{ GITHUB_ACTIONS = 'true' }
        Assert-True (([regex]::Matches($inside.Output, '::group::')).Count -eq 2) "Expected two group markers. Output: $($inside.Output)"
        Assert-True (([regex]::Matches($inside.Output, '::endgroup::')).Count -eq 2) "Expected two endgroup markers. Output: $($inside.Output)"

        $outside = Invoke-Driver -SuiteRoot $root -EnvVar @{ GITHUB_ACTIONS = '' }
        Assert-True ($outside.Output -notmatch '::group::') "A run outside Actions must emit no group markers. Output: $($outside.Output)"
    } finally {
        Remove-SuiteFixture -Root $root
    }
}

Invoke-TestCase 'A targeted run keeps the stored timings of every suite it did not select' {
    # A copy of the runner in a temporary tree, so this is a real run that saves timings without
    # touching the store the real runs read.
    $fakeRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterepo-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'tests') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'markers') -Force | Out-Null

        foreach ($name in @('run-powershell-suites.ps1', 'progress.common.ps1', 'progress.parallel.ps1', 'powershell-suites.common.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $fakeRepo "scripts/$name")
        }

        foreach ($name in @('01-one.Tests.ps1', '02-two.Tests.ps1')) {
            Add-FakeSuite -Root $fakeRepo -Name $name -Ending 'pass'
            Move-Item -LiteralPath (Join-Path $fakeRepo $name) -Destination (Join-Path $fakeRepo "tests/$name")
        }

        $manifest = [ordered]@{ suites = @(
                [ordered]@{ name = '01-one.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
                [ordered]@{ name = '02-two.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            ) }
        Set-Content -LiteralPath (Join-Path $fakeRepo 'tests/powershell-suites.json') -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding utf8

        $driver = Join-Path $fakeRepo 'scripts/run-powershell-suites.ps1'
        $timings = Join-Path $fakeRepo 'TestResults/progress/run-powershell-suites.json'

        & $script:HostExe -NoProfile -File $driver 2>&1 | Out-Null
        $before = Get-Content -LiteralPath $timings -Raw | ConvertFrom-Json
        Assert-True ($null -ne $before.'01-one.Tests.ps1' -and $null -ne $before.'02-two.Tests.ps1') 'The full run must store both suites.'

        & $script:HostExe -NoProfile -File $driver -Suite '01-one*' 2>&1 | Out-Null
        $after = Get-Content -LiteralPath $timings -Raw | ConvertFrom-Json
        Assert-True ($null -ne $after.PSObject.Properties['02-two.Tests.ps1']) 'A targeted run must keep the other suite''s history.'
        Assert-True ($null -ne $after.PSObject.Properties['01-one.Tests.ps1']) 'A targeted run must store the suite it ran.'
    } finally {
        Remove-Item -LiteralPath $fakeRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'A stored entry whose suite file no longer exists is dropped' {
    $fakeRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterepo-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'tests') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'markers') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'TestResults/progress') -Force | Out-Null

        foreach ($name in @('run-powershell-suites.ps1', 'progress.common.ps1', 'progress.parallel.ps1', 'powershell-suites.common.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $fakeRepo "scripts/$name")
        }

        Add-FakeSuite -Root $fakeRepo -Name '01-one.Tests.ps1' -Ending 'pass'
        Move-Item -LiteralPath (Join-Path $fakeRepo '01-one.Tests.ps1') -Destination (Join-Path $fakeRepo 'tests/01-one.Tests.ps1')

        $manifest = [ordered]@{ suites = @(
                [ordered]@{ name = '01-one.Tests.ps1'; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
            ) }
        Set-Content -LiteralPath (Join-Path $fakeRepo 'tests/powershell-suites.json') -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding utf8

        $timings = Join-Path $fakeRepo 'TestResults/progress/run-powershell-suites.json'
        Set-Content -LiteralPath $timings -Value '{ "deleted.Tests.ps1": 42 }' -Encoding utf8

        & $script:HostExe -NoProfile -File (Join-Path $fakeRepo 'scripts/run-powershell-suites.ps1') 2>&1 | Out-Null

        $saved = Get-Content -LiteralPath $timings -Raw | ConvertFrom-Json
        Assert-True ($null -eq $saved.PSObject.Properties['deleted.Tests.ps1']) 'An entry whose suite file is gone must be dropped.'
        Assert-True ($null -ne $saved.PSObject.Properties['01-one.Tests.ps1']) 'The suite that ran must be stored.'
    } finally {
        Remove-Item -LiteralPath $fakeRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# A storing run needs a tree the runner treats as a repository of its own, with no -NoStore. The
# two cases above build that same shape inline; this helper is the reusable form of it. Collapsing
# those two onto it is optional tidying, and this contract is what the new case below needs.
# -Suite names the suites, each of which gets a plain passing body. -Body overrides the body of any
# of them, as an array of script lines.
function New-StoringRepoFixture {
    param([string[]] $Suite, [hashtable] $Body = @{}, [switch] $CountSaves)

    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterepo-' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($folder in @('scripts', 'tests', 'markers', 'TestResults/progress')) {
            New-Item -ItemType Directory -Path (Join-Path $repo $folder) -Force | Out-Null
        }
        foreach ($name in @('run-powershell-suites.ps1', 'progress.common.ps1', 'progress.parallel.ps1', 'powershell-suites.common.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $repo "scripts/$name")
        }

        if ($CountSaves) {
            # Append a counting wrapper to the *copy* of the module, so a run in this fixture
            # records every actual call to Save-ProgressTimings. Reading the timings file proves
            # when the save landed; this proves how many times it ran, which no reading of the file
            # and no reading of the source can establish on its own. The real module is untouched.
            Add-Content -LiteralPath (Join-Path $repo 'scripts/progress.common.ps1') -Value @'

$global:AhkflowSaveTimingsInner = ${function:Save-ProgressTimings}
function Save-ProgressTimings {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot '..\markers\savecalls') -Value 'called'
    & $global:AhkflowSaveTimingsInner @args
}
'@
        }

        $entries = foreach ($name in $Suite) {
            if ($Body.ContainsKey($name)) {
                Set-Content -LiteralPath (Join-Path $repo "tests/$name") -Value ($Body[$name] -join [Environment]::NewLine) -Encoding utf8
            } else {
                Add-FakeSuite -Root $repo -Name $name -Ending 'pass'
                Move-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $repo "tests/$name")
            }
            [ordered]@{ name = $name; jobs = @('suites'); execution = 'parallel'; baselineSeconds = $null }
        }
        $manifest = [ordered]@{ suites = @($entries) }
        Set-Content -LiteralPath (Join-Path $repo 'tests/powershell-suites.json') -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding utf8

        return $repo
    } catch {
        # The caller's try block only starts once this function has returned, so a failure part way
        # through here would otherwise leave the half-built tree in the temporary folder for good.
        Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

# Invoke-Driver runs the repository's own runner against a fixture suite folder. This runs the
# copy inside a fixture repository instead, so the run stores its timings there.
function Invoke-DriverAt {
    param([string] $Repo, [int] $MaxParallel = 0, [string[]] $Suite = @())

    $arguments = @('-NoProfile', '-File', (Join-Path $Repo 'scripts/run-powershell-suites.ps1'))
    if ($PSBoundParameters.ContainsKey('MaxParallel')) { $arguments += @('-MaxParallel', $MaxParallel) }
    if ($Suite.Count -gt 0) { $arguments += @('-Suite') + $Suite }

    $output = & $script:HostExe @arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

Invoke-TestCase 'The timings file is written once, after the last suite ends' {
    # The acceptance claim is "written once, after every selected suite ends". It takes three
    # checks, and this case carries two of them. Read them together with the position case below;
    # no single one of the three is the proof.
    #
    # The watcher is the behavioural half of "after". One suite finishes early; the other stays
    # alive and looks at the timings file after it has. A runner that saves from a per-suite
    # completion handler writes the file the moment 01-first ends, and the watcher then sees it.
    # The grace period only ever helps that bug show itself: a correct runner cannot write the file
    # during it, because the run has not ended, so a longer wait produces no false failure.
    #
    # What the watcher does not give is "after" in full. It samples at one instant, so a save
    # landing in the gap between that sample and the watcher's own exit would pass here. The gap is
    # milliseconds wide and it cannot be closed by sampling - any chain of watchers has a last one,
    # with the same gap after it. The position case below closes it from the source side instead.
    #
    # "Once" is the call count, and neither the watcher nor the source position gives it: two saves
    # that both land at the end look exactly like one, and a single call site can run twice. The
    # fixture's -CountSaves wrapper records every call, so the count is read rather than inferred.
    $fake = New-StoringRepoFixture -Suite @('01-first.Tests.ps1', '02-watcher.Tests.ps1') -CountSaves
    try {
        # Both bodies embed the fixture's own path, which only exists once the fixture is built, so
        # they are written here and not above. Every embedded path goes through
        # ConvertTo-ScriptLiteral, and the watcher times out on the monotonic counter for the same
        # reason Add-IntervalSuite does.
        $first = @(
            'Start-Sleep -Milliseconds 200'
            "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral (Join-Path $fake 'markers\01-first.done')) -Value 'done' -Encoding ascii"
        )
        $watcher = @(
            "`$done = $(ConvertTo-ScriptLiteral (Join-Path $fake 'markers\01-first.done'))"
            "`$watch = [System.Diagnostics.Stopwatch]::StartNew()"
            'while ($watch.Elapsed.TotalSeconds -lt 15 -and -not (Test-Path -LiteralPath $done)) { Start-Sleep -Milliseconds 25 }'
            'if (-not (Test-Path -LiteralPath $done)) { throw ''01-first never finished; the watcher proved nothing.'' }'
            'Start-Sleep -Milliseconds 1500'
            "`$timings = $(ConvertTo-ScriptLiteral (Join-Path $fake 'TestResults\progress\run-powershell-suites.json'))"
            "`$seen = if (Test-Path -LiteralPath `$timings) { 'present' } else { 'absent' }"
            "Set-Content -LiteralPath $(ConvertTo-ScriptLiteral (Join-Path $fake 'markers\sawtimings')) -Value `$seen -Encoding ascii"
        )
        Set-Content -LiteralPath (Join-Path $fake 'tests\01-first.Tests.ps1') -Value ($first -join [Environment]::NewLine) -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fake 'tests\02-watcher.Tests.ps1') -Value ($watcher -join [Environment]::NewLine) -Encoding utf8

        $timings = Join-Path $fake 'TestResults\progress\run-powershell-suites.json'
        Assert-True (-not (Test-Path -LiteralPath $timings)) 'The fixture must start with no timings file.'

        $result = Invoke-DriverAt -Repo $fake -MaxParallel 2
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $sawtimings = Join-Path $fake 'markers\sawtimings'
        Assert-True (Test-Path -LiteralPath $sawtimings) "The watcher suite never reached its sample. Output: $($result.Output)"
        $seen = (Get-Content -Raw -LiteralPath $sawtimings).Trim()
        Assert-True ($seen -eq 'absent') 'The timings file existed while a suite was still running; the save must land once, at the end.'

        # Exactly one call, counted at run time. A per-suite save writes one line per suite, and a
        # call site that runs twice writes two lines, whatever the file's final contents look like.
        $saveCalls = @(Get-Content -LiteralPath (Join-Path $fake 'markers\savecalls') -ErrorAction SilentlyContinue)
        Assert-True ($saveCalls.Count -eq 1) "Save-ProgressTimings ran $($saveCalls.Count) times; it must run exactly once per run."

        Assert-True (Test-Path -LiteralPath $timings) 'The run must write the timings file when it ends.'
        $stored = (Get-Content -Raw -LiteralPath $timings | ConvertFrom-Json)
        foreach ($name in @('01-first.Tests.ps1', '02-watcher.Tests.ps1')) {
            Assert-True ($stored.PSObject.Properties.Name -contains $name) "The timings file must carry $name."
        }
    } finally {
        Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'The one Save-ProgressTimings call sits at the top level, after the parallel loop' {
    # Position, which is what the two runtime checks cannot give. The watcher proves the file did
    # not exist at the instant it sampled, and the counter proves the save ran once. Neither rules
    # out a save that lands in the gap between the watcher's sample and the watcher's exit. That
    # gap is milliseconds wide, but it is real, and a claim of "only after every suite ends"
    # deserves better than a narrow window.
    #
    # This closes it from the other side. The call is at the script's top level: not in a function,
    # not in a script block, not in a loop. So it runs where it is written, and it is written after
    # the parallel pipeline. That pipeline does not return until every child has been processed, so
    # a call after it cannot run before the last suite ends. Position plus a counted single call is
    # the whole claim.
    $runner = Join-Path $repoRoot 'scripts/run-powershell-suites.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref] $null, [ref] $null)

    $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Save-ProgressTimings'
            }, $true))
    Assert-True ($calls.Count -eq 1) "Expected exactly one Save-ProgressTimings call site, found $($calls.Count)."

    # Walk to the root, not to the first named block. A function body has a named block of its own,
    # so stopping there would read a call inside Show-SuiteResult as top level.
    $nested = @()
    $node = $calls[0].Parent
    while ($null -ne $node) {
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
            $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or
            $node -is [System.Management.Automation.Language.LoopStatementAst]) {
            $nested += $node.GetType().Name
        }
        $node = $node.Parent
    }
    Assert-True ($nested.Count -eq 0) "Save-ProgressTimings must be called at the top level of the script, but it is inside: $($nested -join ', ')."

    $parallel = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'ForEach-Object' -and
                $node.Extent.Text -like '*-Parallel*'
            }, $true))
    Assert-True ($parallel.Count -eq 1) "Expected exactly one parallel pipeline, found $($parallel.Count)."
    Assert-True ($calls[0].Extent.StartOffset -gt $parallel[0].Extent.EndOffset) 'The save must be written after the parallel loop, not before it.'
}

# --- Checks over this repository's own manifest ---

Invoke-TestCase 'The manifest lists every suite in tests/, exactly once' {
    $manifestPath = Join-Path $PSScriptRoot 'powershell-suites.json'
    Assert-True (Test-Path -LiteralPath $manifestPath) "The manifest must exist at $manifestPath."

    $onDisk = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
    $entries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $onDisk)
    Assert-True ($entries.Count -eq $onDisk.Count) "Manifest holds $($entries.Count) entries for $($onDisk.Count) files."
}

# One list of invariant suites, not two. The invariant job cannot call the runner yet, because it
# runs on Linux and nobody has run the runner there. Backlog 127 owns that. Until then this Check
# keeps the two records in step.
Invoke-TestCase 'The manifest invariants set matches check-repo-invariants.ps1' {
    $manifestPath = Join-Path $PSScriptRoot 'powershell-suites.json'
    $onDisk = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
    $fromManifest = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $onDisk |
            Where-Object { $_.Jobs -contains 'invariants' } | ForEach-Object { $_.Name } | Sort-Object)

    # Read the parsed assignment, not the file text. The parser drops comments, so a suite named
    # only in a comment cannot count as the script running that suite.
    $checkScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/ci/check-repo-invariants.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($checkScript, [ref] $null, [ref] $null)
    $assignment = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'suites'
        }, $true)
    Assert-True ($null -ne $assignment) 'check-repo-invariants.ps1 must assign a $suites variable.'

    $fromScript = @($assignment.Right.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { $_.Value } | Sort-Object)

    Assert-True (($fromManifest -join ',') -eq ($fromScript -join ',')) `
        "The two lists disagree. Manifest: $($fromManifest -join ','). Script: $($fromScript -join ',')."
}

# The Codex suite runs on Linux in its own job, because the bash setup script it compares against
# refuses to run under Windows Git Bash. It is the only suite outside the suites job.
Invoke-TestCase 'CodexSkillsHashParity is the only suite outside the suites job' {
    $manifestPath = Join-Path $PSScriptRoot 'powershell-suites.json'
    $onDisk = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
    $outside = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $onDisk |
            Where-Object { $_.Jobs -notcontains 'suites' } | ForEach-Object { $_.Name })

    Assert-True ($outside.Count -eq 1) "Expected one suite outside the suites job, got: $($outside -join ', ')"
    Assert-True ($outside[0] -eq 'CodexSkillsHashParity.Tests.ps1') "Got: $($outside[0])"
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'CI PowerShell suite runner tests passed.' -ForegroundColor Green
exit 0
