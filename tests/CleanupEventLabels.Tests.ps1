#Requires -Version 7.0

# The cleanup event ledger and its labels are two files that must stay paired. Backlog 103
# labelled the 18 rows; without this suite the labelled file is something nothing checks, and
# the next edit to either file breaks the pairing in silence.
#
# It reads committed files only. The labelling script needs the machine-local transcripts under
# ~/.claude/projects, so it cannot run in CI - but its output can be checked anywhere.
#
# Run it by hand with:  pwsh ./tests/CleanupEventLabels.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$ledgerPath = Join-Path $repoRoot 'docs/development/friction-samples/ledgers/cleanup-events.csv'
$labelledPath = Join-Path $repoRoot 'docs/development/friction-samples/cleanup-events-labelled.csv'
$rulePath = Join-Path $repoRoot 'docs/development/cleanup-event-identity.md'

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

# --- The three files exist ---

Assert-True (Test-Path -LiteralPath $ledgerPath) "The frozen ledger is missing: $ledgerPath"
Assert-True (Test-Path -LiteralPath $labelledPath) "The labelled file is missing: $labelledPath"
Assert-True (Test-Path -LiteralPath $rulePath) "The rule sheet is missing: $rulePath"

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
    throw "Cleanup event label tests failed with $($failures.Count) problem(s). See the detail above."
}

$ledger = @(Import-Csv -LiteralPath $ledgerPath)
$labelled = @(Import-Csv -LiteralPath $labelledPath)

function Assert-Schema {
    <#
    .SYNOPSIS
        A committed artifact's columns, in order.
    .DESCRIPTION
        Every check below reads columns by name. A renamed or dropped column would make those
        checks read $null and pass, so the schema is asserted before anything reads it.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Rows,
        [Parameter(Mandatory)][string[]] $Expected,
        [Parameter(Mandatory)][string] $What
    )

    if ($Rows.Count -eq 0) {
        Assert-True $false "$What has no rows, so its schema cannot be checked."
        return
    }
    $actual = @($Rows[0].PSObject.Properties.Name)
    Assert-True (($actual -join ',') -eq ($Expected -join ',')) `
        "$What schema changed. Expected '$($Expected -join ',')', got '$($actual -join ',')'."
}

# --- 1. Both files have the schema every check below reads ---

Assert-Schema -Rows $ledger -What 'The frozen ledger' -Expected @(
    'Key', 'Session', 'Timestamp', 'Type', 'Matched', 'Line')
Assert-Schema -Rows $labelled -What 'The labelled file' -Expected @(
    'Key', 'Session', 'Route', 'EventStamp', 'MessageStamp', 'InCurrentLog', 'CheckedOn',
    'IsGenuineLogLine', 'Matched', 'Line')

# --- 2. Every ledger row is labelled, paired on its whole identity ---

Assert-True ($labelled.Count -eq $ledger.Count) `
    "The labelled file has $($labelled.Count) rows and the ledger has $($ledger.Count). They must pair one to one."

# Pair on Key and Line together, not on Line alone. One key carries several lines and one line
# appears under several keys, so matching on either half lets a row swap its key and still pass.
function Get-RowIdentity {
    param([Parameter(Mandatory)] $Row)
    return "$([string]$Row.Key)|$(([string]$Row.Line).TrimEnd())"
}

$labelledIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($row in $labelled) {
    $identity = Get-RowIdentity -Row $row
    Assert-True ($labelledIdentities.Add($identity)) `
        "The labelled file holds the same key and line twice: $identity"
}

foreach ($row in $ledger) {
    Assert-True ($labelledIdentities.Contains((Get-RowIdentity -Row $row))) `
        "A ledger row has no labelled row with the same key and line: $(Get-RowIdentity -Row $row)"
}

# The ledger is frozen and its rows are distinct events. A repeat means the same event was
# counted twice, which is the defect backlog 103 was filed against.
$ledgerIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($row in $ledger) {
    Assert-True ($ledgerIdentities.Add((Get-RowIdentity -Row $row))) `
        "The frozen ledger holds the same key and line twice: $(Get-RowIdentity -Row $row)"
}

# Every Key must be an identity the labeller can look up. Get-MessageKey also writes a 'text:'
# fallback, and a row carrying one can never be resolved to a record.
foreach ($row in $labelled) {
    Assert-True ([string]$row.Key -match '^(?:msg|uuid):.+$') `
        "A Key names no record. Only 'msg:' and 'uuid:' can be looked up: '$($row.Key)'"
}

# --- 3. Route is decided on every row, and the published split still holds ---

