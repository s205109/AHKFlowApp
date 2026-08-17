#Requires -Version 7.0
<#
.SYNOPSIS
    Compares a plan's Appendix A against the canonical process in workflow.md.

.DESCRIPTION
    A plan that transcribes the stage machine becomes a second place the rules live. When
    `workflow.md` changes and the transcription does not, a resumed session follows the stale
    copy.
    Reviews of backlog 071 found that drift three rounds running, each time by hand.

    This checks every stage on both sides for the exit string and all five edge targets.

    The narrative fields - Action, Technique, Context - are NOT compared. They are prose, and
    a plan legitimately compresses them. A green result means the stage machine agrees, not
    that every sentence does.

    Exits 1 on any difference, so it can be used as a gate step.

.PARAMETER PlanPath
    A single plan to check. Defaults to the backlog-071 plan in the private plans repo when
    neither -PlanPath nor -PlansRoot is given.

.PARAMETER PlansRoot
    A folder to search. Every '*.md' under it carrying an '## Appendix A' heading is checked.
    An absent folder, or one with no such plan, prints a reason and exits 0: the plans
    repository is not in the checkout in CI, and a check that cannot run must say so rather
    than fail the run.

.PARAMETER RequirePlans
    Fail when -PlansRoot exists but holds no plan with an '## Appendix A'. Pre-push passes
    this: there, the plans repository IS in the checkout, so an empty result means the
    discovery missed something rather than that there is nothing to check.

.PARAMETER WorkflowPath
    The canonical process document. Defaults to docs/development/workflow.md.

.NOTES
    Exit strings are compared with one deliberate tolerance: a trailing period is trimmed from
    both sides. Appendix A writes the exit as prose - 'Exit — <text> Next —' - so a plan ends
    the sentence and the source's bullet does not. Nothing else is trimmed, and the comparison
    is case-sensitive. The document-to-document check in check-process-parity.ps1 has no such
    tolerance, because those three files hold the same string rather than the same sentence.

.EXAMPLE
    pwsh ./scripts/check-plan-workflow-parity.ps1
.EXAMPLE
    pwsh ./scripts/check-plan-workflow-parity.ps1 -PlansRoot docs/superpowers/plans
