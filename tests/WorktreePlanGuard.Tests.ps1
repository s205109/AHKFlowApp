#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
. (Join-Path $scriptsDir 'worktree-git.common.ps1')

function Assert-True {
    param($Condition, [string] $Message)
    if ($Condition -isnot [bool]) {
        $caller = (Get-PSCallStack)[1]
        $typeName = if ($null -eq $Condition) { 'null' } else { $Condition.GetType().FullName }
        throw ("Assert-True needs a boolean. Got [$typeName] with $(@($Condition).Count) value(s) " +
            "from line $($caller.ScriptLineNumber): $(@($Condition) -join ' | '). Original message: $Message")
    }
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

# A scratch main checkout, so no case reads the real backlog. The item file and the plan file are
# both optional: which row of the table a case exercises is decided by which of them exist.
$scenarios = @()
function New-Scenario {
    param([string] $ItemBody, [string] $PlanBody)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $root 'backlog') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs\superpowers\plans') -Force | Out-Null
    if ($ItemBody) {
        Set-Content -LiteralPath (Join-Path $root 'backlog\073-probe.md') -Value $ItemBody
    }
    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $root 'docs\superpowers\plans\probe-plan-073.md') -Value $PlanBody
    }
    $script:scenarios += $root
    return $root
}

try {
    # --- Row 5: a plan with no ticked step keeps the worktree ---------------
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``" `
                         -PlanBody "- [ ] Step 1`n- [ ] Step 2"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073'
    Assert-True (-not $verdict.Allow) 'A plan with no ticked step must keep the worktree'
    Assert-True ($verdict.Reason -match 'never implemented') "Reason must say the plan was never implemented, got '$($verdict.Reason)'"

    # --- Row 4: one ticked step allows removal ------------------------------
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``" `
                         -PlanBody "- [x] Step 1`n- [ ] Step 2"
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        'One ticked step means the plan was implemented'

    # A plan with every step ticked has no unticked step at all, which must also allow.
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``" `
                         -PlanBody "- [x] Step 1`n- [x] Step 2"
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        'A fully ticked plan means the plan was implemented'

    # --- Row 3: no Plan bullet, and "Plan: none", both allow removal --------
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: none - trivial" -PlanBody $null
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        '"Plan: none" allows removal'

    $root = New-Scenario -ItemBody "# 073 - probe`n`nNo plan bullet at all." -PlanBody $null
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        'An item with no Plan bullet allows removal'

    # --- Row 1: a recorded item that is missing keeps the worktree ----------
    $root = New-Scenario -ItemBody $null -PlanBody $null
    Assert-True (-not (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow) `
        'A recorded item that cannot be found must keep the worktree'

    # --- Row 2: a Plan bullet naming a missing file keeps the worktree ------
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/gone.md``" -PlanBody $null
    Assert-True (-not (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow) `
        'A plan that cannot be read must keep the worktree'

    # --- Row 6: no recorded item allows removal -----------------------------
    $root = New-Scenario -ItemBody $null -PlanBody $null
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '').Allow `
        'A worktree with no recorded item is a legacy worktree and is allowed through'

    # --- the item is found in done/ too -------------------------------------
    # A worktree usually outlives the pull request that moved its item into backlog/done.
    $root = New-Scenario -ItemBody $null -PlanBody "- [ ] Step 1"
    New-Item -ItemType Directory -Path (Join-Path $root 'backlog\done') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'backlog\done\073-probe.md') `
        -Value "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``"
    Assert-True (-not (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow) `
        'An item in backlog/done is found and judged the same way'

    # --- a bullet written without backticks reads the same ------------------
    # Both forms are in the backlog today.
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: docs/superpowers/plans/probe-plan-073.md" `
                         -PlanBody "- [ ] Step 1"
    Assert-True (-not (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow) `
        'A Plan bullet without backticks is read the same way'

    # --- the sweep carries the guard ----------------------------------------
    $sweepSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')
    Assert-True ($sweepSource -match 'Test-WorktreePlanWasImplemented') 'The sweep must call the plan guard'
    Assert-True ($sweepSource -match 'Get-ManifestBacklogItem') 'The sweep must read the manifest key'
    Assert-True ($sweepSource -match 'Kept: the plan was never implemented\.') 'The sweep writes its own outcome line'

    # --- the watcher's temp copy refuses when the guard cannot run ----------
    # A guard that cannot run is not a guard that passes. The one asymmetry: with no recorded item
    # the fallback still allows, so a legacy worktree never becomes unremovable.
    $removeSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'remove-worktree-local-dev.ps1')
    Assert-True ($removeSource -match 'Get-Command Test-WorktreePlanWasImplemented -ErrorAction SilentlyContinue') `
        'remove-worktree-local-dev.ps1 must carry an inline fallback for the plan guard'
    Assert-True ($removeSource -match 'the plan check could not run') 'The fallback must say why it refused'
    Assert-True ($removeSource -match 'Kept: the plan was never implemented\.') 'The hook gate writes its own outcome line'

    Write-Host 'Worktree plan guard tests passed.'
} finally {
    foreach ($scenario in $scenarios) {
        Remove-Item -LiteralPath $scenario -Recurse -Force -ErrorAction SilentlyContinue
    }
}
