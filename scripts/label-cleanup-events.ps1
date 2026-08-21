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
    and it computes it from record fields, never from reading the text:

      tool-result   the record has a toolUseResult field
      human-paste   promptSource is 'typed', or origin.kind is 'human'
      unresolved    the record was not found

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
function Get-SessionRecord {
    param(
        [Parameter(Mandatory)][string] $SessionFile,
        [Parameter(Mandatory)][string] $Uuid
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
                # from one. Indexing them would let a sidechain record win the uuid and hand back
                # the wrong route. The measurement script drops them the same way.
                if ((Get-RecordProperty -Record $record -Name 'isSidechain') -eq $true) { continue }

                $id = Get-RecordProperty -Record $record -Name 'uuid'
                if (-not $id) { continue }
                $id = [string]$id

                # One session file name can appear under more than one project directory. First
                # one read wins, which is arbitrary, so say when the choice was ever made rather
                # than resolving it in silence.
                if ($index.ContainsKey($id)) {
                    Write-Warning "uuid $id appears more than once under $SessionFile. Keeping the first record read."
                    continue
                }
                $index[$id] = $record
            }
        }
        $recordBySession[$SessionFile] = $index
    }

    $byUuid = $recordBySession[$SessionFile]
    if ($byUuid.ContainsKey($Uuid)) { return $byUuid[$Uuid] }
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

$labelled = foreach ($row in $rows) {
    $uuid = if ($row.Key -match '^uuid:(?<id>.+)$') { $Matches['id'] } else { '' }
    $record = if ($uuid) { Get-SessionRecord -SessionFile $row.Session -Uuid $uuid } else { $null }
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
Write-Host "  checked on        : $checkedOn"
Write-Host ''
foreach ($group in ($labelled | Group-Object Route | Sort-Object Name)) {
    Write-Host ("  route {0,-12} {1,3}" -f $group.Name, $group.Count)
}
foreach ($group in ($labelled | Group-Object InCurrentLog | Sort-Object Name)) {
    Write-Host ("  in log {0,-12} {1,3}" -f $group.Name, $group.Count)
}

$missing = @($labelled | Where-Object { -not $_.IsGenuineLogLine })
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Warning "$($missing.Count) row(s) have no IsGenuineLogLine yet. Fill that column in by hand."
}
