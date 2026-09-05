#Requires -Version 7.0
<#
.SYNOPSIS
Proves scripts/run-powershell-suites.ps1 starts, reads a manifest, and selects suites on the
platform it is running on.

.DESCRIPTION
Backlog 127. Nobody had ever run the runner on Linux. The repo-invariants job runs on Linux, and
this suite belongs to that job, so every pull request now proves the runner works there. It runs
on Windows too, in the powershell-suites job, so the same three claims are checked on both.

The construct that made Linux an open question is the dot-source at the top of the runner:

    . "$PSScriptRoot\progress.common.ps1"

Microsoft documents that paths given to cmdlets are slash-agnostic on Linux and macOS, but
dot-sourcing is not a cmdlet, so that rule did not settle it. Every case here spawns the real
runner, which executes those three dot-sources before it does anything else. A run that produces
output at all has already proved they load.

Each case builds a disposable folder of tiny fake suites under the system temp directory and runs
the runner against it with -SuiteRoot. No case touches the repository's real tests folder, so this
suite is fast and makes no claim about any real suite.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A failing runner run is the expected result in some cases below, and PowerShell 7.4 turns a
# non-zero native exit code into a terminating error while $ErrorActionPreference is 'Stop'.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:RunnerPath = Join-Path $repoRoot 'scripts/run-powershell-suites.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

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
    } catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function New-Fixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-runnerlinux-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
}

function Remove-Fixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# A fake suite that prints its own name and ends cleanly, so a case can read the output and see
# which suites the runner chose.
function Add-FakeSuite {
    param([string] $Root, [string] $Name)

    $body = @(
        "Write-Host 'ran $Name'"
        'exit 0'
    )
    Set-Content -LiteralPath (Join-Path $Root $Name) -Value ($body -join [Environment]::NewLine) -Encoding utf8
}

function Set-FixtureManifest {
    param([string] $Root, [object[]] $Entry)

    $payload = [ordered]@{ suites = @($Entry) }
    Set-Content -LiteralPath (Join-Path $Root 'powershell-suites.json') -Value ($payload | ConvertTo-Json -Depth 6) -Encoding utf8
}

# Spawns the runner as a child of the current host, the way CI does.
function Invoke-Runner {
    param([string] $SuiteRoot, [string[]] $ExtraArgument = @())

    $arguments = @('-NoProfile', '-File', $script:RunnerPath, '-SuiteRoot', $SuiteRoot) + $ExtraArgument
    $output = & $script:HostExe @arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$script:ThisPlatform = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } else { 'other' }
$script:OtherPlatform = if ($script:ThisPlatform -eq 'windows') { 'linux' } else { 'windows' }

Write-Host "Running on: $($script:ThisPlatform)"

if ($script:ThisPlatform -eq 'other') {
    Write-Host 'This platform is neither windows nor linux, so the manifest cannot describe it.' -ForegroundColor Red
    throw 'SuiteRunnerLinux tests need a windows or linux host.'
}

# --- The runner starts ---

# The first claim, and the one the item asked about. Reaching any output at all means the three
# dot-sources at the top of the runner loaded, including the two written with a backslash.
Invoke-TestCase 'The runner starts and reaches its own header' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-one.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-one.Tests.ps1'; jobs = @('suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'Running 1 PowerShell suite') "The runner must print its header. Output: $($result.Output)"
        Assert-True ($result.Output -match 'ran 01-one\.Tests\.ps1') "The suite must actually run. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# The dot-source proof, stated on its own so a failure names the cause rather than the symptom.
# The runner writes progress lines, and that code lives in scripts/progress.common.ps1 - the file
# reached through the backslash path. A run that prints a progress line loaded it.
Invoke-TestCase 'The backslash dot-source loads, on this platform' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-one.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-one.Tests.ps1'; jobs = @('suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.Output -match '\[1/1 done\]') "scripts/progress.common.ps1 must load through its backslash path on $($script:ThisPlatform). Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'progress\.common\.ps1.*not (found|recognized)') "The dot-source must not fail. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# --- It reads a manifest ---

