#Requires -Version 7.0
<#
.SYNOPSIS
    Labels every row of the cleanup event ledger with the route its line took into a transcript.
.DESCRIPTION
    Backlog 103 asked whether the 18 published cleanup rows are reported events or quoted ones.
    The labelling answered a different question, because that split does not exist: a tool
    result is a read of worktree-removal.log, and so is a human paste. Both carry the line's
    own stamp, which is the event time. See docs/development/cleanup-event-identity.md.

    So this script computes the split that does survive - how the line entered the transcript -
    and it computes it from record fields, never from reading the text. The first rule that
    matches wins:

      tool-result   the record has a toolUseResult field
      human-paste   Test-HumanTurn says so: type is 'user', and either origin.kind is 'human'
                    or promptSource is 'typed', 'suggestion_accepted' or 'queued'
      unresolved    neither rule matched, or no record answers to the row's Key

    A row's Key is the identity the metric wrote for its record: msg:<message.id> when the
    record carries a message id, uuid:<uuid> otherwise. Both are looked up.

    One column is not computed here. IsGenuineLogLine is filled in by hand, and a re-run
    carries the existing value forward rather than blanking it.

    This is a one-shot, like measure-process-friction.ps1. It reads session transcripts under
    ~/.claude/projects, which are machine-local, so no CI job runs it.
.PARAMETER ProjectRoot
    Where the session transcripts live. Defaults to ~/.claude/projects.
.PARAMETER LedgerPath
    The frozen ledger to label. Defaults to the committed cleanup-events.csv.
.PARAMETER OutputPath
    Where the labelled rows are written. Defaults to the committed cleanup-events-labelled.csv.
.PARAMETER LogPath
    The removal log, used only for the InCurrentLog snapshot. Defaults to the copy under the
    main checkout, which is the only copy: a worktree has no .claude/worktrees directory.
#>
[CmdletBinding()]
param(
    [string] $ProjectRoot,
    [string] $LedgerPath,
    [string] $OutputPath,
    [string] $LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# Copy every parameter out before dot-sourcing. measure-process-friction.ps1 has a ProjectRoot
# parameter of its own, and dot-sourcing binds it - which overwrites the value passed here.
# Its own help warns about exactly this, which is why its clone parameter is not called
# RepoRoot.
$sessionRoot = $ProjectRoot
$ledger = $LedgerPath
$output = $OutputPath
$removalLog = $LogPath

# Reuse the measurement script's record helpers rather than copying them. Two copies of one
# rule is how this metric went wrong before.
. (Join-Path $PSScriptRoot 'measure-process-friction.ps1') -AsModule

function Resolve-RemovalLogPath {
    <#
    .SYNOPSIS
        The removal log under the main checkout.
    .DESCRIPTION
        The log lives at <main>/.claude/worktrees/worktree-removal.log and nowhere else. A
        worktree holds no .claude/worktrees directory, so a path built from $PSScriptRoot
        resolves to a file that does not exist, and every row would read as absent. The common
        git directory is the main checkout's .git in a worktree as well as in the checkout.
    #>
    param([Parameter(Mandatory)][string] $FromRepo)

    $common = & git -C $FromRepo rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $common) {
        throw "Could not resolve the main checkout from $FromRepo. Pass -LogPath instead."
    }
    $main = Split-Path -Parent ([string]$common).Trim()
    return (Join-Path $main '.claude/worktrees/worktree-removal.log')
}

if (-not $sessionRoot) { $sessionRoot = Join-Path $HOME '.claude/projects' }
if (-not $ledger) { $ledger = Join-Path $repoRoot 'docs/development/friction-samples/ledgers/cleanup-events.csv' }
if (-not $output) { $output = Join-Path $repoRoot 'docs/development/friction-samples/cleanup-events-labelled.csv' }
if (-not $removalLog) { $removalLog = Resolve-RemovalLogPath -FromRepo $repoRoot }

if (-not (Test-Path -LiteralPath $ledger)) { throw "Ledger not found: $ledger" }
if (-not (Test-Path -LiteralPath $sessionRoot)) { throw "Transcript root not found: $sessionRoot" }

$rows = @(Import-Csv -LiteralPath $ledger)
Write-Host "Ledger      : $ledger ($($rows.Count) rows)"
Write-Host "Transcripts : $sessionRoot"
Write-Host "Removal log : $removalLog"

