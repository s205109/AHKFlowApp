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

    # Wildcards matched against suite file names, for the inner development loop. Leave the
    # argument out and the run covers every suite in the 'suites' job, which is what CI and the
    # Gate both want. A value that matches nothing fails the run: a typo must never look like a
    # green run. So does a blank value, and so does the argument with no value at all.
    [string[]] $Suite = @(),

    # How many suites may run at once. With no value the run uses the processor count, capped at
    # eight, and AHKFLOW_SUITE_MAX_PARALLEL overrides that default. An explicit value wins over the
    # variable. These suites wait on git child processes more than on the processor, so more workers
    # than processors may still be faster; nobody has measured that, and the variable makes the
    # measurement cheap.
    [int] $MaxParallel = 0
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
. "$PSScriptRoot\progress.parallel.ps1"

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

    # Leaving -Suite out is the only way to ask for the whole job. A caller who passes the argument
    # asked for a subset, so an argument that names nothing is a mistake. '-Suite $env:FILTER' with
    # the variable unset binds $null, and that used to run every suite.
    if ($PSBoundParameters.ContainsKey('Suite') -and ($null -eq $Suite -or $Suite.Count -eq 0)) {
        throw '-Suite was given no value to match. Leave -Suite out to run every suite in the suites job.'
    }

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

$workerCount = [Math]::Min([Environment]::ProcessorCount, 8)

# The explicit parameter is settled first, and the variable is then never read. "An explicit value
# wins over the variable" has to mean this: validating the variable first would fail the run on a
# value the caller has already overridden.
if ($PSBoundParameters.ContainsKey('MaxParallel')) {
    if ($MaxParallel -lt 1) {
        Write-Failure "-MaxParallel must be a whole number of at least one. Got: $MaxParallel"
        exit 1
    }
    $workerCount = $MaxParallel
} else {
    $envMaxParallel = $env:AHKFLOW_SUITE_MAX_PARALLEL
    if (-not [string]::IsNullOrWhiteSpace($envMaxParallel)) {
        $parsedMaxParallel = 0
        if (-not [int]::TryParse($envMaxParallel.Trim(), [ref] $parsedMaxParallel) -or $parsedMaxParallel -lt 1) {
            # Falling back to the default here would hide a misconfigured CI job for months.
            Write-Failure "AHKFLOW_SUITE_MAX_PARALLEL must be a whole number of at least one. Got: '$envMaxParallel'"
            exit 1
        }
        $workerCount = $parsedMaxParallel
    }
}

# The suites are written for the host that runs this script, so run them under the same one.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$inActions = $env:GITHUB_ACTIONS -eq 'true'

Write-Host "Running $($suites.Count) PowerShell suite(s) from $SuiteRoot"
Write-Host "Host: $hostExe"

$progress = New-ProgressTracker -RunnerKey 'run-powershell-suites' -Unit @($suites.Name) -RepoRoot $repoRoot -NoStore:(-not $keepTimings)

Write-Host "Workers: $workerCount"

$schedule = @(Get-SuiteSchedule -Entry $selected -History $progress.History)
$parallelProgress = New-ParallelProgressTracker -Tracker $progress -Schedule $schedule -MaxParallel $workerCount

$results = [System.Collections.Generic.List[object]]::new()

# Invoke-SuiteChild comes from powershell-suites.common.ps1, which this script already dot-sources.
# Prints one suite's whole block, in this runspace. Buffering the child's output and printing it
# here is what stops two suites writing over each other.
function Show-SuiteResult {
    param([object] $Result)

    if ($inActions) { Write-Host "::group::$($Result.Name)" }

    Complete-ParallelProgressUnit -Tracker $parallelProgress -Name $Result.Name -Seconds $Result.Seconds
    Write-Host (Get-ParallelProgressLine -Tracker $parallelProgress -Name $Result.Name -Seconds $Result.Seconds)

    if (-not [string]::IsNullOrWhiteSpace($Result.Output)) {
        Write-Host $Result.Output.TrimEnd()
    }

    if ($inActions) { Write-Host '::endgroup::' }

    if ($Result.ExitCode -ne 0) {
        Write-Failure "FAILED: $($Result.Name) (exit code $($Result.ExitCode))"
    }

    $results.Add([pscustomobject]@{
            Name     = $Result.Name
            ExitCode = $Result.ExitCode
            Seconds  = [math]::Round($Result.Seconds, 1)
        })
}

$byPath = @{}
foreach ($file in $suites) { $byPath[$file.Name] = $file.FullName }

# Exclusive suites first, one at a time. Nothing else may run while one of them does, so putting
# them first leaves the pool's longest-first order intact afterwards.
foreach ($item in ($schedule | Where-Object { $_.Execution -eq 'exclusive' })) {
    Show-SuiteResult (Invoke-SuiteChild -Path $byPath[$item.Name] -Name $item.Name -HostExe $hostExe)
}

$shared = @($schedule | Where-Object { $_.Execution -ne 'exclusive' } |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $byPath[$_.Name] } })

$childText = (${function:Invoke-SuiteChild}).ToString()

if ($shared.Count -gt 0) {
    # Longest first. Starting the slowest suite last would leave it running alone at the end, which
    # is exactly the shape that makes a parallel run no faster than a sequential one.
    #
    # Results reach this pipeline as each child exits, so the parent-side ForEach-Object below
    # prints one whole block at a time.
    $shared | ForEach-Object -ThrottleLimit $workerCount -Parallel {
        # Rebuild the function from its text, inside this runspace. Do not pass the scriptblock
        # itself: Microsoft documents that "Scriptblock invocation always attempts to run in its
        # home runspace, regardless of where it's actually invoked", and a scriptblock made in the
        # parent would therefore run back in the parent - serialising the whole run, which is the
        # one failure this task exists to prevent. See
        # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object?view=powershell-7.6
        ${function:Invoke-SuiteChild} = [scriptblock]::Create($using:childText)

        # Fresh runspace: opt out again so a non-zero suite exit code is data, not a throw.
        $PSNativeCommandUseErrorActionPreference = $false

        $child = Invoke-SuiteChild -Path $_.Path -Name $_.Name -HostExe $using:hostExe

        [pscustomobject]@{
            Name     = $child.Name
            ExitCode = $child.ExitCode
            Seconds  = $child.Seconds
            Output   = $child.Output
        }
    } | ForEach-Object { Show-SuiteResult $_ }
}

# Once, after every suite has settled. A save per suite would break the case that reads this
# file's last-write time while a child runs. -KnownUnit drops a suite that no longer exists.
Save-ProgressTimings -Tracker $progress -KnownUnit @($discovered.Name)

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('### PowerShell suites')
$lines.Add('')
$lines.Add('| Suite | Result | Exit code | Duration |')
$lines.Add('|---|---|---|---|')
# By name, not by finish order. A parallel run finishes in a different order every time, and a
# table nobody can scan is no use in a CI log.
foreach ($result in ($results | Sort-Object Name)) {
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
