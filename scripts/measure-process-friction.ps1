#Requires -Version 7.0
<#
.SYNOPSIS
    Measures the five friction counts from this project's session transcripts.
.DESCRIPTION
    Three earlier attempts produced numbers that were withdrawn in review. Each fixed the
    previous defect and kept or introduced another. So every rule below names the field it
    reads, rather than describing an intention: two scripts that both follow this list must
    produce the same number.

    What each rule exists to stop:

    - Window. Select on the record's own 'timestamp' field, never on file modification time.
      A file touched today can hold records from weeks ago.
    - Human turn. type is 'user' AND (origin.kind is 'human' OR promptSource is typed,
      suggestion_accepted, or queued). The two fields are alternatives. Requiring both drops
      every accepted suggestion, every queued prompt, and every slash command. Tool results
      and injected skill content are also stored with type 'user', which is what inflated the
      first two attempts. The shape of message.content separates nothing, so it is not read.
    - Sidechain. Subagent records are excluded, and the number excluded is printed even when
      it is zero. A missing line reads as "the rule never ran", which is a different fact.
    - Deduplication. Assistant records carry message.id; user records do not carry it at all.
      So assistant metrics deduplicate on message.id and user metrics on the record's own
      top-level uuid. Using message.id for a user metric deduplicates nothing, because every
      comparison is against a null.
    - File list. Windows paths are case-insensitive, so one glob can match the same directory
      twice under two spellings. Every candidate is resolved, lowercased, and deduplicated
      before a single record is read.
    - Units. Metric 2 counts command lines, because one message can hand over several.

    The match set for each metric is a literal list in this file and is printed with the
    number, so any figure can be challenged rather than believed.
.PARAMETER AsModule
    Define the functions and return without measuring anything. The test suite uses this.
.PARAMETER ProjectRoot
    Where the session transcripts live. Defaults to ~/.claude/projects.
.PARAMETER ClonePath
    The clone used to resolve a CI run's changed files. Defaults to this repository. It is not
    called RepoRoot on purpose: the suite dot-sources this file, PowerShell variable names are
    case-insensitive, and a parameter called RepoRoot overwrites the caller's own $repoRoot
    with an empty string.
.PARAMETER SkipCi
    Skip metric 5, which needs the gh CLI and the network.
#>
[CmdletBinding()]
param(
    [switch] $AsModule,
    [string] $ProjectRoot,
    [string] $ClonePath,
    [switch] $SkipCi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The window is fixed: four weeks ending at the moment wave 1 merged. A window running past
# that merge would mix old-process friction with fixed-process friction.
$script:WindowStart = [datetime]::Parse('2026-07-15T14:14:32Z').ToUniversalTime()
$script:WindowEnd = [datetime]::Parse('2026-08-12T14:14:32Z').ToUniversalTime()

# Each match set is literal and is printed with its number.
$script:MatchSets = @{
    'handoffs'                 = @(
        'i cannot reach', 'i am not able to reach', 'run this in your terminal',
        'run it yourself', 'you will need to run', 'please run', 'you need to run',
        'run the following yourself', 'i cannot run', 'blocked by the guard',
        'the guard refuses', 'from the main checkout yourself'
    )
    'next-step-asks'           = @(
        'next step', 'what next', "what's next", 'what should i do next',
        'what do we do next', 'how do we proceed', 'what now'
    )
    'cleanup-events'           = @(
        'worktree removed', 'watcher done', 'cleanup popup', 'remove-worktree',
        'worktree remove failed', 'is locked', 'is dirty', 'cleanup blocked'
    )
    'directory-bound-commands' = @(
        '^\s*cd\s+', '^\s*set-location\s+', '^\s*push-location\s+', '^\s*pushd\s+',
        'git\s+-c\s+\S', '-workingdirectory\s+\S', '^\s*chdir\s+'
    )
}

function Get-RecordProperty {
    <#
    .SYNOPSIS
        Reads a property that may be absent, without throwing under StrictMode.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()] $Record,
        [Parameter(Mandatory)][string] $Name
    )
    if ($null -eq $Record) { return $null }
    if ($Record -isnot [psobject]) { return $null }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-HumanTurn {
    <#
    .SYNOPSIS
        True when a record is a turn a person actually typed, accepted, or queued.
    #>
    param([Parameter(Mandatory)][AllowNull()] $Record)

    if ((Get-RecordProperty -Record $Record -Name 'type') -ne 'user') { return $false }

    $origin = Get-RecordProperty -Record $Record -Name 'origin'
    if ((Get-RecordProperty -Record $origin -Name 'kind') -eq 'human') { return $true }

    $promptSource = Get-RecordProperty -Record $Record -Name 'promptSource'
    return ($promptSource -in @('typed', 'suggestion_accepted', 'queued'))
}

