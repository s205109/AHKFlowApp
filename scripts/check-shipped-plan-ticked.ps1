#Requires -Version 7.0
<#
.SYNOPSIS
    Fails the push when this branch ships a backlog item whose plan has no ticked step.

.DESCRIPTION
    The worktree cleanup sweep already refuses to remove a worktree whose plan holds unticked steps
    and no ticked step. That rule is right, but it runs weeks after the work merges. Items 126 and
    129 both shipped with every plan step unticked, at 68 and 21 steps, and somebody added the ticks
    by hand long afterwards. The push is the cheap place to catch the next one.

    The verdict comes from Test-WorktreePlanWasImplemented in scripts/worktree-git.common.ps1, not
    from a second copy of the rule.

    Only items THIS BRANCH SHIPS are judged, never every item the branch touches. Six items sitting
    in backlog/done/ today would fail the tick rule. If the check judged every touched path, a
    branch that fixed a typo in one of them would have its push refused for debt it did not create,
    and the gate would be switched off inside a week.

    An item is shipped by this branch when both halves hold:

      - The commit being judged gives it exactly one '- **Stage**:' line, and that line reads
        '9-ship'. That commit is TargetCommit, and never the working tree: a push carries commits,
        so an uncommitted edit must not decide whether a committed record is judged.
      - The merge base does not already have it shipped. The base has it shipped when the base
        carries the item, its Stage line there also reads '9-ship', and its path there is already
        under backlog/done/. Any one of those three being false makes this branch the shipper.

    The second half is what closes the plain-rename case: a branch that only runs 'git mv' into
    backlog/done/, leaving the Stage line untouched at '9-ship', is still the branch that shipped
    the item, and is still judged.

    The base is looked up under the number the item carried IN THE BASE, which differs from its
    number now only across a renumber. An item's identity is the file, not the number, so a branch
    that renumbers an already-shipped item did not ship it. A branch that renumbers an item the base
    still holds open, and ships it in the same breath, did ship it and is judged.

    An item with no Stage line, or with more than one, is skipped. Those are already the business of
    the backlog numbering check, and this must not report them a second time.

    Only the never-implemented refusal fails the push. Every other refusal - an unreadable item, a
    plan pointer outside the plans folder, a plan file that is not there - is a real problem, but it
    is not this item's problem. Those print one diagnostic line and pass.

.PARAMETER RepoRoot
    The repository root. Defaults to the parent of this script's folder.

.PARAMETER MergeBase
    The commit to compare against. Defaults to the merge base of TargetCommit and origin/main.

.PARAMETER TargetCommit
    The commit being pushed. Defaults to HEAD. Every backlog read comes from this commit, never
    from the working tree: a push carries commits, and an uncommitted edit must not decide whether
    a committed record is judged. The plan file is the exception and still comes from disk.

.PARAMETER AsModule
    Dot-source the functions and return, without running the check.

.EXAMPLE
    pwsh ./scripts/check-shipped-plan-ticked.ps1
