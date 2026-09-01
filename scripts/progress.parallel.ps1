#Requires -Version 7.0
# Progress lines for a parallel run. Backlog 126.
#
# scripts/progress.common.ps1 walks a list one unit at a time and prints a line before each unit.
# A parallel run cannot do that: several suites are in flight, and no line can name "the current
# one". So this module prints one line when a suite ends. It prints no estimate of the time left;
# the spec's section 7 says why wave 1 drops it.
#
# Dot-source progress.common.ps1 first, then this file. This module uses Format-ProgressDuration
# from there, and wraps a tracker made by New-ProgressTracker.
#
#   . "$PSScriptRoot\progress.common.ps1"
#   . "$PSScriptRoot\progress.parallel.ps1"
#
# Three functions:
#   New-ParallelProgressTracker    wrap a common tracker with the run's schedule
#   Complete-ParallelProgressUnit  record one finished suite
#   Get-ParallelProgressLine       build the line for one finished suite
#
# This file is 7.0, and progress.common.ps1 is 5.1. That split is deliberate. scripts/test-fast.ps1
# dot-sources the common module and declares 5.1, and a '#Requires' inside a dot-sourced file is
# enforced, so a 7.0 line in that file would break the wrapper.
#
# It does not call Set-StrictMode. That call leaks from a dot-sourced file into the caller's scope.

function New-ParallelProgressTracker {
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Schedule,
        [Parameter(Mandatory)][int] $MaxParallel
    )

    # Ordered, so the pending set keeps the schedule's longest-first order. Nothing depends on it
    # today, but a reader comparing the line to the run's order should see the same sequence.
    $pending = [ordered]@{}
    foreach ($item in $Schedule) {
        $pending[$item.Name] = [double] $item.EffectiveSeconds
    }

    return [pscustomobject]@{
        Inner       = $Tracker
        Pending     = $pending
        Total       = @($Schedule).Count
        Done        = 0
        MaxParallel = [Math]::Max(1, $MaxParallel)
    }
}

function Complete-ParallelProgressUnit {
    <#
      Records one finished suite. Call this before Get-ParallelProgressLine, so the line reads the
      count and the pending set as they are after this suite finished.
    #>
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][double] $Seconds
    )

    if ($Tracker.Pending.Contains($Name)) {
        $Tracker.Pending.Remove($Name)
    }

    $Tracker.Done++

    # The common tracker owns the store, so the measurement goes there and Save-ProgressTimings
    # finds it without this module knowing anything about files.
    $Tracker.Inner.Completed[$Name] = [Math]::Round($Seconds, 1)
}

function Get-ParallelProgressLine {
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][double] $Seconds
    )

    $elapsed = Format-ProgressDuration -Seconds $Tracker.Inner.RunWatch.Elapsed.TotalSeconds
    return ('[{0}/{1} done] {2}  {3:0.0}s  elapsed {4}' -f
        $Tracker.Done, $Tracker.Total, $Name, $Seconds, $elapsed)
}
