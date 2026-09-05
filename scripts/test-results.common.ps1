#Requires -Version 5.1
<#
.SYNOPSIS
  Reading test counts back out of a TRX file, shared by every script that runs .NET tests.
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

      Returns 0 when the file carries no Counters element, which is what an aborted or
      malformed run leaves behind.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrxPath
    )

    [xml]$trx = Get-Content -LiteralPath $TrxPath -Raw
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

function New-AhkFlowTestSummary {
    <#
      One row of the table a test slice prints, plus the guard that refuses an empty one.

      The zero-test throw lives here rather than at each call site because its wording is the
      thing a developer greps for when a filter typo makes a slice silently empty. Two copies
      of that message drift.
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
        throw "$Project discovered zero tests for filter '$Filter'."
    }

    [pscustomobject]@{
        Project = $Project
        Filter = $Filter
        Tests = $Tests
        TrxPath = $TrxPath
    }
}
