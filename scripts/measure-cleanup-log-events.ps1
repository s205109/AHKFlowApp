#Requires -Version 7.0
<#
.SYNOPSIS
    Counts the cleanup outcome lines the removal log itself holds, inside the friction window.
.DESCRIPTION
    Friction metric 3 counts the cleanup outcome log lines that reached a session transcript.
    This script counts the lines the log holds, which is the closest thing to the size of the
    real population.

    Both are counts of log lines, never of cleanup runs. One removal writes several lines, so
    neither number is a count of removals. Measured on 2026-08-21: the log held 201 distinct
    in-window outcome log lines, of which 91 are "Watcher started." and 87 are "Watcher done (",
    across 64 named worktrees.

    The two numbers together say what the metric is. On 2026-08-21, 15 of the 18 witnessed rows
    were among those 201; the other 3 predate the log, so the true in-window population is 204
    log lines or more. That makes 18 a floor rather than an upper bound, and its share a ceiling
    rather than a measurement. See docs/development/cleanup-event-identity.md.

    It reuses the measurement script's line shape and outcome patterns rather than copying
    them. Two copies of one rule is how this metric went wrong before.

    Two kinds of number come out of this, and they must not be mixed:

      In-window figures are stable for one log file. The window closed on 2026-08-12, so no new
      line can land inside it, and re-running against the same file prints the same count.

      Whole-log figures are floors. The log grows every time a worktree is removed.

    Neither kind is reproducible across machines. The removal log is machine-local and
    gitignored (`.gitignore:451`, ".claude/worktrees/"), it records only the removals that ran on
    that machine, and it does not reach back to the start of the window. So the committed ledger
    is a dated snapshot of one machine's log, not a figure a second machine can regenerate. Read
    the ledger to audit the published numbers; re-run this script to measure a different log.

    The log stamps are local time and carry no offset. The count is printed at UTC+1, UTC+2 and
    UTC+3 so a reader can see the window edges do not depend on that reading.
.PARAMETER LogPath
    The removal log. Defaults to the copy under the main checkout, which is the only copy: a
    worktree has no .claude/worktrees directory of its own.
.PARAMETER LedgerPath
    Where the in-window rows are written. Defaults to the committed cleanup-log-events.csv.
.PARAMETER AssumedOffsetHours
    The local-time offset used for the committed ledger. Defaults to 2. Only the offsets this
    script computes are accepted, because an offset with no dataset behind it used to select a
    missing hashtable key and export an empty ledger over the committed rows.
#>
[CmdletBinding()]
param(
    [string] $LogPath,
    [string] $LedgerPath,
    [ValidateSet(1, 2, 3)]
    [int] $AssumedOffsetHours = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# The offsets this script computes a dataset for. -AssumedOffsetHours may name one of these and
# nothing else; the ValidateSet on the parameter has to repeat them as literals.
$script:ReportedOffsetHours = @(1, 2, 3)

# Copy the parameters out before dot-sourcing, the same way label-cleanup-events.ps1 does.
$logFile = $LogPath
$ledger = $LedgerPath

. (Join-Path $PSScriptRoot 'measure-process-friction.ps1') -AsModule

function Resolve-RemovalLogPath {
    <#
    .SYNOPSIS
        The removal log under the main checkout.
    .DESCRIPTION
        The log lives at <main>/.claude/worktrees/worktree-removal.log and nowhere else. A path
        built from $PSScriptRoot resolves to nothing in a worktree, and the script would then
        report zero lines instead of failing. The common git directory is the main checkout's
        .git in a worktree as well as in the checkout.
    #>
    param([Parameter(Mandatory)][string] $FromRepo)

    $common = & git -C $FromRepo rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $common) {
        throw "Could not resolve the main checkout from $FromRepo. Pass -LogPath instead."
    }
    $main = Split-Path -Parent ([string]$common).Trim()
    return (Join-Path $main '.claude/worktrees/worktree-removal.log')
}

if (-not $logFile) { $logFile = Resolve-RemovalLogPath -FromRepo $repoRoot }
if (-not $ledger) { $ledger = Join-Path $repoRoot 'docs/development/friction-samples/ledgers/cleanup-log-events.csv' }

if (-not (Test-Path -LiteralPath $logFile)) {
    throw "Removal log not found: $logFile. It lives under the main checkout, not the worktree."
}

$runDate = (Get-Date).ToString('yyyy-MM-dd')
Write-Host "Removal log : $logFile"
Write-Host "Window      : $($script:WindowStart.ToString('u')) to $($script:WindowEnd.ToString('u'))"
Write-Host "Run date    : $runDate"
Write-Host ''

$allLines = @(Get-Content -LiteralPath $logFile)
$oldestAnyLine = ''

