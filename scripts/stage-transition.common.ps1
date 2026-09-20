#Requires -Version 7.0
<#
.SYNOPSIS
    Reads the legal stage transitions out of docs/development/workflow.md.
.DESCRIPTION
    Backlog 081. Every legal target is read from the document at run time. A list copied into a
    script is one more copy of a process rule, and copies of process rules drift.

    Two tables in workflow.md speak about Pickup's target. The stage's own Edge table names the
    candidates. The Difficulty jump table says which candidate a Difficulty picks. Both are read,
    and they check each other, so an edit to one table and not the other stops the script rather
    than picking a stage the Edge does not allow.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

# The Edge words this reader will resolve. Two of the five are deliberately absent, for the
# same reason: neither writes a Stage field. 'resume' targets 'stay', and 'blocked' targets the
# backlog/blocked/ folder, which is a move and not a stage.
$script:TransitionEdge = @('success', 'failure', 'not applicable')

# Get-WorkflowStage keys its dictionary by the bare stage id, because its anchor regex captures
# the text after 'stage-'. Callers hold the id in both spellings: an item's Stage field reads
# '2-design', and a workflow.md link reads '#stage-2-design'. Accepting both here keeps that
# difference out of every call site.
function Get-BareStageId {
    param([Parameter(Mandatory)][string] $Stage)
    return ($Stage -replace '^stage-', '')
}

function Get-StageEdgeTarget {
    param(
        [Parameter(Mandatory)][string] $WorkflowPath,
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $Edge
    )

    $id = Get-BareStageId -Stage $Stage
    $stages = Get-WorkflowStage -Path $WorkflowPath
    if (-not $stages.Contains($id)) {
        throw "workflow.md has no stage '$id'."
    }

    $edges = $stages[$id].Edges
    if (-not $edges.Contains($Edge)) {
        throw "Stage '$id' has no '$Edge' edge in workflow.md."
    }

    # The raw target string, as the table gives it: one stage id, several separated by '/', or a
    # word that names no stage at all, such as 'blocked/', 'stay', 'none' or 'terminal'.
    $raw = $edges[$Edge]

    return @($raw -split '/' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+-[a-z-]+$' })
}

function Get-DifficultyJumpStage {
    param(
        [Parameter(Mandatory)][string] $WorkflowPath,
        [Parameter(Mandatory)][string] $Difficulty
    )

    $text = (Get-Content -LiteralPath $WorkflowPath -Raw) -replace "`r`n", "`n"

    # The row links a stage anchor, so the stage id is read from the link rather than spelled out
    # here. Example row: | `complex` | [Design](#stage-2-design) | Spec, then plan, then execution |
    $pattern = '(?m)^\|\s*`' + [regex]::Escape($Difficulty) + '`\s*\|\s*\[[^\]]+\]\(#stage-(?<id>[0-9a-z-]+)\)'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw "workflow.md's Difficulty jump table has no row for '$Difficulty'."
    }

    return $match.Groups['id'].Value
}

function Resolve-TransitionTarget {
    param(
        [Parameter(Mandatory)][string] $WorkflowPath,
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $Edge,
        [AllowEmptyString()][string] $Difficulty = '',
        [AllowEmptyString()][string] $To = ''
    )

    if ($Edge -notin $script:TransitionEdge) {
        throw "'$Edge' is not a transition. Legal edges: $($script:TransitionEdge -join ', ')."
    }

    $id = Get-BareStageId -Stage $Stage
    $candidates = @(Get-StageEdgeTarget -WorkflowPath $WorkflowPath -Stage $id -Edge $Edge)
    if ($candidates.Count -eq 0) {
        throw "The '$Edge' edge of '$id' names no stage, so there is no field to write."
    }

    if ($candidates.Count -eq 1) {
        if ($To -and $To -ne $candidates[0]) {
            throw "-To '$To' is not a target of '$Edge' from '$id'. The only target is '$($candidates[0])'."
        }
        return $candidates[0]
    }

    # Several candidates. Difficulty picks, and -To may confirm but never override.
    if (-not $Difficulty) {
        throw "The '$Edge' edge of '$id' names several targets, so the item's Difficulty is needed to pick one."
    }

    $picked = Get-DifficultyJumpStage -WorkflowPath $WorkflowPath -Difficulty $Difficulty
    if ($picked -notin $candidates) {
        throw ("workflow.md disagrees with itself: Difficulty '$Difficulty' jumps to '$picked', " +
               "which is not a target of '$Edge' from '$id' ($($candidates -join ', ')). Fix the document first.")
    }

    if ($To -and $To -ne $picked) {
        throw "-To '$To' disagrees with Difficulty '$Difficulty', which jumps to '$picked'. Revise the item's Difficulty, or drop -To."
    }

    return $picked
}