#>
[CmdletBinding()]
param(
    [string] $RepoRoot,
    [string] $MergeBase = '',
    [string] $TargetCommit = '',
    [switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootDefault = Split-Path -Parent $PSScriptRoot

# This file runs nothing on its own. It carries the plan verdict, the backlog snapshot readers, and
# the number pattern, which is everything this check needs.
#
# backlog.common.ps1 is deliberately NOT dot-sourced. Its Get-BacklogItem reads the working tree,
# and the working tree is exactly what this check must not read.
. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')

# Get-SingleBacklogStage, Get-BacklogNumberFromPath and Get-BranchBacklogCandidate moved here in
# backlog 151, so check-shipping-pr-closes-item.ps1 could share them. It cannot dot-source THIS
# file: this one has a param block, and dot-sourcing a script with a param block rebinds every
# parameter name into the caller's scope, wiping the caller's own RepoRoot, MergeBase and
# TargetCommit. A *.common.ps1 has no param block, so it is safe to share.
. (Join-Path $PSScriptRoot 'backlog-snapshot.common.ps1')

# The two-half rule, as plain data. No git, no files: this is the part a test can drive directly.
#
# An empty BasePath means the base does not carry the item at all, which makes this branch the
# shipper whatever the base Stage lines say.
function Test-BacklogItemIsNewlyShipped {
    param(
        [string[]] $WorkingStages,
        # Accepted so both halves of the rule read the same way at the call site. It decides
        # nothing: an item whose Stage line already reads '9-ship' while the file still sits in
        # backlog/ is shipped by this branch, and the folder it moves into does not change that.
        [AllowEmptyString()][string] $WorkingPath = '',
        [string[]] $BaseStages,
        [AllowEmptyString()][string] $BasePath = ''
    )

    $working = @($WorkingStages)
    if ($working.Count -ne 1 -or $working[0] -ne '9-ship') { return $false }

    if ([string]::IsNullOrWhiteSpace($BasePath)) { return $true }

    $base = @($BaseStages)
    if ($base.Count -ne 1 -or $base[0] -ne '9-ship') { return $true }

    $normalised = $BasePath -replace '\\', '/'
    if (-not $normalised.StartsWith('backlog/done/')) { return $true }

    return $false
}

# One record per item the target commit ships: Number, RelativePath and Stage. One record per
# number, never one per changed path.
#
# Every backlog read comes from a commit: the base snapshot for "was it already shipped", and the
# target snapshot for "what does it say now". Nothing here reads the working tree, because the
# working tree is not what a push carries.
function Get-BranchShippedItem {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase,
        [Parameter(Mandatory)][string] $TargetCommit
    )

    $candidate = @(Get-BranchBacklogCandidate -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
    if ($candidate.Count -eq 0) { return @() }

    $inventory = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $MergeBase
    if ($inventory.Status -ne 'ok') {
        throw "The base '$MergeBase' $($inventory.Detail), so which items this branch ships is unknown."
    }

    $target = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $TargetCommit
    if ($target.Status -ne 'ok') {
        throw "The pushed commit '$TargetCommit' $($target.Detail), so which items it ships is unknown."
    }

    $shipped = @()
    foreach ($record in $candidate) {
        $number = $record.Number

        # The item as the pushed commit holds it: its Stage line and its path there.
        $targetLines = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $target -ItemNumber $number
        if ($targetLines.Status -ne 'found') { continue }

        $targetPattern = '^backlog/(done/|blocked/)?' + [regex]::Escape($number) + '-[^/]*\.md$'
        $targetPaths = @(@($target.Paths) | Where-Object { $_ -match $targetPattern })
        if ($targetPaths.Count -ne 1) { continue }

        $item = [pscustomobject]@{
            RelativePath = $targetPaths[0]
            Stages = @(Get-SingleBacklogStage -Lines $targetLines.Lines | Where-Object { $_ })
        }

        # The base is looked up under the number the file carried THERE, which is the same number
        # unless this branch renumbered it. Looking it up under the new number would find nothing
        # and call every renumbered item newly shipped.
        $baseNumber = $record.BaseNumber

        # A base that carries two files for one number is treated as 'not shipped in the base',
        # which judges the item here. That is the fail-closed reading, and the duplicate is already
        # reported by the backlog numbering check.
        $pattern = '^backlog/(done/|blocked/)?' + [regex]::Escape($baseNumber) + '-[^/]*\.md$'
        $basePaths = @(@($inventory.Paths) | Where-Object { $_ -match $pattern })
        $basePath = ''
        $baseStages = @()
        if ($basePaths.Count -eq 1) {
            $basePath = $basePaths[0]
            $fromRef = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $inventory -ItemNumber $baseNumber
            if ($fromRef.Status -eq 'found') {
                $baseStages = @(Get-SingleBacklogStage -Lines $fromRef.Lines | Where-Object { $_ })
            }
        }

        $isShipped = Test-BacklogItemIsNewlyShipped `
            -WorkingStages @($item.Stages) -WorkingPath $item.RelativePath `
            -BaseStages $baseStages -BasePath $basePath
        if (-not $isShipped) { continue }

        $shipped += [pscustomobject]@{
            Number = $number
            RelativePath = $item.RelativePath
            Stage = @($item.Stages)[0]
        }
    }

    return @($shipped)
}

# Failures and diagnostics for the items the target commit ships.
#
# Only a verdict whose Code reads 'plan-never-implemented' becomes a failure. Its plan path and its
# two counts are read as fields, never parsed back out of Reason: Reason is a sentence written for a
# person, and it would break the first time somebody improved the wording.
#
# -BaseRef is the pushed commit, so the item and its '- Plan:' bullet are read from that commit.
# Without it an uncommitted rewrite of the bullet to 'none' hid the pushed pointer.
#
# The plan FILE it names still comes from disk, and must. docs/superpowers is a second repository
# that this one ignores, so no commit here ever carries a plan. That asymmetry is the whole shape of
# the check: the record is judged as pushed, the plan is read where it actually lives.
function Get-ShippedPlanTickFailure {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [psobject[]] $Item,
        [Parameter(Mandatory)][string] $TargetCommit
    )

    $failures = @()
    $diagnostics = @()

    # An empty array binds as $null, and @($null) is a one-element list holding nothing. Without
    # this filter the loop below would ask a null for its Number on every clean run.
    foreach ($record in @($Item | Where-Object { $null -ne $_ })) {
        $verdict = Test-WorktreePlanWasImplemented -MainCheckout $RepoRoot -ItemNumber $record.Number -BaseRef $TargetCommit
        if ($verdict.Allow) { continue }

        if ($verdict.Code -ne 'plan-never-implemented') {
            $diagnostics += "Backlog item $($record.Number): $($verdict.Reason). This check does not fail the push for that."
            continue
        }

        $planPath = $verdict.PlanPath
        $full = (Resolve-Path -LiteralPath $RepoRoot).Path
        if ($planPath -and $planPath.StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase)) {
            $planPath = $planPath.Substring($full.Length).TrimStart('\', '/') -replace '\\', '/'
        }

        $failures += [pscustomobject]@{
            Number = $record.Number
            ItemPath = $record.RelativePath
            PlanPath = $planPath
            TickedCount = $verdict.TickedCount
            UntickedCount = $verdict.UntickedCount
        }
    }

    return [pscustomobject]@{ Failures = @($failures); Diagnostics = @($diagnostics) }
}

if ($AsModule) { return }

if (-not $RepoRoot) { $RepoRoot = $repoRootDefault }

if (-not $TargetCommit) { $TargetCommit = 'HEAD' }

$resolvedTarget = & git -C $RepoRoot rev-parse --verify --quiet "$TargetCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0 -or -not $resolvedTarget) {
    throw "Could not resolve the commit '$TargetCommit', so there is nothing to judge."
}
$TargetCommit = ([string] $resolvedTarget).Trim()