$hits = foreach ($raw in $allLines) {
    $line = $raw.TrimEnd()
    $match = [regex]::Match($line, $script:CleanupLogLinePattern)
    if (-not $match.Success) { continue }

    $stampText = $line.Substring(0, 19)
    if (-not $oldestAnyLine) { $oldestAnyLine = $stampText }

    $message = $match.Groups['message'].Value
    foreach ($pattern in $script:CleanupOutcomePatterns) {
        if ($message -notmatch $pattern) { continue }

        $local = [datetime]::ParseExact($stampText, 'yyyy-MM-dd HH:mm:ss', $null)
        # The worktree sits between the stamp and the message, both separated by two spaces.
        $worktree = ($line.Substring(19) -split '\s\s+', 3)[1]
        [pscustomobject]@{
            EventStampLocal = $stampText
            LocalTime       = $local
            Worktree        = $worktree
            Matched         = $pattern
            Line            = $line
            HasPid          = ($message -match 'PID=')
        }
        break
    }
}
$hits = @($hits)

$distinctTotal = @($hits.Line | Select-Object -Unique).Count
$oldestOutcome = if ($hits.Count -gt 0) { (@($hits | Sort-Object LocalTime) | Select-Object -First 1).EventStampLocal } else { '' }

Write-Host 'Whole log - these are floors. The log grows every time a worktree is removed.'
Write-Host "  log lines read        : $($allLines.Count)"
Write-Host "  outcome lines         : $($hits.Count)"
Write-Host "  distinct outcome lines: $distinctTotal"
Write-Host "  all distinct          : $(if ($hits.Count -eq $distinctTotal) { 'yes' } else { 'NO - two identical lines exist' })"
# Two oldest stamps, and they differ. The log opens with a removal request, which is not an
# outcome, so an executor reading one number against the other would chase a phantom.
Write-Host "  oldest line, any kind : $oldestAnyLine"
Write-Host "  oldest outcome line   : $oldestOutcome"
Write-Host ''

Write-Host 'PID= per outcome pattern. Only Watcher started. carries a process id, so the id is'
Write-Host 'not what makes deduplication safe. The ratio is the claim, never the counts.'
foreach ($group in ($hits | Group-Object Matched | Sort-Object Name)) {
    $withPid = @($group.Group | Where-Object { $_.HasPid }).Count
    Write-Host ("  {0,-58} {1,4} lines, {2,4} with PID=" -f $group.Name, $group.Count, $withPid)
}
Write-Host ''

Write-Host 'In-window - these are stable. The window closed on 2026-08-12, so no new line can'
Write-Host 'land inside it and a later run must print the same numbers.'
Write-Host 'The log stamps are local time with no offset recorded, so the count is shown at three.'
$byOffset = @{}
foreach ($offset in $script:ReportedOffsetHours) {
    $inWindow = @($hits | Where-Object {
            $utc = $_.LocalTime.AddHours(-$offset)
            $utc -ge $script:WindowStart -and $utc -lt $script:WindowEnd
        })
    $byOffset[$offset] = $inWindow
    $distinct = @($inWindow.Line | Select-Object -Unique).Count
    Write-Host ("  UTC+{0}: {1,4} in-window lines, {2,4} distinct" -f $offset, $inWindow.Count, $distinct)
}

# ValidateSet already refuses an unknown offset. This second check is what keeps the two from
# drifting: adding an offset to the set without adding it to the loop would otherwise export an
# empty ledger over the committed rows, and report it as a successful run.
if (-not $byOffset.ContainsKey($AssumedOffsetHours)) {
    throw ("No dataset was computed for UTC+$AssumedOffsetHours. This script computes " +
        "$($script:ReportedOffsetHours -join ', ') only. Nothing was written to $ledger.")
}

$chosen = $byOffset[$AssumedOffsetHours]
$rows = foreach ($hit in ($chosen | Sort-Object LocalTime)) {
    [pscustomobject]@{
        EventStampLocal = $hit.EventStampLocal
        # ISO 8601 with the Z marker. Without it this column is the same shape as the local
        # stamp beside it, and a reader cannot tell the two apart.
        EventStampUtc   = $hit.LocalTime.AddHours(-$AssumedOffsetHours).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        Worktree        = $hit.Worktree
        Matched         = $hit.Matched
        Line            = $hit.Line
    }
}
$rows = @($rows)
$rows | Export-Csv -LiteralPath $ledger -NoTypeInformation -Encoding utf8

Write-Host ''
Write-Host "Ledger      : $ledger"
Write-Host "  rows written : $($rows.Count) (at the assumed UTC+$AssumedOffsetHours)"
# Every figure printed below comes from this run. A recited number - the witnessed count, the
# published share - would drift the moment the input changed, and read as though this run had
# measured it.
Write-Host ''
Write-Host 'These are outcome log lines, not cleanup runs. One removal writes several, so this'
Write-Host 'count is larger than the number of removals behind it:'
foreach ($group in ($rows | Group-Object Matched | Sort-Object Count -Descending)) {
    Write-Host ("  {0,-58} {1,4}" -f $group.Name, $group.Count)
}
Write-Host ("  {0,-58} {1,4}" -f 'distinct worktrees named', @($rows.Worktree | Select-Object -Unique).Count)
Write-Host ''
Write-Host 'The witnessed figure, its share, and the decision behind them are recorded in'
Write-Host 'docs/development/cleanup-event-identity.md. This run computed none of those.'
