#Requires -Version 7.0
<#
.SYNOPSIS
    Compares a plan's Appendix A against the canonical process in workflow.md.

.DESCRIPTION
    A plan that transcribes the stage machine becomes a second normative source. When the
    canon changes and the transcription does not, a resumed session follows the stale copy.
    Reviews of backlog 071 found that drift three rounds running, each time by hand.

    This checks every stage on both sides for the exit string and all five edge targets.
    It does not read the narrative fields - Action, Technique, Context - so a green result
    means the stage machine agrees, not that every sentence does.

    Exits 1 on any difference, so it can be used as a gate step.

.PARAMETER PlanPath
    The plan to check. Defaults to the backlog-071 plan in the private plans repo.

.PARAMETER CanonPath
    The canonical process document. Defaults to docs/development/workflow.md.

.EXAMPLE
    pwsh ./scripts/check-plan-canon-parity.ps1
#>
[CmdletBinding()]
param(
    [string] $PlanPath,
    [string] $CanonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $CanonPath) { $CanonPath = Join-Path $repoRoot 'docs\development\workflow.md' }
if (-not $PlanPath) {
    $PlanPath = Join-Path $repoRoot 'docs\superpowers\plans\2026-08-10-development-process-plan-071.md'
}

foreach ($path in @($CanonPath, $PlanPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Not found: $path" }
}

$canon = (Get-Content -LiteralPath $CanonPath -Raw) -replace "`r`n", "`n"
$plan = (Get-Content -LiteralPath $PlanPath -Raw) -replace "`r`n", "`n"

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

# Appendix A only. The last stage otherwise runs to end-of-file, and the greedy edge match
# swallows Appendix B's walkthrough arrows - round 7 hid real Stage 10 drift that way.
# Both headings are required. A lazy match with an end-of-file fallback would drop the bound
# silently the day Appendix B is renamed, which is that same failure a second time.
if ($plan -notmatch '(?m)^## Appendix A') { throw 'Appendix A not found in the plan. Fix this script before trusting a green result.' }
if ($plan -notmatch '(?m)^## Appendix B') { throw 'Appendix B not found in the plan, so Appendix A has no end bound. Fix this script before trusting a green result.' }
$plan = [regex]::Match($plan, '(?sm)^## Appendix A.*?(?=^## Appendix B)').Value

# The canon carries one explicit anchor per stage, then a five-row edge table.
$canonStages = [ordered]@{}
$anchors = [regex]::Matches($canon, '<a id="stage-([0-9a-z-]+)"></a>')
for ($i = 0; $i -lt $anchors.Count; $i++) {
    $id = $anchors[$i].Groups[1].Value
    $start = $anchors[$i].Index
    $end = if ($i + 1 -lt $anchors.Count) { $anchors[$i + 1].Index } else { $canon.Length }
    $block = $canon.Substring($start, $end - $start)

    $edges = [ordered]@{}
    foreach ($m in [regex]::Matches($block, '(?m)^\| (success|failure|blocked|not applicable|resume) \| [^|]+ \| ([^|]+) \|$')) {
        $word = $m.Groups[1].Value
        # A duplicate must be reported, never silently overwritten: a wrong row followed by
        # a correct one passed before this check existed.
        if ($edges.Contains($word)) { $problems.Add("canon/$id : duplicate '$word' edge") ; continue }
        $edges[$word] = $m.Groups[2].Value.Trim()
    }

    $exitMatches = [regex]::Matches($block, '(?m)^- \*\*Exit\*\* — (.+)$')
    $exit = if ($exitMatches.Count -ge 1) { $exitMatches[0].Groups[1].Value.Trim() } else { '' }
    Assert-StageShape -Side 'canon' -Id $id -Exit $exit -Edges $edges -ExitCount $exitMatches.Count

    $canonStages[$id] = @{ Exit = $exit; Edges = $edges }
}

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

    $edges = [ordered]@{}
    foreach ($segment in ([regex]::Match($flat, 'Edges: (.+)$').Groups[1].Value -split ' · ')) {
        $word = [regex]::Match($segment, '^\s*(not applicable|success|failure|blocked|resume)').Groups[1].Value
        if (-not $word) { continue }
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

"canon stages: $($canonStages.Count)   plan stages: $($planStages.Count)"

# Count is asserted, not merely reported. A document whose format drifted extracts fewer
# stages, and comparing whatever survived is how a check passes vacuously.
if ($canonStages.Count -ne $expectedStageCount) { $problems.Add("canon: expected $expectedStageCount stages, extracted $($canonStages.Count)") }
if ($planStages.Count -ne $expectedStageCount) { $problems.Add("plan: expected $expectedStageCount stages, extracted $($planStages.Count)") }
foreach ($id in $planStages.Keys) {
    if (-not $canonStages.Contains($id)) { $problems.Add("plan/$id : stage not present in the canon") }
}

if ($problems.Count) {
    ''
    'STRUCTURE:'
    $problems | ForEach-Object { "  $_" }
    ''
    "RESULT: $($problems.Count) structural problem(s). Nothing was compared."
    exit 1
}

$differences = 0
foreach ($id in $canonStages.Keys) {
    if (-not $planStages.Contains($id)) {
        "MISSING in plan: $id"
        $differences++
        continue
    }

    $canonExit = ($canonStages[$id].Exit -replace '\s+', ' ').TrimEnd('.')
    $planExit = ($planStages[$id].Exit -replace '\s+', ' ').TrimEnd('.')
    if ($canonExit -cne $planExit) {
        "EXIT  $id"
        "   canon: $canonExit"
        "   plan : $planExit"
        $differences++
    }

    foreach ($edge in $canonStages[$id].Edges.Keys) {
        $canonTarget = $canonStages[$id].Edges[$edge]
        $planTarget = if ($planStages[$id].Edges.Contains($edge)) { $planStages[$id].Edges[$edge] } else { '<missing>' }
        if ($canonTarget -cne $planTarget) {
            "EDGE  $id / $edge   canon=$canonTarget   plan=$planTarget"
            $differences++
        }
    }
}

''
if ($differences) {
    "RESULT: $differences difference(s). workflow.md wins - fix the plan."
    exit 1
}

'RESULT: Appendix A matches the canon on every exit and edge target'
