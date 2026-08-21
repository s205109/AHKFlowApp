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
    - Units. Metric 2 counts command lines inside a powershell, pwsh, bash, sh or shell fence,
      deduplicated on message id plus line text. Prose that mentions a command is not a
      handed-over command, and neither is a here-string body inside the fence.
    - Metric 3 is a line rule, not a word list. Cleanup outcomes reach a transcript through
      Write-WorktreeLog, which stamps every line. A phrase matched anywhere in a message counted
      the script's own source, injected skill instructions, and reviews quoting an outcome.
    - Metric 5 base. CI runs on pull_request, so head_sha is a branch head, not a merge commit.
      Its first-parent diff is one commit's change, not the pull request's. The base is the
      branch point instead: the merge that landed the work - taken only from origin/main's
      first-parent chain - then the merge base of that merge's first parent and the head.
    - Metric 5 population. The API filters on a calendar date range, which is a superset of the
      window. Both numbers are printed, and every count comes from the window.
    - Metric 5 zero. A pull request that lands no net change is classified, not unresolved.

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
}

# Metric 3 is not a word list at all. Every cleanup outcome reaches a transcript as a line
# written by Write-WorktreeLog, which stamps it 'yyyy-MM-dd HH:mm:ss  <worktree>  <message>'
# (`scripts/worktree-log.common.ps1:92`, "    return '{0}  {1}  {2}' -f $stamp, $Worktree, $single").
# Matching the wording anywhere in a message counted the
# script's own source, injected skill instructions, and reviews quoting an outcome: measured on
# 2026-08-16, 65 of 75 rows were one of those, and six of the eleven phrases then in use appear
# in no script at all. So the rule is the line shape first, and the outcome second.
$script:CleanupLogLinePattern = '^\s*\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s\s+\S.*?\s\s+(?<message>\S.*)$'

# Each entry is the start of a line one of the cleanup scripts writes, with the file and line
# that writes it. An entry that no script writes cannot appear here.
$script:CleanupOutcomePatterns = @(
    # --- the shape written from backlog 073 onward: one line per removal attempt ---
    '^Removed\.'                                                # remove-worktree-local-dev.ps1, watcher terminal state
    '^Kept: '                                                   # every deliberate refusal, hook, watcher and sweep
    '^Failed: '                                                 # every failure that left the worktree half-removed

    # --- the shape written before backlog 073. Kept so the historical part of the same file
    # --- stays readable to this script. Do not delete these.
    '^Watcher started\.'
    '^Watcher done \('
    '^Worktree was preserved \(not removed\):'
    '^Could not remove worktree because the folder is still locked:'
    '^Worktree folder already gone \(removed elsewhere\)'
    '^Worktree folder does not exist; nothing to remove\.'
    '^REFUSING:'
    '^Git refused safe branch deletion'
    '^force override: AHKFLOW_WORKTREE_FORCE_REMOVE set'
)

# Metric 2 is a syntax rule, not a word list: a command line inside a shell fence that names a
# directory. Two filters keep prose out. The line must START with a command, because
# 'Records the `git -C docs/superpowers` form' is a sentence, not a command. And a here-string
# body is text, so its lines are skipped: a pull request body passed as @' ... '@ inside a
# powershell fence put two sentences in the ledger on 2026-08-16.
$script:DirectoryLinePatterns = @(
    '^\s*(cd|chdir|pushd)\s+\S', '^\s*(Set-Location|Push-Location)\s+\S',
    '\s-C\s+\S', '-WorkingDirectory\s+\S', '[A-Za-z]:\\[^\s"'']+', '/c/[^\s"'']+'
)

# The head of a command line. A line that does not start with one of these, or with a call
# operator, is prose however many paths it names.
$script:CommandHeadPattern = '^\s*(&\s+)?[''"]?(cd|chdir|pushd|popd|Set-Location|Push-Location|Pop-Location|git|gh|rtk|pwsh|powershell|dotnet|npm|npx|node|python|py|docker|az|bash|sh|wsl|code|make|cargo|go|Copy-Item|Move-Item|Remove-Item|New-Item|Get-ChildItem|Get-Content|Set-Content|Test-Path|Start-Process|Invoke-Expression|Invoke-WebRequest|Resolve-Path|\.\\[\w.-]+|\./[\w./-]+)[''"]?(\s|$)'

