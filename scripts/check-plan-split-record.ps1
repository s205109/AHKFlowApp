#Requires -Version 7.0
<#
.SYNOPSIS
    Fails the push when a backlog item enters Execute on this branch and its plan carries no
    complete Split record.

.DESCRIPTION
    Every plan carries a '## Split' section near its top, with three fields: an estimate in work
    sessions, the task at which the user story closes, and a verdict on splitting. A plan meets the
    split trigger when the estimate is more than two sessions, or when 15 or more of its lines name
    a test-run command. A plan at the trigger needs a verdict that names both the extension test and
    the disjoint set test. The rule is in docs/development/workflow.md, under 'The split record'.
    The reasons are in docs/adr/0019-a-plan-declares-its-split-and-its-extension.md.

    Backlog item 146 is why this exists. Its plan never said where the user story ended, so two
    sessions of Extension stayed invisible until Execute was days old.

    Only items that enter Execute on THIS BRANCH are judged. An item enters Execute here when the
    pushed commit holds it at 4-execute or later, and the merge base does not. So no plan written
    before this rule is ever read, and no branch is refused for a record nobody asked it to write.

    The backlog item is read from the pushed commit. The plan is read from disk, because
    docs/superpowers is a second repository that this one ignores. That is the shape of
    scripts/check-shipped-plan-ticked.ps1, and this check copies it.

.PARAMETER RepoRoot
    The repository root. Defaults to the parent of this script's folder.

.PARAMETER MergeBase
    The commit to compare against. Defaults to the merge base of TargetCommit and origin/main.

.PARAMETER TargetCommit
    The commit being pushed. Defaults to HEAD. Every backlog read comes from this commit.

.PARAMETER AsModule
    Dot-source the functions and return, without running the check.

.EXAMPLE
    pwsh ./scripts/check-plan-split-record.ps1
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

# The same pair scripts/check-shipped-plan-ticked.ps1 loads: the plan pointer readers and the
# backlog snapshot readers. backlog.common.ps1 is deliberately not loaded, because its
# Get-BacklogItem reads the working tree.
. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'backlog-snapshot.common.ps1')

# Get-FenceLineMap, so an example inside a fenced block is never read as the record.
. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

# The split trigger. Design measured both numbers against the committed plans, and the spec
# records the measurement: docs/superpowers/specs/2026-09-17-plan-split-record-design-157.md.
#
# An estimate of MORE THAN this many work sessions meets the trigger. One work session is about
# five hours of work on one item, and CONTEXT.md pins the term.
$PlanSplitSessionLimit = 2

# This many or more plan lines that name a test-run command meet the trigger. Measured again on
# 2026-09-18 with the pattern below: 12 of the 65 numbered plans reach 15, and item 146 scores 19.
# The count is a proxy for how often the plan runs the suites, and its only job is to catch an
# estimate that is wrong.
$PlanSplitTestRunLineLimit = 15

# The four command names the calibration counted. A suite started directly with pwsh is not
# counted, because the limit above was measured without it.
$PlanSplitTestRunPattern = 'test-fast\.ps1|run-powershell-suites|Invoke-Pester|dotnet test'

