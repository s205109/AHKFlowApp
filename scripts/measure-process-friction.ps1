#Requires -Version 7.0
<#
.SYNOPSIS
    Measures the five friction counts from this project's session transcripts.
.DESCRIPTION
    Four earlier attempts produced numbers that were withdrawn in review. Each fixed the
    previous defect and kept or introduced another. So every rule below names the field it
    reads, rather than describing an intention: two scripts that both follow this list must
    produce the same number.

    Everything reads one shared shape. Records are normalized once into logical messages, and
    every metric and the sampler consume that. The alternative - each metric walking raw
    records with its own filter - is how the same defect arrived twice by different routes.

    What each rule exists to stop:

    - Window. Select on the record's own 'timestamp' field, never on file modification time.
    - Human turn. type is 'user' AND (origin.kind is 'human' OR promptSource is typed,
      suggestion_accepted, or queued). The two fields are alternatives. Requiring both drops
      every accepted suggestion, every queued prompt, and every slash command.
    - Fragments. One assistant message arrives as several records sharing one message.id, and
      the first of them often carries no text at all. Measured on 2026-08-16: 9,942 of 15,662
      in-window message ids span more than one record, and 3,171 have an empty first record and
      text in a later one. So text is assembled BEFORE anything is deduplicated. Deduplicating
      first keeps the empty fragment and throws the message away.
    - Sidechain. Subagent records are excluded, and the number excluded is printed. Their
      transcripts live in subdirectories, so discovery is recursive; reading only the top level
      printed an exclusion count of zero that proved nothing.
    - Identity. A logical message is keyed on message.id when it has one, and on the record's
      own uuid when it does not. User records carry no message.id at all.
    - Units. Metric 2 counts command lines inside a powershell or bash fence, deduplicated on
      message id plus line text. Prose that mentions a command is not a handed-over command.
    - Metric 5 base. CI runs on pull_request, so head_sha is a branch head, not a merge commit.
      Its first-parent diff is one commit's change, not the pull request's. The base is the
      branch point instead: the merge that landed the work, then the merge base of that merge's
      first parent and the head.

    Every metric returns row-level ledger rows, and the script writes them next to the summary,
    so a figure can be recomputed from the rows rather than believed.
.PARAMETER AsModule
    Define the functions and return without measuring anything. The test suite uses this.
.PARAMETER ProjectRoot
    Where the session transcripts live. Defaults to ~/.claude/projects.
.PARAMETER ClonePath
    The clone used to resolve a CI run's changed files. Defaults to this repository. It is not
    called RepoRoot on purpose: the suite dot-sources this file, PowerShell variable names are
    case-insensitive, and a parameter called RepoRoot overwrites the caller's own $repoRoot.
.PARAMETER LedgerRoot
    Where the row-level ledgers are written. Defaults to the system temporary folder.
.PARAMETER SkipCi
    Skip metric 5, which needs the gh CLI and the network.
