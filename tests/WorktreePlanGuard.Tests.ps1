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

    # --- the worktree name decides which item is judged ---------------------
    # The recorded number goes stale: a renumber is a hand `git mv` plus a heading edit, and
    # nothing rewrites the manifest. The worktree directory name carries the title slug, which a
    # renumber never changes, so the slug names the item the worktree really serves.

    # A scratch checkout with two items whose verdicts differ, so which one was judged is visible
    # in the answer rather than only in a field.
    function New-SlugScenario {
        param(
            [string] $OwnSlug = 'give-each-worktree-removal',
            [string] $OwnNumber = '120',
            [string] $OwnFolder = 'backlog',
            [string] $OwnPlanBody = "- [x] Step 1",
            [string] $RecordedNumber = '118'
        )

        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-slug-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $root 'backlog') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root ('docs\superpowers\plans')) -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root $OwnFolder) -Force | Out-Null
        $script:scenarios += $root

        # The item the worktree name points at. Its plan is implemented, so judging it allows.
        Set-Content -LiteralPath (Join-Path $root ('docs\superpowers\plans\own-plan.md')) -Value $OwnPlanBody
        Set-Content -LiteralPath (Join-Path $root (Join-Path $OwnFolder "$OwnNumber-$OwnSlug.md")) `
            -Value "# $OwnNumber - own`n`n- Plan: ``docs/superpowers/plans/own-plan.md``"

        # The item the manifest still records. Somebody else's item, still open, with the unfilled
        # template pointer -- exactly the shape that kept one finished worktree alive for days.
        if ($RecordedNumber) {
            Set-Content -LiteralPath (Join-Path $root "backlog\$RecordedNumber-a-different-title.md") `
                -Value "# $RecordedNumber - other`n`n- Plan: <path, or ""none - reason"">"
        }

        return $root
    }

    $root = New-SlugScenario
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow "The item the worktree name matches must be judged, got '$($verdict.Reason)'"
    Assert-Equal '120' $verdict.ItemNumber 'The verdict reports the item it judged'
    Assert-Equal '118' $verdict.RecordedItemNumber 'The verdict still reports what the manifest recorded'
    Assert-True ($verdict.Reason -match 'records item 118') `
        "A disagreement must name both numbers, got '$($verdict.Reason)'"

    # The same wiring in the refusing direction, so the case cannot pass by allowing everything.
    $root = New-SlugScenario -OwnPlanBody "- [ ] Step 1"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True (-not $verdict.Allow) 'An unimplemented plan on the name-matched item must still refuse'
    Assert-True ($verdict.Reason -match 'item 120') "The refusal must name item 120, got '$($verdict.Reason)'"

    # --- the name-matched item is found in backlog/done too -----------------
    # This is the worktree that started this item: its own item shipped, and the sweep kept
    # refusing because the manifest still named an open item belonging to somebody else.
    $root = New-SlugScenario -OwnFolder 'backlog\done'
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow "A shipped item in backlog/done must still resolve by slug, got '$($verdict.Reason)'"
    Assert-Equal '120' $verdict.ItemNumber 'The done/ item is the one judged'

    # blocked/ is scanned as well, for the same reason.
    $root = New-SlugScenario -OwnFolder 'backlog\blocked'
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal').Allow `
        'An item in backlog/blocked must resolve by slug'

    # --- a name that matches nothing falls back to the recorded number ------
    # Never the other way round. A slug that matches nothing must not skip a check the guard would
    # otherwise make, or any worktree whose name does not match its item would walk past the gate.
    $root = New-SlugScenario
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-no-item-has-this-slug'
    Assert-True (-not $verdict.Allow) 'A name that matches no item falls back to the recorded number'
    Assert-Equal '118' $verdict.ItemNumber 'The fallback judges the recorded number'
    Assert-True ($verdict.Reason -match 'backlog item 118 names a plan outside') `
        "The refusal must come from judging item 118, not from the slug lookup, got '$($verdict.Reason)'"
    Assert-True (-not ($verdict.Reason -match 'records item')) `
        "Numbers that agree must not be reported as a disagreement, got '$($verdict.Reason)'"

    # The case that tells "fell back and refused" apart from "refused instead of falling back":
    # the recorded item allows. Refusing on `absent` would keep every worktree whose name does not
    # match an item, which is most of them, and a guard that always fires gets ignored.
    $root = New-SlugScenario -RecordedNumber ''
    Set-Content -LiteralPath (Join-Path $root 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: none - nothing to do"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-no-item-has-this-slug'
    Assert-True $verdict.Allow `
        "A slug that matches nothing must fall back, not refuse, got '$($verdict.Reason)'"
    Assert-Equal '118' $verdict.ItemNumber 'The fallback judges the recorded number'

    # --- a name and a number that agree give the same verdict as before -----
    $root = New-SlugScenario -OwnNumber '120' -RecordedNumber ''
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '120' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow 'A name and a number that agree keep the old verdict'
    Assert-Equal '120' $verdict.RecordedItemNumber 'Agreement still reports the recorded number'

    # --- a leaf with no wt- prefix runs the number path, and throws nothing --
    $root = New-SlugScenario
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'plain-directory-name'
    Assert-True (-not $verdict.Allow) 'A leaf with no wt- prefix runs the number path'
    Assert-Equal '118' $verdict.ItemNumber 'A leaf with no wt- prefix judges the recorded number'
    Assert-Equal '' (Get-WorktreeSlugFromName -WorktreeName 'plain-directory-name') 'A name without the prefix has no slug'
    Assert-Equal '' (Get-WorktreeSlugFromName -WorktreeName '') 'An empty name has no slug'
    Assert-Equal 'probe' (Get-WorktreeSlugFromName -WorktreeName 'C:\somewhere\wt-probe\') 'A full path yields its leaf slug'

    # --- an empty recorded number still allows, even when the name matches ---
    # The empty-number allow stays ahead of the name lookup. A worktree with nothing recorded is
    # removable by contract, and production always passes a name, so this case must pass one too.
    $root = New-SlugScenario -OwnPlanBody "- [ ] Step 1"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow 'An empty recorded number allows removal even when the name matches an item'
    Assert-True ($verdict.Reason -match 'no backlog item is recorded') `
        "The empty-number reason must not change, got '$($verdict.Reason)'"

    # --- a suffixed item number resolves through the slug route -------------
    # A collision is settled by suffixing a number, so 022b is a real shape. A digits-only pattern
    # would skip it in silence and fall back to a number that is not this worktree's.
    $root = New-SlugScenario -OwnNumber '022b'
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow "A suffixed item number must resolve, got '$($verdict.Reason)'"
    Assert-Equal '022b' $verdict.ItemNumber 'The suffixed number is reported as the item judged'

    # --- a slug lookup that cannot answer refuses, it never falls back ------
    # Two statuses are not one. "absent" means no item carries this slug, so the recorded number is
    # the only thing left to judge, and judging it is the old behaviour. "unusable" means the slug
    # DID name this worktree's item and the lookup could not deliver it. Falling back there judges a
    # different item, which is the defect this whole change exists to stop.
    $root = New-SlugScenario
    Set-Content -LiteralPath (Join-Path $root 'backlog\131-give-each-worktree-removal.md') `
        -Value "# 131 - twin`n`n- Plan: none - twin"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True (-not $verdict.Allow) 'Two items sharing one slug must refuse'
    Assert-True ($verdict.Reason -match "2 backlog items carry the slug 'give-each-worktree-removal'") `
        "The refusal must name the ambiguity, got '$($verdict.Reason)'"

    # The case that proves it is a refusal and not a lucky fallback: the recorded item states it has
    # no plan, so judging it would ALLOW. Before this rule the guard removed the worktree here,
    # after judging an item that was never its own.
    $root = New-SlugScenario -RecordedNumber ''
    Set-Content -LiteralPath (Join-Path $root 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: none - nothing to do"
    Set-Content -LiteralPath (Join-Path $root 'backlog\131-give-each-worktree-removal.md') `
        -Value "# 131 - twin`n`n- Plan: none - twin"
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True (-not $verdict.Allow) `
        "An ambiguous slug must refuse even when the recorded item would allow, got '$($verdict.Reason)'"

    # --- an item found by slug but unreadable refuses, and names itself -----
    # The number is already known at that point, so the refusal says which item it could not read.
    # Reporting the recorded number here would blame an item the guard never opened.
    $root = New-SlugScenario -RecordedNumber ''
    Set-Content -LiteralPath (Join-Path $root 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: none - nothing to do"
    $ownItem = Join-Path $root 'backlog\120-give-each-worktree-removal.md'
    $heldItem = [System.IO.File]::Open($ownItem, 'Open', 'Read', 'None')
    try {
        $verdict = Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '118' -WorktreeName 'wt-give-each-worktree-removal'
        Assert-True (-not $verdict.Allow) 'An item another process holds must refuse'
        Assert-Equal '120' $verdict.ItemNumber 'The refusal reports the item it could not read, not the recorded one'
        Assert-True ($verdict.Reason -match 'backlog item 120 could not be read') `
            "The refusal must name the item it could not read, got '$($verdict.Reason)'"
    } finally {
        $heldItem.Dispose()
    }

    # --- an empty recorded number still allows, even on an unusable slug ----
    # The empty-number allow keeps its place ahead of the whole slug route. A worktree with nothing
    # recorded is removable by contract, and the new refusal must not quietly take that away.
    $root = New-SlugScenario -RecordedNumber ''
    Set-Content -LiteralPath (Join-Path $root 'backlog\131-give-each-worktree-removal.md') `
        -Value "# 131 - twin`n`n- Plan: none - twin"
    Assert-True (Test-WorktreePlanWasImplemented -MainCheckout $root -ItemNumber '' -WorktreeName 'wt-give-each-worktree-removal').Allow `
        'An empty recorded number allows removal even when the slug is ambiguous'

    # --- the slug route runs against the base ref as well -------------------
    # The number path reads the base when one is supplied, and the slug path has to read the same
    # base. Otherwise a worktree whose item merged on GitHub is judged from a stale local disk.
    $slugRefRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-planguard-sr-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $scenarios += $slugRefRoot
    New-Item -ItemType Directory -Path (Join-Path $slugRefRoot 'backlog\done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $slugRefRoot 'docs\superpowers\plans') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $slugRefRoot 'docs\superpowers\plans\own-plan.md') -Value "- [x] Step 1"
    Invoke-QuietGit $slugRefRoot @('init')
    Invoke-QuietGit $slugRefRoot @('symbolic-ref', 'HEAD', 'refs/heads/main')
    Invoke-QuietGit $slugRefRoot @('config', 'user.email', 'test@example.com')
    Invoke-QuietGit $slugRefRoot @('config', 'user.name', 'Plan Guard Test')
    Set-Content -LiteralPath (Join-Path $slugRefRoot 'backlog\done\120-give-each-worktree-removal.md') `
        -Value "# 120 - own`n`n- Plan: ``docs/superpowers/plans/own-plan.md``"
    Set-Content -LiteralPath (Join-Path $slugRefRoot 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: <path, or ""none - reason"">"
    Invoke-QuietGit $slugRefRoot @('add', '-A')
    Invoke-QuietGit $slugRefRoot @('commit', '-m', 'two items')

    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $slugRefRoot -ItemNumber '118' -BaseRef 'main' `
        -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True $verdict.Allow "The slug route must read the base ref, got '$($verdict.Reason)'"
    Assert-Equal '120' $verdict.ItemNumber 'The base ref supplies the name-matched item'

    # With no name, the same call still refuses on the recorded number. That is the old behavior,
    # and it is what makes the case above a measurement of the name rather than of the fixture.
    Assert-True (-not (Test-WorktreePlanWasImplemented -MainCheckout $slugRefRoot -ItemNumber '118' -BaseRef 'main').Allow) `
        'Without a name the recorded number still decides'

    # --- the same refusal rule applies on the base-ref route ----------------
    # An unusable answer from the base is not permission to read a different item. Two items sharing
    # the slug in the base ref must keep the worktree, whatever the recorded number would have said.
    Set-Content -LiteralPath (Join-Path $slugRefRoot 'backlog\131-give-each-worktree-removal.md') `
        -Value "# 131 - twin`n`n- Plan: none - twin"
    Set-Content -LiteralPath (Join-Path $slugRefRoot 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: none - nothing to do"
    Invoke-QuietGit $slugRefRoot @('add', '-A')
    Invoke-QuietGit $slugRefRoot @('commit', '-m', 'a second item with the same slug')

    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $slugRefRoot -ItemNumber '118' -BaseRef 'main' `
        -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True (-not $verdict.Allow) `
        "An ambiguous slug in the base must refuse even when the recorded item would allow, got '$($verdict.Reason)'"
    Assert-True ($verdict.Reason -match "2 backlog items carry the slug 'give-each-worktree-removal'") `
        "The base-ref refusal must name the ambiguity, got '$($verdict.Reason)'"

    # A base that cannot be resolved is unusable too, so the slug route refuses rather than
    # quietly handing the decision to the recorded number.
    $verdict = Test-WorktreePlanWasImplemented -MainCheckout $slugRefRoot -ItemNumber '118' -BaseRef 'no-such-ref' `
        -WorktreeName 'wt-give-each-worktree-removal'
    Assert-True (-not $verdict.Allow) 'An unresolvable base must refuse on the slug route as well'
    Assert-True ($verdict.Reason -match 'could not be resolved') `
        "The reason must say the base could not be resolved, got '$($verdict.Reason)'"

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
    Assert-True ($sweepSource -match "Kept: ' \+ \(Format-WorktreeLogReason -Text \`$planVerdict\.Reason\)") `
        "The sweep's outcome line must carry the guard's own reason"
    Assert-True ($sweepSource -match '-WorktreeName \$wtFull') `
        'The sweep must hand the worktree name to the plan guard'

    # --- the watcher's temp copy refuses when the guard cannot run ----------
    # A guard that cannot run is not a guard that passes. The one asymmetry: with no recorded item
    # the fallback still allows, so a legacy worktree never becomes unremovable.
    $removeSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'remove-worktree-local-dev.ps1')
    Assert-True ($removeSource -match 'Get-Command Test-WorktreePlanWasImplemented -ErrorAction SilentlyContinue') `
        'remove-worktree-local-dev.ps1 must carry an inline fallback for the plan guard'
    Assert-True ($removeSource -match 'the plan check could not run') 'The fallback must say why it refused'

    # --- one writer of the Kept line, carrying the reason that applied ------
    # The gate used to write its own fixed sentence and suppress the writer that would have logged
    # the real reason. A human reading worktree-removal.log saw a reason nobody had checked.
    Assert-True (-not ($removeSource -match 'Kept: the plan was never implemented')) `
        'The hook gate must not write a fixed plan-gate sentence any more'
    Assert-True (-not ($removeSource -match 'NoOutcome')) `
        'The hook gate must not suppress the writer that carries the reason'
    Assert-True ($removeSource -match '(?s)plan gate: \$\(\$planVerdict\.Reason\).*?-Reason \$planVerdict\.Reason') `
        "The hook gate must pass the guard's own reason into the preserve guidance"
    Assert-True ($removeSource -match '-WorktreeName \$worktreeFull') `
        'The hook gate must hand the worktree name to the plan guard'

    # Both writers flatten the reason before it reaches the log, so a long or multi-line reason
    # still becomes exactly one line. Format-WorktreeLogReason's own behaviour is pinned by
    # tests/WorktreeRemovalLog.Tests.ps1; what matters here is that neither writer bypasses it.
    Assert-True ($removeSource -match "Write-Outcome \('Kept: ' \+ \(Format-WorktreeLogReason -Text \`$Reason\) \+ '\.'\)") `
        'The hook gate must flatten the reason before it writes the Kept line'
    Assert-Equal 1 (@([regex]::Matches($removeSource, "Write-Outcome \('Kept: ")).Count) `
        'There must be exactly one writer of the Kept line in the hook gate'

    Write-Host 'Worktree plan guard tests passed.'
} finally {
    foreach ($scenario in $scenarios) {
        Remove-Item -LiteralPath $scenario -Recurse -Force -ErrorAction SilentlyContinue
    }
}
