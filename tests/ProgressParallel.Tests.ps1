#Requires -Version 7.0

# Backlog 126. scripts/progress.parallel.ps1 prints one line per finished suite during a parallel
# run. It prints no estimate of the time left; the spec's section 7 says why wave 1 drops it.
#
# Run it by hand with:  pwsh ./tests/ProgressParallel.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/progress.common.ps1')
. (Join-Path $repoRoot 'scripts/progress.parallel.ps1')

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

function New-TestSchedule {
    param([hashtable] $Seconds)

    return @($Seconds.Keys | Sort-Object | ForEach-Object {
            [pscustomobject]@{ Name = $_; EffectiveSeconds = [double] $Seconds[$_] }
        })
}

function New-TestTracker {
    param([hashtable] $Seconds, [int] $Worker)

    $schedule = New-TestSchedule -Seconds $Seconds
    $inner = New-ProgressTracker -RunnerKey 'parallel-tests' -Unit @($schedule.Name) -NoStore
    return New-ParallelProgressTracker -Tracker $inner -Schedule $schedule -MaxParallel $Worker
}

# --- The line carries the count, the suite, its seconds, and the elapsed time ---

$tracker = New-TestTracker -Seconds @{ 'a.Tests.ps1' = 10; 'b.Tests.ps1' = 10; 'c.Tests.ps1' = 10 } -Worker 2
Complete-ParallelProgressUnit -Tracker $tracker -Name 'a.Tests.ps1' -Seconds 9.6
$line = Get-ParallelProgressLine -Tracker $tracker -Name 'a.Tests.ps1' -Seconds 9.6

Assert-True ($line -match '^\[1/3 done\]') "The line must open with the done count, got: $line"
Assert-True ($line -match 'a\.Tests\.ps1') "The line must name the suite, got: $line"
Assert-True ($line -match '9\.6s') "The line must carry the suite's seconds, got: $line"
Assert-True ($line -match 'elapsed \d') "The line must carry the elapsed time, got: $line"
Assert-True ($line -notmatch 'remaining') "Wave 1 prints no remaining-time estimate, got: $line"

# --- A finished unit leaves the pending set and reaches the inner tracker ---

Assert-True ($tracker.Done -eq 1) "Done must count the finished suite, got $($tracker.Done)."
Assert-True (-not $tracker.Pending.Contains('a.Tests.ps1')) 'A finished suite must leave the pending set.'
Assert-True ($tracker.Inner.Completed['a.Tests.ps1'] -eq 9.6) "The measurement must reach the inner tracker, got $($tracker.Inner.Completed['a.Tests.ps1'])."

# --- The last suite still prints a well-formed line ---

$tracker = New-TestTracker -Seconds @{ 'only.Tests.ps1' = 3 } -Worker 4
Complete-ParallelProgressUnit -Tracker $tracker -Name 'only.Tests.ps1' -Seconds 3.1
$line = Get-ParallelProgressLine -Tracker $tracker -Name 'only.Tests.ps1' -Seconds 3.1

Assert-True ($line -match '^\[1/1 done\]') "The last line must read 1 of 1, got: $line"

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "ProgressParallel tests failed with $($failures.Count) problem(s)."
}

Write-Host 'ProgressParallel tests passed.' -ForegroundColor Green