#>
[CmdletBinding()]
param(
    [switch] $AsModule,
    [string] $ProjectRoot,
    [string] $ClonePath,
    [string] $LedgerRoot,
    [switch] $SkipCi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# The window is fixed: four weeks ending at the moment wave 1 merged.
$script:WindowStart = [datetime]::Parse('2026-07-15T14:14:32Z').ToUniversalTime()
$script:WindowEnd = [datetime]::Parse('2026-08-12T14:14:32Z').ToUniversalTime()

# Each match set is literal and is printed with its number.
$script:MatchSets = @{
    'handoffs'       = @(
        'i cannot reach', 'i am not able to reach', 'run this in your terminal',
        'run it yourself', 'you will need to run', 'you need to run',
        'run the following yourself', 'i cannot run', 'blocked by the guard',
        'the guard refuses', 'from the main checkout yourself', 'needs a handover',
        'so a handover', 'you will have to run', 'please run it', 'over to you'
    )
    'next-step-asks' = @(
        'next step', 'what next', "what's next", 'what should i do next',
        'what do we do next', 'how do we proceed', 'what now', 'next items to pick up',
        'next backlog items', 'what do you suggest'
    )
    # Every term here is a line the cleanup scripts print, not a word people use about them.
    # The bare script name 'remove-worktree' produced 180 of 233 rows on 2026-08-16 - almost
    # all of them sentences discussing the script - which made a lexical count wear an event
    # count's label.
    'cleanup-events' = @(
        'worktree removed', 'watcher done', 'cleanup popup',
        'worktree remove failed', 'cleanup blocked', 'worktree is locked',
        'worktree is dirty', 'could not remove the worktree',
        'is not clean, skipping', 'branch preserved', 'removing worktree'
    )
}

# Metric 2 is a syntax rule, not a word list: a line inside a powershell or bash fence that
# names a directory.
$script:DirectoryLinePatterns = @(
    '^\s*(cd|chdir|pushd)\s+\S', '^\s*(Set-Location|Push-Location)\s+\S',
    '\s-C\s+\S', '-WorkingDirectory\s+\S', '[A-Za-z]:\\[^\s"'']+', '/c/[^\s"'']+'
)

function Get-RecordProperty {
    param(
        [Parameter(Mandatory)][AllowNull()] $Record,
        [Parameter(Mandatory)][string] $Name
    )
    if ($null -eq $Record) { return $null }
    # A hashtable answers to ContainsKey, not to PSObject.Properties. The CI resolver returns
    # one, so reading it as a psobject silently returned null for every field.
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains($Name)) { return $Record[$Name] }
        return $null
    }
    if ($Record -isnot [psobject]) { return $null }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-RecordTimestamp {
    <#
    .SYNOPSIS
        A record's timestamp as a UTC DateTime, whatever shape it arrives in.
    .DESCRIPTION
        ConvertFrom-Json already turns an ISO string into a DateTime whose Kind is Utc. Passing
        that object to [datetime]::Parse stringifies it in local time and parses the result as
        Unspecified, so the following ToUniversalTime subtracts the local offset a second time.
        Measured on 2026-08-16 in a UTC+2 session: 10:00Z came back as 08:00Z, which moved
        records and CI runs across both edges of the window.
    #>
    param([Parameter(Mandatory)][AllowNull()] $Record)

    $value = Get-RecordProperty -Record $Record -Name 'timestamp'
    if (-not $value) { $value = Get-RecordProperty -Record $Record -Name 'created_at' }
    if (-not $value) { return $null }

    if ($value -is [datetime]) { return $value.ToUniversalTime() }
    return ([datetimeoffset]::Parse([string]$value)).UtcDateTime
}

function Test-HumanTurn {
    param([Parameter(Mandatory)][AllowNull()] $Record)

    if ((Get-RecordProperty -Record $Record -Name 'type') -ne 'user') { return $false }

    $origin = Get-RecordProperty -Record $Record -Name 'origin'
    if ((Get-RecordProperty -Record $origin -Name 'kind') -eq 'human') { return $true }

    $promptSource = Get-RecordProperty -Record $Record -Name 'promptSource'
    return ($promptSource -in @('typed', 'suggestion_accepted', 'queued'))
}

function Select-FrictionRecord {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Records,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End
    )

    $kept = foreach ($record in $Records) {
        if ((Get-RecordProperty -Record $record -Name 'isSidechain') -eq $true) { continue }
        $when = Get-RecordTimestamp -Record $record
        if (-not $when) { continue }
        if ($when -lt $Start -or $when -ge $End) { continue }
        $record
    }
    return @($kept)
}

function Get-SidechainCount {
    <#
    .SYNOPSIS
        How many sidechain records the window holds.
    .DESCRIPTION
        The window is required. Counting every sidechain record ever read, while the metrics
        count only in-window ones, publishes an exclusion figure for a different population -
        21,040 against 19,586 - which reads as though the metrics saw more than they did.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Records,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End
    )

    $count = 0
    foreach ($record in $Records) {
        if ((Get-RecordProperty -Record $record -Name 'isSidechain') -ne $true) { continue }
        $when = Get-RecordTimestamp -Record $record
        if (-not $when) { continue }
        if ($when -lt $Start -or $when -ge $End) { continue }
        $count++
    }
    return $count
}