function Select-FrictionRecord {
    <#
    .SYNOPSIS
        Keeps the in-window records that are not subagent traffic.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Records,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End
    )

    $kept = foreach ($record in $Records) {
        if ((Get-RecordProperty -Record $record -Name 'isSidechain') -eq $true) { continue }
        $stamp = Get-RecordProperty -Record $record -Name 'timestamp'
        if (-not $stamp) { continue }
        $when = ([datetime]::Parse($stamp)).ToUniversalTime()
        if ($when -lt $Start -or $when -ge $End) { continue }
        $record
    }
    return @($kept)
}

function Get-SidechainCount {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array] $Records)
    return @($Records | Where-Object { (Get-RecordProperty -Record $_ -Name 'isSidechain') -eq $true }).Count
}

function Get-RecordText {
    <#
    .SYNOPSIS
        The text a record carries, flattened to one string.
    .DESCRIPTION
        message.content is a string on a typed prompt and an array of blocks on an assistant
        record. A tool result carries its text in toolUseResult instead. All three are read,
        because a metric matches on words rather than on shape.
    #>
    param([Parameter(Mandatory)][AllowNull()] $Record)

    $parts = New-Object System.Collections.Generic.List[string]

    $message = Get-RecordProperty -Record $Record -Name 'message'
    $content = Get-RecordProperty -Record $message -Name 'content'
    if ($content -is [string]) {
        $parts.Add($content)
    }
    elseif ($content) {
        foreach ($block in @($content)) {
            if ($block -is [string]) { $parts.Add($block); continue }
            $text = Get-RecordProperty -Record $block -Name 'text'
            if ($text) { $parts.Add([string]$text) }
        }
    }

    $toolResult = Get-RecordProperty -Record $Record -Name 'toolUseResult'
    if ($toolResult -is [string]) { $parts.Add($toolResult) }
    elseif ($toolResult) { $parts.Add(($toolResult | Out-String)) }

    return ($parts -join "`n")
}

function Get-DedupKey {
    <#
    .SYNOPSIS
        The identity of a record for one metric.
    .DESCRIPTION
        message.id exists only on assistant records. A user record carries none, so a user
        metric deduplicates on the record's own uuid instead. This was verified against a live
        transcript, not assumed.
    #>
    param([Parameter(Mandatory)][AllowNull()] $Record)

    $message = Get-RecordProperty -Record $Record -Name 'message'
    $id = Get-RecordProperty -Record $message -Name 'id'
    if ($id) { return "msg:$id" }

    $uuid = Get-RecordProperty -Record $Record -Name 'uuid'
    if ($uuid) { return "uuid:$uuid" }

    # No identity at all: fall back to the text, so two identical records do not both count.
    return "text:$(Get-RecordText -Record $Record)"
}

function Get-SessionName {
    param([Parameter(Mandatory)][AllowNull()] $Record)
    $file = Get-RecordProperty -Record $Record -Name 'sourceFile'
    if ($file) { return [string]$file }
    $session = Get-RecordProperty -Record $Record -Name 'sessionId'
    if ($session) { return [string]$session }
    return 'unknown'
}

function Get-FrictionCount {
    <#
    .SYNOPSIS
        Counts one metric over already-selected records.
    .DESCRIPTION
        Returns the item count, the session count, the match set used, and the number of
        sidechain records the input still held. Metric 'directory-bound-commands' counts
        command LINES; every other metric counts records.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Records,
        [Parameter(Mandatory)][ValidateSet('handoffs', 'directory-bound-commands', 'cleanup-events', 'next-step-asks')][string] $Metric
    )

    $patterns = $script:MatchSets[$Metric]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sessions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $items = 0

    foreach ($record in $Records) {
        # Metric 4 reads human turns; the other three read what the agent said or what a tool
        # reported. Reading the wrong side is how attempt 2 counted injected content.
        $type = Get-RecordProperty -Record $record -Name 'type'
        if ($Metric -eq 'next-step-asks') {
            if (-not (Test-HumanTurn -Record $record)) { continue }
        }
        elseif ($Metric -eq 'cleanup-events') {
            if ($type -ne 'user') { continue }
        }
        else {
            if ($type -ne 'assistant') { continue }
        }

        $key = Get-DedupKey -Record $record
        if (-not $seen.Add($key)) { continue }

        $text = Get-RecordText -Record $record
        if (-not $text) { continue }

        if ($Metric -eq 'directory-bound-commands') {
            $lines = 0
            foreach ($line in ($text -split "`n")) {
                foreach ($pattern in $patterns) {
                    if ($line -match $pattern) { $lines++; break }
                }
            }
            if ($lines -gt 0) {
                $items += $lines
                [void]$sessions.Add((Get-SessionName -Record $record))
            }
            continue
        }

        foreach ($pattern in $patterns) {
            if ($text -match [regex]::Escape($pattern)) {
                $items++
                [void]$sessions.Add((Get-SessionName -Record $record))
                break
            }
        }
    }

    return @{
        Items             = $items
        Sessions          = $sessions.Count
        MatchSet          = $patterns
        SidechainExcluded = (Get-SidechainCount -Records $Records)
    }
}