# A here-string opens with @' or @" at the end of a line and closes with '@ or "@ at the start
# of one. Everything between is text.
$script:HereStringOpenPattern = '@[''"]\s*$'
$script:HereStringClosePattern = '^\s*[''"]@'

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

        # A message copied into a second transcript appears under two session names. Taking the
        # first one read made every per-metric session total depend on enumeration order, which
        # Get-ChildItem does not fix. The lowest name is the same answer whatever the order.
        $session = Get-SessionName -Record $record
        if ([string]::Compare($session, $entry.Session, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $entry.Session = $session
        }

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
        The command lines inside every shell fence in a message.
    .DESCRIPTION
        A command in prose is not a command handed over, so the line must sit inside a shell
        fence. Five tags open one: powershell, pwsh, bash, sh and shell. An earlier version of
        this comment named only two of them while the code accepted all five, which is the
        opposite of a rule that two scripts can follow to the same number.

        A here-string body is skipped. It sits inside the fence but it is text: a pull request
        body passed as @' ... '@ put two English sentences in the ledger on 2026-08-16, because
        both contain 'git -C'.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $lines = New-Object System.Collections.Generic.List[string]
    $inside = $false
    $inHereString = $false

    foreach ($line in ($Text -split "`n")) {
        if (-not $inHereString) {
            if ($line -match '^\s*```\s*(powershell|pwsh|bash|sh|shell)\s*$') { $inside = $true; continue }
            if ($line -match '^\s*```') { $inside = $false; continue }
        }
        if (-not $inside) { continue }

        if ($inHereString) {
            if ($line -match $script:HereStringClosePattern) { $inHereString = $false }
            continue
        }
        if ($line -match $script:HereStringOpenPattern) { $inHereString = $true; continue }

        $lines.Add($line.TrimEnd())
    }
    return @($lines)
}

function Test-DirectoryBoundLine {
    <#
    .SYNOPSIS
        Whether one fenced line is a command that names a directory.
    .DESCRIPTION
        Both halves are needed. Without the command head, any sentence that mentions a Windows
        path or the string ' -C ' counts; with it alone, every command counts.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)

    if ($Line -notmatch $script:CommandHeadPattern) { return $false }
    foreach ($pattern in $script:DirectoryLinePatterns) {
        if ($Line -match $pattern) { return $true }
    }
    return $false
}

function Get-CleanupEventLine {
    <#
    .SYNOPSIS
        The cleanup log lines a message carries, with the outcome each one reports.
    .DESCRIPTION
        A line qualifies twice over: it has the shared log line's stamp and worktree prefix, and
        its message part starts with something a cleanup script actually writes. Either half
        alone counts discussion as an event. Both halves together do not separate a line a
        tool read from a line a person pasted, and they are not meant to: both are reads of
        the same persistent log. See docs/development/cleanup-event-identity.md.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($Text -split "`n")) {
        $trimmed = $line.TrimEnd()
        $match = [regex]::Match($trimmed, $script:CleanupLogLinePattern)
        if (-not $match.Success) { continue }
        $message = $match.Groups['message'].Value
        foreach ($pattern in $script:CleanupOutcomePatterns) {
            if ($message -match $pattern) {
                $hits.Add([pscustomobject]@{ Line = $trimmed.Trim(); Matched = $pattern })
                break
            }
        }
    }
    return $hits.ToArray()
}

