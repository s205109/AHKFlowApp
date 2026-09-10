#Requires -Version 7.0
<#
.SYNOPSIS
    Fails a ready pull request that finishes a backlog item without closing its records.

.DESCRIPTION
    Backlog 151. Pull request #400 merged all of backlog 132's work on 2026-09-10. The branch
    ticked all five Acceptance boxes and wrote its measurements into the item. It left the Stage
    line at '4-execute' and never moved the file into backlog/done/. Three checks sat near the
    problem and every one of them missed, because all three read the Stage line, and the Stage
    line was what never moved.

    THE INVARIANT IS TWO CONDITIONS HELD TOGETHER:

      1. The pull request is not a draft.
      2. Every Acceptance box in the item is ticked, and the item still sits in backlog/.

    Neither condition works alone, and each one blocks a different wrong report:

      | Situation                     | Boxes         | Draft | Verdict             |
      |-------------------------------|---------------|-------|---------------------|
      | Partial delivery, PR 1 of 3   | some unticked | ready | passes, boxes open  |
      | Document-to-Ship window       | all ticked    | draft | passes, still draft |
      | Backlog 132                   | all ticked    | ready | fails, correct      |

    Box state alone would refuse the Document-to-Ship window. workflow.md ticks the boxes at
    Document and moves the file at Ship, so between those two stages an item legitimately has
    every box ticked and still sits in backlog/. A check that refused that state would be
    switched off inside a week.

    Ready state alone would refuse every pull request but the last of a multi-pull-request item.
    That is the candidate BACKLOG 106 ALREADY REJECTED. Read backlog 106's rejections before
    proposing any change to this rule.

    STATED ASSUMPTION. This rule is correct only because this repository opens pull requests as
    drafts and flips them to ready at Ship. workflow.md stage 1 makes that the route. A pull
    request opened ready from the start would be refused at Document time. That is an assumption
    about the process, not a fact about GitHub, and it is the first thing to check when a refusal
    here looks wrong.

    Every backlog read comes from a commit, never from the working tree. A pull request carries
    commits, and an uncommitted edit must not decide whether a committed record is judged. This
    is why backlog.common.ps1 is not dot-sourced here, for the same reason
    check-shipped-plan-ticked.ps1 does not dot-source it.

    The plan and spec freeze is NOT checked here. check-archived-plan-frozen.ps1 already owns it,
    and CI cannot see docs/superpowers at all.

.PARAMETER RepoRoot
    The repository root. Defaults to the parent of this script's folder.

.PARAMETER MergeBase
    The commit to compare against.

.PARAMETER TargetCommit
    The pull request head. Every backlog read comes from this commit.

.PARAMETER PullRequestIsDraft
    Whether the pull request is still a draft. Supplied by the caller, never read here: the draft
    state lives in the GitHub event, and a parameter is what lets a fixture drive both values.

.PARAMETER AsModule
    Dot-source the functions and return, without running the check.

.EXAMPLE
    pwsh ./scripts/check-shipping-pr-closes-item.ps1 -MergeBase abc123 -TargetCommit def456 -PullRequestIsDraft $false
