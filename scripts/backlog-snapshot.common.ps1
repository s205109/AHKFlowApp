#Requires -Version 7.0
# Finds the backlog items a branch touched, by diffing two commits.
#
# Backlog 151 moved this out of check-shipped-plan-ticked.ps1 so two checks could share it. That
# script has a param block, and dot-sourcing a script with a param block binds every one of its
# parameter names into the caller's scope. Both callers here take -RepoRoot, -MergeBase and
# -TargetCommit, so sharing through its -AsModule switch wiped the caller's own arguments and
# failed with "Cannot bind argument to parameter 'RepoRoot' because it is an empty string."
#
# A *.common.ps1 has no param block, so it cannot collide with anything. That is why every shared
# file in this folder is shaped this way.
#
# Nothing here reads the working tree. A pull request carries commits, and an uncommitted edit
# must never decide whether a committed record is judged.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')

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

# The number in a backlog path, or '' when the path carries none.
function Get-BacklogNumberFromPath {
    param([AllowEmptyString()][string] $Path)

    if ($Path -match ('/(' + $WorktreeBacklogNumberPattern + ')-')) { return $Matches[1] }
    return ''
}

# One record per item number this branch touches under backlog/: Number, from the path as it is
# now, and BaseNumber, the number that same file carried in the base.
#
# The two differ only across a renumber, and that is the whole reason this reads the diff as
# name-status rather than name-only. An item's identity is the FILE, not the number: a renumber is
# a 'git mv' plus a heading edit, and the item it moves is the same item. 'git diff --name-only'
# prints only the destination of a rename, so the old number vanished, the base lookup found
# nothing under the new one, and a branch that merely renumbered a shipped item was told it had
# shipped it. This repository renumbers shipped items for real: b9f38820 renumbered done item 105
# to 107, and 7c762117 renumbered 118 to 120.
#
# -z, so a path holding a space or a non-ASCII byte arrives whole. Without it git quotes and
# escapes such a path, and the number would be read out of an escaped string.
#
# A copy is not a rename. --find-copies is off by default so 'C' never appears, but its two paths
# are still parsed, because a caller who turns copies on must not desynchronise the token walk. Its
# source is deliberately not used as identity: the source still exists, so the destination is a new
# item, not the same one moved.
#
# Suffix-aware, because this repository ships items such as 022b and a digits-only pattern would
# skip them in silence.
#
# Fail closed on the diff. An empty list would switch the whole check off in silence, which is the
# same rule pre-push already applies when it cannot read the backlog diff.
function Get-BranchBacklogCandidate {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase,
        [Parameter(Mandatory)][string] $TargetCommit
    )

    # Two commits, never one. A one-commit diff compares the base against the WORKING TREE, so an
    # uncommitted edit decided the answer: HEAD read 'Stage: 9-ship' with an unticked plan, the
    # developer changed the Stage line on disk without committing, and the gate passed while the
    # 9-ship record went to the remote. A push carries commits, so commits are what get judged.
    $diff = & git -C $RepoRoot diff --name-status -z --find-renames $MergeBase $TargetCommit -- backlog 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the backlog diff against '$MergeBase', so which items this branch ships is unknown."
    }

    # A -z stream holds no newline, so PowerShell hands it back as one string. Joining on a newline
    # is exact either way: with one element it returns that element unchanged, and were a path ever
    # to carry a literal newline the join puts it back where it was.
    $raw = [string]::Join("`n", @($diff))
    $token = @($raw -split "`0")

    # One record per number, not per changed path. BaseNumber takes the first rename source seen: a
    # branch that deletes backlog/073-a.md and adds backlog/073-b.md produces two path entries for
    # one number, and they fold into the single record that answers for that number.
    $baseByNumber = @{}
    $order = [System.Collections.Generic.List[string]]::new()

    $i = 0
    while ($i -lt $token.Count) {
        $status = $token[$i]
        if ([string]::IsNullOrEmpty($status)) { $i++; continue }

        $sourcePath = ''
        if ($status[0] -eq 'R' -or $status[0] -eq 'C') {
            if ($i + 2 -ge $token.Count) { break }
            if ($status[0] -eq 'R') { $sourcePath = $token[$i + 1] }
            $path = $token[$i + 2]
            $i += 3
        }
        else {
            if ($i + 1 -ge $token.Count) { break }
            $path = $token[$i + 1]
            $i += 2
        }

        $number = Get-BacklogNumberFromPath -Path $path
        if (-not $number) { continue }

        if (-not $baseByNumber.ContainsKey($number)) {
            $order.Add($number)
            $baseByNumber[$number] = ''
        }
        if (-not $baseByNumber[$number]) {
            $sourceNumber = Get-BacklogNumberFromPath -Path $sourcePath
            if ($sourceNumber) { $baseByNumber[$number] = $sourceNumber }
        }
    }

    $candidate = @()
    foreach ($number in ($order | Sort-Object)) {
        $baseNumber = $baseByNumber[$number]
        if (-not $baseNumber) { $baseNumber = $number }
        $candidate += [pscustomobject]@{ Number = $number; BaseNumber = $baseNumber }
    }
    return @($candidate)
}

