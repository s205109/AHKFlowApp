#Requires -Version 7.0

# Backlog 153. The shipping check used to be a step in ci.yml's repo-invariants job, and ci.yml
# listed ready_for_review so that the step would see the ready flip. Every ready flip then re-ran
# all five ci.yml jobs, about ten minutes, for a step that takes under one second. The check now
# runs alone in .github/workflows/shipping-pr-closes-item.yml.
#
# This suite pins what the rule depends on in that workflow, and proves ci.yml gave up both the
# trigger and the step. It reads text with regular expressions, the same way
# tests/RepoInvariantsCiJob.Tests.ps1 does, because PowerShell ships no YAML parser.
#
# Run it by hand with:  pwsh ./tests/ShippingPrClosesItemWorkflow.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

# YAML and PowerShell both start a comment with '#'. The workflow's own comments explain why the
# base must never come from base.sha, and why the draft state must never come from the event, so a
# match on the raw text would find the forbidden words inside those explanations. Drop every
# whole-line comment first. A '#' later in a line stays, because an expression or a PowerShell
# string can hold one.
function Remove-CommentLine {
    param([AllowEmptyString()][string] $Text)
    $kept = @(($Text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' })
    return ($kept -join "`n")
}

# Every problem the two files have, one line of text each. No problems means the wiring is right.
function Get-ShippingWorkflowProblem {
    param(
        [AllowEmptyString()][string] $WorkflowText,
        [AllowEmptyString()][string] $CiText
    )

    $problems = @()
    $workflow = Remove-CommentLine -Text $WorkflowText
    $ci = Remove-CommentLine -Text $CiText

    if ([string]::IsNullOrWhiteSpace($workflow)) {
        $problems += 'The shipping workflow is missing or empty.'
    }
    else {
        # Every new head commit needs a result. With ready_for_review alone, a push to a ready pull
        # request gets none, and a required check with no result blocks the merge. The list must
        # use the flow form, [a, b], which is how ci.yml writes it.
        $typesMatch = [regex]::Match($workflow, '(?m)^\s+types:\s*\[(?<list>[^\]]*)\]')
        $types = @()
        if ($typesMatch.Success) {
            $types = @($typesMatch.Groups['list'].Value -split ',' |
                ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        foreach ($type in @('opened', 'synchronize', 'reopened', 'ready_for_review')) {
            if ($types -notcontains $type) {
                $problems += "The shipping workflow must run on the pull request type '$type'."
            }
        }

        # The check reads the merge base, so the checkout needs the whole history.
        if ($workflow -notmatch '(?m)^\s+fetch-depth:\s*0\s*(#.*)?$') {
            $problems += 'The shipping workflow must check out with fetch-depth: 0.'
        }

        # The head comes from the event: a pull_request checkout is the merge commit, so HEAD is
        # not the branch head. The base comes from git merge-base: base.sha is the tip of main,
        # not the fork point, and it pulls in items that other branches changed.
        if ($workflow -notmatch 'github\.event\.pull_request\.head\.sha') {
            $problems += 'The shipping workflow must take the head from github.event.pull_request.head.sha.'
        }
        if ($workflow -notmatch 'git merge-base') {
            $problems += 'The shipping workflow must take the base from git merge-base.'
        }
        if ($workflow -match 'base\.sha') {
            $problems += 'The shipping workflow must never read base.sha.'
        }

        # The draft state is read at run time, never taken from the event payload. Two runs can
        # report on one commit, and GitHub says the order they finish in "is not guaranteed". A run
        # that trusts the payload reports the state the event carried, which can be a stale 'draft'
        # that passes a pull request that is now ready. A run that reads the API reports the state
        # the pull request is in now, so both runs reach the same verdict in any order, and so does
        # a re-run of an old run.
        if ($workflow -match 'github\.event\.pull_request\.draft') {
            $problems += 'The shipping workflow must never read the draft state from github.event.pull_request.draft. A stale payload can pass a ready pull request.'
        }
        if ($workflow -notmatch 'gh api .*pulls/') {
            $problems += 'The shipping workflow must read the pull request at run time with gh api.'
        }
        if ($workflow -notmatch "--jq '\.draft'") {
            $problems += "The shipping workflow must read the draft state with --jq '.draft'."
        }
        if ($workflow -notmatch '(?m)^\s+pull-requests:\s*read\s*(#.*)?$') {
            $problems += 'The shipping workflow needs the pull-requests: read permission. Without it the draft read fails.'
        }
        if ($workflow -notmatch 'GH_TOKEN') {
            $problems += 'The shipping workflow must give gh a token in GH_TOKEN.'
        }
        # Two runs on one commit read the state at different moments. The log line is what tells a
        # reader which state each run used, and it is the only evidence the two runs leave behind.
        if ($workflow -notmatch 'draft state at run time') {
            $problems += 'The shipping workflow must print the draft state it read, so a run log shows which state that run used.'
        }

        if ($workflow -notmatch 'scripts/check-shipping-pr-closes-item\.ps1') {
            $problems += 'The shipping workflow must run scripts/check-shipping-pr-closes-item.ps1.'
        }
        foreach ($parameter in @('-MergeBase', '-TargetCommit', '-PullRequestIsDraft')) {
            if ($workflow -notmatch [regex]::Escape($parameter)) {
                $problems += "The shipping workflow must pass $parameter to the check."
            }
        }

        # A draft must report success from the script, never a skip. An if: on the job or on a
        # step can turn the check into a skip, so the file holds none.
        if ($workflow -match '(?m)^\s*(-\s+)?if:') {
            $problems += 'The shipping workflow must hold no if: condition. A draft passes inside the script.'
        }

        # One run at a time per pull request. Stage 9 pushes, then flips to ready seconds later, so
        # two runs of this job can report on one commit. The queue saves duplicate work and keeps
        # the common case in order. Correctness rests on the run-time draft read above, not here.
        if ($workflow -notmatch '(?m)^concurrency:\s*$') {
            $problems += 'The shipping workflow must declare a top-level concurrency group.'
        }
        if ($workflow -notmatch '(?m)^\s+group:.*github\.event\.pull_request\.number') {
            $problems += 'The concurrency group must be keyed on github.event.pull_request.number.'
        }
        if ($workflow -notmatch '(?m)^\s+cancel-in-progress:\s*false\s*(#.*)?$') {
            $problems += 'The concurrency group must queue runs: cancel-in-progress: false.'
        }

        # Branch protection requires this exact job name.
        if ($workflow -notmatch '(?m)^  shipping-pr-closes-item:\s*$') {
            $problems += "The shipping workflow must define the job 'shipping-pr-closes-item'. Branch protection requires that name."
        }
    }

    if ($ci -match 'ready_for_review') {
        $problems += 'ci.yml must not run on ready_for_review. The shipping workflow owns the ready flip.'
    }
    if ($ci -match 'check-shipping-pr-closes-item') {
        $problems += 'ci.yml must not run the shipping check. The shipping workflow runs it.'
    }

    return @($problems)
}

$workflowPath = Join-Path $repoRoot '.github/workflows/shipping-pr-closes-item.yml'
$ciPath = Join-Path $repoRoot '.github/workflows/ci.yml'

$workflowText = ''
if (Test-Path -LiteralPath $workflowPath) { $workflowText = [System.IO.File]::ReadAllText($workflowPath) }
$ciText = [System.IO.File]::ReadAllText($ciPath)

# --- The real files ---

foreach ($problem in @(Get-ShippingWorkflowProblem -WorkflowText $workflowText -CiText $ciText)) {
    Assert-True $false $problem
}

# --- Each assertion can go red ---

# A replacement that changes nothing proves nothing, and its case would pass for the wrong reason.
function Get-Mutation {
    param([string] $Text, [string] $Old, [string] $New)
    if (-not $Text.Contains($Old)) {
        throw "The mutation target '$Old' is not in the text. Fix this suite, not the workflow."
    }
    return $Text.Replace($Old, $New)
}

function Test-MutationCase {
    param([string] $Name, [string] $WorkflowText, [string] $CiText, [string] $Expected)
    $found = @(Get-ShippingWorkflowProblem -WorkflowText $WorkflowText -CiText $CiText)
    $hit = @($found | Where-Object { $_.Contains($Expected) })
    Assert-True ($hit.Count -gt 0) "Mutation '$Name' must report a problem containing '$Expected'. Got: $($found -join ' | ')"
}

# The cases need the real workflow to mutate. Before it exists, the real-file section above is
# already red, so nothing is lost by skipping them.
if ($workflowText) {
    $readyOnly = Get-Mutation $workflowText 'types: [opened, synchronize, reopened, ready_for_review]' 'types: [ready_for_review]'
    Test-MutationCase 'ready_for_review alone' $readyOnly $ciText "type 'synchronize'"

    $shallow = Get-Mutation $workflowText 'fetch-depth: 0' 'fetch-depth: 1'
    Test-MutationCase 'shallow checkout' $shallow $ciText 'fetch-depth: 0'

    $eventBase = Get-Mutation $workflowText '(git merge-base $head origin/main)' '''${{ github.event.pull_request.base.sha }}'''
    Test-MutationCase 'base from the event' $eventBase $ciText 'never read base.sha'
    Test-MutationCase 'base from the event, no merge-base' $eventBase $ciText 'from git merge-base'

    # The hole the review found. A run that trusts the payload can report a stale green.
    $eventDraft = Get-Mutation $workflowText "          `$draftNow = (@(gh api ""repos/`${{ github.repository }}/pulls/`$number"" --jq '.draft') -join '').Trim()" "          `$draftNow = '`${{ github.event.pull_request.draft }}'"
    Test-MutationCase 'draft from the event payload' $eventDraft $ciText 'never read the draft state from github.event.pull_request.draft'
    Test-MutationCase 'draft from the event payload, no gh api' $eventDraft $ciText 'at run time with gh api'

    # The case above drops 'gh api' as well, so it cannot show that the --jq assertion goes red on
    # its own. This one keeps the call and changes only the field it asks for.
    $wrongField = Get-Mutation $workflowText "--jq '.draft'" "--jq '.state'"
    Test-MutationCase 'gh api asks for the wrong field' $wrongField $ciText "with --jq '.draft'"

    $noPermission = Get-Mutation $workflowText "`n  pull-requests: read" ''
    Test-MutationCase 'no pull-requests permission' $noPermission $ciText 'pull-requests: read permission'

    $noToken = Get-Mutation $workflowText 'GH_TOKEN: ${{ github.token }}' 'CI: true'
    Test-MutationCase 'no token for gh' $noToken $ciText 'token in GH_TOKEN'

    $quiet = Get-Mutation $workflowText 'draft state at run time: $draftNow' 'checked'
    Test-MutationCase 'run log does not say which state it read' $quiet $ciText 'must print the draft state it read'

    $skipped = Get-Mutation $workflowText "    runs-on: ubuntu-latest" "    if: github.event.pull_request.draft == false`n    runs-on: ubuntu-latest"
    Test-MutationCase 'job skipped for drafts' $skipped $ciText 'no if: condition'

    $cancelling = Get-Mutation $workflowText 'cancel-in-progress: false' 'cancel-in-progress: true'
    Test-MutationCase 'cancel instead of queue' $cancelling $ciText 'queue runs'

    $renamed = Get-Mutation $workflowText '  shipping-pr-closes-item:' '  shipping-check:'
    Test-MutationCase 'job renamed' $renamed $ciText "job 'shipping-pr-closes-item'"

    Test-MutationCase 'workflow missing' '' $ciText 'missing or empty'

    $ciReady = Get-Mutation $ciText 'types: [opened, synchronize, reopened]' 'types: [opened, synchronize, reopened, ready_for_review]'
    Test-MutationCase 'ci.yml runs on the ready flip again' $workflowText $ciReady 'ci.yml must not run on ready_for_review'

    $ciStep = $ciText + "`n      - run: ./scripts/check-shipping-pr-closes-item.ps1`n"
    Test-MutationCase 'ci.yml runs the check again' $workflowText $ciStep 'ci.yml must not run the shipping check'

    # The opposite direction: a comment that names a forbidden term must not count. The real
    # workflow has such comments only by chance, so this case adds both on purpose.
    $commented = $workflowText + "`n# base.sha is never read here.`n# github.event.pull_request.draft is never read here.`n"
    $commentProblems = @(Get-ShippingWorkflowProblem -WorkflowText $commented -CiText $ciText)
    Assert-True ($commentProblems.Count -eq 0) "A comment that names base.sha or the draft payload must not be a problem. Got: $($commentProblems -join ' | ')"
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "ShippingPrClosesItemWorkflow tests failed with $($failures.Count) problem(s)."
}

Write-Host 'ShippingPrClosesItemWorkflow tests passed.'
