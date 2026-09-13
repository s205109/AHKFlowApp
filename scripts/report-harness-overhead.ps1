#Requires -Version 7.0
<#
.SYNOPSIS
  Turns one counted run's artifacts into a named breakdown of where its time went.
.DESCRIPTION
  Backlog 140. It reads a folder and starts nothing. A report that ran the tests itself would
  describe a different run from the one the headline timed, and the two use different containers
  and different commands.

  The residual is the part of the TRX run interval that no test interval and no fixture interval
  covers. Intervals are merged, never added: four stacks run at the same time, so adding lengths
  counts the same seconds several times and can return a negative residual.

  The TRX run interval is not the test host's process lifetime. See Get-AhkFlowTrxRunInterval.
.PARAMETER RunDirectory
  The folder holding one run's TRX and its fixture-timing subfolder.
.PARAMETER CommandSeconds
  The wall clock of the whole command. The difference between that and the TRX run interval holds
  the build, the publish, the container step and process start. Leave it out and the run folder's
  own run.json supplies it, which is where the driver writes what it measured.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $RunDirectory,
    [double] $CommandSeconds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-results.common.ps1')

if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
    throw "No run folder at $RunDirectory."
}

$trxPath = Get-AhkFlowLatestTrxPath -ResultsDirectory $RunDirectory

if (-not $trxPath) {
    throw "No TRX under $RunDirectory, so there is no run to report on."
}

$trxName = Split-Path -Leaf $trxPath
$runInterval = Get-AhkFlowTrxRunInterval -TrxPath $trxPath
$testResults = @(Read-TrxResults -TrxPath $trxPath -ProjectName 'run')

# The driver writes run.json beside the artifacts. Reading it here means the command boundary is
# never a number somebody retyped.
$commandBoundarySeconds = $null
$runJsonPath = Join-Path $RunDirectory 'run.json'
if ($PSBoundParameters.ContainsKey('CommandSeconds')) {
    $commandBoundarySeconds = $CommandSeconds
}
elseif (Test-Path -LiteralPath $runJsonPath) {
    $commandBoundarySeconds = [double](Get-Content -LiteralPath $runJsonPath -Raw | ConvertFrom-Json).ElapsedSeconds
}

# Backlog 140 review. A shared component such as the host start gate serves stack fixtures and
# tests alike, so a figure that ignores the caller measures nobody. The reader gives an empty caller
# to a record that carried none, and that record never joins a named caller's row.
$fixtureEntries = @(Read-FixtureTimingEntries -FixtureTimingDirectory (Join-Path $RunDirectory 'fixture-timing'))

$undated = @($fixtureEntries | Where-Object { $null -eq $_.StartUtc -or $null -eq $_.EndUtc })
if ($undated.Count -gt 0) {
    throw "$($undated.Count) fixture timing record(s) carry no startedUtc or finishedUtc, so they cannot be placed on the run interval."
}

$testIntervals = @($testResults | Where-Object { $null -ne $_.StartUtc -and $null -ne $_.EndUtc } |
    ForEach-Object { [pscustomobject]@{ Start = $_.StartUtc; End = $_.EndUtc } })
$fixtureIntervals = @($fixtureEntries | ForEach-Object { [pscustomobject]@{ Start = $_.StartUtc; End = $_.EndUtc } })

$covered = Get-AhkFlowIntervalUnionMilliseconds `
    -Interval @($testIntervals + $fixtureIntervals) `
    -ClipStart $runInterval.Start `
    -ClipEnd $runInterval.End

$runLength = ($runInterval.End - $runInterval.Start).TotalMilliseconds

# Three readings per step, because four stacks overlap. The sum says what the machine paid, the
# median says what one stack costs, and the span says what the wall clock felt.
#
# The caller is part of the key. The host start gate's four stack starts and every host a test
# starts for itself share one component and one operation, so without it the medians below mix
# them, and the row for the gate describes no single kind of start.
$steps = @($fixtureEntries | Group-Object -Property Component, Operation, Caller | ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
        Component = $group[0].Component
        Operation = $group[0].Operation
        Caller = $group[0].Caller
        Count = $group.Count
        SumMilliseconds = [math]::Round((($group | Measure-Object -Property ElapsedMilliseconds -Sum).Sum), 3)
        MedianMilliseconds = Get-AhkFlowMedian -Values @($group | ForEach-Object { $_.ElapsedMilliseconds })
        SpanMilliseconds = [math]::Round(((($group | Measure-Object -Property EndUtc -Maximum).Maximum) - (($group | Measure-Object -Property StartUtc -Minimum).Minimum)).TotalMilliseconds, 3)
    }
})

$report = [pscustomobject]@{
    TrxPath = $trxPath
    RunIntervalMilliseconds = [math]::Round($runLength, 3)
    CoveredMilliseconds = $covered
    HarnessOverheadMilliseconds = [math]::Round($runLength - $covered, 3)
    TestCount = $testResults.Count
    Step = $steps
    OutsideRunIntervalMilliseconds = if ($null -ne $commandBoundarySeconds) {
        [math]::Round(($commandBoundarySeconds * 1000) - $runLength, 3)
    }
    else { $null }
}

Write-Host ''
Write-Host "=== Harness overhead, from $trxName ===" -ForegroundColor Cyan
Write-Host ("TRX run interval      : {0,10:N0} ms" -f $report.RunIntervalMilliseconds)
Write-Host ("Covered by work       : {0,10:N0} ms  ({1} tests, {2} fixture records)" -f $report.CoveredMilliseconds, $report.TestCount, $fixtureEntries.Count)
Write-Host ("Harness overhead      : {0,10:N0} ms" -f $report.HarnessOverheadMilliseconds) -ForegroundColor Yellow
if ($null -ne $report.OutsideRunIntervalMilliseconds) {
    Write-Host ("Outside the run       : {0,10:N0} ms  (build, publish, container, process start)" -f $report.OutsideRunIntervalMilliseconds)
}

if ($steps.Count -gt 0) {
    Write-Host ''
    $steps | Sort-Object -Property SumMilliseconds -Descending |
        Format-Table -AutoSize -Property Component, Operation, Caller, Count, SumMilliseconds, MedianMilliseconds, SpanMilliseconds |
        Out-Host
}

return $report