# A plan's text, read into its Split record. No git, no files: this is the part a test can drive
# directly.
#
# The record is the first '## Split' heading outside a fenced block, and it ends at the next
# heading of level one or two. A field is a top-level bullet such as '- **Estimate**: 2 sessions'.
# An indented line continues the field above it, because plans wrap at about 100 characters.
#
# Test-run lines are counted on every line, fenced or not. Design measured the limit that way, and
# a test-run command usually sits inside a fenced block.
function Get-PlanSplitRecord {
    param([AllowEmptyString()][string] $PlanText)

    $lines = @(($PlanText -replace "`r`n", "`n") -split "`n")
    $fenced = Get-FenceLineMap -Lines $lines

    $taskNumbers = @()
    $testRunLineCount = 0
    $sectionStart = -1
    $firstTaskLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $PlanSplitTestRunPattern) { $testRunLineCount++ }
        if ($fenced[$i]) { continue }
        # Plans write '### Task 1:', '## Task 1 -' and more, so the level is not fixed.
        if ($lines[$i] -match '^#{2,4}\s+Task\s+(?<n>\d+)\b') {
            $taskNumbers += [int] $Matches.n
            if ($firstTaskLine -lt 0) { $firstTaskLine = $i }
        }
        if ($sectionStart -lt 0 -and $lines[$i] -match '^##\s+Split\s*$') { $sectionStart = $i }
    }

    # The rule is "after the plan header and before the first task". A Split section that starts
    # at or after the first task heading defeats that, even when its fields are complete, so it is
    # not the record.
    if ($firstTaskLine -ge 0 -and $sectionStart -ge $firstTaskLine) { $sectionStart = -1 }

    $fields = @{ Estimate = ''; UserStoryClosesAt = ''; Verdict = '' }
    if ($sectionStart -ge 0) {
        $current = ''
        for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($fenced[$i]) { $current = ''; continue }
            if ($line -match '^#{1,2}\s') { break }

            if ($line -match '^-\s+\*\*(?<label>[^*]+)\*\*:\s*(?<value>.*)$') {
                $value = $Matches.value.Trim()
                $current = switch ($Matches.label.Trim()) {
                    'Estimate' { 'Estimate' }
                    'User story closes at' { 'UserStoryClosesAt' }
                    'Verdict' { 'Verdict' }
                    default { '' }
                }
                if ($current) { $fields[$current] = $value }
                continue
            }

            if ($current -and $line -match '^\s+\S') {
                $fields[$current] = ($fields[$current] + ' ' + $line.Trim()).Trim()
                continue
            }
            $current = ''
        }
    }

    # A number is required. 'two sessions' cannot be compared with the limit.
    $estimate = $null
    if ($fields.Estimate -match '^(?<n>\d+(?:\.\d+)?)\s*sessions?\b') { $estimate = [double] $Matches.n }

    $userStoryTask = $null
    if ($fields.UserStoryClosesAt -match '^Task\s+(?<n>\d+)\b') { $userStoryTask = [int] $Matches.n }

    return [pscustomobject]@{
        HasSection = ($sectionStart -ge 0)
        Estimate = $estimate
        UserStoryTask = $userStoryTask
        Verdict = $fields.Verdict
        TaskNumbers = @($taskNumbers | Sort-Object -Unique)
        TestRunLineCount = $testRunLineCount
    }
}

# Why a record meets the split trigger, one clause per condition. Empty means below the trigger.
function Get-PlanSplitTriggerReason {
    param([Parameter(Mandatory)][psobject] $Record)

    $reasons = @()
    if ($null -ne $Record.Estimate -and $Record.Estimate -gt $PlanSplitSessionLimit) {
        $reasons += "the estimate is $($Record.Estimate) sessions, more than $PlanSplitSessionLimit"
    }
    if ($Record.TestRunLineCount -ge $PlanSplitTestRunLineLimit) {
        $reasons += "$($Record.TestRunLineCount) lines name a test-run command, and the limit is $PlanSplitTestRunLineLimit"
    }
    return @($reasons)
}

# What is wrong with a record, one sentence per problem. Each sentence says what to write.
#
# At the trigger, the verdict must name both tests. A verdict that names neither is a shrug, and
# the written evaluation is the only override this rule has.
function Get-PlanSplitProblem {
    param([Parameter(Mandatory)][psobject] $Record)

    if (-not $Record.HasSection) {
        return @("The plan carries no '## Split' section. Add it after the plan header and before the first task.")
    }

    $problems = @()
    if ($null -eq $Record.Estimate) {
        $problems += "The Split record carries no estimate. Write '- **Estimate**: <number> sessions'."
    }

    if ($null -eq $Record.UserStoryTask) {
        $problems += "The Split record does not name the task at which the user story closes. Write '- **User story closes at**: Task <number>'."
    }
    elseif ($Record.TaskNumbers -notcontains $Record.UserStoryTask) {
        $problems += "The Split record says the user story closes at Task $($Record.UserStoryTask), and the plan has no Task $($Record.UserStoryTask) heading."
    }

    $reasons = @(Get-PlanSplitTriggerReason -Record $Record)
    if ($reasons.Count -gt 0) {
        $why = $reasons -join '; '
        if (-not $Record.Verdict) {
            $problems += "The plan meets the split trigger ($why), and the Split record carries no verdict. Write '- **Verdict**:' with the result of the extension test and the disjoint set test."
        }
        elseif ($Record.Verdict -notmatch 'extension test' -or $Record.Verdict -notmatch 'disjoint set test') {
            $problems += "The plan meets the split trigger ($why), and the verdict does not name both the extension test and the disjoint set test."
        }
    }

    return @($problems)
}