Invoke-TestCase 'A manifest it cannot read stops the run before any suite starts' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-one.Tests.ps1'
        Set-Content -LiteralPath (Join-Path $root 'powershell-suites.json') -Value '{ not json' -Encoding utf8

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'not valid JSON') "The message must say the manifest is unreadable. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ran 01-one') "No suite may run behind an unreadable manifest. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# --- It selects the suites the manifest's job names ---

Invoke-TestCase 'The default run selects the suites job and nothing else' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-in-suites.Tests.ps1'
        Add-FakeSuite -Root $root -Name '02-in-both.Tests.ps1'
        Add-FakeSuite -Root $root -Name '03-parity-only.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-in-suites.Tests.ps1'; jobs = @('suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '02-in-both.Tests.ps1'; jobs = @('invariants', 'suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '03-parity-only.Tests.ps1'; jobs = @('codex-parity'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'ran 01-in-suites') "Output: $($result.Output)"
        Assert-True ($result.Output -match 'ran 02-in-both') "Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ran 03-parity-only') "A codex-parity suite must not run in the suites job. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# The invariants selection is what scripts/ci/check-repo-invariants.ps1 passes, so it needs its own
# proof on the platform that job runs on.
Invoke-TestCase '-Job invariants selects exactly the invariants entries' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-in-suites.Tests.ps1'
        Add-FakeSuite -Root $root -Name '02-in-both.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-in-suites.Tests.ps1'; jobs = @('suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '02-in-both.Tests.ps1'; jobs = @('invariants', 'suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root -ExtraArgument @('-Job', 'invariants')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'Running 1 PowerShell suite') "Only one suite belongs to the invariants job. Output: $($result.Output)"
        Assert-True ($result.Output -match 'ran 02-in-both') "Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ran 01-in-suites') "A suites-only suite must not run in the invariants job. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# The platform field is a rule the runner obeys, not a note for a human. A suite recorded as
# passing only on the other platform must be dropped here.
Invoke-TestCase 'A suite for the other platform is dropped, and the header says which platform ran' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-here.Tests.ps1'
        Add-FakeSuite -Root $root -Name '02-elsewhere.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-here.Tests.ps1'; jobs = @('suites'); platform = @($script:ThisPlatform); execution = 'parallel'; baselineSeconds = $null }
            [ordered]@{ name = '02-elsewhere.Tests.ps1'; jobs = @('suites'); platform = @($script:OtherPlatform); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match "Platform: $($script:ThisPlatform)") "The header must name the platform. Output: $($result.Output)"
        Assert-True ($result.Output -match 'ran 01-here') "Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ran 02-elsewhere') "A suite for the other platform must not run. Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# A run with nothing to run must not look green, and the message has to say why it emptied.
Invoke-TestCase 'A selection emptied by the platform filter fails the run and says so' {
    $root = New-Fixture
    try {
        Add-FakeSuite -Root $root -Name '01-elsewhere.Tests.ps1'
        Set-FixtureManifest -Root $root -Entry @(
            [ordered]@{ name = '01-elsewhere.Tests.ps1'; jobs = @('suites'); platform = @($script:OtherPlatform); execution = 'parallel'; baselineSeconds = $null }
        )

        $result = Invoke-Runner -SuiteRoot $root
        Assert-True ($result.ExitCode -eq 1) "Expected exit code 1, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'another platform') "The message must blame the platform filter. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ran 01-elsewhere') "Output: $($result.Output)"
    } finally {
        Remove-Fixture -Root $root
    }
}

# --- Report ---

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    foreach ($failure in $script:Failures) { Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "SuiteRunnerLinux tests failed with $($script:Failures.Count) problem(s)."
}

Write-Host 'SuiteRunnerLinux tests passed.'
exit 0
