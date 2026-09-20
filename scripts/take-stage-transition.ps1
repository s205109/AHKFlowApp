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
    # 'blocked' is absent on purpose. Its target is the backlog/blocked/ folder, not a stage, so
    # this script has no field to write. Blocking an item stays a manual 'git mv' plus the
    # unblock note, as section 4 of workflow.md describes.
    [ValidateSet('success', 'failure', 'not applicable')]
    [string] $Edge,
    [string] $To = '',
    [string] $Note = '',
    [string] $Evidence = '',
    [string] $RecoveryTask = '',
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

# Everything the three item paths need, gathered once. Each of them used to repeat the same
# five lines, and the dispatcher then resolved the target a second time so it could choose a
# path. One context means workflow.md is parsed once and the item file is read once.
function Get-TransitionContext {
    param(
        [string] $Worktree, [string] $Item, [string] $Edge, [string] $To = ''
    )

    $record = Find-TransitionItem -Worktree $Worktree -Item $Item
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'
    $stage = $record.Stages[0]

    # Resolve before anything is written. A refused transition must change nothing, and the
    # target is also what the dispatcher reads to pick the Ship path.
    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage $stage -Edge $Edge `
                                       -Difficulty $record.Difficulty -To $To

    return [pscustomobject]@{
        Branch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
        Record = $record
        Stage  = $stage
        Target = $target
    }
}

# A pull request number is typed by hand, and a stale or mistyped one points at somebody
# else's work. Every path that mutates a pull request asks GitHub which branch it belongs to
# first, and refuses before it touches any record.
function Assert-PrOnBranch {
    param([int] $Pr, [string] $Branch)

    if ($Pr -le 0) { throw 'This transition needs -Pr: the pull request number it acts on.' }

    $head = (& gh pr view $Pr --repo s205109/AHKFlowApp --json headRefName -q .headRefName) -join ''
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read pull request $Pr. Check the number, and that gh is signed in."
    }

    $head = $head.Trim()
    if ($head -ne $Branch) {
        throw ("Pull request $Pr belongs to branch '$head', but this worktree is on '$Branch'. " +
               'Nothing was changed. Pass the number of this branch''s own pull request.')
    }
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

# Every reason a failure edge could be refused, checked and nothing written. This runs before
# the remote pre-flight, which pushes: a refused transition must change nothing, and the
# pre-flight publishing the branch is a change.
function Assert-FailureEdgeReady {
    param([string] $Worktree, [string] $Evidence, [string] $RecoveryTask, [switch] $HasProgressFile)

    if (-not $Evidence)     { throw 'A failure edge needs -Evidence: the failing command and its output.' }
    if (-not $RecoveryTask) { throw 'A failure edge needs -RecoveryTask: the named task that fixes it.' }

    if ($HasProgressFile -and -not (Test-Path -LiteralPath (Join-Path $Worktree 'PLAN-PROGRESS.md'))) {
        throw ('There is no PLAN-PROGRESS.md, so this work never reached Execute and a failure ' +
               'edge is not possible from here.')
    }
}

function Get-FailureRecordText {
    param([string] $Target, [string] $Evidence, [string] $RecoveryTask)

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

    return $block
}

function Add-FailureRecord {
    param(
        [string] $Worktree, [string] $Target, [string] $Evidence, [string] $RecoveryTask
    )

    Add-Content -LiteralPath (Join-Path $Worktree 'PLAN-PROGRESS.md') `
                -Value (Get-FailureRecordText -Target $Target -Evidence $Evidence -RecoveryTask $RecoveryTask) `
                -Encoding utf8
}

function Invoke-StageTransition {
    param(
        [string] $Worktree, [string] $Item, [pscustomobject] $Context, [string] $Edge,
        [string] $Note = '', [string] $Evidence = '', [string] $RecoveryTask = ''
    )

    $branch = $Context.Branch
    $record = $Context.Record
    $target = $Context.Target

    # Every refusal first, then the pre-flight, then the writes. The pre-flight pushes, so a
    # failure edge judged after it would publish the branch and only then refuse.
    if ($Edge -eq 'failure') {
        Assert-FailureEdgeReady -Worktree $Worktree -Evidence $Evidence `
                                -RecoveryTask $RecoveryTask -HasProgressFile
    }

    Invoke-RemotePreflight -Worktree $Worktree -Branch $branch

    if ($Edge -eq 'failure') {
        Add-FailureRecord -Worktree $Worktree -Target $target `
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

    # The exit code matters as much as the output. git rev-list prints nothing and returns
    # non-zero for a ref it cannot resolve, so reading stdout alone makes a misspelled -Base
    # look like 'this branch has no commits of its own'.
    $own = @(& git -C $Worktree rev-list "$BaseRef..HEAD" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "'$BaseRef' is not a ref this worktree can resolve. Check -Base, and fetch if the branch is new."
    }
    if ($own.Count -gt 0) { return }

    & git -C $Worktree commit --allow-empty -m "chore: $Item pickup, opening draft PR"
    if ($LASTEXITCODE -ne 0) { throw 'The pickup marker commit failed.' }
}

function Invoke-PickupTransition {
    param([string] $Worktree, [string] $Item, [pscustomobject] $Context, [string] $Note = '', [string] $Base = 'main')

    $branch = $Context.Branch
    $record = $Context.Record
    $target = $Context.Target

    # 1. A commit to open the pull request against, judged against the SAME base the pull request
    #    will use. The two must agree: asking 'does this branch differ from origin/main' while
    #    opening the pull request against another branch answers a question nobody asked.
    Add-PickupMarkerCommit -Worktree $Worktree -Item $Item -BaseRef "origin/$Base"

    # 2. Publish the branch. Nothing is stamped yet.
    & git -C $Worktree push -u origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'The branch push failed, so there is nothing to open a pull request against.' }

    # 3. The draft pull request, unless this branch already has one. A session that died
    #    between a successful 'gh pr create' and the stamp leaves exactly that state, and
    #    GitHub refuses a second pull request for the same branch. Without this lookup the
    #    rerun fails forever and the item can never leave 1-pickup.
    $existing = ((& gh pr list --repo s205109/AHKFlowApp --head $branch --state open --json number -q '.[0].number') -join '').Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not ask GitHub whether this branch already has a pull request. Nothing was stamped.'
    }

    if ($existing) {
        Write-Host "Pull request $existing is already open for $branch. Reusing it."
    } else {
        # The body carries the Sessions bullet and nothing else: a script cannot write a good
        # description, and the item does not ask it to.
        $title = "$(Get-ItemTitle -Path $record.Path) (backlog $Item)"
        $body = Get-SessionsBody
        & gh pr create --draft --base $Base --head $branch --title $title --body $body
        if ($LASTEXITCODE -ne 0) {
            throw ('gh pr create failed, so the Stage was not stamped. The branch is pushed; ' +
                   'open the pull request and run this again.')
        }
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
    param([string] $Worktree, [string] $Item, [pscustomobject] $Context, [int] $Pr, [string] $Note = '')

    $branch = $Context.Branch
    $record = $Context.Record
    $target = $Context.Target

    # The pull request number is checked before any record moves, because Ship's whole job is
    # to leave the records and the pull request agreeing with each other.
    Assert-PrOnBranch -Pr $Pr -Branch $branch

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

# A housekeeping round files no item, so its record is the 'Stage:' line in its pull request
# body. The branch name is fixed precisely so a round can be found.
$script:RoundBranch = 'chore/wt-backlog-housekeeping'

function Invoke-RoundTransition {
    param(
        [string] $Worktree, [string] $Edge, [int] $Pr, [string] $To = '',
        [string] $Evidence = '', [string] $RecoveryTask = ''
    )

    Assert-TransitionAllowed -Worktree $Worktree
    if ($Pr -le 0) { throw 'A housekeeping round needs -Pr: the round pull request number.' }

    # A round has no PLAN-PROGRESS.md, so workflow.md puts the same red evidence and recovery
    # task in the pull request body instead. The rule is the same; only the place differs.
    if ($Edge -eq 'failure') {
        Assert-FailureEdgeReady -Worktree $Worktree -Evidence $Evidence -RecoveryTask $RecoveryTask
    }

    # Half the pre-flight applies here. A round has no item and no Stage commit, so there is
    # nothing to compare and nothing of its own to push. A diverged branch is still worth
    # refusing before the body is rewritten.
    $branch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
    Assert-BranchNotDiverged -Worktree $Worktree -Branch $branch
    Assert-PrOnBranch -Pr $Pr -Branch $branch

    $rx = '(?m)^Stage: [^\r\n]+'

    # -join is not cosmetic. PowerShell captures multiline native output as System.Object[], and
    # [regex]::Matches on an array matches nothing.
    $body = (& gh pr view $Pr --repo s205109/AHKFlowApp --json body -q .body) -join "`n"
    $hits = ([regex]::Matches($body, $rx)).Count
    if ($hits -ne 1) { throw "PR $Pr body: expected 1 Stage line, found $hits." }

    $current = ([regex]::Match($body, $rx)).Value -replace '^Stage: ', ''
    $workflow = Join-Path $Worktree 'docs/development/workflow.md'
    $target = Resolve-TransitionTarget -WorkflowPath $workflow -Stage $current -Edge $Edge -To $To

    # gh pr edit --body-file replaces the whole body, so the whole body is written back. A file
    # holding only the Stage line would delete the description.
    $written = $body -replace $rx, "Stage: $target"
    if ($Edge -eq 'failure') {
        $written = $written.TrimEnd() + "`n" +
                   (Get-FailureRecordText -Target $target -Evidence $Evidence -RecoveryTask $RecoveryTask)
    }

    $tmp = New-TemporaryFile
    try {
        $written | Set-Content -LiteralPath $tmp.FullName -Encoding utf8
        & gh pr edit $Pr --repo s205109/AHKFlowApp --body-file $tmp.FullName
        if ($LASTEXITCODE -ne 0) { throw "The round body edit failed. PR $Pr is still at $current." }
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue
    }

    # The read-back is the check, and it is part of the transition.
    $after = (& gh pr view $Pr --repo s205109/AHKFlowApp --json body -q .body) -join "`n"
    # \r? because GitHub returns a pull request body with CRLF line endings, and '$' in
    # multiline mode matches before the '\n' only, so the '\r' would sit in the way.
    $confirmed = ([regex]::Matches($after, "(?m)^Stage: $([regex]::Escape($target))\r?$")).Count
    if ($confirmed -ne 1) {
        throw "Read-back failed: PR $Pr does not read 'Stage: $target'. The round is still at $current."
    }

    # A round flips to ready on the way INTO Ship, the same moment a tracked item does.
    # workflow.md puts the flip in Stage 9's own action: close the records, push, then flip,
    # then wait for CI and merge. Flipping on the way out of Ship would come after the merge,
    # which is too late to be merged at all. A round has no item to move and no closure commit,
    # so nothing is pushed and the push-before-flip rule has nothing to order.
    if ($target -eq '9-ship') {
        & gh pr ready $Pr --repo s205109/AHKFlowApp
        if ($LASTEXITCODE -ne 0) { throw 'The round body is at 9-ship but the ready flip failed.' }
    }

    Write-Host "Round pull request $Pr is now at $target."
}

