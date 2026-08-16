#Requires -Version 7.0
<#
.SYNOPSIS
    Draws the stratified sample that measures the recall of two friction match sets.
.DESCRIPTION
    Metrics 1 and 4 match on wording. A closed match set gives a deterministic number, but its
    recall is unknown, and a figure may only be called an upper bound when nothing real escapes
    the set.

    The sample is stratified, not random over everything. In-window there are roughly 22,000
    assistant records and roughly 900 human turns, while real handoffs number in the tens. A
    random 50 drawn from the whole population would contain approximately zero handoffs: it
    would measure precision and say nothing at all about recall.

    So each metric is split in two:

      1. Every flagged record, all of it, which gives exact precision rather than an estimate.
      2. A random sample of the unflagged remainder, drawn with a fixed seed, which bounds the
         miss rate.

    The seed is a parameter and is printed with the output, so the same sample can be drawn
    again and the labels re-checked.
.PARAMETER Metric
    'handoffs' or 'next-step-asks'.
.PARAMETER Seed
    The random seed. Recorded in the output.
.PARAMETER SampleSize
    How many unflagged records to draw. 200 bounds a zero-miss result at roughly 1.5 percent.
.PARAMETER ExcerptLength
    How much of each record's text to print.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('handoffs', 'next-step-asks')][string] $Metric,
    [int] $Seed = 20260816,
    [int] $SampleSize = 200,
    [int] $ExcerptLength = 160
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'measure-process-friction.ps1') -AsModule

$projectRoot = Join-Path $HOME '.claude/projects'
$directories = @(Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'AHKFlow' })

$candidates = New-Object System.Collections.Generic.List[string]
foreach ($directory in $directories) {
    foreach ($file in (Get-ChildItem -LiteralPath $directory.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        $candidates.Add($file.FullName)
    }
}

$files = Resolve-TranscriptFile -Candidates $candidates
$all = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    foreach ($record in (Read-TranscriptRecord -Path $file)) { $all.Add($record) }
}

$selected = Select-FrictionRecord -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd
$patterns = $script:MatchSets[$Metric]

# The same side of the population the metric reads, and the same deduplication, so the
# unflagged remainder is exactly what the metric could have missed.
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$flagged = New-Object System.Collections.Generic.List[object]
$unflagged = New-Object System.Collections.Generic.List[object]

foreach ($record in $selected) {
    if ($Metric -eq 'next-step-asks') {
        if (-not (Test-HumanTurn -Record $record)) { continue }
    }
    else {
        if ((Get-RecordProperty -Record $record -Name 'type') -ne 'assistant') { continue }
    }

    if (-not $seen.Add((Get-DedupKey -Record $record))) { continue }

    $text = Get-RecordText -Record $record
    if (-not $text) { continue }

    $hit = $false
    foreach ($pattern in $patterns) {
        if ($text -match [regex]::Escape($pattern)) { $hit = $true; break }
    }

    $entry = [pscustomobject]@{
        Key     = Get-DedupKey -Record $record
        Session = Get-SessionName -Record $record
        Excerpt = (($text -replace '\s+', ' ').Trim())
    }
    if ($entry.Excerpt.Length -gt $ExcerptLength) {
        $entry.Excerpt = $entry.Excerpt.Substring(0, $ExcerptLength)
    }

    if ($hit) { $flagged.Add($entry) } else { $unflagged.Add($entry) }
}

# Sort before sampling. Enumeration order over many files is not guaranteed stable, and a
# seed only reproduces a sample when the list it indexes into is in a fixed order.
$ordered = @($unflagged | Sort-Object -Property Key)
$random = [System.Random]::new($Seed)
$picked = [System.Collections.Generic.HashSet[int]]::new()
$take = [Math]::Min($SampleSize, $ordered.Count)
while ($picked.Count -lt $take) { [void]$picked.Add($random.Next(0, $ordered.Count)) }

Write-Host "metric        : $Metric"
Write-Host "seed          : $Seed"
Write-Host "flagged       : $($flagged.Count)"
Write-Host "unflagged     : $($ordered.Count)"
Write-Host "sample drawn  : $take"
Write-Host ''
Write-Host '--- FLAGGED (label each: real / not real) ---'
$i = 0
foreach ($entry in $flagged) {
    $i++
    Write-Host "F$i | $($entry.Session) | $($entry.Excerpt)"
}
Write-Host ''
Write-Host '--- UNFLAGGED SAMPLE (label each: missed / not a case) ---'
$i = 0
foreach ($index in @($picked | Sort-Object)) {
    $i++
    Write-Host "U$i | $($ordered[$index].Excerpt)"
}