#>
[CmdletBinding()]
param(
    [string] $RepoRoot,
    [string] $MergeBase = '',
    [string] $TargetCommit = '',
    [bool] $PullRequestIsDraft = $false,
    [switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootDefault = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'backlog-acceptance.common.ps1')

# -AsModule gives us the commit-based backlog readers without running that check:
# Get-BranchBacklogCandidate, and through worktree-git.common.ps1 the two snapshot readers.
#
# The commit-based item finder, plus the two snapshot readers it dot-sources in turn.
#
# This is a *.common.ps1 with no param block, so it cannot collide with this script's own
# parameters. Dot-sourcing check-shipped-plan-ticked.ps1 instead would wipe RepoRoot, MergeBase
# and TargetCommit to empty strings, because those are its parameter names too. Backlog 151's
# Task 2 moved the function here for that reason.
. (Join-Path $PSScriptRoot 'backlog-snapshot.common.ps1')

function Get-ShippingPrProblem {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase,
        [Parameter(Mandatory)][string] $TargetCommit,
        [Parameter(Mandatory)][bool] $PullRequestIsDraft
    )

    # Condition 1. A draft pull request is work in progress, and the Document-to-Ship window
    # legitimately has every box ticked with the item still open.
    if ($PullRequestIsDraft) { return @() }

    $problems = @()

    $candidate = @(Get-BranchBacklogCandidate -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
    if ($candidate.Count -eq 0) { return @() }

    $target = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $TargetCommit
    if ($target.Status -ne 'ok') {
        return @("The pull request head '$TargetCommit' $($target.Detail), so which items it closes is unknown.")
    }

    foreach ($record in $candidate) {
        $number = $record.Number

        $targetPattern = '^backlog/(done/|blocked/)?' + [regex]::Escape($number) + '-[^/]*\.md$'
        $targetPaths = @(@($target.Paths) | Where-Object { $_ -match $targetPattern })

        # No file, or two files claiming the number. The backlog numbering check owns both, and
        # this must not report them a second time.
        if ($targetPaths.Count -ne 1) { continue }
        $path = ($targetPaths[0] -replace '\\', '/')

        # The template carries placeholder boxes and is never a piece of work.
        if ((Split-Path -Leaf $path) -eq '000-backlog-item-template.md') { continue }

        # A finished item and a parked item are both meant to sit still. This is what keeps a
        # branch that only fixes a typo in a closed item out of the report.
        if ($path -notmatch '^backlog/[^/]+\.md$') { continue }

        $lines = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $target -ItemNumber $number
        if ($lines.Status -ne 'found') { continue }

        # Condition 2. An item with no boxes is vacuously finished, and firing on it would be
        # wrong, so Total must be greater than zero before the comparison means anything.
        $count = Get-AcceptanceBoxCount -Lines $lines.Lines
        if ($count.Total -eq 0) { continue }
        if ($count.Ticked -ne $count.Total) { continue }

        # The Stage is REPORTED, never decided on. An item sitting in backlog/ has its records
        # open whatever its Stage says, and an item reading '9-ship' while still in backlog/ is
        # already the stale-open check's arm 2. Printing it just helps whoever reads the failure.
        $stage = Get-SingleBacklogStage -Lines $lines.Lines
        if (-not $stage) { $stage = '(none, or more than one)' }

        $problems += @"
Backlog $number has every acceptance box ticked and is still open in backlog/.
  File:  $path
  Stage: $stage
  Boxes: $($count.Ticked) of $($count.Total) ticked
  Fix:   close it - set 'Stage: 9-ship' and 'git mv' it into backlog/done/, in one commit.
         If the work is not finished, untick the box that is not true and say why in the item.
"@
    }

    # The progress file is its own problem line. Stage 9 deletes it, and the housekeeping round
    # that closed backlog 132 missed exactly this part, so it is worth naming on its own.
    if ($problems.Count -gt 0) {
        $listed = & git -C $RepoRoot ls-tree -r --name-only $TargetCommit -- PLAN-PROGRESS.md 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($listed -join ''))) {
            $problems += @"
PLAN-PROGRESS.md is still tracked in this pull request.
  Fix:   delete it in the same commit that closes the records. Stage 9 requires it.
"@
        }
    }

    return @($problems)
}

if ($AsModule) { return }

if (-not $RepoRoot) { $RepoRoot = $repoRootDefault }
if (-not $MergeBase -or -not $TargetCommit) {
    Write-Host 'Both -MergeBase and -TargetCommit are required.'
    exit 1
}

$found = @(Get-ShippingPrProblem -RepoRoot $RepoRoot -MergeBase $MergeBase `
    -TargetCommit $TargetCommit -PullRequestIsDraft $PullRequestIsDraft)

if ($found.Count -eq 0) {
    Write-Host 'This pull request closes the records of every item it finishes.'
    exit 0
}

foreach ($problem in $found) { Write-Host ''; Write-Host $problem }
Write-Host ''
Write-Host "Found $($found.Count) problem(s). See docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md for the rule."
exit 1