function Get-MatchingLine {
    <#
    .SYNOPSIS
        The first line of a message that carries a given phrase.
    .DESCRIPTION
        The ledger stores this rather than the whole message. A row of keys and session names
        cannot be re-read; the line that matched can.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [Parameter(Mandatory)][string] $Phrase
    )

    foreach ($line in ($Text -split "`n")) {
        if ($line -match [regex]::Escape($Phrase)) { return $line.Trim() }
    }
    return ''
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
    # Metric 3 alone deduplicates across messages, on the whole line: the same log line reaches
    # two tool results when a session reads the log twice. The line is not a unique event id.
    # Its stamp has one-second resolution, and the process id is not the safeguard an earlier
    # comment claimed. Counted over the whole of worktree-removal.log on 2026-08-21: 134 of
    # 134 'Watcher started.' lines carry PID=, while 0 of 130 'Watcher done (' lines do, and
    # 0 of the 24 lock failures. So two genuine events in the same second, in the same worktree,
    # with the same message would fold into one. That has never happened: all 295 outcome
    # lines in the log are distinct. The collapse is stated rather than fixed, because the
    # line carries no event id to fix it with, and counting occurrences instead would break
    # the rule above - the same line read twice is one event. A command handed over in two
    # messages is two handovers, so metric 2 must not deduplicate at all.
    $seenEvents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $patterns = switch ($Metric) {
        'directory-bound-commands' { $script:DirectoryLinePatterns }
        'cleanup-events' { $script:CleanupOutcomePatterns }
        default { $script:MatchSets[$Metric] }
    }

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
                $rows.Add([pscustomobject]@{
                        Key = $message.Key; Session = $message.Session
                        Timestamp = $message.Timestamp; Type = $message.Type
                        Matched = 'command-line'; Line = $trimmed
                    })
                [void]$sessions.Add($message.Session)
            }
            continue
        }

        if ($Metric -eq 'cleanup-events') {
            # The unit is the log line too. One tool result can carry the whole tail of the
            # worktree log, and each stamped line in it is a separate event.
            foreach ($hit in (Get-CleanupEventLine -Text $text)) {
                if (-not $seenEvents.Add($hit.Line)) { continue }
                $rows.Add([pscustomobject]@{
                        Key = $message.Key; Session = $message.Session
                        Timestamp = $message.Timestamp; Type = $message.Type
                        Matched = $hit.Matched; Line = $hit.Line
                    })
                [void]$sessions.Add($message.Session)
            }
            continue
        }

        foreach ($pattern in $patterns) {
            if ($text -match [regex]::Escape($pattern)) {
                $rows.Add([pscustomobject]@{
                        Key = $message.Key; Session = $message.Session
                        Timestamp = $message.Timestamp; Type = $message.Type
                        Matched = $pattern; Line = (Get-MatchingLine -Text $text -Phrase $pattern)
                    })
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
    <#
    .SYNOPSIS
        Whether one changed path is a .NET file.
    .DESCRIPTION
        The file type decides, never the folder. 'anything under src/ or tests/ is .NET' also
        caught PowerShell suites and an nginx config: 21 in-window runs changed no .NET file
        at all and were counted as .NET work, which took 163.2 minutes out of the metric.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)
    return ($Path -match '\.(cs|csproj|sln|slnx|razor|props|targets)$')
}

$script:MainFirstParentCache = @{}

