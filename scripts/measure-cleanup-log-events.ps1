#Requires -Version 7.0
<#
.SYNOPSIS
    Counts the cleanup outcome lines the removal log itself holds, inside the friction window.
.DESCRIPTION
    Friction metric 3 counts the cleanup outcome lines that reached a session transcript. This
    script counts the lines the log holds, which is the closest thing to the size of the real
    population. The two numbers together say what the metric is: on 2026-08-21 the log held 201
    distinct in-window outcome lines, and 15 of the 18 witnessed rows are among them. The other
    3 predate the log, so the true in-window population is 204 or more. That makes 18 a floor
    rather than an upper bound, and its share a ceiling rather than a measurement. See
    docs/development/cleanup-event-identity.md.

    It reuses the measurement script's line shape and outcome patterns rather than copying
    them. Two copies of one rule is how this metric went wrong before.

    Two kinds of number come out of this, and they must not be mixed:

      In-window figures are stable. The window closed on 2026-08-12, so no new line can land
      inside it and a later run must print the same 201.

      Whole-log figures are floors. The log grows every time a worktree is removed.

    The log stamps are local time and carry no offset. The count is printed at UTC+1, UTC+2 and
    UTC+3 so a reader can see the window edges do not depend on that reading.
.PARAMETER LogPath
    The removal log. Defaults to the copy under the main checkout, which is the only copy: a
    worktree has no .claude/worktrees directory of its own.
.PARAMETER LedgerPath
    Where the in-window rows are written. Defaults to the committed cleanup-log-events.csv.
.PARAMETER AssumedOffsetHours
    The local-time offset used for the committed ledger. Defaults to 2.
#>
[CmdletBinding()]
param(
    [string] $LogPath,
    [string] $LedgerPath,
    [int] $AssumedOffsetHours = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

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
foreach ($offset in 1, 2, 3) {
    $inWindow = @($hits | Where-Object {
            $utc = $_.LocalTime.AddHours(-$offset)
            $utc -ge $script:WindowStart -and $utc -lt $script:WindowEnd
        })
    $byOffset[$offset] = $inWindow
    $distinct = @($inWindow.Line | Select-Object -Unique).Count
    Write-Host ("  UTC+{0}: {1,4} in-window lines, {2,4} distinct" -f $offset, $inWindow.Count, $distinct)
}

$chosen = $byOffset[$AssumedOffsetHours]
$rows = foreach ($hit in ($chosen | Sort-Object LocalTime)) {
    [pscustomobject]@{
        EventStampLocal = $hit.EventStampLocal
        EventStampUtc   = $hit.LocalTime.AddHours(-$AssumedOffsetHours).ToString('yyyy-MM-dd HH:mm:ss')
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
Write-Host ''
Write-Host "From the frozen labelling, not from this run: the transcripts witnessed 18 in-window"
Write-Host "lines, and 15 of those are among these $($rows.Count). The other 3 predate the log, so they"
Write-Host 'sit inside the window and outside this ledger. The published cleanup figure is a floor,'
Write-Host 'not an upper bound, and the witnessed share is a ceiling for the same reason.'
Write-Host 'See docs/development/cleanup-event-identity.md.'
