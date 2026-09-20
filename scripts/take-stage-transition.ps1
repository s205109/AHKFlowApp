#Requires -Version 7.0
<#
.SYNOPSIS
    Performs one stage transition end to end: the field, the commit, the push, and the pull
    request, in the one order that cannot leave them disagreeing.
.DESCRIPTION
    Backlog 081. Three defects in the backlog-071 review rounds were ordering mistakes, not
    judgement mistakes: the Stage was published before the pull request existed, a failure edge
    was recorded after its fixes, and a Ship closure commit was never pushed.

    This script makes the correct order the only order.

    It is PowerShell, and a Claude Code session inside an entered worktree cannot run PowerShell.
    Such a session calls it through the exit and re-enter cycle. See
    docs/adr/0020-a-transition-runs-outside-the-entered-worktree.md for why bash was rejected.
.PARAMETER Worktree
    The absolute path of the worktree to act on. Every git call uses 'git -C' against it, so the
    caller's working directory never matters.
.PARAMETER AsModule
    Dot-source the file without running it. The suite uses this.
#>

[CmdletBinding()]
param(
    [string] $Worktree,
    [string] $Item,
    [ValidateSet('success', 'failure', 'blocked', 'not applicable')]
    [string] $Edge,
    [string] $To = '',
    [string] $Note = '',
    [string] $Evidence = '',
    [string] $RecoveryTask = '',
    [string] $UnblockNote = '',
    [int] $Pr = 0,
    # The branch this work merges into. It decides two things that must agree: whether the branch
    # has a commit of its own, and what 'gh pr create --base' is given. Stacked work created with
    # new-worktree.ps1 -BaseRef passes the same branch here.
    [string] $Base = 'main',
    [switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'stage-transition.common.ps1')
. (Join-Path $PSScriptRoot 'backlog.common.ps1')
. (Join-Path $PSScriptRoot 'backlog-snapshot.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'backlog-acceptance.common.ps1')

function Find-TransitionItem {
    param([string] $Worktree, [string] $Item)

    $items = @(Get-BacklogItem -BacklogRoot (Join-Path $Worktree 'backlog'))
    $match = @($items | Where-Object { $_.Key -eq $Item -or $_.Number -eq [int] $Item })
    if ($match.Count -ne 1) {
        throw "Expected exactly one backlog item numbered '$Item', found $($match.Count)."
    }

    $record = $match[0]
    if ($record.Stages.Count -ne 1) {
        throw "Item '$Item' must carry exactly one Stage line, found $($record.Stages.Count)."
    }

    return $record
}

function Get-ItemDifficulty {
    param([string] $Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $found = @($lines | ForEach-Object {
        if ($_ -match '^- \*\*Difficulty\*\*:\s*(?<value>\S+)\s*$') { $Matches.value }
    })
    if ($found.Count -ne 1) { return '' }
    return $found[0]
}

function Set-ItemStage {
    param([string] $Path, [string] $Stage)

    $lines = @(Get-Content -LiteralPath $Path)
    $written = 0
    $out = foreach ($line in $lines) {
        if ($line -match '^- \*\*Stage\*\*:\s*\S+\s*$') {
            $written++
            "- **Stage**: $Stage"
        } else {
            $line
        }
    }
    if ($written -ne 1) { throw "Expected one Stage line to rewrite, rewrote $written." }
    Set-Content -LiteralPath $Path -Value $out -Encoding utf8
}

function Get-ItemTitle {
    param([string] $Path)
    $first = (Get-Content -LiteralPath $Path -TotalCount 1)
    if ($first -match '^#\s*\S+\s*-\s*(?<title>.+?)\s*$') { return $Matches.title }
    return 'Untitled'
}

function Get-SessionsBody {
    $id = if ($env:CLAUDE_CODE_SESSION_ID) { $env:CLAUDE_CODE_SESSION_ID } else { 'none' }
    return "Sessions:`n`n- $id (agent, 1-pickup)"
}

function Assert-TransitionAllowed {
    param([string] $Worktree)

    if (-not (Test-Path -LiteralPath $Worktree)) {
        throw "The worktree path '$Worktree' does not exist."
    }
    if (-not (Test-LinkedWorktree $Worktree)) {
        throw ("'$Worktree' is the main checkout, not a linked worktree. A transition needs a " +
               'branch of its own, so there is a pull request to point at and something safe to push.')
    }
}

# Half one: refuse a branch that has diverged. This applies to a round too.
function Assert-BranchNotDiverged {
    param([string] $Worktree, [string] $Branch)

    & git -C $Worktree fetch --quiet origin 2>$null
    $upstream = & git -C $Worktree rev-parse --verify --quiet "origin/$Branch"
    if (-not $upstream) { return }   # No upstream yet. Pickup publishes the branch.

    $behind = @(& git -C $Worktree rev-list "HEAD..origin/$Branch")
    if ($behind.Count -gt 0) {
        throw ("The branch has diverged: origin/$Branch has $($behind.Count) commit(s) this " +
               'worktree does not. Merge or rebase first. This script never force-pushes.')
    }
}

# Half two: publish work that was committed but never pushed. This closes the crash window
# workflow.md describes, where a session dies between the Stage commit and the push.
function Invoke-RemotePreflight {
    param([string] $Worktree, [string] $Branch)

    Assert-BranchNotDiverged -Worktree $Worktree -Branch $Branch

    $upstream = & git -C $Worktree rev-parse --verify --quiet "origin/$Branch"
    if (-not $upstream) { return }

    $ahead = @(& git -C $Worktree rev-list "origin/$Branch..HEAD")
    if ($ahead.Count -eq 0) { return }

    # Named, not silent. A push carries the whole branch, so say what went up.
    Write-Host "Pushing $($ahead.Count) commit(s) that were committed but never pushed:"
    & git -C $Worktree log --oneline "origin/$Branch..HEAD"
    & git -C $Worktree push origin $Branch
    if ($LASTEXITCODE -ne 0) { throw 'The pre-flight push failed. Nothing was changed.' }
}

function Add-FailureRecord {
    param(
        [string] $Worktree, [string] $Item, [string] $Target,
        [string] $Evidence, [string] $RecoveryTask
    )

    $progress = Join-Path $Worktree 'PLAN-PROGRESS.md'
    if (-not (Test-Path -LiteralPath $progress)) {
        throw ('There is no PLAN-PROGRESS.md, so this work never reached Execute and a failure ' +
               'edge is not possible from here.')
    }

    $stamp = (Get-Date).ToString('yyyy-MM-dd')
    $block = @(
        ''
        "## Failure edge to $Target ($stamp)"
        ''
        '**Red evidence:**'
        ''
        '```'
        $Evidence
        '```'
        ''
        "**Recovery task:** $RecoveryTask"
        ''
    ) -join "`n"

    Add-Content -LiteralPath $progress -Value $block -Encoding utf8
}

function Invoke-StageTransition {
    param(
        [string] $Worktree, [string] $Item, [string] $Edge,
        [string] $To = '', [string] $Note = '',
        [string] $Evidence = '', [string] $RecoveryTask = ''
    )

    Assert-TransitionAllowed -Worktree $Worktree

    $branch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
    $record = Find-TransitionItem -Worktree $Worktree -Item $Item
    $stage = $record.Stages[0]
    $difficulty = Get-ItemDifficulty -Path $record.Path
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'

    # Resolve before touching anything. A refused transition must change nothing.
    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage $stage `
                                       -Edge $Edge -Difficulty $difficulty -To $To

    Invoke-RemotePreflight -Worktree $Worktree -Branch $branch

    # A failure edge without its red evidence and its named recovery task is a claim with no
    # record behind it. Both refusals run before the Stage is written.
    if ($Edge -eq 'failure') {
        if (-not $Evidence)     { throw 'A failure edge needs -Evidence: the failing command and its output.' }
        if (-not $RecoveryTask) { throw 'A failure edge needs -RecoveryTask: the named task that fixes it.' }
        Add-FailureRecord -Worktree $Worktree -Item $Item -Target $target `
                          -Evidence $Evidence -RecoveryTask $RecoveryTask
    }

    Set-ItemStage -Path $record.Path -Stage $target

    $message = if ($Edge -eq 'failure') { "docs: $Item failure edge to $target" } else { "docs: $Item at $target" }
    if ($Note) { $message = "$message, $Note" }

    & git -C $Worktree add -- $record.RelativePath
    if ($Edge -eq 'failure') { & git -C $Worktree add -- PLAN-PROGRESS.md }
    & git -C $Worktree commit -m $message
    if ($LASTEXITCODE -ne 0) { throw 'The transition commit failed.' }

    & git -C $Worktree push origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'The transition commit was made but the push failed. Push it before anything else.' }

    Write-Host "Item $Item is now at $target."
}

# GitHub refuses a pull request between identical refs, so a branch with no commits of its own
# cannot open one. The empty marker commit is the same device the Source uses for a housekeeping
# round. See workflow.md section 2.
function Add-PickupMarkerCommit {
    param([string] $Worktree, [string] $Item, [string] $BaseRef)

    $own = @(& git -C $Worktree rev-list "$BaseRef..HEAD" 2>$null)
    if ($own.Count -gt 0) { return }

    & git -C $Worktree commit --allow-empty -m "chore: $Item pickup, opening draft PR"
    if ($LASTEXITCODE -ne 0) { throw 'The pickup marker commit failed.' }
}

function Invoke-PickupTransition {
    param([string] $Worktree, [string] $Item, [string] $To = '', [string] $Note = '', [string] $Base = 'main')

    Assert-TransitionAllowed -Worktree $Worktree

    $branch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
    $record = Find-TransitionItem -Worktree $Worktree -Item $Item
    $difficulty = Get-ItemDifficulty -Path $record.Path
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'

    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage '1-pickup' `
                                       -Edge 'success' -Difficulty $difficulty -To $To

    # 1. A commit to open the pull request against, judged against the SAME base the pull request
    #    will use. The two must agree: asking 'does this branch differ from origin/main' while
    #    opening the pull request against another branch answers a question nobody asked.
    Add-PickupMarkerCommit -Worktree $Worktree -Item $Item -BaseRef "origin/$Base"

    # 2. Publish the branch. Nothing is stamped yet.
    & git -C $Worktree push -u origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'The branch push failed, so there is nothing to open a pull request against.' }

    # 3. The draft pull request. The body carries the Sessions bullet and nothing else: a script
    #    cannot write a good description, and the item does not ask it to.
    $title = "$(Get-ItemTitle -Path $record.Path) (backlog $Item)"
    $body = Get-SessionsBody
    & gh pr create --draft --base $Base --head $branch --title $title --body $body
    if ($LASTEXITCODE -ne 0) {
        throw ('gh pr create failed, so the Stage was not stamped. The branch is pushed; ' +
               'open the pull request and run this again.')
    }

    # 4. Only now the stamp.
    Set-ItemStage -Path $record.Path -Stage $target
    & git -C $Worktree add -- $record.RelativePath
    $message = "docs: $Item at $target"
    if ($Note) { $message = "$message, $Note" }
    & git -C $Worktree commit -m $message
    if ($LASTEXITCODE -ne 0) { throw 'The stamp commit failed.' }

    & git -C $Worktree push origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'The stamp was committed but not pushed. Push it before anything else.' }

    Write-Host "Item $Item is now at $target, with a draft pull request open."
}

function Invoke-ShipTransition {
    param([string] $Worktree, [string] $Item, [int] $Pr, [string] $Note = '')

    Assert-TransitionAllowed -Worktree $Worktree

    $branch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
    $record = Find-TransitionItem -Worktree $Worktree -Item $Item
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'

    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage $record.Stages[0] `
                                       -Edge 'success' -Difficulty (Get-ItemDifficulty -Path $record.Path)

    # The records decide the flip. Test results do not: the five-step Gate stays outside this
    # script, which checks records and never runs tests.
    $boxes = Get-AcceptanceBoxCount -Lines (Get-Content -LiteralPath $record.Path)
    if ($boxes.Total -eq 0) {
        throw "Item $Item has no acceptance boxes, so Ship cannot confirm the work is done."
    }
    if ($boxes.Ticked -ne $boxes.Total) {
        throw ("Item $Item has $($boxes.Total - $boxes.Ticked) unticked acceptance box(es). " +
               'Tick them at Document, or write into the item why a box stays unticked.')
    }
    if ($Pr -le 0) { throw 'Ship needs -Pr: the pull request number to flip to ready.' }

    Invoke-RemotePreflight -Worktree $Worktree -Branch $branch

    # Close the records: move the item, delete the progress file, set the Stage. One commit.
    $destination = Join-Path (Join-Path $Worktree 'backlog/done') (Split-Path -Leaf $record.Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Move-Item -LiteralPath $record.Path -Destination $destination
    Set-ItemStage -Path $destination -Stage $target

    $progress = Join-Path $Worktree 'PLAN-PROGRESS.md'
    if (Test-Path -LiteralPath $progress) { Remove-Item -LiteralPath $progress -Force }

    & git -C $Worktree add -A -- backlog PLAN-PROGRESS.md
    $message = "docs: $Item close the records"
    if ($Note) { $message = "$message, $Note" }
    & git -C $Worktree commit -m $message
    if ($LASTEXITCODE -ne 0) { throw 'The closure commit failed.' }

    # Push BEFORE the flip. A merge of an unpushed closure drops the records.
    & git -C $Worktree push origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'The closure commit was made but not pushed. Push it before flipping to ready.' }

    & gh pr ready $Pr --repo s205109/AHKFlowApp
    if ($LASTEXITCODE -ne 0) { throw 'The records are closed and pushed, but the ready flip failed. Flip it by hand.' }

    Write-Host "Item $Item is closed at $target, pushed, and the pull request is ready."
}

# One entry point picks the path. Pickup, Ship, and a housekeeping round each have mechanics the
# ordinary path does not, and the caller must not have to know which is which.
function Invoke-Transition {
    Assert-TransitionAllowed -Worktree $Worktree

    $record = Find-TransitionItem -Worktree $Worktree -Item $Item
    $stage = $record.Stages[0]

    if ($stage -eq '1-pickup' -and $Edge -eq 'success') {
        Invoke-PickupTransition -Worktree $Worktree -Item $Item -To $To -Note $Note -Base $Base
        return
    }

    # Ship is the transition that lands on 9-ship. That is where the records close and the pull
    # request becomes ready, so the target decides the path, not the stage the item is leaving.
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'
    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage $stage -Edge $Edge `
                                       -Difficulty (Get-ItemDifficulty -Path $record.Path) -To $To
    if ($target -eq '9-ship') {
        Invoke-ShipTransition -Worktree $Worktree -Item $Item -Pr $Pr -Note $Note
        return
    }

    Invoke-StageTransition -Worktree $Worktree -Item $Item -Edge $Edge -To $To -Note $Note `
                           -Evidence $Evidence -RecoveryTask $RecoveryTask
}

if ($AsModule) { return }

try {
    Invoke-Transition
    exit 0
} catch {
    Write-Host "REFUSED: $($_.Exception.Message)"
    exit 1
}