function Get-MainFirstParentSet {
    <#
    .SYNOPSIS
        Every commit on origin/main's first-parent chain, as a set.
    .DESCRIPTION
        This is the only chain that means "landed on main". Reachability is not the same test:
        every commit inside a merged branch is reachable from main, and treating those as
        landed is what let the first-parent fallback answer with one commit's change.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)

    if ($script:MainFirstParentCache.ContainsKey($RepoRoot)) { return $script:MainFirstParentCache[$RepoRoot] }

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in (& git -C $RepoRoot rev-list --first-parent origin/main 2>$null)) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed) { [void]$set.Add($trimmed) }
    }
    $script:MainFirstParentCache[$RepoRoot] = $set
    return $set
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
          changed 10, so the run was classified against a change CI never ran on.

        For a branch head the base is the branch point: find the merge that landed the work,
        then take the merge base of that merge's first parent and the head. That is historical
        - it does not move when main advances - and it needs no API.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Sha
    )

    & git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { return @{ Unresolved = $true; Reason = 'head-absent-from-clone' } }

    $parents = (& git -C $RepoRoot rev-list --parents -n 1 $Sha 2>$null) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $parents.Count -lt 2) { return @{ Unresolved = $true; Reason = 'head-has-no-parent' } }

    $mainChain = Get-MainFirstParentSet -RepoRoot $RepoRoot

    # The branch point is tried FIRST, even for a merge commit. A branch head is often itself a
    # merge - of main back into the branch - and its first-parent diff is then empty, which is
    # how run 1507643550b4 was classified as changing no files at all.
    #
    # For a merge that landed ON main this attempt resolves the base to the commit itself, and
    # the check below rejects it, so the first-parent rule still handles that shape.
    #
    # Only merges ON origin/main's first-parent chain qualify. --ancestry-path also returns
    # merges made on the branch, such as 'Merge branch main into feature/x'. Those are older
    # than the landing merge, so the oldest-first pick chose one, its merge base with the head
    # was the head itself, and the code fell through to the first-parent rule. Measured on
    # 2026-08-16: all 8 runs that reached that fallback sat off the chain, and 2 of them changed
    # a .cs file the one-commit diff never saw.
    $merges = @(& git -C $RepoRoot rev-list --ancestry-path --merges "$Sha..origin/main" 2>$null |
            Where-Object { $mainChain.Contains(([string]$_).Trim()) })
    if ($merges.Count -gt 0) {
        # The last is the earliest in time: the merge that landed this work, not a later one.
        $merge = ([string]$merges[-1]).Trim()
        $base = (& git -C $RepoRoot merge-base "$merge^1" $Sha 2>$null)
        if ($LASTEXITCODE -eq 0 -and $base) {
            $base = $base.Trim()
            if ($base -ne $Sha) {
                $files = @(& git -C $RepoRoot diff --name-only $base $Sha 2>$null)
                if ($LASTEXITCODE -eq 0) { return @{ Files = $files; Base = $base; Kind = 'pull-request'; LandingMerge = $merge } }
            }
        }
    }

    # The first-parent fallback is only legitimate for a commit that IS on main's first-parent
    # chain. Reachability is the wrong test: every commit inside a merged branch is reachable
    # from main, and for those the fallback answers with one commit's change and calls it a
    # pull request.
    if (-not $mainChain.Contains($Sha)) { return @{ Unresolved = $true; Reason = 'no-base-on-main-first-parent' } }

    $base = $parents[1]
    $kind = if ($parents.Count -ge 3) { 'merge' } else { 'single-commit' }
    $files = @(& git -C $RepoRoot diff --name-only $base $Sha 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ Unresolved = $true; Reason = 'diff-failed' } }
    return @{ Files = $files; Base = $base; Kind = $kind; LandingMerge = '' }
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
    $nonDotnetRuns = 0
    $unresolved = 0
    $outOfWindow = 0
    $duplicateIds = 0
    $missingTiming = 0
    $missingTimestamp = 0
    $dotnetRuns = 0
    $otherWorkflows = 0
    $noFileChange = 0

    foreach ($run in $Runs) {
        $id = [string](Get-RecordProperty -Record $run -Name 'id')
        if (-not $seenIds.Add($id)) { $duplicateIds++; continue }

        # The window comes before the workflow name. Filtering by name first counted every
        # out-of-window run of another workflow as an 'other workflow', which is how the
        # published population became the API's calendar range - 549 runs, 201 of them CI -
        # instead of the window's 531 and 192.
        $created = Get-RecordTimestamp -Record $run
        if (-not $created) { $missingTimestamp++; continue }
        if ($created -lt $Start -or $created -ge $End) { $outOfWindow++; continue }

        # One workflow, named. The rest are opencode, PR-Agent, and the two deploy workflows,
        # and counting them answers a different question than "CI minutes".
        $name = [string](Get-RecordProperty -Record $run -Name 'name')
        if ($WorkflowName -and $name -ne $WorkflowName) { $otherWorkflows++; continue }

        $sha = [string](Get-RecordProperty -Record $run -Name 'head_sha')
        $ms = Get-RecordProperty -Record $run -Name 'run_duration_ms'
        $timingStatus = if ($ms) { 'reported' } else { 'missing' }
        if (-not $ms) { $ms = 0 }

        $row = [pscustomobject]@{
            Id             = $id
            Name           = $name
            CreatedAt      = $created.ToString('o')
            HeadSha        = $sha
            Classification = 'unresolved'
            Reason         = 'not-attempted'
            BaseKind       = ''
            Base           = ''
            LandingMerge   = ''
            FileCount      = 0
            DurationMs     = [int64]$ms
            TimingStatus   = $timingStatus
            ChangedPaths   = ''
        }
        $rows.Add($row)

        # The resolver says why it could not answer, and the ledger keeps that word. An earlier
        # version printed one explanation for every unresolved run - 'head_sha is not in this
        # clone' - and it was false: all 192 in-window heads were present on 2026-08-16.
        $resolved = & $Resolver $sha
        if ($null -eq $resolved) { $unresolved++; $row.Reason = 'resolver-returned-null'; continue }
        if ((Get-RecordProperty -Record $resolved -Name 'Unresolved') -eq $true) {
            $unresolved++
            $row.Reason = [string](Get-RecordProperty -Record $resolved -Name 'Reason')
            continue
        }

        $files = @(Get-RecordProperty -Record $resolved -Name 'Files')
        $row.BaseKind = [string](Get-RecordProperty -Record $resolved -Name 'Kind')
        $row.Base = [string](Get-RecordProperty -Record $resolved -Name 'Base')
        $row.LandingMerge = [string](Get-RecordProperty -Record $resolved -Name 'LandingMerge')
        $row.FileCount = $files.Count
        $row.ChangedPaths = ($files -join ';')

        $touchesDotnet = $false
        foreach ($file in $files) {
            if (Test-DotnetPath -Path $file) { $touchesDotnet = $true; break }
        }
        if ($touchesDotnet) {
            $dotnetRuns++
            $row.Classification = 'dotnet'
            $row.Reason = 'changed-dotnet-path'
            continue
        }

        # A pull request can land no net change at all. It resolved, so it is classified;
        # calling it unresolved conflated "could not resolve" with "resolved to nothing", and
        # dropped run 30912438833 and its 153,000 ms.
        $row.Classification = 'non-dotnet'
        $row.Reason = if ($files.Count -eq 0) { $noFileChange++; 'no-file-change' } else { 'no-dotnet-path' }
        if ($timingStatus -eq 'missing') { $missingTiming++ }
        $nonDotnetRuns++
        $nonDotnetMs += [int64]$ms
    }

    return @{
        NonDotnetRuns    = $nonDotnetRuns
        DotnetRuns       = $dotnetRuns
        NonDotnetMinutes = [math]::Round($nonDotnetMs / 60000, 1)
        NonDotnetMs      = $nonDotnetMs
        Unresolved       = $unresolved
        NoFileChange     = $noFileChange
        OutOfWindow      = $outOfWindow
        DuplicateIds     = $duplicateIds
        MissingTiming    = $missingTiming
        MissingTimestamp = $missingTimestamp
        OtherWorkflows   = $otherWorkflows
        Rows             = $rows
    }
}