function Get-RecordText {
    <#
    .SYNOPSIS
        The text one record carries, flattened to one string.
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

function Get-MessageKey {
    param([Parameter(Mandatory)][AllowNull()] $Record)

    $message = Get-RecordProperty -Record $Record -Name 'message'
    $id = Get-RecordProperty -Record $message -Name 'id'
    if ($id) { return "msg:$id" }

    $uuid = Get-RecordProperty -Record $Record -Name 'uuid'
    if ($uuid) { return "uuid:$uuid" }

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

function ConvertTo-LogicalMessage {
    <#
    .SYNOPSIS
        Folds records into one object per logical message, with the whole text assembled.
    .DESCRIPTION
        This is the shared representation. Every metric and the sampler read it, so a fix here
        reaches all of them. Records that share a key are joined in the order they were read,
        which is why an empty first fragment no longer hides the rest of the message.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][array] $Records)

    $order = New-Object System.Collections.Generic.List[string]
    $byKey = @{}

    foreach ($record in $Records) {
        $key = Get-MessageKey -Record $record
        if (-not $byKey.ContainsKey($key)) {
            $order.Add($key)
            $byKey[$key] = [pscustomobject]@{
                Key         = $key
                Type        = [string](Get-RecordProperty -Record $record -Name 'type')
                Timestamp   = [string](Get-RecordProperty -Record $record -Name 'timestamp')
                Session     = Get-SessionName -Record $record
                IsSidechain = ((Get-RecordProperty -Record $record -Name 'isSidechain') -eq $true)
                IsHumanTurn = (Test-HumanTurn -Record $record)
                Fragments   = 0
                Text        = ''
                Seen        = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
        }

        $entry = $byKey[$key]
        if ($entry.IsHumanTurn -eq $false -and (Test-HumanTurn -Record $record)) { $entry.IsHumanTurn = $true }

        $text = Get-RecordText -Record $record

        # A record copied forward into a later transcript is the same record, not a second
        # fragment of the message. Appending it again doubled the text and inflated the count
        # of messages said to span several records.
        $fingerprint = "$(Get-RecordProperty -Record $record -Name 'uuid')|$text"
        if (-not $entry.Seen.Add($fingerprint)) { continue }

        $entry.Fragments++
        if ($text) {
            $entry.Text = if ($entry.Text) { "$($entry.Text)`n$text" } else { $text }
        }
    }

    return @($order | ForEach-Object { $byKey[$_] })
}

function Get-FencedBlock {
    <#
    .SYNOPSIS
        The lines inside every powershell or bash fence in a message.
    .DESCRIPTION
        A command in prose is not a command handed over. The specification says the line must
        sit inside a ```powershell or ```bash fence, so a fence of any other language, and text
        outside a fence, are both skipped.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $lines = New-Object System.Collections.Generic.List[string]
    $inside = $false

    foreach ($line in ($Text -split "`n")) {
        if ($line -match '^\s*```\s*(powershell|pwsh|bash|sh|shell)\s*$') { $inside = $true; continue }
        if ($line -match '^\s*```') { $inside = $false; continue }
        if ($inside) { $lines.Add($line.TrimEnd()) }
    }
    return @($lines)
}

function Test-DirectoryBoundLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)
    foreach ($pattern in $script:DirectoryLinePatterns) {
        if ($Line -match $pattern) { return $true }
    }
    return $false
}

function Get-FrictionCount {
    <#
    .SYNOPSIS
        Counts one metric over logical messages, and returns the rows behind the number.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Messages,
        [Parameter(Mandatory)][ValidateSet('handoffs', 'directory-bound-commands', 'cleanup-events', 'next-step-asks')][string] $Metric
    )

    $sessions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = New-Object System.Collections.Generic.List[object]
    $patterns = if ($Metric -eq 'directory-bound-commands') { $script:DirectoryLinePatterns } else { $script:MatchSets[$Metric] }

    foreach ($message in $Messages) {
        # Which side of the conversation each metric reads. Metric 3 reads any record, per the
        # specification: the agent reports cleanup outcomes as often as a tool does.
        #
        # This is an if-chain on purpose. 'continue' inside a PowerShell switch leaves the
        # switch, not the enclosing loop, so a switch here counted every message for every
        # metric: metric 4 read assistant messages and reported 338 asks instead of 36.
        $skip = if ($Metric -eq 'next-step-asks') { -not $message.IsHumanTurn }
        elseif ($Metric -eq 'cleanup-events') { $false }
        else { $message.Type -ne 'assistant' }
        if ($skip) { continue }

        $text = $message.Text
        if (-not $text) { continue }

        if ($Metric -eq 'directory-bound-commands') {
            # One message can hand over several commands, so the unit is the line. The same
            # line repeated inside one message is one command.
            $seenLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($line in (Get-FencedBlock -Text $text)) {
                $trimmed = $line.Trim()
                if (-not $trimmed) { continue }
                if (-not (Test-DirectoryBoundLine -Line $trimmed)) { continue }
                if (-not $seenLines.Add($trimmed)) { continue }
                $rows.Add([pscustomobject]@{ Key = $message.Key; Session = $message.Session; Line = $trimmed })
                [void]$sessions.Add($message.Session)
            }
            continue
        }

        foreach ($pattern in $patterns) {
            if ($text -match [regex]::Escape($pattern)) {
                $rows.Add([pscustomobject]@{ Key = $message.Key; Session = $message.Session; Matched = $pattern })
                [void]$sessions.Add($message.Session)
                break
            }
        }
    }

    return @{
        Items    = $rows.Count
        Sessions = $sessions.Count
        MatchSet = $patterns
        Rows     = $rows
    }
}

