#Requires -Version 7.0
<#
.SYNOPSIS
  Runs every PowerShell test suite in tests/ and fails when any of them fails.
.DESCRIPTION
  Run it locally before a push, and read the table it prints. CI runs the same script in the
  powershell-suites job in .github/workflows/ci.yml.

  This script needs PowerShell 7. Start it with pwsh, which is what every documented command
  already does. tests/powershell-suites.json is the one record of which suites exist and which
  CI jobs run each of them; this script reads and checks it before it starts any child process.

  Each suite runs as its own process. That is the whole point of this script. The suites end in
  two different ways: some call 'exit 1' on failure and 'exit 0' on success, others throw on
  failure and simply run off the end on success. A suite that runs off the end leaves
  $LASTEXITCODE at whatever the last native command inside it returned, so checking $LASTEXITCODE
  after dot-sourcing or calling the suite in this process would report passing suites as failed.
  A child process has none of that history: its exit code is 0 unless the suite failed.

  Every suite runs even after an earlier one fails, so one CI run reports every broken suite.
#>

[CmdletBinding()]
param(
    [string] $SuiteRoot,

    # Wildcards matched against suite file names, for the inner development loop. With none, the
    # run covers every suite in the 'suites' job, which is what CI and the Gate both want.
    # A value that matches nothing fails the run: a typo must never look like a green run.
    [string[]] $Suite = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.4 turns a non-zero exit code from a native command into a terminating error when
# $ErrorActionPreference is 'Stop'. That would abort this script on the first failing suite, which
# is exactly the behaviour this job must not have. Opt out so a failing suite is data, not an error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $PSScriptRoot

. "$PSScriptRoot\progress.common.ps1"
. "$PSScriptRoot\powershell-suites.common.ps1"

if ([string]::IsNullOrWhiteSpace($SuiteRoot)) {
    $SuiteRoot = Join-Path $repoRoot 'tests'
}

function Write-Failure([string]$Message) {
    Write-Host $Message -ForegroundColor Red
}

if (-not (Test-Path -LiteralPath $SuiteRoot -PathType Container)) {
    Write-Failure "Suite folder not found: $SuiteRoot"
    exit 1
}

$SuiteRoot = (Resolve-Path -LiteralPath $SuiteRoot).ProviderPath

# Every run prints progress lines, so a test over a folder of fake suites checks the same code
# path a real run uses. Only a run over the repository's own suites keeps the timings.
$keepTimings = Test-ProgressTimingsWanted -SuiteRoot $SuiteRoot -DefaultSuiteRoot (Join-Path $repoRoot 'tests')

$discovered = @(Get-ChildItem -LiteralPath $SuiteRoot -Filter '*.Tests.ps1' -File | Sort-Object Name)

# A folder the glob finds nothing in cannot have a manifest worth reading, and the message a
# reader needs there names the folder, not the manifest.
if ($discovered.Count -eq 0) {
    Write-Failure "No test suites found in $SuiteRoot"
    Write-Host 'A run with nothing to run must not look green.'
    exit 1
}

$manifestPath = Join-Path $SuiteRoot 'powershell-suites.json'
try {
    $entries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName @($discovered.Name))
    $selected = @(Select-SuiteEntry -Entry $entries -Pattern $Suite)
} catch {
    # Stop before any child starts. A manifest or selection we cannot trust means the coverage this
    # run reports would be a guess.
    Write-Failure $_.Exception.Message
    exit 1
}

$byName = @{}
foreach ($file in $discovered) { $byName[$file.Name] = $file }
$suites = @($selected | ForEach-Object { $byName[$_.Name] })

# The suites are written for the host that runs this script, so run them under the same one.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$inActions = $env:GITHUB_ACTIONS -eq 'true'

Write-Host "Running $($suites.Count) PowerShell suite(s) from $SuiteRoot"
Write-Host "Host: $hostExe"

$progress = New-ProgressTracker -RunnerKey 'run-powershell-suites' -Unit @($suites.Name) -RepoRoot $repoRoot -NoStore:(-not $keepTimings)

$results = [System.Collections.Generic.List[object]]::new()
# Not $suite. PowerShell treats $suite and the -Suite parameter as one variable, and that
# parameter is typed [string[]], so a loop over it would turn each file into a string array.
foreach ($suiteFile in $suites) {
    if ($inActions) { Write-Host "::group::$($suiteFile.Name)" }
    Start-ProgressUnit -Tracker $progress -Name $suiteFile.Name

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $hostExe -NoProfile -File $suiteFile.FullName
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()
    Stop-ProgressUnit -Tracker $progress

    if ($inActions) { Write-Host '::endgroup::' }

    $results.Add([pscustomobject]@{
            Name     = $suiteFile.Name
            ExitCode = $exitCode
            Seconds  = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        })

    if ($exitCode -ne 0) {
        Write-Failure "FAILED: $($suiteFile.Name) (exit code $exitCode)"
    }
}

Save-ProgressTimings -Tracker $progress

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('### PowerShell suites')
$lines.Add('')
$lines.Add('| Suite | Result | Exit code | Duration |')
$lines.Add('|---|---|---|---|')
foreach ($result in $results) {
    $verdict = if ($result.ExitCode -eq 0) { 'passed' } else { 'failed' }
    $lines.Add("| $($result.Name) | $verdict | $($result.ExitCode) | $($result.Seconds)s |")
}
$lines.Add('')
if ($failed.Count -gt 0) {
    $lines.Add("**$($failed.Count) of $($results.Count) suite(s) failed:** $(($failed.Name) -join ', ')")
} else {
    $lines.Add("All $($results.Count) suite(s) passed.")
}

$summary = $lines -join [Environment]::NewLine

Write-Host ''
Write-Host $summary

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding utf8
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
