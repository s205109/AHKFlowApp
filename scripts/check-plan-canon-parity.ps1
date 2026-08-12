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
        $edges[$m.Groups[1].Value] = $m.Groups[2].Value.Trim()
    }

    $canonStages[$id] = @{
        Exit  = [regex]::Match($block, '(?m)^- \*\*Exit\*\* — (.+)$').Groups[1].Value.Trim()
        Edges = $edges
    }
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
        # The last arrow in a segment is its target; earlier ones appear inside conditions.
        $edges[$word] = $targets[$targets.Count - 1].Groups[1].Value.Trim()
    }

    $planStages[$id] = @{
        Exit  = [regex]::Match($flat, 'Exit — (.+?) Next —').Groups[1].Value.TrimEnd('.')
        Edges = $edges
    }
}

"canon stages: $($canonStages.Count)   plan stages: $($planStages.Count)"
if ($canonStages.Count -eq 0 -or $planStages.Count -eq 0) {
    throw 'Extracted no stages from one side. The document format changed; fix this script before trusting a green result.'
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