# The log is a snapshot and it rotates, so InCurrentLog carries its own date rather than
# pretending to be a property of the row.
$checkedOn = (Get-Date).ToString('yyyy-MM-dd')
$logLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
if (Test-Path -LiteralPath $removalLog) {
    foreach ($line in (Get-Content -LiteralPath $removalLog)) { [void]$logLines.Add($line.TrimEnd()) }
    Write-Host "              $($logLines.Count) distinct lines read"
}
else {
    Write-Warning "Removal log not found; every InCurrentLog will read 'unknown'."
}

# A hand-written column survives a re-run. Blanking it would throw away the only judgment in
# the file, and the suite would then fail on the script's own output.
$carried = @{}
if (Test-Path -LiteralPath $output) {
    foreach ($old in (Import-Csv -LiteralPath $output)) {
        $existing = Get-RecordProperty -Record $old -Name 'IsGenuineLogLine'
        if ($existing) { $carried["$($old.Key)|$($old.Line)"] = [string]$existing }
    }
}

# One index per session file, built once. Seven records are wanted across five sessions, and
# each transcript is thousands of lines.
$recordBySession = @{}

# A message id is shared by every fragment of one message, so a repeat is the normal case and
# not a conflict. Counting them keeps the count visible without burying a real clash: on the
# committed ledger there are 291 such repeats and no repeated uuid.
$script:FragmentRepeats = 0
function Get-SessionRecord {
    <#
    .SYNOPSIS
        The record a ledger Key names, from the session file that carries it.
    .DESCRIPTION
        Get-MessageKey in measure-process-friction.ps1 writes 'msg:<message.id>' when the record
        carries a message id and 'uuid:<uuid>' otherwise, so a ledger holds both kinds. Indexing
        uuids alone marked every 'msg:' row 'unresolved', which reads as a missing record rather
        than as a key this script never looked for.
    #>
    param(
        [Parameter(Mandatory)][string] $SessionFile,
        [Parameter(Mandatory)][string] $Identity
    )

    if (-not $recordBySession.ContainsKey($SessionFile)) {
        $index = @{}
        $found = @(Get-ChildItem -LiteralPath $sessionRoot -Filter $SessionFile -File -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $found) {
            foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
                if (-not $line.Trim()) { continue }
                $record = try { $line | ConvertFrom-Json } catch { $null }
                if (-not $record) { continue }

                # Subagent records are excluded from the measurement, so no ledger row can come
                # from one. Indexing them would let a sidechain record win the identity and hand
                # back the wrong route. The measurement script drops them the same way.
                if ((Get-RecordProperty -Record $record -Name 'isSidechain') -eq $true) { continue }

                # Both identity kinds, keyed exactly as the ledger writes them. A record can
                # answer to both, and indexing both is what lets one ledger hold a mix.
                $identities = New-Object System.Collections.Generic.List[string]
                $message = Get-RecordProperty -Record $record -Name 'message'
                $messageId = Get-RecordProperty -Record $message -Name 'id'
                if ($messageId) { $identities.Add("msg:$messageId") }
                $uuid = Get-RecordProperty -Record $record -Name 'uuid'
                if ($uuid) { $identities.Add("uuid:$uuid") }

                # Not $identity: PowerShell variable names are case-insensitive, so a loop
                # variable by that name is the $Identity parameter, and the loop would leave the
                # lookup below asking for the last key indexed instead of the one requested.
                foreach ($indexKey in $identities) {
                    if (-not $index.ContainsKey($indexKey)) {
                        $index[$indexKey] = $record
                        continue
                    }

                    # First record read wins either way, which is what ConvertTo-LogicalMessage
                    # in measure-process-friction.ps1 does with the fields it keeps per key.
                    if ($indexKey.StartsWith('msg:')) {
                        # Every fragment of one message carries that message's id. This is the
                        # rule working, so count it rather than warning 291 times.
                        $script:FragmentRepeats++
                        continue
                    }

                    # A repeated uuid is a real clash. One session file name can appear under
                    # more than one project directory, so say when the choice was made rather
                    # than resolving it in silence.
                    Write-Warning "$indexKey appears more than once under $SessionFile. Keeping the first record read."
                }
            }
        }
        $recordBySession[$SessionFile] = $index
    }

    $byIdentity = $recordBySession[$SessionFile]
    if ($byIdentity.ContainsKey($Identity)) { return $byIdentity[$Identity] }
    return $null
}