function Get-ChangedFileFromFirstParent {
    <#
    .SYNOPSIS
        The files a commit changed against its first parent, or null when it is not local.
    .DESCRIPTION
        The run's own base is what matters. Comparing against today's main reclassifies a run
        every time main moves, which is why the 142.7-minute figure was never reproducible.
        gh exposes no base for a push run, so the local first-parent diff is the resolver.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Sha
    )

    & git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $files = & git -C $RepoRoot diff --name-only "$Sha^1" $Sha 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return , @($files | Where-Object { $_ })
}

function Test-DotnetPath {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)
    return ($Path -match '\.(cs|csproj|sln|razor|props|targets)$' -or $Path -match '^(src|tests)/')
}

function Get-CiClassification {
    <#
    .SYNOPSIS
        Splits CI runs into .NET and non-.NET, using each run's own base.
    .PARAMETER Resolver
        Takes a head_sha, returns the changed paths, or null when the commit is not local.
        Injecting it is what lets the suite run without git or the network.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Runs,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End,
        [Parameter(Mandatory)][scriptblock] $Resolver
    )

    $nonDotnetRuns = 0
    $nonDotnetMs = 0
    $unresolved = 0
    $outOfWindow = 0
    $resolvedBases = New-Object System.Collections.Generic.List[string]

    foreach ($run in $Runs) {
        $created = ([datetime]::Parse((Get-RecordProperty -Record $run -Name 'created_at'))).ToUniversalTime()
        if ($created -lt $Start -or $created -ge $End) { $outOfWindow++; continue }

        $sha = [string](Get-RecordProperty -Record $run -Name 'head_sha')
        $files = & $Resolver $sha
        if ($null -eq $files) { $unresolved++; continue }

        $files = @($files)
        if ($files.Count -eq 0) { $unresolved++; continue }

        $touchesDotnet = $false
        foreach ($file in $files) {
            if (Test-DotnetPath -Path $file) { $touchesDotnet = $true; break }
        }
        if ($touchesDotnet) { continue }

        $nonDotnetRuns++
        $ms = Get-RecordProperty -Record $run -Name 'run_duration_ms'
        if ($ms) { $nonDotnetMs += [int64]$ms }
        $resolvedBases.Add("$sha^1")
    }

    return @{
        NonDotnetRuns    = $nonDotnetRuns
        NonDotnetMinutes = [math]::Round($nonDotnetMs / 60000, 1)
        Unresolved       = $unresolved
        OutOfWindow      = $outOfWindow
        ResolvedBase     = $resolvedBases
    }
}

function Resolve-TranscriptFile {
    <#
    .SYNOPSIS
        Deduplicates transcript paths by resolved, lowercased full path.
    .DESCRIPTION
        Windows paths are case-insensitive, so a glob for 'C--Dev-...' also matches a
        lowercase 'c--dev-...' directory. Reading a file twice doubles every count it feeds,
        which is the same double-count defect that withdrew the third attempt, arriving by a
        different route. So deduplicate before reading a single record.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Candidates)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $full = (Resolve-Path -LiteralPath $candidate).Path
        if ($seen.Add($full.ToLowerInvariant())) { $kept.Add($full) }
    }
    # The comma keeps a one-element result an array. Without it PowerShell unrolls the return
    # value to a bare string, and the caller's .Count throws under StrictMode.
    return , @($kept)
}

function Read-TranscriptRecord {
    <#
    .SYNOPSIS
        Reads one transcript file into records, stamping each with its file name.
    #>
    param([Parameter(Mandatory)][string] $Path)

    $name = Split-Path -Leaf $Path
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if (-not $line.Trim()) { continue }
        try { $record = $line | ConvertFrom-Json -Depth 40 }
        catch { continue }
        Add-Member -InputObject $record -NotePropertyName 'sourceFile' -NotePropertyValue $name -Force
        $records.Add($record)
    }
    return $records
}

if ($AsModule) { return }

# --- The measurement ---

if (-not $ProjectRoot) { $ProjectRoot = Join-Path $HOME '.claude/projects' }
if (-not $ClonePath) { $ClonePath = Split-Path -Parent $PSScriptRoot }