# The pointer and the plan for each item that enters Execute, judged against the rule above.
#
# The item's lines come from the pushed commit, so the pointer is judged as pushed. The plan FILE
# comes from disk, and must: docs/superpowers is a second repository that this one ignores, so no
# commit here ever carries a plan.
#
# A pointer the check cannot follow is a failure, not a pass. That is where this differs from
# scripts/check-shipped-plan-ticked.ps1, which prints a diagnostic and passes. Here the plan IS the
# thing being judged, so passing would let one mistyped path switch the rule off for that item.
#
# Judged lists every plan that was read, passing or not, so the push can print each one's size.
function Get-PlanSplitFailure {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [psobject[]] $Item
    )

    $failures = @()
    $judged = @()

    # An empty array binds as $null, and @($null) is a one-element list holding nothing.
    foreach ($record in @($Item | Where-Object { $null -ne $_ })) {
        # A missing bullet is tests/BacklogPlanPointer.Tests.ps1's problem to report. A bullet
        # whose content is only whitespace is not: Test-BacklogPlanPath and Test-BacklogPlanNone
        # both take a mandatory string, so an empty Value throws there and the item is silently
        # read as zero problems. This check reports the empty bullet instead.
        $bulletLine = @($record.Lines) | Where-Object { $_ -match '^\s*-\s*Plan:' } | Select-Object -First 1
        if (-not $bulletLine) { continue }

        $null = $bulletLine -match '^\s*-\s*Plan:\s*(?<rest>.*)$'
        $rest = $Matches.rest.Trim()
        if (-not $rest) {
            $failures += [pscustomobject]@{
                Number = $record.Number
                ItemPath = $record.RelativePath
                PlanPath = ''
                Problems = @("The '- Plan:' bullet is empty, so no Split record can be read. Write a path under $WorktreePlansFolder, or 'none — <reason>'.")
            }
            continue
        }
        if ($rest -match '^none\b') { continue }

        $relative = Get-BacklogPlanRelativePath -BulletRest $rest
        if (-not $relative) {
            $failures += [pscustomobject]@{
                Number = $record.Number
                ItemPath = $record.RelativePath
                PlanPath = $rest
                Problems = @("The '- Plan:' bullet does not name one file under $WorktreePlansFolder, so no Split record can be read.")
            }
            continue
        }

        $planPath = Resolve-BacklogPlanPath -MainCheckout $RepoRoot -PlanRelative $relative
        if (-not $planPath) {
            $failures += [pscustomobject]@{
                Number = $record.Number
                ItemPath = $record.RelativePath
                PlanPath = $relative
                Problems = @("The plan file is not on disk, so its Split record cannot be read. Pull the plans repository, or correct the '- Plan:' bullet.")
            }
            continue
        }

        $planRecord = Get-PlanSplitRecord -PlanText (Get-Content -Raw -LiteralPath $planPath)
        $judged += [pscustomobject]@{ Number = $record.Number; PlanPath = $relative; Record = $planRecord }

        $problems = @(Get-PlanSplitProblem -Record $planRecord)
        if ($problems.Count -gt 0) {
            $failures += [pscustomobject]@{
                Number = $record.Number
                ItemPath = $record.RelativePath
                PlanPath = $relative
                Problems = $problems
            }
        }
    }

    return [pscustomobject]@{ Failures = @($failures); Judged = @($judged) }
}

# One line per judged plan, printed on every push that carries an item into Execute. The user
# story of backlog 157 asks for exactly this: the size of the work, seen before the work starts.
function Format-PlanSplitSummary {
    param(
        [Parameter(Mandatory)][string] $Number,
        [Parameter(Mandatory)][psobject] $Record
    )

    if (-not $Record.HasSection) { return "Backlog item ${Number}: the plan carries no Split record." }

    $estimate = if ($null -eq $Record.Estimate) { 'no estimate' } else { "estimate $($Record.Estimate) session(s)" }

    # Guarded, because strict mode refuses an index into an empty array.
    $tasks = @($Record.TaskNumbers)
    $lastTask = if ($tasks.Count -gt 0) { $tasks[-1] } else { 0 }
    $closes = if ($null -eq $Record.UserStoryTask) { 'no task closes the user story' }
              else { "the user story closes at Task $($Record.UserStoryTask) of $lastTask" }

    $trigger = if (@(Get-PlanSplitTriggerReason -Record $Record).Count -gt 0) { 'at the split trigger' } else { 'below the split trigger' }

    return "Backlog item ${Number}: $estimate; $closes; $($Record.TestRunLineCount) line(s) name a test-run command; $trigger."
}

# Whether a Stage value is 4-execute or later. Stages carry their number first, and the numbers
# are ordinal, so the number decides. A text sort would put 10-cleanup before 4-execute.
function Test-BacklogStageIsExecuteOrLater {
    param([AllowEmptyString()][string] $Stage)

    if ($Stage -match '^(?<n>\d+)-') { return ([int] $Matches.n -ge 4) }
    return $false
}

