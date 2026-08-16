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
.PARAMETER ExistingManifest
    A manifest whose labels must survive. Rows whose Key is still in the population keep their
    Id and their Label, and the draw tops the sample up to SampleSize instead of replacing it.
    Without this, re-running after the transcripts grow throws away every hand-written label.
.NOTES
    A seed alone does not reproduce a selection. It indexes into the ordered unflagged list, and
    that list changes whenever a session is written - which happens while the script runs. So the
    script also writes a selection record beside the manifest: the population count, a digest of
    the ordered keys, the drawn positions, and the drawn keys themselves. The digest says whether
    the positions still mean anything; the keys identify the rows either way.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('handoffs', 'next-step-asks')][string] $Metric,
    [Parameter(Mandatory)][string] $OutputPath,
    [int] $Seed = 20260816,
    [int] $SampleSize = 200,
    [string] $ExistingManifest
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

# The digest of the ordered keys. It is what tells a later reader whether the recorded positions
# still point at the same messages, which a seed on its own cannot say.
$keyText = ($ordered | ForEach-Object { $_.Key }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $populationDigest = [System.BitConverter]::ToString(
        $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-', '').ToLowerInvariant()
}
finally { $sha.Dispose() }

# Labels already written are evidence. Keep every one whose message is still in the population,
# and top the sample up rather than drawing a fresh one.
$existingLabels = @{}
$existingIds = @{}
$keptKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
if ($ExistingManifest) {
    if (-not (Test-Path -LiteralPath $ExistingManifest)) {
        throw "ExistingManifest not found: $ExistingManifest"
    }
    foreach ($row in (Import-Csv -LiteralPath $ExistingManifest)) {
        $existingLabels[$row.Key] = $row.Label
        $existingIds[$row.Key] = $row.Id
        if ($row.Stratum -eq 'unflagged') { [void]$keptKeys.Add($row.Key) }
    }
}

$byKeyPosition = @{}
for ($i = 0; $i -lt $ordered.Count; $i++) { $byKeyPosition[$ordered[$i].Key] = $i }

$picked = [System.Collections.Generic.SortedSet[int]]::new()
foreach ($key in $keptKeys) {
    if ($byKeyPosition.ContainsKey($key)) { [void]$picked.Add($byKeyPosition[$key]) }
}
$carriedOver = $picked.Count

$random = [System.Random]::new($Seed)
$take = [Math]::Min($SampleSize, $ordered.Count)
$attempts = 0
while ($picked.Count -lt $take) {
    [void]$picked.Add($random.Next(0, $ordered.Count))
    $attempts++
    if ($attempts -gt ($ordered.Count * 20)) { throw 'the draw could not reach the sample size' }
}

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

# A carried-over row keeps its Id, so a new row cannot simply be numbered by position: the
# earlier manifest already used those numbers, and two rows sharing an Id break every reference
# to a label. New rows are numbered above the highest one already in use.
function Get-NextId {
    param([Parameter(Mandatory)][string] $Prefix)
    $script:idCounters[$Prefix]++
    while ($script:usedIds.Contains("$Prefix$($script:idCounters[$Prefix])")) { $script:idCounters[$Prefix]++ }
    $id = "$Prefix$($script:idCounters[$Prefix])"
    [void]$script:usedIds.Add($id)
    return $id
}

$script:usedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:idCounters = @{ 'F' = 0; 'U' = 0 }
foreach ($id in $existingIds.Values) { [void]$script:usedIds.Add($id) }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($message in $flagged) {
    $rows.Add([pscustomobject]@{
            Id        = if ($existingIds.ContainsKey($message.Key)) { $existingIds[$message.Key] } else { (Get-NextId -Prefix 'F') }
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'flagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = if ($existingLabels.ContainsKey($message.Key)) { $existingLabels[$message.Key] } else { '' }
            Text      = $message.Text
        })
}
$selectedPositions = @($picked)
$selectedKeys = New-Object System.Collections.Generic.List[string]
foreach ($position in $selectedPositions) {
    $message = $ordered[$position]
    $selectedKeys.Add($message.Key)
    $rows.Add([pscustomobject]@{
            Id        = if ($existingIds.ContainsKey($message.Key)) { $existingIds[$message.Key] } else { (Get-NextId -Prefix 'U') }
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'unflagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = if ($existingLabels.ContainsKey($message.Key)) { $existingLabels[$message.Key] } else { '' }
            Text      = $message.Text
        })
}

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8

# The selection record. A seed indexes into a list that changes while the script runs, so the
# list itself has to be described: how long it was, what it hashed to, and which positions and
# keys came out. With it a reader can say whether a redraw is the same draw.
$selectionPath = [System.IO.Path]::ChangeExtension($OutputPath, '.selection.json')
[pscustomobject]@{
    metric            = $Metric
    seed              = $Seed
    sampleSize        = $SampleSize
    windowStart       = $script:WindowStart.ToString('o')
    windowEnd         = $script:WindowEnd.ToString('o')
    transcriptFiles   = $files.Count
    recordsInWindow   = $selected.Count
    populationCount   = $population.Count
    flaggedCount      = $flagged.Count
    unflaggedCount    = $ordered.Count
    populationDigest  = $populationDigest
    carriedOverLabels = $carriedOver
    selectedPositions = $selectedPositions
    selectedKeys      = $selectedKeys.ToArray()
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $selectionPath -Encoding utf8

Write-Host "metric      : $Metric"
Write-Host "seed        : $Seed"
Write-Host "population  : $($population.Count) logical messages"
Write-Host "flagged     : $($flagged.Count)"
Write-Host "unflagged   : $($ordered.Count), of which $take sampled ($carriedOver carried over already labelled)"
Write-Host "digest      : $populationDigest"
Write-Host "manifest    : $OutputPath"
Write-Host "selection   : $selectionPath"
Write-Host ''
Write-Host 'Every row carries its full text. Fill in each empty Label, then commit the manifest'
Write-Host 'and the selection record together: the labels are the evidence for the published range.'
