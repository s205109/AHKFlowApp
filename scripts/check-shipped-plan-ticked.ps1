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

      - The working tree gives it exactly one '- **Stage**:' line, and that line reads '9-ship'.
      - The merge base does not already have it shipped. The base has it shipped when the base
        carries the item, its Stage line there also reads '9-ship', and its path there is already
        under backlog/done/. Any one of those three being false makes this branch the shipper.

    The second half is what closes the plain-rename case: a branch that only runs 'git mv' into
    backlog/done/, leaving the Stage line untouched at '9-ship', is still the branch that shipped
    the item, and is still judged.

    An item with no Stage line, or with more than one, is skipped. Those are already the business of
    the backlog numbering check, and this must not report them a second time.

    Only the never-implemented refusal fails the push. Every other refusal - an unreadable item, a
    plan pointer outside the plans folder, a plan file that is not there - is a real problem, but it
    is not this item's problem. Those print one diagnostic line and pass.

.PARAMETER RepoRoot
    The repository root. Defaults to the parent of this script's folder.

.PARAMETER MergeBase
    The commit to compare against. Defaults to 'git merge-base HEAD origin/main'.

.PARAMETER AsModule
    Dot-source the functions and return, without running the check.

.EXAMPLE
    pwsh ./scripts/check-shipped-plan-ticked.ps1
#>
[CmdletBinding()]
param(
    [string] $RepoRoot,
    [string] $MergeBase = '',
    [switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootDefault = Split-Path -Parent $PSScriptRoot

# Neither file runs anything on its own. backlog.common.ps1 does dot-source slug.common.ps1, which
# calls Set-StrictMode -Version Latest, and that call leaks into this scope. This script sets strict
# mode itself, so the leak changes nothing here.
. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'backlog.common.ps1')

# The one Stage line an item carries, or '' when it carries none or more than one. An item with no
# Stage line, or with two, is not a shipping decision this check may take: the backlog numbering
# check owns that problem and already reports it.
function Get-SingleBacklogStage {
    param([string[]] $Lines)

    if ($null -eq $Lines) { return '' }
    $stages = @($Lines | ForEach-Object {
        if ($_ -match '^- \*\*Stage\*\*:\s*(?<stage>\S+)\s*$') { $Matches.stage }
    })
    if ($stages.Count -ne 1) { return '' }
    return $stages[0]
}

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

# The item numbers this branch touches under backlog/. A prefilter for speed only: the base
# comparison in Get-BranchShippedItem is what decides who shipped what.
#
# Suffix-aware, because this repository ships items such as 022b and a digits-only pattern would
# skip them in silence. The numbers are made unique here: a 'git mv' reports the old path and the
# new path, and both carry the same number.
#
# Fail closed on the diff. An empty list would switch the whole check off in silence, which is the
# same rule pre-push already applies when it cannot read the backlog diff.
function Get-BranchBacklogCandidateNumber {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase
    )

    $diff = & git -C $RepoRoot diff --name-only $MergeBase -- backlog 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the backlog diff against '$MergeBase', so which items this branch ships is unknown."
    }

    return @(@($diff) |
        ForEach-Object { if ($_ -match ('/(' + $WorktreeBacklogNumberPattern + ')-')) { $Matches[1] } } |
        Sort-Object -Unique)
}

# One record per item this branch ships: Number, RelativePath and Stage. One record per number,
# never one per changed path.
function Get-BranchShippedItem {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase
    )

    $numbers = @(Get-BranchBacklogCandidateNumber -RepoRoot $RepoRoot -MergeBase $MergeBase)
    if ($numbers.Count -eq 0) { return @() }

    $inventory = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $MergeBase
    if ($inventory.Status -ne 'ok') {
        throw "The base '$MergeBase' $($inventory.Detail), so which items this branch ships is unknown."
    }

    $backlogRoot = Join-Path $RepoRoot 'backlog'
    $items = @{}
    foreach ($item in @(Get-BacklogItem -BacklogRoot $backlogRoot)) {
        if ($item.Key) { $items[$item.Key] = $item }
    }

    $shipped = @()
    foreach ($number in $numbers) {
        if (-not $items.ContainsKey($number)) { continue }
        $item = $items[$number]

        # A base that carries two files for one number is treated as 'not shipped in the base',
        # which judges the item here. That is the fail-closed reading, and the duplicate is already
        # reported by the backlog numbering check.
        $pattern = '^backlog/(done/|blocked/)?' + [regex]::Escape($number) + '-[^/]*\.md$'
        $basePaths = @(@($inventory.Paths) | Where-Object { $_ -match $pattern })
        $basePath = ''
        $baseStages = @()
        if ($basePaths.Count -eq 1) {
            $basePath = $basePaths[0]
            $fromRef = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $inventory -ItemNumber $number
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

# Failures and diagnostics for the items this branch ships.
#
# Only a verdict whose Code reads 'plan-never-implemented' becomes a failure. Its plan path and its
# two counts are read as fields, never parsed back out of Reason: Reason is a sentence written for a
# person, and it would break the first time somebody improved the wording.
function Get-ShippedPlanTickFailure {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [psobject[]] $Item
    )

    $failures = @()
    $diagnostics = @()

    # An empty array binds as $null, and @($null) is a one-element list holding nothing. Without
    # this filter the loop below would ask a null for its Number on every clean run.
    foreach ($record in @($Item | Where-Object { $null -ne $_ })) {
        $verdict = Test-WorktreePlanWasImplemented -MainCheckout $RepoRoot -ItemNumber $record.Number
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

if (-not $MergeBase) {
    $resolved = & git -C $RepoRoot merge-base HEAD origin/main 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $resolved) {
        throw "Could not resolve the merge base with origin/main, so which items this branch ships is unknown. Fetch the remote and retry."
    }
    $MergeBase = ([string] $resolved).Trim()
}

$candidate = @(Get-BranchBacklogCandidateNumber -RepoRoot $RepoRoot -MergeBase $MergeBase)
$shippedItem = @(Get-BranchShippedItem -RepoRoot $RepoRoot -MergeBase $MergeBase)
$result = Get-ShippedPlanTickFailure -RepoRoot $RepoRoot -Item $shippedItem

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