function Format-RecordStamp {
    <#
    .SYNOPSIS
        A record timestamp as a culture-independent ISO 8601 string.
    #>
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('o', [cultureinfo]::InvariantCulture) }

    $text = [string]$Value
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        return $parsed.ToString('o', [cultureinfo]::InvariantCulture)
    }
    return $text
}

function Get-RecordRoute {
    <#
    .SYNOPSIS
        How the line entered the transcript, from record fields alone.
    #>
    param([AllowNull()] $Record)

    if ($null -eq $Record) { return 'unresolved' }
    if ($null -ne (Get-RecordProperty -Record $Record -Name 'toolUseResult')) { return 'tool-result' }
    if (Test-HumanTurn -Record $Record) { return 'human-paste' }
    return 'unresolved'
}

$unknownKeyKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$labelled = foreach ($row in $rows) {
    # 'msg:' and 'uuid:' are the two kinds Get-MessageKey writes for a record it can identify.
    # 'text:' is its fallback for a record with neither, and it is not an identity this script
    # can look up, so it is named rather than passed silently through as 'unresolved'.
    $key = [string]$row.Key
    $identity = if ($key -match '^(?:msg|uuid):.+$') { $key } else { '' }
    if (-not $identity) { [void]$unknownKeyKinds.Add(($key -split ':', 2)[0]) }
    $record = if ($identity) { Get-SessionRecord -SessionFile $row.Session -Identity $identity } else { $null }
    $line = $row.Line.TrimEnd()

    $inLog = if (-not (Test-Path -LiteralPath $removalLog)) { 'unknown' }
    elseif ($logLines.Contains($line)) { 'yes' }
    else { 'no' }

    [pscustomobject]@{
        Key              = $row.Key
        Session          = $row.Session
        Route            = Get-RecordRoute -Record $record
        EventStamp       = if ($line.Length -ge 19) { $line.Substring(0, 19) } else { '' }
        # ConvertFrom-Json turns an ISO timestamp into a [datetime], and casting that to a string
        # uses the current culture. A committed artifact must not change shape with the machine
        # that wrote it, so the round-trip format is written explicitly.
        MessageStamp     = if ($record) { Format-RecordStamp -Value (Get-RecordProperty -Record $record -Name 'timestamp') } else { '' }
        InCurrentLog     = $inLog
        CheckedOn        = $checkedOn
        IsGenuineLogLine = if ($carried.ContainsKey("$($row.Key)|$($row.Line)")) { $carried["$($row.Key)|$($row.Line)"] } else { '' }
        Matched          = $row.Matched
        Line             = $row.Line
    }
}
$labelled = @($labelled)

$labelled | Export-Csv -LiteralPath $output -NoTypeInformation -Encoding utf8

Write-Host ''
Write-Host "Labelled    : $output"
Write-Host "  rows              : $($labelled.Count)"
Write-Host "  distinct keys     : $(@($labelled.Key | Select-Object -Unique).Count)"
Write-Host "  distinct sessions : $(@($labelled.Session | Select-Object -Unique).Count)"
Write-Host "  message fragments : $script:FragmentRepeats repeat of an already-indexed message id"
Write-Host "  checked on        : $checkedOn"
Write-Host ''
foreach ($group in ($labelled | Group-Object Route | Sort-Object Name)) {
    Write-Host ("  route {0,-12} {1,3}" -f $group.Name, $group.Count)
}
foreach ($group in ($labelled | Group-Object InCurrentLog | Sort-Object Name)) {
    Write-Host ("  in log {0,-12} {1,3}" -f $group.Name, $group.Count)
}

if ($unknownKeyKinds.Count -gt 0) {
    $kinds = ($unknownKeyKinds | Sort-Object) -join ', '
    Write-Host ''
    Write-Warning ("Ledger key kinds that name no record: $kinds. Only msg: and uuid: can be " +
        'looked up, so those rows read Route=unresolved.')
}

$missing = @($labelled | Where-Object { -not $_.IsGenuineLogLine })
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Warning "$($missing.Count) row(s) have no IsGenuineLogLine yet. Fill that column in by hand."
}