function Test-DotnetPath {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)
    return ($Path -match '\.(cs|csproj|sln|slnx|razor|props|targets)$' -or $Path -match '^(src|tests)/')
}

function Get-ChangedFileForRun {
    <#
    .SYNOPSIS
        The files a CI run's commit really changed, with the base it was measured against.
    .DESCRIPTION
        Three shapes, because a run's head_sha is not always the same kind of commit:

        - A merge commit on main: its first-parent diff IS the pull request's net change.
        - A commit already on main's first-parent chain: its own change.
        - Anything else - and this is the common case, because CI runs on pull_request - is a
          branch head. Its first-parent diff is the last commit only. Measured on 2026-08-16
          for 1507643550b4: the first-parent diff returns 0 files while the pull request
          changed 10, one of them a .NET file, so the run was classified non-.NET wrongly.

        For a branch head the base is the branch point: find the merge that landed the work,
        then take the merge base of that merge's first parent and the head. That is historical
        - it does not move when main advances - and it needs no API.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Sha
    )

    & git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $parents = (& git -C $RepoRoot rev-list --parents -n 1 $Sha 2>$null) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $parents.Count -lt 2) { return $null }

    # The branch point is tried FIRST, even for a merge commit. A branch head is often itself a
    # merge - of main back into the branch - and its first-parent diff is then empty, which is
    # how run 1507643550b4 was classified as changing no files at all.
    #
    # For a merge that landed ON main this attempt resolves the base to the commit itself, and
    # the check below rejects it, so the first-parent rule still handles that shape.
    #
    # The merge that landed this commit, if any. --ancestry-path keeps only merges that this
    # commit actually reaches, and the last of them is the earliest in time.
    $merges = @(& git -C $RepoRoot rev-list --ancestry-path --merges "$Sha..origin/main" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $merges.Count -gt 0) {
        $merge = $merges[-1]
        $base = (& git -C $RepoRoot merge-base "$merge^1" $Sha 2>$null)
        if ($LASTEXITCODE -eq 0 -and $base) {
            $base = $base.Trim()
            if ($base -ne $Sha) {
                $files = @(& git -C $RepoRoot diff --name-only $base $Sha 2>$null)
                if ($LASTEXITCODE -eq 0) { return @{ Files = $files; Base = $base; Kind = 'pull-request' } }
            }
        }
    }

    # The first-parent fallback is only legitimate for a commit that actually reached main: a
    # merge that landed there, or a commit on its chain. For anything else it answers with one
    # commit's change and calls it a pull request. An audit on 2026-08-16 found 13 runs where
    # that fallback fired and the real pull request did touch .NET files.
    & git -C $RepoRoot merge-base --is-ancestor $Sha origin/main 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $base = $parents[1]
    $kind = if ($parents.Count -ge 3) { 'merge' } else { 'single-commit' }
    $files = @(& git -C $RepoRoot diff --name-only $base $Sha 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return @{ Files = $files; Base = $base; Kind = $kind }
}

