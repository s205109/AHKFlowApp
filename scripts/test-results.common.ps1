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

function Get-AhkFlowRelativeSpread {
    <#
      How far the slowest and fastest runs sit apart, as a percentage of the median.

      Backlog 150. It answers one question: how much is this median worth? A settled ten-run window
      in that item spread 31.9 percent, so its median carried roughly plus or minus 16 percent, and
      anybody comparing two medians against a 10 percent threshold needs to know that first.

      It does not detect a tree that is uniformly cold, and no figure computed inside one window
      does. The same item records a window taken right after a build whose five runs were 60 percent
      slow and spread only 12.1 percent, which is tighter than the settled window. The settle clock
      in scripts/measure-test-modes.ps1 is what handles a cold tree.

      An empty set throws, for the same reason Get-AhkFlowMedian does: zero would print as a
      perfect measurement.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [double[]]$Values
    )

    if ($Values.Count -lt 1) {
        throw 'Get-AhkFlowRelativeSpread needs at least one value.'
    }

    $median = Get-AhkFlowMedian -Values $Values
    if ($median -le 0) {
        throw 'Get-AhkFlowRelativeSpread needs a median above zero.'
    }

    $measured = $Values | Measure-Object -Minimum -Maximum
    return (($measured.Maximum - $measured.Minimum) / $median) * 100
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

function Get-AhkFlowIntervalUnionMilliseconds {
    <#
      The length of the union of a set of intervals, clipped to a window, in milliseconds.

      Backlog 140. Adding the lengths of intervals is wrong twice over in a suite that runs four
      stacks at once: concurrent work counts several times, and a parent step counts again for
      every child inside it. Merging ranges answers both, because the union of a parent and its
      children is the parent.

      Clipping first is what keeps the answer inside the window, so a residual computed as
      'window minus union' can never go negative.

      Every value must be UTC. Comparing a local time with a UTC time here would shift a whole
      interval by the offset without any error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Interval,
        [Parameter(Mandatory = $true)][datetime] $ClipStart,
        [Parameter(Mandatory = $true)][datetime] $ClipEnd
    )

    if ($ClipEnd -lt $ClipStart) {
        throw "The clip window ends before it starts: $ClipStart to $ClipEnd."
    }

    $clipped = @()
    foreach ($item in $Interval) {
        $start = [datetime]$item.Start
        $end = [datetime]$item.End

        if ($end -lt $start) {
            throw "An interval ends before it starts: $start to $end."
        }

        if ($start -lt $ClipStart) { $start = $ClipStart }
        if ($end -gt $ClipEnd) { $end = $ClipEnd }

        # A zero-length result means the interval fell outside the window, or touched its edge.
        if ($end -gt $start) {
            $clipped += [pscustomobject]@{ Start = $start; End = $end }
        }
    }

    if ($clipped.Count -eq 0) {
        return 0.0
    }

    $ordered = @($clipped | Sort-Object -Property Start)
    $total = 0.0
    $mergeStart = $ordered[0].Start
    $mergeEnd = $ordered[0].End

    for ($i = 1; $i -lt $ordered.Count; $i++) {
        $current = $ordered[$i]

        # -le, not -lt: two intervals that meet exactly are one stretch of busy time.
        if ($current.Start -le $mergeEnd) {
            if ($current.End -gt $mergeEnd) {
                $mergeEnd = $current.End
            }
        }
        else {
            $total += ($mergeEnd - $mergeStart).TotalMilliseconds
            $mergeStart = $current.Start
            $mergeEnd = $current.End
        }
    }

    $total += ($mergeEnd - $mergeStart).TotalMilliseconds
    return [math]::Round($total, 3)
}

function Convert-TrxTimestamp {
    <#
      One TRX timestamp as a UTC [datetime].

      TRX writes local time with an offset, and two machines in two zones write the same instant
      differently. Everything downstream compares timestamps from the TRX with timestamps from the
      fixture timing files, which are UTC, so the conversion happens once, here.
    #>
    param([string] $Timestamp)

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        return $null
    }

    return [datetimeoffset]::Parse($Timestamp, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}

function Get-AhkFlowTrxRunInterval {
    <#
      The run interval a TRX reports, as UTC start and end.

      Backlog 140. This is not the test host's process lifetime. The values come from the logger:
      the interval opens when the logger starts the run and closes when the run completes, so
      process start, assembly loading before that point, and process exit after it all sit outside
      it. The report names it the TRX run interval for exactly that reason.
    #>
    param([Parameter(Mandatory = $true)][string] $TrxPath)

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw
    $times = $trx.GetElementsByTagName('Times') | Select-Object -First 1

    if (-not $times) {
        throw "No Times element in $TrxPath, so the run interval cannot be read."
    }

    $start = Convert-TrxTimestamp -Timestamp $times.start
    $end = Convert-TrxTimestamp -Timestamp $times.finish

    if ($null -eq $start -or $null -eq $end) {
        throw "The Times element in $TrxPath has no start or no finish."
    }

    return [pscustomobject]@{ Start = $start; End = $end }
}

function Convert-TrxDuration {
    param(
        [string]$Duration
    )

    if ([string]::IsNullOrWhiteSpace($Duration)) {
        return 0.0
    }

    return [System.TimeSpan]::Parse($Duration, [System.Globalization.CultureInfo]::InvariantCulture).TotalMilliseconds
}

function Read-TrxResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw
    $unitTests = $trx.GetElementsByTagName('UnitTest')
    $unitTestResults = $trx.GetElementsByTagName('UnitTestResult')
    $testClassesById = @{}

    foreach ($unitTest in $unitTests) {
        $testId = $unitTest.id
        $testMethod = $unitTest.GetElementsByTagName('TestMethod') | Select-Object -First 1
        if ($testId -and $testMethod) {
            $testClassesById[$testId] = $testMethod.className
        }
    }

    $results = @()
    foreach ($result in $unitTestResults) {
        $className = $testClassesById[$result.testId]
        if ([string]::IsNullOrWhiteSpace($className)) {
            $className = '(unknown)'
        }

        $results += [pscustomobject]@{
            Project = $ProjectName
            Class = $className
            Test = $result.testName
            Outcome = $result.outcome
            DurationMilliseconds = [math]::Round((Convert-TrxDuration -Duration $result.duration), 3)
            StartUtc = (Convert-TrxTimestamp -Timestamp $result.startTime)
            EndUtc = (Convert-TrxTimestamp -Timestamp $result.endTime)
        }
    }

    return $results
}
