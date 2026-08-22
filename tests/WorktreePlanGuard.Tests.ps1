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

# Windows PowerShell turns a native command's stderr into an error record, and the file-wide 'Stop'
# preference makes it terminating. Git writes hints and warnings to stderr on success, so this
# suite would fail under powershell.exe while passing under pwsh. The exit code is the real signal.
function Invoke-QuietGit {
    param([string] $RepoDir, [string[]] $GitArgs)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>&1
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
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

    # --- a Plan bullet that ends with a full stop reads the same ------------
    # backlog/031 writes it that way, and scripts/backlog.common.ps1 accepts it, so the guard
    # must not refuse a plan it can plainly see.
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``." `
                         -PlanBody "- [x] Step 1"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073'
    Assert-True $verdict.Allow "A Plan bullet ending with a full stop must be read, got '$($verdict.Reason)'"

    # --- an unreadable manifest must never read as a legacy worktree --------
    # Get-ManifestBacklogItem returns the sentinel when the file is there but cannot be read.
    # Treating that as "nothing to judge" would remove the worktree without checking its plan.
    $root = New-Scenario -ItemBody $null -PlanBody $null
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber $WorktreeBacklogItemUnreadable
    Assert-True (-not $verdict.Allow) 'An unreadable manifest must keep the worktree'
    Assert-True ($verdict.Reason -match 'could not be read') "Reason must say the manifest could not be read, got '$($verdict.Reason)'"

    $manifestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-m-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $scenarios += $manifestRoot
    New-Item -ItemType Directory -Path (Join-Path $manifestRoot 'scripts') -Force | Out-Null
    $manifestFile = Join-Path $manifestRoot 'scripts\.env.worktree'
    Set-Content -LiteralPath $manifestFile -Value 'AHKFLOW_BACKLOG_ITEM=073'
    Assert-Equal '073' (Get-ManifestBacklogItem -WorktreePath $manifestRoot) 'A readable manifest returns its recorded item'

    $held = [System.IO.File]::Open($manifestFile, 'Open', 'Read', 'None')
    try {
        Assert-Equal $WorktreeBacklogItemUnreadable (Get-ManifestBacklogItem -WorktreePath $manifestRoot) `
            'A manifest another process holds must read as unreadable, not as empty'
    } finally {
        $held.Dispose()
    }

    # --- the base ref decides, not a stale working tree ---------------------
    # The merge gate asks about the resolved base. An item filed on the branch and merged on
    # GitHub is in that ref long before a local pull puts it on disk.
    $refRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-r-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $scenarios += $refRoot
    New-Item -ItemType Directory -Path (Join-Path $refRoot 'backlog') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $refRoot 'docs\superpowers\plans') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $refRoot 'docs\superpowers\plans\probe-plan-073.md') -Value "- [ ] Step 1"
    Invoke-QuietGit $refRoot @('init')
    Invoke-QuietGit $refRoot @('symbolic-ref', 'HEAD', 'refs/heads/main')
    Invoke-QuietGit $refRoot @('config', 'user.email', 'test@example.com')
    Invoke-QuietGit $refRoot @('config', 'user.name', 'Plan Guard Test')
    Set-Content -LiteralPath (Join-Path $refRoot 'backlog\073-probe.md') `
        -Value "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``"
    Invoke-QuietGit $refRoot @('add', '-A')
    Invoke-QuietGit $refRoot @('commit', '-m', 'file 073')
    # The stale local checkout: the item never landed on disk.
    Remove-Item -LiteralPath (Join-Path $refRoot 'backlog\073-probe.md') -Force

    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $refRoot -ItemNumber '073'
    Assert-True (-not $verdict.Allow) 'Without a base ref the working tree still decides'

    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $refRoot -ItemNumber '073' -BaseRef 'main'
    Assert-True (-not $verdict.Allow) 'The item read from the base ref names an unimplemented plan'
    Assert-True ($verdict.Reason -match 'never implemented') `
        "The base ref must supply the item, got '$($verdict.Reason)'"

    # --- a supplied base that cannot answer refuses, it does not fall back ---
    # Falling back to the working tree throws away the reason the base was resolved. A stale
    # local item saying "Plan: none" would then allow the very removal the guard exists to stop.
    $staleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-s-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $scenarios += $staleRoot
    New-Item -ItemType Directory -Path (Join-Path $staleRoot 'backlog') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $staleRoot 'docs\superpowers\plans') -Force | Out-Null
    Invoke-QuietGit $staleRoot @('init')
    Invoke-QuietGit $staleRoot @('symbolic-ref', 'HEAD', 'refs/heads/main')
    Invoke-QuietGit $staleRoot @('config', 'user.email', 'test@example.com')
    Invoke-QuietGit $staleRoot @('config', 'user.name', 'Plan Guard Test')
    Set-Content -LiteralPath (Join-Path $staleRoot 'README.md') -Value 'seed'
    Invoke-QuietGit $staleRoot @('add', '-A')
    Invoke-QuietGit $staleRoot @('commit', '-m', 'seed')
    # On disk only, never committed: the stale reading the guard must not trust.
    Set-Content -LiteralPath (Join-Path $staleRoot 'backlog\073-probe.md') -Value "# 073 - probe`n`n- Plan: none - nothing to do"

    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $staleRoot -ItemNumber '073' -BaseRef 'main'
    Assert-True (-not $verdict.Allow) `
        'A base that does not carry the item must refuse, not read the working tree'
    Assert-True ($verdict.Reason -match "not in 'main'") `
        "The reason must name the base, got '$($verdict.Reason)'"

    # A base that cannot be resolved at all is the same answer for a different reason.
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $staleRoot -ItemNumber '073' -BaseRef 'no-such-ref'
    Assert-True (-not $verdict.Allow) 'A base that cannot be resolved must refuse'
    Assert-True ($verdict.Reason -match 'could not be resolved') `
        "The reason must say the base could not be resolved, got '$($verdict.Reason)'"

    # Two items sharing one number cannot be told apart, so that refuses too.
    Set-Content -LiteralPath (Join-Path $staleRoot 'backlog\073-first.md') -Value '# 073 - first'
    New-Item -ItemType Directory -Path (Join-Path $staleRoot 'backlog\done') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $staleRoot 'backlog\done\073-second.md') -Value '# 073 - second'
    Invoke-QuietGit $staleRoot @('add', '-A')
    Invoke-QuietGit $staleRoot @('commit', '-m', 'two items share 073')
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $staleRoot -ItemNumber '073' -BaseRef 'main'
    Assert-True (-not $verdict.Allow) 'Two items sharing one number must refuse'

    # --- a plan pointer must name a file under docs/superpowers/plans -------
    # The pointer is read straight off a markdown bullet. Any other existing file is almost
    # certain to hold no unticked step, which would read as "implemented" and allow removal.
    foreach ($escape in @('README.md', '../README.md', 'docs/superpowers/plans/../../../README.md', 'docs/superpowers/specs/some-design.md')) {
        $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``$escape``" -PlanBody $null
        Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'no checkboxes here'
        New-Item -ItemType Directory -Path (Join-Path $root 'docs\superpowers\specs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'docs\superpowers\specs\some-design.md') -Value 'no checkboxes here'
        $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073'
        Assert-True (-not $verdict.Allow) "A plan pointer of '$escape' must keep the worktree"
    }

    # The two shapes the backlog really uses still work.
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: ``docs/superpowers/plans/probe-plan-073.md``" `
                         -PlanBody "- [x] Step 1"
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        'A backtick-quoted pointer under the plans folder still reads'
    $root = New-Scenario -ItemBody "# 073 - probe`n`n- Plan: docs/superpowers/plans/probe-plan-073.md" `
                         -PlanBody "- [x] Step 1"
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '073').Allow `
        'An unquoted pointer, as backlog/done/104 writes it, still reads'

    # --- the hook gate asks the guard only after the merge gate -------------
    # Asking first made an unmerged worktree fail with the plan guard's wording, and read the
    # working tree while the merge gate read the resolved base.
    $removeSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'remove-worktree-local-dev.ps1')
    Assert-True ($removeSource -match '(?s)Test-WorktreeClean.*plan gate:') `
        'remove-worktree-local-dev.ps1 must run the plan gate after the merge and clean gates'
    Assert-True ($removeSource -match '-BaseRef \$baseRef') `
        'The hook gate must hand the resolved base to the plan guard'

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