function Get-CiClassification {
    <#
    .SYNOPSIS
        Splits CI runs into .NET and non-.NET, using each run's own base.
    .PARAMETER Resolver
        Takes a head_sha and returns @{ Files; Base }, or null when it cannot be resolved.
        Injecting it is what lets the suite run without git or the network.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Runs,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End,
        [Parameter(Mandatory)][scriptblock] $Resolver,
        [string] $WorkflowName = 'CI'
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $nonDotnetMs = 0
    $unresolved = 0
    $outOfWindow = 0
    $duplicateIds = 0
    $missingTiming = 0
    $dotnetRuns = 0
    $otherWorkflows = 0

    foreach ($run in $Runs) {
        # One workflow, named. In this window the repository ran 549 workflow runs, of which
        # 201 were CI and the rest were opencode, PR-Agent, and the two deploy workflows.
        # Counting all of them answers a different question than "CI minutes".
        $name = [string](Get-RecordProperty -Record $run -Name 'name')
        if ($WorkflowName -and $name -ne $WorkflowName) { $otherWorkflows++; continue }

        $id = [string](Get-RecordProperty -Record $run -Name 'id')
        if (-not $seenIds.Add($id)) { $duplicateIds++; continue }

        $created = Get-RecordTimestamp -Record $run
        if (-not $created) { $unresolved++; continue }
        if ($created -lt $Start -or $created -ge $End) { $outOfWindow++; continue }

        $sha = [string](Get-RecordProperty -Record $run -Name 'head_sha')
        $resolved = & $Resolver $sha
        if ($null -eq $resolved) { $unresolved++; continue }

        $files = @(Get-RecordProperty -Record $resolved -Name 'Files')
        if ($files.Count -eq 0) { $unresolved++; continue }

        $touchesDotnet = $false
        foreach ($file in $files) {
            if (Test-DotnetPath -Path $file) { $touchesDotnet = $true; break }
        }
        if ($touchesDotnet) { $dotnetRuns++; continue }

        $ms = Get-RecordProperty -Record $run -Name 'run_duration_ms'
        if (-not $ms) { $missingTiming++; $ms = 0 }
        $nonDotnetMs += [int64]$ms

        $rows.Add([pscustomobject]@{
                Id      = $id
                HeadSha = $sha
                Base    = [string](Get-RecordProperty -Record $resolved -Name 'Base')
                Files   = $files.Count
                Minutes = [math]::Round([int64]$ms / 60000, 2)
            })
    }

    return @{
        NonDotnetRuns    = $rows.Count
        DotnetRuns       = $dotnetRuns
        NonDotnetMinutes = [math]::Round($nonDotnetMs / 60000, 1)
        Unresolved       = $unresolved
        OutOfWindow      = $outOfWindow
        DuplicateIds     = $duplicateIds
        MissingTiming    = $missingTiming
        OtherWorkflows   = $otherWorkflows
        Rows             = $rows
    }
}

function Resolve-TranscriptFile {
    <#
    .SYNOPSIS
        Deduplicates transcript paths by resolved, lowercased full path.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Candidates)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $full = (Resolve-Path -LiteralPath $candidate).Path
        if ($seen.Add($full.ToLowerInvariant())) { $kept.Add($full) }
    }
    return @($kept)
}

function Get-TranscriptFile {
    <#
    .SYNOPSIS
        Every AHKFlow transcript under the project root, nested ones included.
    .DESCRIPTION
        Subagent transcripts live in subdirectories. Reading only the top level hid all of
        them, so the sidechain exclusion count printed zero and proved nothing. Measured on
        2026-08-16: 392 files at the top level, 694 with the subdirectories.
    #>
    param([Parameter(Mandatory)][string] $ProjectRoot)

    $directories = @(Get-ChildItem -LiteralPath $ProjectRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'AHKFlow' })

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($directory in $directories) {
        foreach ($file in (Get-ChildItem -LiteralPath $directory.FullName -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue)) {
            $candidates.Add($file.FullName)
        }
    }
    return (Resolve-TranscriptFile -Candidates $candidates)
}

