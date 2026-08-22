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

    Archived means "this worktree can see the item in backlog/done/", resolved through that item's
    '- Plan:' and '- Spec:' pointers first and its number second. A plan file name does not reliably
    name the item that shipped it: 2026-08-17-personal-plans-home-plan-105.md says 105, and item 107
    shipped that work.

    Anything the worktree cannot place is skipped, never treated as shipped. The plans repository is
    shared between worktrees while each backlog is not, so a plan for an item open on another branch
    simply has no item here. Reading that absence as "shipped" would demand a freeze on somebody
    else's live work and block their neighbour's push, which is the problem this whole item removes.

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

# What this worktree can PROVE has shipped: the numbers in backlog/done/, plus the plan and spec
# files those items name in their own '- Plan:' and '- Spec:' bullets.
#
# A pointer beats a file name, because the two disagree. Item 107 shipped the work in
# 2026-08-17-personal-plans-home-plan-105.md, and no item 105 ever existed.
#
# Read the pointer defensively rather than trusting it. Item 107's own bullet named a plan-107 file
# that never existed until pull request 341 repaired it, and while it was wrong this check could
# not place the real plan at all.
#
# The trailing number stays as the fall-back and carries most of the load: only 30 of the 104 items
# in backlog/done/ name a plan at all.
function Get-ShippedRecord {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $numbers = [System.Collections.Generic.HashSet[string]]::new()
    $files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $done = Join-Path $BacklogRoot 'done'
    if (Test-Path -LiteralPath $done -PathType Container) {
        foreach ($item in (Get-ChildItem -LiteralPath $done -Filter '*.md' -File)) {
            if ($item.Name -match '^(\d{3})-') { [void] $numbers.Add($Matches[1]) }

            foreach ($line in (Get-Content -LiteralPath $item.FullName -ErrorAction SilentlyContinue)) {
                if ($line -notmatch '^\s*-\s+(Plan|Spec):') { continue }
                # Take the file name out of a backticked path. 'none - <reason>' matches nothing.
                if ($line -match '`[^`]*/([^/`]+\.md)`') { [void] $files.Add($Matches[1]) }
            }
        }
    }

    # The comma is not cosmetic. PowerShell unrolls any IEnumerable it returns, and a pscustomobject
    # is safe, but the two sets inside it are handed out by reference and must not be re-wrapped.
    return , [pscustomobject]@{ Numbers = $numbers; Files = $files }
}

function Get-UnfrozenArchivedPlan {
    param(
        [Parameter(Mandatory)][string] $PlansRoot,
        [Parameter(Mandatory)][string] $BacklogRoot
    )

    $shipped = Get-ShippedRecord -BacklogRoot $BacklogRoot
    $unfrozen = [System.Collections.Generic.List[string]]::new()

    foreach ($sub in @('plans', 'specs')) {
        $folder = Join-Path $PlansRoot $sub
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.md' -File)) {
            # Archived means "this worktree can see the item in backlog/done/". Anything else is
            # unknown, and unknown is skipped - never read as shipped.
            #
            # The plans repository is one shared working tree, but each worktree carries only its
            # own branch's backlog. A plan written for an item that is open on another branch has
            # no item here at all. Reading that absence as "shipped" made this check demand a
            # freeze on somebody else's live work, which is the cross-worktree blocking backlog 112
            # exists to remove. Found in review on 2026-08-22, with item 113 already open on main
            # and invisible from this worktree.
            $isShipped = $shipped.Files.Contains($file.Name)
            if (-not $isShipped -and $file.Name -match '-(\d{3})\.md$') {
                $isShipped = $shipped.Numbers.Contains($Matches[1])
            }
            if (-not $isShipped) { continue }

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
