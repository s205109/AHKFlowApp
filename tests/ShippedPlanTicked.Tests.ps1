#Requires -Version 7.0

# CI cannot see the plans repository (.gitignore keeps docs/superpowers out), so this suite tests
# the rule against fixture folders. Pre-push applies it to the real plans.
#
# Never point a case at the real docs/superpowers. Every worktree links to that one folder, and it
# is shared live.
#
# Run it by hand with:  pwsh ./tests/ShippedPlanTicked.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $suiteRoot 'scripts/check-shipped-plan-ticked.ps1') -AsModule

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

function New-Root {
    param([string] $Prefix)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $script:roots += $root
    return $root
}

# A scratch checkout holding a backlog folder and a plans folder, so no case reads the real ones.
function New-CheckoutFixture {
    param(
        [string] $Number = '073',
        [string] $Folder = 'backlog/done',
        [string] $Stage = '9-ship',
        [AllowEmptyString()][string] $PlanBullet = '- Plan: `docs/superpowers/plans/probe-plan-073.md`',
        [AllowEmptyString()][string] $PlanBody = ''
    )

    $root = New-Root -Prefix 'shipped-plan'
    New-Item -ItemType Directory -Path (Join-Path $root 'backlog/done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs/superpowers/plans') -Force | Out-Null

    $body = @("# $Number - probe", '', "- **Stage**: $Stage", '')
    if ($PlanBullet) { $body += $PlanBullet }
    New-Item -ItemType Directory -Path (Join-Path $root $Folder) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root "$Folder/$Number-probe.md") -Value ($body -join "`n") -Encoding utf8

    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $root 'docs/superpowers/plans/probe-plan-073.md') `
            -Value $PlanBody -Encoding utf8
    }
    return $root
}

function New-ItemRecord {
    param([string] $Number = '073', [string] $RelativePath = 'backlog/done/073-probe.md')
    return [pscustomobject]@{ Number = $Number; RelativePath = $RelativePath; Stage = '9-ship' }
}

# A throwaway git repository, built the way tests/PrePushHook.Tests.ps1 builds one.
function New-TempGitRepo {
    $root = New-Root -Prefix 'shipped-plan-git'
    New-Item -ItemType Directory -Path (Join-Path $root 'backlog/done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs/superpowers/plans') -Force | Out-Null

    & git -C $root init *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Shipped Plan Test' *> $null
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'seed' -Encoding utf8
    & git -C $root add -A *> $null
    & git -C $root commit -m 'seed' *> $null

    return (Resolve-Path -LiteralPath $root).Path
}

function Write-Item {
    param(
        [string] $Root,
        [string] $Number,
        [string] $Folder = 'backlog',
        [string] $Stage = '9-ship',
        [string] $Extra = ''
    )

    New-Item -ItemType Directory -Path (Join-Path $Root $Folder) -Force | Out-Null
    $body = @("# $Number - probe", '', "- **Stage**: $Stage", '', '- Plan: none - trivial')
    if ($Extra) { $body += $Extra }
    Set-Content -LiteralPath (Join-Path $Root "$Folder/$Number-probe.md") -Value ($body -join "`n") -Encoding utf8
}

function Get-BaseSha {
    param([string] $Root)
    return ((& git -C $Root rev-parse HEAD) | Out-String).Trim()
}

