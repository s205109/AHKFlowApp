#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that a shipped plan or spec has been frozen against the citation check.

.DESCRIPTION
    A plan records the tree as it was when the work was planned. Once the item ships, re-auditing
    its citations against a tree that has moved reports rot nobody should repair. Stage 9 of
    docs/development/workflow.md therefore freezes the plan and spec with a file-level
    citation-check:ignore-file directive. This checks that it happened.

    Without this, the debt grows back one shipped item at a time, which is how backlog 112 started:
    18 shipped files held 180 canonical citations, and 52 of them had already gone stale.

    Archived means "no open backlog item carries this number". A plan file name does not reliably
    name the item that shipped it: 2026-08-17-personal-plans-home-plan-105.md says 105, and item
    107 shipped that work. The open set is exact, so the rule reads that instead.

    Only a file holding at least one canonical citation is asked to freeze. A legacy citation is
    never read by tier 2, so a legacy-only plan cannot rot into a failure, and demanding a freeze
    would mean editing 250 old plans for nothing.

.PARAMETER PlansRoot
    The plans repository. Its plans/ and specs/ folders are scanned.

.PARAMETER BacklogRoot
    The backlog folder. Its own files and blocked/ are the open set.

.PARAMETER AsModule
    Dot-source the functions and return, without running the check.

.EXAMPLE
    pwsh ./scripts/check-archived-plan-frozen.ps1
#>
[CmdletBinding()]
param(
    [string] $PlansRoot,
    [string] $BacklogRoot,
    [switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'citation-freshness.common.ps1')

# Every backlog number with an item still in play. blocked/ counts: that work is paused, not done,
# and its plan still makes live claims.
function Get-OpenBacklogNumber {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $open = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($folder in @($BacklogRoot, (Join-Path $BacklogRoot 'blocked'))) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.md' -File)) {
            if ($file.Name -match '^(\d{3})-') { [void] $open.Add($Matches[1]) }
        }
    }
    # The comma is not cosmetic. PowerShell unrolls any IEnumerable it returns, so a bare
    # `return $open` hands back $null for an empty set and a plain object[] for a full one. The
    # caller would then throw on an empty backlog, and silently lose case-insensitive matching on
    # a full one, because object[].Contains is ordinal.
    return , $open
}

function Get-UnfrozenArchivedPlan {
    param(
        [Parameter(Mandatory)][string] $PlansRoot,
        [Parameter(Mandatory)][string] $BacklogRoot
    )

    $open = Get-OpenBacklogNumber -BacklogRoot $BacklogRoot
    $unfrozen = [System.Collections.Generic.List[string]]::new()

    foreach ($sub in @('plans', 'specs')) {
        $folder = Join-Path $PlansRoot $sub
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.md' -File)) {
            # A name with no trailing number belongs to no open item, so it is archived by
            # definition. Most of the old plans are in that shape.
            if ($file.Name -match '-(\d{3})\.md$' -and $open.Contains($Matches[1])) { continue }

            $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
            if (Test-CitationIgnoreFile -Lines $lines) { continue }

            $canonical = 0
            foreach ($line in $lines) {
                foreach ($citation in (Get-CitationOnLine -Line $line)) {
                    if ($citation.Kind -eq 'Canonical') { $canonical++ }
                }
            }
            if ($canonical -eq 0) { continue }

            $unfrozen.Add(('{0}/{1}' -f $sub, $file.Name))
        }
    }

    return $unfrozen
}

if ($AsModule) { return }

if (-not $PlansRoot) { $PlansRoot = Join-Path $repoRoot 'docs/superpowers' }
if (-not $BacklogRoot) { $BacklogRoot = Join-Path $repoRoot 'backlog' }

$unfrozen = @(Get-UnfrozenArchivedPlan -PlansRoot $PlansRoot -BacklogRoot $BacklogRoot)

if ($unfrozen.Count -gt 0) {
    ''
    'These files hold canonical citations, and no open backlog item owns them:'
    foreach ($path in $unfrozen) { "  $path" }
    ''
    'Freeze each one. Put these two lines at the top, above the heading:'
    ''
    '  <!-- citation-check:ignore-file -->'
    '  <!-- Frozen: the work this file planned has shipped, so its citations record the tree as it was, not a claim about the tree as it is. See docs/development/workflow.md stage 9. -->'
    ''
    'Stage them by name. The plans repository is a shared working tree, so adding a whole folder'
    'commits whatever another session has open in it.'
    ''
    "RESULT: $($unfrozen.Count) shipped plan or spec still open to the citation check."
    exit 1
}

"RESULT: every shipped plan and spec is frozen. Scanned $PlansRoot against $BacklogRoot."