# One record per backlog item this branch touches, holding everything a stage rule needs to judge
# it: the item as the pushed commit holds it, and the same item as the merge base held it.
#
# Backlog 159 pulled this out of Get-BranchShippedItem and Get-BranchExecutingItem, which walked it
# twice. Each caller now keeps only its own rule and its own output shape.
#
# The base is read under BaseNumber. Get-BranchBacklogCandidate above says why that matters.
#
# An item the pushed commit does not hold, or holds under two file names, is skipped. That is the
# fail-closed reading, and the backlog numbering check already reports the duplicate.
#
# BaseUnknownClause and TargetUnknownClause are the middle of the sentence each caller throws, so
# a failed push says which question could not be answered. A caller that ships items and a caller
# that judges items entering Execute cannot honestly print the same sentence.
function Get-BranchBacklogTransition {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase,
        [Parameter(Mandatory)][string] $TargetCommit,
        [Parameter(Mandatory)][string] $BaseUnknownClause,
        [Parameter(Mandatory)][string] $TargetUnknownClause
    )

    $candidate = @(Get-BranchBacklogCandidate -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
    if ($candidate.Count -eq 0) { return @() }

    $base = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $MergeBase
    if ($base.Status -ne 'ok') {
        throw "The base '$MergeBase' $($base.Detail), so $BaseUnknownClause is unknown."
    }

    $target = Get-BacklogInventoryFromRef -MainCheckout $RepoRoot -BaseRef $TargetCommit
    if ($target.Status -ne 'ok') {
        throw "The pushed commit '$TargetCommit' $($target.Detail), so $TargetUnknownClause is unknown."
    }

    $transition = @()
    foreach ($record in $candidate) {
        $targetLines = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $target -ItemNumber $record.Number
        if ($targetLines.Status -ne 'found') { continue }

        $targetPattern = '^backlog/' + $WorktreeBacklogSubfolderPattern + [regex]::Escape($record.Number) + '-[^/]*\.md$'
        $targetPaths = @(@($target.Paths) | Where-Object { $_ -match $targetPattern })
        if ($targetPaths.Count -ne 1) { continue }

        $basePath = ''
        $baseStages = @()
        $basePattern = '^backlog/' + $WorktreeBacklogSubfolderPattern + [regex]::Escape($record.BaseNumber) + '-[^/]*\.md$'
        $basePaths = @(@($base.Paths) | Where-Object { $_ -match $basePattern })
        if ($basePaths.Count -eq 1) {
            $basePath = $basePaths[0]
            $fromBase = Get-BacklogItemLinesFromRef -MainCheckout $RepoRoot -Inventory $base -ItemNumber $record.BaseNumber
            if ($fromBase.Status -eq 'found') {
                $baseStages = @(Get-SingleBacklogStage -Lines $fromBase.Lines | Where-Object { $_ })
            }
        }

        $transition += [pscustomobject]@{
            Number = $record.Number
            RelativePath = $targetPaths[0]
            Lines = @($targetLines.Lines)
            Stages = @(Get-SingleBacklogStage -Lines $targetLines.Lines | Where-Object { $_ })
            BasePath = $basePath
            BaseStages = $baseStages
        }
    }

    return @($transition)
}
