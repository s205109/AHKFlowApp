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

# --- 1. Every ledger row is labelled, and no row was invented ---

Assert-True ($labelled.Count -eq $ledger.Count) `
    "The labelled file has $($labelled.Count) rows and the ledger has $($ledger.Count). They must pair one to one."

$labelledLines = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($row in $labelled) { [void]$labelledLines.Add([string]$row.Line) }

foreach ($row in $ledger) {
    Assert-True ($labelledLines.Contains([string]$row.Line)) `
        "A ledger line has no labelled row: $($row.Line)"
}

# --- 2. Route is decided on every row, and only from the two mechanical values ---

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

# --- 3. The one hand-written column is filled in on every row ---

foreach ($row in $labelled) {
    Assert-True ([bool][string]$row.IsGenuineLogLine) `
        "A row has no IsGenuineLogLine. That column is the only judgment in the file: $($row.Line)"
}

# --- 4. The decision stays a floor ---

# The whole point of backlog 103 is that 18 is a floor and not an upper bound. A later edit that
# quietly restores 'upper bound' would put the withdrawn claim back into the documentation.
$ruleText = Get-Content -LiteralPath $rulePath -Raw
Assert-True ($ruleText -match 'floor') `
    "The rule sheet no longer contains the word 'floor'. The decision is that the count is a floor."

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