# The two-half scope rule, as plain data. An item enters Execute on this branch when both hold:
#
#   - The pushed commit gives it exactly one Stage line, at 4-execute or later.
#   - The merge base does not already hold it at 4-execute or later. A base that does not carry
#     the item at all means this branch filed it, so it enters here too.
#
# The second half keeps the rule from reaching backwards: an item the base already holds past Plan
# was planned before this rule, and its plan is never read. An in-flight branch that takes in this
# check is judged at its next push, which costs its plan three lines.
#
# A base that carries the item with no Stage line, or with two, reads as 'not yet in Execute'.
# That is the fail-closed reading, and the backlog numbering check reports the duplicate.
function Test-BacklogItemEntersExecute {
    param(
        [string[]] $WorkingStages,
        [string[]] $BaseStages,
        [AllowEmptyString()][string] $BasePath = ''
    )

    $working = @($WorkingStages)
    if ($working.Count -ne 1 -or -not (Test-BacklogStageIsExecuteOrLater -Stage $working[0])) { return $false }

    if ([string]::IsNullOrWhiteSpace($BasePath)) { return $true }

    $base = @($BaseStages)
    if ($base.Count -ne 1) { return $true }
    return (-not (Test-BacklogStageIsExecuteOrLater -Stage $base[0]))
}

# One record per item the pushed commit carries into Execute: Number, RelativePath, Stage, and
# Lines. Lines is the item as pushed, so Get-PlanSplitFailure reads the pointer without a second
# git call.
#
# Get-BranchBacklogTransition does the walk and the two snapshot reads. This function is the rule
# and the output shape, and nothing else.
function Get-BranchExecutingItem {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MergeBase,
        [Parameter(Mandatory)][string] $TargetCommit
    )

    $transition = @(Get-BranchBacklogTransition -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit `
        -BaseUnknownClause 'which items enter Execute on this branch' `
        -TargetUnknownClause 'which items it carries into Execute')

    $entering = @()
    foreach ($record in $transition) {
        $enters = Test-BacklogItemEntersExecute -WorkingStages @($record.Stages) `
            -BaseStages $record.BaseStages -BasePath $record.BasePath
        if (-not $enters) { continue }

        $entering += [pscustomobject]@{
            Number = $record.Number
            RelativePath = $record.RelativePath
            Stage = @($record.Stages)[0]
            Lines = @($record.Lines)
        }
    }

    return @($entering)
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
        throw "Could not resolve the merge base with origin/main, so which items enter Execute on this branch is unknown. Fetch the remote and retry."
    }
    $MergeBase = ([string] $resolved).Trim()
}

$entering = @(Get-BranchExecutingItem -RepoRoot $RepoRoot -MergeBase $MergeBase -TargetCommit $TargetCommit)
$result = Get-PlanSplitFailure -RepoRoot $RepoRoot -Item $entering

foreach ($judged in $result.Judged) { "  $(Format-PlanSplitSummary -Number $judged.Number -Record $judged.Record)" }

if ($result.Failures.Count -gt 0) {
    foreach ($failure in $result.Failures) {
        ''
        "Backlog item $($failure.Number) enters Execute on this branch, and its plan's Split record is not complete."
        ''
        "  Item:  $($failure.ItemPath)"
        "  Plan:  $($failure.PlanPath)"
        foreach ($problem in $failure.Problems) { "  - $problem" }
    }
    ''
    'Every plan carries a ## Split section after its header and before its first task:'
    '  - **Estimate**: <number> sessions'
    '  - **User story closes at**: Task <number>'
    '  - **Verdict**: <the split taken, or why the extension test and the disjoint set test found none>'
    'The verdict is required when the plan meets the split trigger. The rule is in'
    'docs/development/workflow.md, under Stage 3, in the section "The split record".'
    ''
    'The plan belongs to the private plans repository, so it takes its own commit:'
    '  git -C docs/superpowers add <the plan file>'
    '  git -C docs/superpowers commit -m "add the split record" -- <the plan file>'
    ''
    'Skip this check with: SKIP_PUSH_HOOK=1 git push'
    ''
    "RESULT: $($result.Failures.Count) item(s) entering Execute carry an incomplete Split record."
    exit 1
}

"RESULT: every plan entering Execute carries a complete Split record. Judged $($entering.Count) backlog item(s) that enter Execute on this branch, against $MergeBase."