function Get-RunPopulationSummary {
    <#
    .SYNOPSIS
        How many workflow runs the window holds, by workflow name.
    .DESCRIPTION
        The API is asked for a calendar range, because 'created' takes dates and the window
        starts and ends at 14:14:32. That range is a superset, so it must be reported as one:
        printing it as the population described 549 runs and 201 CI runs where the window holds
        531 and 192.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Runs,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $End
    )

    $byName = @{}
    $inWindow = 0
    foreach ($run in $Runs) {
        $created = Get-RecordTimestamp -Record $run
        if (-not $created) { continue }
        if ($created -lt $Start -or $created -ge $End) { continue }
        $inWindow++
        $name = [string](Get-RecordProperty -Record $run -Name 'name')
        if (-not $byName.ContainsKey($name)) { $byName[$name] = 0 }
        $byName[$name]++
    }

    return @{
        Returned = $Runs.Count
        InWindow = $inWindow
        ByName   = $byName
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
    foreach ($directory in ($directories | Sort-Object -Property FullName)) {
        foreach ($file in (Get-ChildItem -LiteralPath $directory.FullName -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object -Property FullName)) {
            $candidates.Add($file.FullName)
        }
    }
    # Sorted, because Get-ChildItem does not promise an order across hundreds of files and a
    # message copied into two transcripts takes its session from whichever came first.
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
    $unit = switch ($metric) {
        'directory-bound-commands' { 'command lines' }
        'cleanup-events' { 'log lines' }
        default { 'messages' }
    }
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
$population = Get-RunPopulationSummary -Runs $runs -Start $script:WindowStart -End $script:WindowEnd
Write-Host "  workflow runs returned by the API for the calendar range: $($population.Returned)"
Write-Host "  of those, inside the window: $($population.InWindow)"
foreach ($entry in ($population.ByName.GetEnumerator() | Sort-Object Value -Descending)) {
    Write-Host "    $($entry.Value) $($entry.Key)"
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

$classified = $ci.NonDotnetRuns + $ci.DotnetRuns
Write-Host "ci-minutes on non-.NET changes : $($ci.NonDotnetMinutes) minutes across $($ci.NonDotnetRuns) run(s)"
Write-Host "  in-window CI runs : $($ci.Rows.Count), of which $classified classified"
Write-Host "  in-window runs of another workflow, not counted : $($ci.OtherWorkflows)"
Write-Host "  runs that touch .NET files : $($ci.DotnetRuns)"
Write-Host "  non-.NET runs whose pull request changed no file : $($ci.NoFileChange)"
Write-Host "  runs outside the window : $($ci.OutOfWindow)"
Write-Host "  repeated run ids skipped : $($ci.DuplicateIds)"
# Not 'absent from this clone'. Every in-window head_sha was present on 2026-08-16; these are
# heads with no landing merge on origin/main's first-parent chain, which is a different fact.
Write-Host "  runs with no base on main's first-parent chain, so unresolved : $($ci.Unresolved)"
Write-Host "  runs counted with no duration : $($ci.MissingTiming)   timing calls that failed : $timingFailures"
Write-Host "  ledger : $ciLedger"
Write-Host ''