if (-not $MergeBase) {
    $resolved = & git -C $RepoRoot merge-base $TargetCommit origin/main 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $resolved) {
        throw "Could not resolve the merge base with origin/main, so which items this branch ships is unknown. Fetch the remote and retry."
    }
    $MergeBase = ([string] $resolved).Trim()
}

$candidate = @(Get-BranchBacklogCandidate -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
$shippedItem = @(Get-BranchShippedItem -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
$result = Get-ShippedPlanTickFailure -RepoRoot $RepoRoot -Item $shippedItem -TargetCommit $TargetCommit

foreach ($line in $result.Diagnostics) { "  $line" }

if ($result.Failures.Count -gt 0) {
    foreach ($failure in $result.Failures) {
        ''
        "Backlog item $($failure.Number) reads 'Stage: 9-ship', and no step in its plan is ticked."
        ''
        "  Item:  $($failure.ItemPath)"
        "  Plan:  $($failure.PlanPath)"
        "  Steps: $($failure.UntickedCount) unticked, $($failure.TickedCount) ticked"
    }
    ''
    'Tick every step you carried out, then push again. A tick claims the step was done, so tick'
    'only those. A plan with some steps ticked and some not passes: work can be descoped.'
    ''
    'The plan belongs to the private plans repository, so it takes its own commit:'
    '  git -C docs/superpowers add <the plan file>'
    '  git -C docs/superpowers commit -m "tick the plan steps"'
    ''
    'Skip this check with: SKIP_PUSH_HOOK=1 git push'
    ''
    "RESULT: $($result.Failures.Count) shipped item carries a plan with no ticked step."
    exit 1
}

"RESULT: every shipped plan carries a ticked step. Looked at $($candidate.Count) backlog item(s) this branch touches, of which it ships $($shippedItem.Count), judged against $MergeBase."