Write-Host ''
Write-Host 'Friction measurement'
Write-Host "  window : $($script:WindowStart.ToString('u')) to $($script:WindowEnd.ToString('u'))"
Write-Host "  source : $ProjectRoot"

$directories = @(Get-ChildItem -LiteralPath $ProjectRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'AHKFlow' })

$candidates = New-Object System.Collections.Generic.List[string]
foreach ($directory in $directories) {
    foreach ($file in (Get-ChildItem -LiteralPath $directory.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        $candidates.Add($file.FullName)
    }
}

$files = Resolve-TranscriptFile -Candidates $candidates
Write-Host "  files  : $($files.Count) after deduplication, from $($directories.Count) project directories"

# Per-directory split, so the main checkout and the worktrees are visible separately.
$mainFiles = @($files | Where-Object { (Split-Path -Leaf (Split-Path -Parent $_)) -notmatch 'worktrees' })
Write-Host "           $($mainFiles.Count) in main project directories, $($files.Count - $mainFiles.Count) in worktree directories"

$all = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    foreach ($record in (Read-TranscriptRecord -Path $file)) { $all.Add($record) }
}
Write-Host "  records: $($all.Count) read"

$selected = Select-FrictionRecord -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd
$sidechain = Get-SidechainCount -Records $all.ToArray()
Write-Host "  in window: $($selected.Count) records"
Write-Host "  sidechain records excluded: $sidechain"
Write-Host ''

foreach ($metric in @('handoffs', 'directory-bound-commands', 'cleanup-events', 'next-step-asks')) {
    $count = Get-FrictionCount -Records $selected -Metric $metric
    $unit = if ($metric -eq 'directory-bound-commands') { 'command lines' } else { 'records' }
    Write-Host "$metric : $($count.Items) $unit across $($count.Sessions) session(s)"
    Write-Host "  match set: $($count.MatchSet -join ' | ')"
    Write-Host ''
}

if ($SkipCi) {
    Write-Host 'ci-minutes : skipped by -SkipCi'
    return
}

# The runs come from the paginated API with a 'created' filter, never from
# 'gh run list --limit N'. Measured on 2026-08-16: --limit 400 reached back only to
# 2026-08-07, which is three weeks short of this window, and it says so nowhere. A truncated
# list produces a smaller number that looks like a measurement.
$runLines = & gh api -X GET 'repos/s205109/AHKFlowApp/actions/runs' `
    -f 'created=2026-07-15..2026-08-12' -f 'per_page=100' --paginate `
    --jq '.workflow_runs[] | {id: .id, head_sha: .head_sha, created_at: .created_at} | tostring' 2>$null

if ($LASTEXITCODE -ne 0 -or -not $runLines) {
    Write-Host 'ci-minutes : skipped - gh returned nothing, so no run could be classified'
    return
}

$runs = @($runLines | Where-Object { $_ } | ForEach-Object {
        $parsed = $_ | ConvertFrom-Json
        [pscustomobject]@{
            id              = $parsed.id
            head_sha        = $parsed.head_sha
            created_at      = $parsed.created_at
            run_duration_ms = 0
        }
    })
Write-Host "  ci runs returned by the API for this window: $($runs.Count)"

# Duration comes from the timing endpoint. 'billable' reads 0 for this repository.
# One API call per run, so only in-window runs are asked: an out-of-window run is dropped by
# the classification anyway, and its duration is never read.
foreach ($run in $runs) {
    $created = ([datetime]::Parse($run.created_at)).ToUniversalTime()
    if ($created -lt $script:WindowStart -or $created -ge $script:WindowEnd) { continue }
    $timing = & gh api "repos/s205109/AHKFlowApp/actions/runs/$($run.id)/timing" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $timing) { continue }
    $parsed = $timing | ConvertFrom-Json
    $duration = Get-RecordProperty -Record $parsed -Name 'run_duration_ms'
    if ($duration) { $run.run_duration_ms = [int64]$duration }
}

$resolver = { param([string] $Sha) Get-ChangedFileFromFirstParent -RepoRoot $ClonePath -Sha $Sha }
$ci = Get-CiClassification -Runs $runs -Start $script:WindowStart -End $script:WindowEnd -Resolver $resolver

Write-Host "ci-minutes on non-.NET changes : $($ci.NonDotnetMinutes) minutes across $($ci.NonDotnetRuns) run(s)"
Write-Host "  runs outside the window : $($ci.OutOfWindow)"
Write-Host "  runs whose head_sha is not in this clone, so unresolved : $($ci.Unresolved)"
Write-Host ''
