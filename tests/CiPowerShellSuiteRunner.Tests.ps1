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

# Runs the driver as its own process and returns its exit code, everything it printed, and the
# job summary it wrote. The child process is the point: it is exactly what the CI step measures.
#
# The child inherits this process's environment. Under CI that includes GITHUB_STEP_SUMMARY, so
# without the redirect below every fake suite table here would be appended to the real
# powershell-suites job summary — including the deliberate failures. Point the child at a scratch
# file instead. Redirecting rather than clearing keeps the driver's summary-writing branch covered.
function Invoke-Driver {
    param([string] $SuiteRoot, [string[]] $Suite = @())

    $suiteLiteral = if ($Suite.Count -eq 0) {
        ''
    } else {
        ' -Suite @(' + (($Suite | ForEach-Object { ConvertTo-ScriptLiteral $_ }) -join ',') + ')'
    }

    $summaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-suiterunner-summary-' + [guid]::NewGuid().ToString('N') + '.md')
    $previousSummary = $env:GITHUB_STEP_SUMMARY
    $env:GITHUB_STEP_SUMMARY = $summaryPath

    try {
        $command = "& $(ConvertTo-ScriptLiteral $script:DriverPath) -SuiteRoot $(ConvertTo-ScriptLiteral $SuiteRoot)$suiteLiteral; exit `$LASTEXITCODE"
        $output = & $script:HostExe -NoProfile -Command $command 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $summary = if (Test-Path -LiteralPath $summaryPath) {
            Get-Content -LiteralPath $summaryPath -Raw
        } else {
            ''
        }
    } finally {
        $env:GITHUB_STEP_SUMMARY = $previousSummary
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

        Assert-True ($result.Output -match '\[1/2\] 01-pass\.Tests\.ps1') "Expected a progress line for the first suite. Output: $($result.Output)"
        Assert-True ($result.Output -match '\[2/2\] 02-pass\.Tests\.ps1') "Expected a progress line for the second suite. Output: $($result.Output)"

        # A fixture run reads no history, so it can only report the time left as unknown. That is
        # also what proves it did not reach the real store.
        Assert-True ($result.Output -match 'remaining unknown') "A fixture run must report the remaining time as unknown. Output: $($result.Output)"

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

        foreach ($name in @('run-powershell-suites.ps1', 'progress.common.ps1', 'powershell-suites.common.ps1')) {
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
