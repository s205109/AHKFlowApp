#Requires -Version 5.1
<#
.SYNOPSIS
  Runs every PowerShell test suite in tests/ and fails when any of them fails.
.DESCRIPTION
  Called by the worktree-powershell-tests job in .github/workflows/ci.yml.

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

    # Suites that have their own CI job. CodexSkillsHashParity runs on Linux in the
    # codex-skills-hash-parity job, because the bash setup script it compares against
    # refuses to run under Windows Git Bash.
    [string[]] $Exclude = @('CodexSkillsHashParity.Tests.ps1')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.4 turns a non-zero exit code from a native command into a terminating error when
# $ErrorActionPreference is 'Stop'. That would abort this script on the first failing suite, which
# is exactly the behaviour this job must not have. Opt out so a failing suite is data, not an error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
$discovered = @(Get-ChildItem -LiteralPath $SuiteRoot -Filter '*.Tests.ps1' -File | Sort-Object Name)

# An exclusion that names a file which no longer exists is a rename nobody finished. Fail on it,
# or the excluded suite silently stops running everywhere.
$discoveredNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $discovered) { [void]$discoveredNames.Add($file.Name) }

$staleExclusions = @($Exclude | Where-Object { -not $discoveredNames.Contains($_) })
if ($staleExclusions.Count -gt 0) {
    Write-Failure "These excluded suites do not exist in ${SuiteRoot}: $($staleExclusions -join ', ')"
    Write-Host 'Update the -Exclude default in this script, or restore the file.'
    exit 1
}

$excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($name in $Exclude) { [void]$excluded.Add($name) }

$suites = @($discovered | Where-Object { -not $excluded.Contains($_.Name) })
if ($suites.Count -eq 0) {
    Write-Failure "No test suites found in $SuiteRoot"
    Write-Host 'A run with nothing to run must not look green.'
    exit 1
}

# The suites are written for the host that runs this script, so run them under the same one.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$inActions = $env:GITHUB_ACTIONS -eq 'true'

Write-Host "Running $($suites.Count) PowerShell suite(s) from $SuiteRoot"
Write-Host "Host: $hostExe"

$results = [System.Collections.Generic.List[object]]::new()
foreach ($suite in $suites) {
    if ($inActions) { Write-Host "::group::$($suite.Name)" }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $hostExe -NoProfile -File $suite.FullName
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()

    if ($inActions) { Write-Host '::endgroup::' }

    $results.Add([pscustomobject]@{
            Name     = $suite.Name
            ExitCode = $exitCode
            Seconds  = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        })

    if ($exitCode -ne 0) {
        Write-Failure "FAILED: $($suite.Name) (exit code $exitCode)"
    }
}

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