# One entry point picks the path. Pickup, Ship, and a housekeeping round each have mechanics the
# ordinary path does not, and the caller must not have to know which is which.
function Invoke-Transition {
    Assert-TransitionAllowed -Worktree $Worktree

    # The round is found before the item is looked for, because a round has no item to find.
    # The branch name is the only test. A missing -Item is not a second way in: on an item
    # worktree that would rewrite an arbitrary pull request body, or flip it to ready.
    $onBranch = (& git -C $Worktree rev-parse --abbrev-ref HEAD).Trim()
    if ($onBranch -eq $script:RoundBranch) {
        Invoke-RoundTransition -Worktree $Worktree -Edge $Edge -Pr $Pr -To $To `
                               -Evidence $Evidence -RecoveryTask $RecoveryTask
        return
    }

    if (-not $Item) {
        throw ("This worktree is on '$onBranch', which is not the housekeeping round branch " +
               "'$($script:RoundBranch)'. A tracked transition needs -Item.")
    }

    # Read the item, the branch and the target once, then hand the same context to whichever
    # path runs. Resolving here is also the refusal: an illegal edge or an impossible -To stops
    # the run before any path is chosen.
    $context = Get-TransitionContext -Worktree $Worktree -Item $Item -Edge $Edge -To $To

    if ($context.Stage -eq '1-pickup' -and $Edge -eq 'success') {
        Invoke-PickupTransition -Worktree $Worktree -Item $Item -Context $context -Note $Note -Base $Base
        return
    }

    # Ship is the transition that lands on 9-ship. That is where the records close and the pull
    # request becomes ready, so the target decides the path, not the stage the item is leaving.
    if ($context.Target -eq '9-ship') {
        Invoke-ShipTransition -Worktree $Worktree -Item $Item -Context $context -Pr $Pr -Note $Note
        return
    }

    # Cleanup is reached only after the pull request has merged, and workflow.md says the Stage
    # field is never written after merge: the backlog/done/ location and the merged pull request
    # are the durable record, and a shipped item must keep reading 'Stage: 9-ship'. Writing
    # 10-cleanup would also put a commit on a branch that no longer has anywhere to go.
    if ($context.Target -eq '10-cleanup') {
        throw ('Cleanup writes no Stage field. The item stays at 9-ship in backlog/done/, and ' +
               'the merged pull request is the record. Remove the worktree and the branch instead.')
    }

    Invoke-StageTransition -Worktree $Worktree -Item $Item -Context $context -Edge $Edge -Note $Note `
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