#>
[CmdletBinding()]
param(
    [string] $PlanPath,
    [string] $PlansRoot,
    [string] $WorkflowPath,
    [switch] $RequirePlans
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

if (-not $WorkflowPath) { $WorkflowPath = Join-Path $repoRoot 'docs/development/workflow.md' }
if (-not $PlanPath -and -not $PlansRoot) {
    $PlanPath = Join-Path $repoRoot 'docs/superpowers/plans/2026-08-10-development-process-plan-071.md'
}

if (-not (Test-Path -LiteralPath $WorkflowPath)) { throw "Not found: $WorkflowPath" }

# Discover the plans to check. A plan without an '## Appendix A' transcribes no stage machine,
# so there is nothing for this check to compare.
#
# Up to three leading spaces is still a Markdown heading, so the pattern allows them. Anchoring
# at column one alone meant an indented heading was not a plan at all, and the run reported
# nothing to check rather than a difference.
$appendixA = '(?m)^ {0,3}## Appendix A'
$appendixB = '(?m)^ {0,3}## Appendix B'
$planPaths = @()
if ($PlansRoot) {
    if (-not (Test-Path -LiteralPath $PlansRoot)) {
        "RESULT: skipped - the plans folder $PlansRoot is not in this checkout"
        exit 0
    }
    $planPaths = @(Get-ChildItem -LiteralPath $PlansRoot -Filter '*.md' -File -Recurse |
            Where-Object { (Get-NormalizedText -Path $_.FullName) -match $appendixA } |
            ForEach-Object { $_.FullName })
    if (-not $planPaths) {
        if ($RequirePlans) {
            "RESULT: no plan under $PlansRoot carries an '## Appendix A'. The folder is here, so this is a discovery failure, not an empty job."
            exit 1
        }
        "RESULT: skipped - no plan under $PlansRoot carries an '## Appendix A'"
        exit 0
    }
}
else {
    if (-not (Test-Path -LiteralPath $PlanPath)) { throw "Not found: $PlanPath" }
    $planPaths = @($PlanPath)
}

$workflowStages = Get-WorkflowStage -Path $WorkflowPath

# Every stage must yield exactly one exit and these five edges, on both sides. Without this
# the check fails open: a deleted row, a deleted Exit, or a duplicated edge all compare
# equal to nothing and pass. Review round 7 proved all three.
$expectedStageCount = 11
$requiredEdges = @('success', 'failure', 'blocked', 'not applicable', 'resume')
$problems = New-Object System.Collections.Generic.List[string]

function Assert-StageShape {
    param([string] $Side, [string] $Id, [string] $Exit, $Edges, [int] $ExitCount)

    if ($ExitCount -ne 1) { $script:problems.Add("$Side/$Id : expected 1 Exit, found $ExitCount") }
    elseif ([string]::IsNullOrWhiteSpace($Exit)) { $script:problems.Add("$Side/$Id : Exit is empty") }

    foreach ($edge in $script:requiredEdges) {
        if (-not $Edges.Contains($edge)) { $script:problems.Add("$Side/$Id : missing '$edge' edge") }
    }
    foreach ($edge in $Edges.Keys) {
        if ($script:requiredEdges -notcontains $edge) { $script:problems.Add("$Side/$Id : unexpected edge '$edge'") }
        if ([string]::IsNullOrWhiteSpace($Edges[$edge])) { $script:problems.Add("$Side/$Id : '$edge' has an empty target") }
    }
}

# The source comes from the shared parser, so a format change is handled in one place. The
# duplicate report it carries is kept: a wrong edge row followed by a correct one passed
# before this check existed, and sharing the parser must not drop that.
foreach ($id in $workflowStages.Keys) {
    foreach ($word in $workflowStages[$id].Duplicates) {
        $problems.Add("source/$id : duplicate '$word' edge")
    }
    Assert-StageShape -Side 'source' -Id $id -Exit $workflowStages[$id].Exit -Edges $workflowStages[$id].Edges -ExitCount $workflowStages[$id].ExitCount
}

# The source's own problems belong to every plan's report, so each plan starts from them.
$workflowProblems = @($problems)

$exitCode = 0
foreach ($currentPlanPath in $planPaths) {
    ''
    "PLAN: $currentPlanPath"
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($workflowProblem in $workflowProblems) { $problems.Add($workflowProblem) }
    $plan = Get-NormalizedText -Path $currentPlanPath

# Appendix A only. The last stage otherwise runs to end-of-file, and the greedy edge match
# swallows Appendix B's walkthrough arrows - round 7 hid real Stage 10 drift that way.
# Both headings are required. A lazy match with an end-of-file fallback would drop the bound
# silently the day Appendix B is renamed, which is that same failure a second time.
if ($plan -notmatch $appendixA) { throw "Appendix A not found in $currentPlanPath. Fix this script before trusting a green result." }
if ($plan -notmatch $appendixB) { throw "Appendix B not found in $currentPlanPath, so Appendix A has no end bound. Fix this script before trusting a green result." }
$plan = [regex]::Match($plan, '(?sm)^ {0,3}## Appendix A.*?(?=^ {0,3}## Appendix B)').Value

# Appendix A writes each stage as prose, wrapped mid-sentence. Flatten before matching:
# splitting the edge list on ' · ' against unflattened text silently under-reports, which
# reported seven false differences the first time this was written.
$planStages = [ordered]@{}
$heads = [regex]::Matches($plan, '#### Stage \d+ — [^(]+\(`stage-([0-9a-z-]+)`\)')
for ($i = 0; $i -lt $heads.Count; $i++) {
    $id = $heads[$i].Groups[1].Value
    $start = $heads[$i].Index
    $end = if ($i + 1 -lt $heads.Count) { $heads[$i + 1].Index } else { $plan.Length }
    $flat = ($plan.Substring($start, $end - $start) -replace "\n", ' ') -replace '\s+', ' '

    if ($planStages.Contains($id)) {
        # Assigning by id let a second block replace the first while the count still read 11,
        # so a plan carrying two Stage 0 blocks passed with one of them never compared.
        $problems.Add("plan/$id : the stage is written more than once; it repeats")
        continue
    }

    $edges = [ordered]@{}
    foreach ($segment in ([regex]::Match($flat, 'Edges: (.+)$').Groups[1].Value -split ' · ')) {
        # The edge word ends where the word ends. Without the boundary, 'successfully' read as
        # 'success', so a segment that is not an edge at all answered for one that is.
        $word = [regex]::Match($segment, '^\s*(not applicable|success|failure|blocked|resume)(?![A-Za-z])').Groups[1].Value
        if (-not $word) {
            # An unknown segment used to be skipped, so a plan could invent an edge the stage
            # machine does not have and stay green. A segment that looks like an edge but is
            # not one of the five is a difference, not noise.
            $invented = [regex]::Match($segment, '^\s*([A-Za-z][A-Za-z ]*?)\s*→').Groups[1].Value
            if ($invented) { $problems.Add("plan/$id : edge '$invented' is not one of the five") }
            continue
        }
        $targets = [regex]::Matches($segment, '→\s*`([^`]+)`')
        if ($targets.Count -eq 0) { continue }
        if ($edges.Contains($word)) { $problems.Add("plan/$id : duplicate '$word' edge") ; continue }
        # The last arrow in a segment is its target; earlier ones appear inside conditions.
        $edges[$word] = $targets[$targets.Count - 1].Groups[1].Value.Trim()
    }

    $exitMatches = [regex]::Matches($flat, 'Exit — (.+?) Next —')
    $exit = if ($exitMatches.Count -ge 1) { $exitMatches[0].Groups[1].Value.TrimEnd('.') } else { '' }
    Assert-StageShape -Side 'plan' -Id $id -Exit $exit -Edges $edges -ExitCount $exitMatches.Count

    $planStages[$id] = @{ Exit = $exit; Edges = $edges }
}

"source stages: $($workflowStages.Count)   plan stages: $($planStages.Count)"

# Count is asserted, not merely reported. A document whose format drifted extracts fewer
# stages, and comparing whatever survived is how a check passes vacuously.
if ($workflowStages.Count -ne $expectedStageCount) { $problems.Add("source: expected $expectedStageCount stages, extracted $($workflowStages.Count)") }
if ($planStages.Count -ne $expectedStageCount) { $problems.Add("plan: expected $expectedStageCount stages, extracted $($planStages.Count)") }
foreach ($id in $planStages.Keys) {
    if (-not $workflowStages.Contains($id)) { $problems.Add("plan/$id : stage not present in the source") }
}

if ($problems.Count) {
    ''
    'STRUCTURE:'
    $problems | ForEach-Object { "  $_" }
    ''
    "RESULT: $($problems.Count) structural problem(s) in $currentPlanPath. Nothing was compared."
    $exitCode = 1
    continue
}

$differences = 0
foreach ($id in $workflowStages.Keys) {
    if (-not $planStages.Contains($id)) {
        "MISSING in plan: $id"
        $differences++
        continue
    }

    $workflowExit = ($workflowStages[$id].Exit -replace '\s+', ' ').TrimEnd('.')
    $planExit = ($planStages[$id].Exit -replace '\s+', ' ').TrimEnd('.')
    if ($workflowExit -cne $planExit) {
        "EXIT  $id"
        "   source: $workflowExit"
        "   plan : $planExit"
        $differences++
    }

    foreach ($edge in $workflowStages[$id].Edges.Keys) {
        $workflowTarget = $workflowStages[$id].Edges[$edge]
        $planTarget = if ($planStages[$id].Edges.Contains($edge)) { $planStages[$id].Edges[$edge] } else { '<missing>' }
        if ($workflowTarget -cne $planTarget) {
            "EDGE  $id / $edge   source=$workflowTarget   plan=$planTarget"
            $differences++
        }
    }
}

''
if ($differences) {
    "RESULT: $differences difference(s) in $currentPlanPath. workflow.md wins - fix the plan."
    $exitCode = 1
    continue
}

"RESULT: Appendix A matches the source on every exit and edge target in $currentPlanPath"
}

''
"Plans checked: $($planPaths.Count). The narrative fields - Action, Technique, Context - stay manual."
exit $exitCode