# 'unresolved' means the script could not find the record. It is a real output of the labelling
# script and it must never survive into the committed file: an unresolved row is a row nobody
# labelled.
$allowedRoutes = @('tool-result', 'human-paste')
foreach ($row in $labelled) {
    $route = [string]$row.Route
    Assert-True ([bool]$route) "A row has an empty Route: $($row.Line)"
    Assert-True ($allowedRoutes -contains $route) `
        "Route must be 'tool-result' or 'human-paste', not '$route': $($row.Line)"
}

# The ledger is frozen, so these two totals are fixed. They are the figures backlog 072, backlog
# 103 and friction-recall-sample.md all publish, and a change to either without a change to
# those documents would leave the published split describing data that no longer exists.
$expectedRouteTotals = @{ 'tool-result' = 14; 'human-paste' = 4 }
foreach ($route in ($expectedRouteTotals.Keys | Sort-Object)) {
    $actual = @($labelled | Where-Object { [string]$_.Route -eq $route }).Count
    Assert-True ($actual -eq $expectedRouteTotals[$route]) `
        "The published split is $($expectedRouteTotals[$route]) '$route' rows. The file has $actual."
}

# --- 4. The one hand-written column says the line is genuine, on every row ---

# Not 'is filled in'. The published claim is that all 18 rows are genuine log lines, so a row
# reading 'no' would withdraw that claim in silence while this suite stayed green.
foreach ($row in $labelled) {
    Assert-True ([string]$row.IsGenuineLogLine -eq 'yes') `
        ("IsGenuineLogLine must read 'yes'. It reads '$($row.IsGenuineLogLine)' for: $($row.Line). " +
        'The published result is that every row is a genuine log line; a row that is not ' +
        'withdraws that claim, and the documents that quote it have to change with it.')
}

# --- 5. The rule sheet's overlap arithmetic matches the data ---

# The witnessed rows are NOT a subset of the log's in-window rows. Three of the 18 are stamped
# before the log's earliest surviving line, so they are in the window but not in the log. An
# earlier draft wrote "the transcripts witnessed 18 of the 201", which silently counted three
# rows the denominator does not hold. The numbers below are computed from the two committed
# CSVs, so this check follows the data rather than repeating a figure.
$ruleText = Get-Content -LiteralPath $rulePath -Raw
$logLedgerPath = Join-Path $repoRoot 'docs/development/friction-samples/ledgers/cleanup-log-events.csv'
Assert-True (Test-Path -LiteralPath $logLedgerPath) "The log ledger is missing: $logLedgerPath"

if (Test-Path -LiteralPath $logLedgerPath) {
    $logLedger = @(Import-Csv -LiteralPath $logLedgerPath)
    $logLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $logLedger) { [void]$logLines.Add(([string]$row.Line).TrimEnd()) }

    $witnessedInLog = @($labelled | Where-Object { $logLines.Contains(([string]$_.Line).TrimEnd()) }).Count
    $unwitnessedInLog = $logLedger.Count - $witnessedInLog

    # Match against whitespace-normalised text. These phrases are prose and they wrap, so a
    # check that forbids a line break would fail on reflowing rather than on a wrong number.
    $ruleFlat = ($ruleText -replace '\s+', ' ')

    Assert-True ($ruleFlat -match "$witnessedInLog of the $($labelled.Count)") `
        "The rule sheet must say that $witnessedInLog of the $($labelled.Count) witnessed rows are among the log's in-window lines."
    Assert-True ($ruleFlat -match "$unwitnessedInLog of the $($logLedger.Count)") `
        "The rule sheet must say that $unwitnessedInLog of the $($logLedger.Count) log lines reached no transcript."
    Assert-True ($ruleFlat -notmatch "witnessed $($labelled.Count) of them") `
        "The rule sheet claims the transcripts witnessed all $($labelled.Count) rows out of the log's in-window lines. Only $witnessedInLog of them are in that set."
}

# --- 6. The decision stays a floor ---

# The whole point of backlog 103 is that 18 is a floor and not an upper bound. A later edit that
# quietly restores 'upper bound' would put the withdrawn claim back into the documentation.
Assert-True ($ruleText -match 'floor') `
    "The rule sheet no longer contains the word 'floor'. The decision is that the count is a floor."

# --- 7. The rule sheet still names the unit ---

# 201 and 204 are counts of outcome log lines, never of cleanup runs. One removal writes several
# lines, so the two units differ by more than a factor of two, and the earlier wording called
# them 'popups and blocked runs'.
if (Test-Path -LiteralPath $logLedgerPath) {
    $logLedger = @(Import-Csv -LiteralPath $logLedgerPath)
    $startedCount = @($logLedger | Where-Object { ([string]$_.Line) -match 'Watcher started\.' }).Count

    Assert-True (($ruleText -replace '\s+', ' ') -match 'not a count of cleanup runs') `
        "The rule sheet must say the figure is not a count of cleanup runs. One removal writes several lines."
    Assert-True (($ruleText -replace '\s+', ' ') -match "$startedCount of the $($logLedger.Count)") `
        ("The rule sheet must say that $startedCount of the $($logLedger.Count) log lines are " +
        "'Watcher started.', which is what shows the unit is a line and not a run.")
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Cleanup event label tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host "Cleanup event label tests passed. $($labelled.Count) labelled rows checked against the ledger."
