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

$trxFile = Get-ChildItem -LiteralPath $RunDirectory -Recurse -Filter '*.trx' |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $trxFile) {
    throw "No TRX under $RunDirectory, so there is no run to report on."
}

$runInterval = Get-AhkFlowTrxRunInterval -TrxPath $trxFile.FullName
$testResults = @(Read-TrxResults -TrxPath $trxFile.FullName -ProjectName 'run')

# The driver writes run.json beside the artifacts. Reading it here means the command boundary is
# never a number somebody retyped.
$runJsonPath = Join-Path $RunDirectory 'run.json'
if (-not $PSBoundParameters.ContainsKey('CommandSeconds') -and (Test-Path -LiteralPath $runJsonPath)) {
    $CommandSeconds = [double](Get-Content -LiteralPath $runJsonPath -Raw | ConvertFrom-Json).ElapsedSeconds
    $PSBoundParameters['CommandSeconds'] = $CommandSeconds
}

$timingDirectory = Join-Path $RunDirectory 'fixture-timing'
$fixtureEntries = @()
if (Test-Path -LiteralPath $timingDirectory -PathType Container) {
    foreach ($timingFile in Get-ChildItem -LiteralPath $timingDirectory -Filter 'fixture-timings-*.jsonl') {
        foreach ($line in Get-Content -LiteralPath $timingFile.FullName) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $entry = $line | ConvertFrom-Json
            $fixtureEntries += [pscustomobject]@{
                Component = $entry.component
                Operation = $entry.operation
                StartUtc = ([datetimeoffset]$entry.startedUtc).UtcDateTime
                EndUtc = ([datetimeoffset]$entry.finishedUtc).UtcDateTime
                ElapsedMilliseconds = [double]$entry.elapsedMilliseconds
            }
        }
    }
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
$steps = @($fixtureEntries | Group-Object -Property Component, Operation | ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
        Component = $group[0].Component
        Operation = $group[0].Operation
        Count = $group.Count
        SumMilliseconds = [math]::Round((($group | Measure-Object -Property ElapsedMilliseconds -Sum).Sum), 3)
        MedianMilliseconds = Get-AhkFlowMedian -Values @($group | ForEach-Object { $_.ElapsedMilliseconds })
        SpanMilliseconds = [math]::Round(((($group | Measure-Object -Property EndUtc -Maximum).Maximum) - (($group | Measure-Object -Property StartUtc -Minimum).Minimum)).TotalMilliseconds, 3)
    }
})

$report = [pscustomobject]@{
    TrxPath = $trxFile.FullName
    RunIntervalMilliseconds = [math]::Round($runLength, 3)
    CoveredMilliseconds = $covered
    HarnessOverheadMilliseconds = [math]::Round($runLength - $covered, 3)
    TestCount = $testResults.Count
    Step = $steps
    OutsideRunIntervalMilliseconds = if ($PSBoundParameters.ContainsKey('CommandSeconds')) {
        [math]::Round(($CommandSeconds * 1000) - $runLength, 3)
    }
    else { $null }
}

Write-Host ''
Write-Host "=== Harness overhead, from $($trxFile.Name) ===" -ForegroundColor Cyan
Write-Host ("TRX run interval      : {0,10:N0} ms" -f $report.RunIntervalMilliseconds)
Write-Host ("Covered by work       : {0,10:N0} ms  ({1} tests, {2} fixture records)" -f $report.CoveredMilliseconds, $report.TestCount, $fixtureEntries.Count)
Write-Host ("Harness overhead      : {0,10:N0} ms" -f $report.HarnessOverheadMilliseconds) -ForegroundColor Yellow
if ($null -ne $report.OutsideRunIntervalMilliseconds) {
    Write-Host ("Outside the run       : {0,10:N0} ms  (build, publish, container, process start)" -f $report.OutsideRunIntervalMilliseconds)
}

if ($steps.Count -gt 0) {
    Write-Host ''
    $steps | Sort-Object -Property SumMilliseconds -Descending |
        Format-Table -AutoSize -Property Component, Operation, Count, SumMilliseconds, MedianMilliseconds, SpanMilliseconds |
        Out-Host
}

return $report
