#Requires -Version 7.0
<#
.SYNOPSIS
    Writes the stratified sample manifest that measures the recall of two friction match sets.
.DESCRIPTION
    Metrics 1 and 4 match on wording. A closed match set gives a repeatable number, but its
    recall is unknown, and a figure may only be called an upper bound when nothing real escapes
    the set.

    The sample is stratified. In-window there are tens of thousands of assistant messages and
    roughly a thousand human turns, while real handoffs number in the tens. A random draw over
    the whole population would contain almost no real cases: it would measure precision and say
    nothing at all about recall. So each metric is split in two - every flagged message, which
    gives exact precision, and a seeded random sample of the unflagged remainder, which bounds
    the miss rate.

    The manifest carries the FULL text of every sampled message, not an excerpt. A 160-character
    excerpt cannot be labelled honestly: the sentence that makes a message a handoff is often
    further in, and a reviewer cannot check a label against text that was thrown away.

    It reads the same logical messages the measurement reads, through
    scripts/measure-process-friction.ps1, so the sample cannot drift from the population.
.PARAMETER Metric
    'handoffs' or 'next-step-asks'.
.PARAMETER OutputPath
    Where to write the manifest CSV.
.PARAMETER Seed
    The random seed. Recorded in every row.
.PARAMETER SampleSize
    How many unflagged messages to draw. 200 bounds a zero-miss result at roughly 1.5 percent.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('handoffs', 'next-step-asks')][string] $Metric,
    [Parameter(Mandatory)][string] $OutputPath,
    [int] $Seed = 20260816,
    [int] $SampleSize = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'measure-process-friction.ps1') -AsModule

$files = @(Get-TranscriptFile -ProjectRoot (Join-Path $HOME '.claude/projects'))
$all = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    foreach ($record in (Read-TranscriptRecord -Path $file)) { $all.Add($record) }
}

$selected = @(Select-FrictionRecord -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd)
$messages = @(ConvertTo-LogicalMessage -Records $selected)
$patterns = $script:MatchSets[$Metric]

# The same side of the conversation the metric reads, so the unflagged remainder is exactly
# what the metric could have missed.
$population = @($messages | Where-Object {
        if ($Metric -eq 'next-step-asks') { $_.IsHumanTurn } else { $_.Type -eq 'assistant' }
    } | Where-Object { $_.Text })

$flagged = New-Object System.Collections.Generic.List[object]
$unflagged = New-Object System.Collections.Generic.List[object]

foreach ($message in $population) {
    $hit = $false
    foreach ($pattern in $patterns) {
        if ($message.Text -match [regex]::Escape($pattern)) { $hit = $true; break }
    }
    if ($hit) { $flagged.Add($message) } else { $unflagged.Add($message) }
}

# Sort before sampling. Enumeration order over hundreds of files is not guaranteed stable, and
# a seed only reproduces a sample when the list it indexes into is in a fixed order.
$ordered = @($unflagged | Sort-Object -Property Key)
$random = [System.Random]::new($Seed)
$picked = [System.Collections.Generic.HashSet[int]]::new()
$take = [Math]::Min($SampleSize, $ordered.Count)
while ($picked.Count -lt $take) { [void]$picked.Add($random.Next(0, $ordered.Count)) }

# A wide screen, run over the WHOLE text of every sampled message. It is deliberately far
# wider than the metric's own match set: its job is to find every message that could possibly
# be a case, so the ones it does not select carry evidence rather than an opinion. A label of
# 'not a case' on an unscreened row means no word associated with the concept appears anywhere
# in the message, which a reviewer can check against the Text column.
$screens = @{
    'handoffs'       = @(
        'yourself', 'manually', 'by hand', 'cannot', "can't", 'unable', 'blocked', 'refuse',
        'guard', 'permission', 'terminal', 'copy', 'paste', 'over to you', 'you run',
        'please run', 'need you', 'needs you', 'handover', 'hand over', 'login', 'auth'
    )
    'next-step-asks' = @(
        'next', 'suggest', 'proceed', 'what should', 'what do', 'which one', 'priority',
        'order', 'pick up', 'shall we', 'do we', 'should i', 'should we', 'options'
    )
}
$screen = $screens[$Metric]

function Get-ScreenHit {
    param([string] $Text)
    $hits = foreach ($word in $screen) {
        if ($Text -match [regex]::Escape($word)) { $word }
    }
    return (@($hits) -join '; ')
}

$rows = New-Object System.Collections.Generic.List[object]
$index = 0
foreach ($message in $flagged) {
    $index++
    $rows.Add([pscustomobject]@{
            Id        = "F$index"
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'flagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = ''
            Text      = $message.Text
        })
}
$index = 0
foreach ($position in @($picked | Sort-Object)) {
    $index++
    $message = $ordered[$position]
    $rows.Add([pscustomobject]@{
            Id        = "U$index"
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'unflagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = ''
            Text      = $message.Text
        })
}

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8

Write-Host "metric      : $Metric"
Write-Host "seed        : $Seed"
Write-Host "population  : $($population.Count) logical messages"
Write-Host "flagged     : $($flagged.Count)"
Write-Host "unflagged   : $($ordered.Count), of which $take sampled"
Write-Host "manifest    : $OutputPath"
Write-Host ''
Write-Host 'Every row carries its full text and an empty Label column. Fill each Label in, then'
Write-Host 'commit the manifest: the labels are the evidence for the published range.'
