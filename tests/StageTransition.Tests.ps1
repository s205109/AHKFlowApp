#Requires -Version 7.0

# Run it by hand with:  pwsh ./tests/StageTransition.Tests.ps1
#
# Never point a case at the real docs/superpowers. Every worktree links to that one folder and it
# is shared live.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $suiteRoot 'scripts/stage-transition.common.ps1')
. (Join-Path $suiteRoot 'scripts/backlog-snapshot.common.ps1')

$failures = @()
$roots = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:failures += "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern, [string] $Message)
    try {
        & $Action
        $script:failures += "$Message (expected a throw, got none)"
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            $script:failures += "$Message (throw did not match '$Pattern': $($_.Exception.Message))"
        }
    }
}

try {
    $workflow = Join-Path $suiteRoot 'docs/development/workflow.md'

    # The real document is the fixture here. It is read-only for this suite, and reading it is the
    # whole point: a copied fixture would stop catching the drift this item exists to catch.
    $pickup = @(Get-StageEdgeTarget -WorkflowPath $workflow -Stage 'stage-1-pickup' -Edge 'success')
    Assert-Equal 3 $pickup.Count 'Pickup success must name three candidate stages'
    Assert-True ($pickup -contains '2-design') 'Pickup success must offer 2-design'
    Assert-True ($pickup -contains '3-plan')   'Pickup success must offer 3-plan'
    Assert-True ($pickup -contains '4-execute') 'Pickup success must offer 4-execute'

    $design = @(Get-StageEdgeTarget -WorkflowPath $workflow -Stage 'stage-2-design' -Edge 'success')
    Assert-Equal 1 $design.Count 'Design success must name one stage'
    Assert-Equal '3-plan' $design[0] 'Design success must target 3-plan'

    # An Edge whose target names no stage returns nothing, rather than a made-up stage id.
    $blocked = @(Get-StageEdgeTarget -WorkflowPath $workflow -Stage 'stage-2-design' -Edge 'blocked')
    Assert-Equal 0 $blocked.Count 'A blocked Edge names no stage'

    Assert-Equal '2-design' (Get-DifficultyJumpStage -WorkflowPath $workflow -Difficulty 'complex') `
        'complex must jump to 2-design'
    Assert-Equal '3-plan' (Get-DifficultyJumpStage -WorkflowPath $workflow -Difficulty 'moderate') `
        'moderate must jump to 3-plan'
    Assert-Equal '2-design' (Get-DifficultyJumpStage -WorkflowPath $workflow -Difficulty 'to-be-determined') `
        'to-be-determined must jump to 2-design'

    # The cross-check: the jump table's answer must be one the Edge allows.
    Assert-Equal '2-design' (Resolve-TransitionTarget -WorkflowPath $workflow -Stage 'stage-1-pickup' -Edge 'success' -Difficulty 'complex' -To '') `
        'Pickup with complex resolves to 2-design'

    Assert-Throws { Resolve-TransitionTarget -WorkflowPath $workflow -Stage 'stage-1-pickup' -Edge 'success' -Difficulty 'complex' -To '3-plan' } `
        'disagrees' 'A -To that contradicts Difficulty must throw'

    Assert-Throws { Resolve-TransitionTarget -WorkflowPath $workflow -Stage 'stage-2-design' -Edge 'success' -Difficulty 'complex' -To '9-ship' } `
        'not a target' 'A -To outside the Edge target set must throw'

    Assert-Throws { Resolve-TransitionTarget -WorkflowPath $workflow -Stage 'stage-2-design' -Edge 'resume' -Difficulty 'complex' -To '' } `
        'not a transition' 'The resume Edge must be refused'

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
        throw "$($failures.Count) stage transition test(s) failed."
    }

    Write-Host 'Stage transition tests passed.'
} finally {
    foreach ($root in $roots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
