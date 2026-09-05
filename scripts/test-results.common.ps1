#Requires -Version 5.1
<#
.SYNOPSIS
  The numbers a .NET test run reports back, shared by every script that runs one: how many tests
  a TRX says executed, and the median of several timed runs.
.DESCRIPTION
  Backlog 128. Two scripts have to answer the same question after a run: how many tests did
  that actually execute? scripts/test-fast.ps1 asks so it can refuse a slice that discovered
  nothing, and scripts/measure-test-modes.ps1 asks so a soak repetition that exited zero with
  an empty suite is not counted as a pass.

  Before this file the answer was written three times: once in test-fast.ps1's Read-TestCount,
  once inline in its Invoke-TestRun to find the newest TRX, and once in measure-test-modes.ps1's
  Get-SoakTestCount. Nothing kept the three in step, and a change to how a count is read - a
  namespace, a missing ResultSummary, a different counter - had to land in all three.

  A count of zero is the answer for a TRX that is missing, unreadable as a result summary, or
  genuinely empty. Every caller treats zero the same way: the run proved nothing.
#>

function Get-AhkFlowLatestTrxPath {
    <#
      The newest .trx under a results directory, or $null when there is none.

      Newest by LastWriteTimeUtc rather than by name, because a results directory can hold
      files from an earlier run that this one did not overwrite.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultsDirectory
    )

    $trxFile = Get-ChildItem -LiteralPath $ResultsDirectory -Recurse -Filter '*.trx' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $trxFile) { return $null }

    return $trxFile.FullName
}

function Get-AhkFlowTestCount {
    <#
      The total test count recorded in one TRX file.

      Returns 0 when the file carries no Counters element, and also when it cannot be read or
      parsed at all. A run killed part-way leaves a TRX whose XML never closes, and letting the
      parse error out of here ended a soak at its first bad run instead of counting it. Both
      callers already treat 0 as "this run proved nothing", which is the right answer for a file
      nobody can read.

      A killed run leaves three shapes, and only one of them is a parse error. The emptiness
      check has to come first: Get-Content -Raw answers $null for a zero-byte file, casting
      $null to [xml] succeeds quietly, and the null then throws on the first method call - past
      the catch, and straight out of this function. A zero-byte TRX is the likeliest shape of
      all, because the logger creates the file before it writes anything into it.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath
    )

    try {
        $raw = Get-Content -LiteralPath $TrxPath -Raw
    }
    catch {
        return 0
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 0
    }

    try {
        [xml]$trx = $raw
    }
    catch {
        return 0
    }

    $counters = $trx.GetElementsByTagName('Counters') | Select-Object -First 1
    if (-not $counters) {
        return 0
    }

    return [int]$counters.total
}

function Get-AhkFlowTestCountFromResults {
    <#
      The total test count for a results directory: find its newest TRX, then read the count.

      Returns 0 when no TRX was written at all, which the caller treats the same way as an
      empty one.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultsDirectory
    )

    $trxPath = Get-AhkFlowLatestTrxPath -ResultsDirectory $ResultsDirectory
    if (-not $trxPath) { return 0 }

    return Get-AhkFlowTestCount -TrxPath $trxPath
}

function Get-AhkFlowMedian {
    <#
      The median of a set of numbers: the middle of the sorted values, or the mean of the two
      middle values when the count is even.

      It lives here, beside the other numbers a test run reports, rather than inline in
      scripts/measure-test-modes.ps1, because a median computed inline can only be checked
      through wall-clock timings. tests/MeasureTestModes.Tests.ps1 calls it with fixed values,
      so machine load cannot move the assertion.

      An empty set throws. Returning 0 would print as a very fast run.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [double[]]$Values
    )

    if ($Values.Count -lt 1) {
        throw 'Get-AhkFlowMedian needs at least one value.'
    }

    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)

    if ($sorted.Count % 2 -eq 1) {
        return $sorted[$middle]
    }

    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

function New-AhkFlowTestSummary {
    <#
      One row of the table a test slice prints, plus the guard that refuses an empty one.

      The zero-test throw lives here rather than at each call site because its wording is the
      thing a developer greps for when a filter typo makes a slice silently empty. Two copies
      of that message drift.

      The message names the second cause as well. Get-AhkFlowTestCount answers zero for a TRX
      it cannot read, so a run killed mid-write arrives here looking exactly like a filter that
      matched nothing. Naming the TRX path gives the reader somewhere to look.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [int]$Tests,

        [Parameter(Mandatory = $true)]
        [string]$TrxPath
    )

    if ($Tests -lt 1) {
        throw "$Project discovered zero tests for filter '$Filter'. Either the filter matched nothing, or $TrxPath could not be read."
    }

    [pscustomobject]@{
        Project = $Project
        Filter = $Filter
        Tests = $Tests
        TrxPath = $TrxPath
    }
}