function Read-TranscriptRecord {
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
# The ledgers are committed, not left in a temporary folder. The transcripts change under the
# measurement, so a figure whose rows live in %TEMP% cannot be recomputed from the commit.
if (-not $LedgerRoot) { $LedgerRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/development/friction-samples/ledgers' }
New-Item -ItemType Directory -Path $LedgerRoot -Force | Out-Null

Write-Host ''
Write-Host 'Friction measurement'
Write-Host "  window : $($script:WindowStart.ToString('u')) to $($script:WindowEnd.ToString('u'))"
Write-Host "  source : $ProjectRoot"
Write-Host "  ledgers: $LedgerRoot"

$files = Get-TranscriptFile -ProjectRoot $ProjectRoot
Write-Host "  files  : $($files.Count) after deduplication, subdirectories included"

$mainFiles = @($files | Where-Object { $_ -notmatch 'worktrees' })
Write-Host "           $($mainFiles.Count) in main project directories, $($files.Count - $mainFiles.Count) in worktree directories"

$all = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    foreach ($record in (Read-TranscriptRecord -Path $file)) { $all.Add($record) }
}
Write-Host "  records: $($all.Count) read"

$sidechain = Get-SidechainCount -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd
$selected = Select-FrictionRecord -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd
$messages = ConvertTo-LogicalMessage -Records $selected
$multiFragment = @($messages | Where-Object { $_.Fragments -gt 1 }).Count

Write-Host "  in window, not sidechain: $($selected.Count) records"
Write-Host "  sidechain records excluded: $sidechain"
Write-Host "  logical messages: $($messages.Count), of which $multiFragment were assembled from more than one record"
Write-Host ''

foreach ($metric in @('handoffs', 'directory-bound-commands', 'cleanup-events', 'next-step-asks')) {
    $count = Get-FrictionCount -Messages $messages -Metric $metric
    $unit = if ($metric -eq 'directory-bound-commands') { 'command lines' } else { 'messages' }
    $ledger = Join-Path $LedgerRoot "$metric.csv"
    $count.Rows | Export-Csv -LiteralPath $ledger -NoTypeInformation -Encoding utf8
    Write-Host "$metric : $($count.Items) $unit across $($count.Sessions) session(s)"
    Write-Host "  match set: $($count.MatchSet -join ' | ')"
    Write-Host "  ledger   : $ledger"
    Write-Host ''
}

if ($SkipCi) {
    Write-Host 'ci-minutes : skipped by -SkipCi'
    return
}

# The runs come from the paginated API with a 'created' filter, never from
# 'gh run list --limit N'. Measured on 2026-08-16: --limit 400 reached back only to
# 2026-08-07, three weeks short of this window, and it says so nowhere.
$runLines = & gh api -X GET 'repos/s205109/AHKFlowApp/actions/runs' `
    -f 'created=2026-07-15..2026-08-12' -f 'per_page=100' --paginate `
    --jq '.workflow_runs[] | {id: .id, name: .name, event: .event, head_sha: .head_sha, created_at: .created_at} | tostring' 2>$null

if ($LASTEXITCODE -ne 0 -or -not $runLines) {
    Write-Host 'ci-minutes : skipped - gh returned nothing, so no run could be classified'
    return
}

$runs = @($runLines | Where-Object { $_ } | ForEach-Object {
        $parsed = $_ | ConvertFrom-Json
        [pscustomobject]@{
            id              = $parsed.id
            name            = $parsed.name
            event           = $parsed.event
            head_sha        = $parsed.head_sha
            created_at      = $parsed.created_at
            run_duration_ms = 0
        }
    })
Write-Host "  workflow runs returned by the API for this window: $($runs.Count)"
foreach ($group in ($runs | Group-Object name | Sort-Object Count -Descending)) {
    Write-Host "    $($group.Count) $($group.Name)"
}

# Duration comes from the timing endpoint. 'billable' reads 0 for this repository. A failed
# call is counted rather than left as a silent zero.
$timingFailures = 0
foreach ($run in $runs) {
    if ($run.name -ne 'CI') { continue }
    $created = Get-RecordTimestamp -Record $run
    if (-not $created) { continue }
    if ($created -lt $script:WindowStart -or $created -ge $script:WindowEnd) { continue }
    $timing = & gh api "repos/s205109/AHKFlowApp/actions/runs/$($run.id)/timing" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $timing) { $timingFailures++; continue }
    $parsed = $timing | ConvertFrom-Json
    $duration = Get-RecordProperty -Record $parsed -Name 'run_duration_ms'
    if ($duration) { $run.run_duration_ms = [int64]$duration } else { $timingFailures++ }
}

$resolver = { param([string] $Sha) Get-ChangedFileForRun -RepoRoot $ClonePath -Sha $Sha }
$ci = Get-CiClassification -Runs $runs -Start $script:WindowStart -End $script:WindowEnd -Resolver $resolver

$ciLedger = Join-Path $LedgerRoot 'ci-runs.csv'
$ci.Rows | Export-Csv -LiteralPath $ciLedger -NoTypeInformation -Encoding utf8

Write-Host "ci-minutes on non-.NET changes : $($ci.NonDotnetMinutes) minutes across $($ci.NonDotnetRuns) run(s)"
Write-Host "  runs of another workflow, not counted : $($ci.OtherWorkflows)"
Write-Host "  runs that touch .NET files : $($ci.DotnetRuns)"
Write-Host "  runs outside the window : $($ci.OutOfWindow)"
Write-Host "  repeated run ids skipped : $($ci.DuplicateIds)"
Write-Host "  runs whose head_sha is not in this clone, so unresolved : $($ci.Unresolved)"
Write-Host "  runs counted with no duration : $($ci.MissingTiming)   timing calls that failed : $timingFailures"
Write-Host "  ledger : $ciLedger"
Write-Host ''