try {
    # === Test-BacklogItemIsNewlyShipped: plain data, no git ==================

    # 1. The base does not carry the item at all, so this branch filed and shipped it.
    Assert-True (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship') -WorkingPath 'backlog/done/073-probe.md' `
        -BaseStages @() -BasePath '') 'An item absent from the base is shipped by this branch'

    # 2. The base has it open at an earlier stage.
    Assert-True (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship') -WorkingPath 'backlog/done/073-probe.md' `
        -BaseStages @('8-review') -BasePath 'backlog/073-probe.md') `
        'An item the base holds at 8-review is shipped by this branch'

    # 3. The base already has it shipped and filed. This is the case that keeps the items already
    #    sitting in backlog/done/ inert: without it, a branch that fixed a typo in one of them
    #    would have its push refused for debt it did not create.
    Assert-True (-not (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship') -WorkingPath 'backlog/done/073-probe.md' `
        -BaseStages @('9-ship') -BasePath 'backlog/done/073-probe.md')) `
        'An item already shipped in the base is not shipped again by this branch'

    # 4. The plain rename: the Stage line was already 9-ship and this branch only ran 'git mv'.
    Assert-True (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship') -WorkingPath 'backlog/done/073-probe.md' `
        -BaseStages @('9-ship') -BasePath 'backlog/073-probe.md') `
        'A branch that only moves the file into backlog/done is still the shipper'

    # 5. The Stage line moved before the file did.
    Assert-True (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship') -WorkingPath 'backlog/073-probe.md' `
        -BaseStages @('8-review') -BasePath 'backlog/073-probe.md') `
        'An item stamped 9-ship while still in backlog/ is shipped by this branch'

    # 6. Not at 9-ship, whatever the base says.
    Assert-True (-not (Test-BacklogItemIsNewlyShipped -WorkingStages @('6-verify') -WorkingPath 'backlog/073-probe.md' `
        -BaseStages @() -BasePath '')) 'An item at 6-verify is not shipped'

    # 7 and 8. No Stage line, or two of them. Both belong to the backlog numbering check, and this
    #    one must not report them a second time.
    Assert-True (-not (Test-BacklogItemIsNewlyShipped -WorkingStages @() -WorkingPath 'backlog/073-probe.md' `
        -BaseStages @() -BasePath '')) 'An item with no Stage line is skipped'
    Assert-True (-not (Test-BacklogItemIsNewlyShipped -WorkingStages @('9-ship', '9-ship') -WorkingPath 'backlog/073-probe.md' `
        -BaseStages @() -BasePath '')) 'An item with two Stage lines is skipped'

    # === Get-ShippedPlanTickFailure: fixture folders =========================

    # 9. Unticked steps and none ticked. Reported, naming the plan file and the counts.
    $root = New-CheckoutFixture -PlanBody "- [ ] Step 1`n- [ ] Step 2`n- [ ] Step 3"
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 1 $result.Failures.Count 'A plan with no ticked step is reported'
    if ($result.Failures.Count -eq 1) {
        Assert-True ($result.Failures[0].PlanPath -match 'probe-plan-073\.md$') `
            "The failure must name the plan file, got '$($result.Failures[0].PlanPath)'"
        Assert-Equal 3 $result.Failures[0].UntickedCount 'The failure must carry the unticked count'
        Assert-Equal 0 $result.Failures[0].TickedCount 'The failure must carry the ticked count'
        Assert-Equal 'backlog/done/073-probe.md' $result.Failures[0].ItemPath 'The failure must name the item file'
    }

    # 10. One ticked step and nine unticked. Silent: work can be descoped.
    $root = New-CheckoutFixture -PlanBody ("- [x] Step 1`n" + (1..9 | ForEach-Object { "- [ ] Step $_" }) -join "`n")
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count 'A plan with one ticked step passes'
    Assert-Equal 0 $result.Diagnostics.Count 'A plan with one ticked step prints no diagnostic'

    # 11. Every step ticked.
    $root = New-CheckoutFixture -PlanBody "- [x] Step 1`n- [x] Step 2"
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count 'A fully ticked plan passes'

    # 12. No checkbox at all. Measured on 2026-09-03: 68 of the 180 plans in
    #     docs/superpowers/plans/ carry no checkbox, and the guard allows every one of them.
    $root = New-CheckoutFixture -PlanBody "# A plan written as prose, with no step list at all."
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count 'A plan with no checkbox passes'

    # 13. A '- Plan:' bullet reading 'none' with a reason.
    $root = New-CheckoutFixture -PlanBullet '- Plan: none - trivial' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count '"Plan: none" passes'
    Assert-Equal 0 $result.Diagnostics.Count '"Plan: none" prints no diagnostic'

    # 14. No '- Plan:' bullet at all.
    $root = New-CheckoutFixture -PlanBullet '' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count 'An item with no Plan bullet passes'

    # 15. A pointer naming a file that is not there. That is a real problem, but it is not this
    #     item's problem, so it prints one diagnostic and does not fail the push.
    $root = New-CheckoutFixture -PlanBullet '- Plan: `docs/superpowers/plans/gone.md`' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $root -Item @(New-ItemRecord)
    Assert-Equal 0 $result.Failures.Count 'A missing plan file does not fail the push'
    Assert-Equal 1 $result.Diagnostics.Count 'A missing plan file prints one diagnostic'

    # === Get-BranchShippedItem: throwaway git repositories ===================

    # 16. A branch that adds an item at 9-ship under backlog/done/.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship'
    # Committed, because 'git diff --name-only <base>' never reports an untracked file, and
    # pre-push runs after the commit anyway.
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'file and ship 073' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base)
    Assert-Equal 1 $shipped.Count 'A newly added shipped item is returned'
    if ($shipped.Count -eq 1) { Assert-Equal '073' $shipped[0].Number 'The returned record names the item' }

    # 17. A branch that only edits the body of an item the base already shipped. This is the
    #     typo-fix case, and it is the one that decides whether the gate survives.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'ship 073' *> $null
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship' -Extra '- Typo repaired.'
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base)
    Assert-Equal 0 $shipped.Count 'Editing an item the base already shipped returns nothing'

    # 18. A branch that only moves an item into backlog/done/, its Stage line already 9-ship. The
    #     diff names two paths for that one number, and exactly one record must come back.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Number '073' -Folder 'backlog' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'stamp 073' *> $null
    $base = Get-BaseSha -Root $repo
    & git -C $repo mv 'backlog/073-probe.md' 'backlog/done/073-probe.md' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base)
    Assert-Equal 1 $shipped.Count 'A plain rename into backlog/done returns exactly one record'

    # 19. A suffixed item. A digits-only pattern would skip 022b in silence.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '022b' -Folder 'backlog/done' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'file and ship 022b' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base)
    Assert-Equal 1 $shipped.Count 'A suffixed item is not skipped'
    if ($shipped.Count -eq 1) { Assert-Equal '022b' $shipped[0].Number 'The suffixed number is returned whole' }

    # 20. A branch that touches nothing under backlog/.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'edited' -Encoding utf8
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base)
    Assert-Equal 0 $shipped.Count 'A branch that touches no backlog file ships nothing'

    # 21. An unresolvable merge base must throw, never return empty. An empty list would switch the
    #     whole check off in silence.
    $repo = New-TempGitRepo
    $threw = $false
    try {
        $null = Get-BranchShippedItem -RepoRoot $repo -MergeBase '0000000000000000000000000000000000000000'
    } catch {
        $threw = $true
    }
    Assert-True $threw 'An unresolvable merge base must throw'

    # === the pre-push wiring, as written down ================================
    # This is a source assertion. It does not prove the step runs, because pre-push builds the
    # solution first and no unit test can afford that. It does stop a later edit from deleting the
    # step while this suite stays green. Task 5 of the plan supplies the one behavioural proof.
    $prePushSource = Get-Content -Raw -LiteralPath (Join-Path $suiteRoot 'scripts/pre-push-quick-checks.ps1')
    Assert-True ($prePushSource -match 'check-shipped-plan-ticked\.ps1') `
        'pre-push-quick-checks.ps1 must run check-shipped-plan-ticked.ps1'
    Assert-True ($prePushSource -match '-MergeBase \(\[string\] \$mergeBase\)\.Trim\(\)') `
        'pre-push must hand the step the merge base the citation step already resolved'
    Assert-True ($prePushSource -match '(?s)check-shipped-plan-ticked\.ps1.*?\$LASTEXITCODE -ne 0.*?throw ') `
        'pre-push must throw when the check exits non-zero'

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
        throw "$($failures.Count) shipped-plan tick check test(s) failed."
    }

    Write-Host 'Shipped plan tick check tests passed.'
} finally {
    foreach ($root in $roots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
