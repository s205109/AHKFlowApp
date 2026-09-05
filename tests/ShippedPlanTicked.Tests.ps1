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
#
# The backlog item is committed, because the check reads every backlog file from a commit. The plan
# file is left uncommitted on purpose: docs/superpowers is a second repository this one ignores, so
# no commit here ever carries a plan, and the check must read it from disk. Returns the root and
# the commit that holds the item.
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

    & git -C $root init *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Shipped Plan Test' *> $null

    $body = @("# $Number - probe", '', "- **Stage**: $Stage", '')
    if ($PlanBullet) { $body += $PlanBullet }
    New-Item -ItemType Directory -Path (Join-Path $root $Folder) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root "$Folder/$Number-probe.md") -Value ($body -join "`n") -Encoding utf8

    & git -C $root add -A -- backlog *> $null
    & git -C $root commit -m "ship $Number" *> $null

    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $root 'docs/superpowers/plans/probe-plan-073.md') `
            -Value $PlanBody -Encoding utf8
    }
    return [pscustomobject]@{
        Root = (Resolve-Path -LiteralPath $root).Path
        Head = ((& git -C $root rev-parse HEAD) | Out-String).Trim()
    }
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
        [string] $Extra = '',
        [string] $PlanBullet = '- Plan: none - trivial'
    )

    New-Item -ItemType Directory -Path (Join-Path $Root $Folder) -Force | Out-Null
    $body = @("# $Number - probe", '', "- **Stage**: $Stage", '', $PlanBullet)
    if ($Extra) { $body += $Extra }
    Set-Content -LiteralPath (Join-Path $Root "$Folder/$Number-probe.md") -Value ($body -join "`n") -Encoding utf8
}

function Write-Plan {
    param([string] $Root, [string] $Body)

    New-Item -ItemType Directory -Path (Join-Path $Root 'docs/superpowers/plans') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'docs/superpowers/plans/probe-plan-073.md') -Value $Body -Encoding utf8
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
    $fx = New-CheckoutFixture -PlanBody "- [ ] Step 1`n- [ ] Step 2`n- [ ] Step 3"
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 1 $result.Failures.Count 'A plan with no ticked step is reported'
    if ($result.Failures.Count -eq 1) {
        Assert-True ($result.Failures[0].PlanPath -match 'probe-plan-073\.md$') `
            "The failure must name the plan file, got '$($result.Failures[0].PlanPath)'"
        Assert-Equal 3 $result.Failures[0].UntickedCount 'The failure must carry the unticked count'
        Assert-Equal 0 $result.Failures[0].TickedCount 'The failure must carry the ticked count'
        Assert-Equal 'backlog/done/073-probe.md' $result.Failures[0].ItemPath 'The failure must name the item file'
    }

    # 10. One ticked step and nine unticked. Silent: work can be descoped.
    $fx = New-CheckoutFixture -PlanBody ("- [x] Step 1`n" + (1..9 | ForEach-Object { "- [ ] Step $_" }) -join "`n")
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 0 $result.Failures.Count 'A plan with one ticked step passes'
    Assert-Equal 0 $result.Diagnostics.Count 'A plan with one ticked step prints no diagnostic'

    # 11. Every step ticked.
    $fx = New-CheckoutFixture -PlanBody "- [x] Step 1`n- [x] Step 2"
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 0 $result.Failures.Count 'A fully ticked plan passes'

    # 12. No checkbox at all. Measured on 2026-09-03: 68 of the 180 plans in
    #     docs/superpowers/plans/ carry no checkbox, and the guard allows every one of them.
    $fx = New-CheckoutFixture -PlanBody "# A plan written as prose, with no step list at all."
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 0 $result.Failures.Count 'A plan with no checkbox passes'

    # 13. A '- Plan:' bullet reading 'none' with a reason.
    $fx = New-CheckoutFixture -PlanBullet '- Plan: none - trivial' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 0 $result.Failures.Count '"Plan: none" passes'
    Assert-Equal 0 $result.Diagnostics.Count '"Plan: none" prints no diagnostic'

    # 14. No '- Plan:' bullet at all.
    $fx = New-CheckoutFixture -PlanBullet '' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
    Assert-Equal 0 $result.Failures.Count 'An item with no Plan bullet passes'

    # 15. A pointer naming a file that is not there. That is a real problem, but it is not this
    #     item's problem, so it prints one diagnostic and does not fail the push.
    $fx = New-CheckoutFixture -PlanBullet '- Plan: `docs/superpowers/plans/gone.md`' -PlanBody ''
    $result = Get-ShippedPlanTickFailure -RepoRoot $fx.Root -Item @(New-ItemRecord) -TargetCommit $fx.Head
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
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
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
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
    Assert-Equal 0 $shipped.Count 'Editing an item the base already shipped returns nothing'

    # 18. A branch that only moves an item into backlog/done/, its Stage line already 9-ship. The
    #     diff names two paths for that one number, and exactly one record must come back.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Number '073' -Folder 'backlog' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'stamp 073' *> $null
    $base = Get-BaseSha -Root $repo
    & git -C $repo mv 'backlog/073-probe.md' 'backlog/done/073-probe.md' *> $null
    & git -C $repo commit -m 'move 073 into done' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
    Assert-Equal 1 $shipped.Count 'A plain rename into backlog/done returns exactly one record'

    # 18b. Renumbering an item the base already shipped. The item keeps its identity across a
    #      renumber, because the identity is the file and not the number. 'git diff --name-only'
    #      prints only the destination of a rename, so the old number vanishes and the base lookup
    #      finds nothing under the new one. That made this branch look like the shipper of debt it
    #      did not create, which is the exact failure the typo-fix case above exists to stop.
    #      This repository really does renumber shipped items: b9f38820 renumbered done item 105 to
    #      107, and 7c762117 renumbered 118 to 120.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'ship 073' *> $null
    $base = Get-BaseSha -Root $repo
    & git -C $repo mv 'backlog/done/073-probe.md' 'backlog/done/074-probe.md' *> $null
    & git -C $repo commit -am 'renumber 073 to 074' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
    Assert-Equal 0 $shipped.Count 'Renumbering an item the base already shipped returns nothing'

    # 18c. Renumbering an item the base holds OPEN, and shipping it in the same branch. The rename
    #      must not turn into a free pass: the base never shipped this item, so this branch is the
    #      shipper and its plan is judged.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Number '073' -Folder 'backlog' -Stage '8-review'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'file 073' *> $null
    $base = Get-BaseSha -Root $repo
    & git -C $repo mv 'backlog/073-probe.md' 'backlog/done/074-probe.md' *> $null
    Write-Item -Root $repo -Number '074' -Folder 'backlog/done' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'renumber and ship 074' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
    Assert-Equal 1 $shipped.Count 'Renumbering an open item and shipping it is still shipped here'
    if ($shipped.Count -eq 1) { Assert-Equal '074' $shipped[0].Number 'The new number names the shipped item' }

    # 19. A suffixed item. A digits-only pattern would skip 022b in silence.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '022b' -Folder 'backlog/done' -Stage '9-ship'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'file and ship 022b' *> $null
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
    Assert-Equal 1 $shipped.Count 'A suffixed item is not skipped'
    if ($shipped.Count -eq 1) { Assert-Equal '022b' $shipped[0].Number 'The suffixed number is returned whole' }

    # 20. A branch that touches nothing under backlog/.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'edited' -Encoding utf8
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-BaseSha -Root $repo))
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

    # === the pushed commit decides, not the working tree =====================
    # A push carries commits. Judging the working tree let an uncommitted edit hide a committed
    # item: HEAD reads 'Stage: 9-ship' with an unticked plan, the developer downgrades the Stage
    # line on disk without committing, and the gate passed while the 9-ship record went to the
    # remote. The plan file is the one thing that must still come from disk, because it lives in a
    # second repository this one never carries.

    # 26. An uncommitted Stage downgrade must not hide the committed item.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship' `
        -PlanBullet '- Plan: `docs/superpowers/plans/probe-plan-073.md`'
    Write-Plan -Root $repo -Body "- [ ] Step 1`n- [ ] Step 2"
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'ship 073 with an unticked plan' *> $null
    $head = Get-BaseSha -Root $repo

    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '8-review' `
        -PlanBullet '- Plan: `docs/superpowers/plans/probe-plan-073.md`'
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit $head)
    Assert-Equal 1 $shipped.Count 'An uncommitted Stage downgrade must not hide the pushed item'

    $result = Get-ShippedPlanTickFailure -RepoRoot $repo -Item $shipped -TargetCommit $head
    Assert-Equal 1 $result.Failures.Count 'The pushed commit still carries an unticked plan'

    # 27. An uncommitted rewrite of the '- Plan:' bullet must not hide it either. The pointer comes
    #     from the pushed commit; the plan file it names still comes from disk.
    $repo = New-TempGitRepo
    $base = Get-BaseSha -Root $repo
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship' `
        -PlanBullet '- Plan: `docs/superpowers/plans/probe-plan-073.md`'
    Write-Plan -Root $repo -Body "- [ ] Step 1`n- [ ] Step 2"
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'ship 073 with an unticked plan' *> $null
    $head = Get-BaseSha -Root $repo

    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '9-ship' `
        -PlanBullet '- Plan: none - trivial'
    $shipped = @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit $head)
    $result = Get-ShippedPlanTickFailure -RepoRoot $repo -Item $shipped -TargetCommit $head
    Assert-Equal 1 $result.Failures.Count 'An uncommitted "Plan: none" must not hide the pushed pointer'

    # 28. The plan file itself is read from disk, not from the commit. docs/superpowers is a second
    #     repository that this one ignores, so the pushed commit never carries a plan at all. Here
    #     the commit holds an unticked plan and the working tree ticks a step: the tick counts, and
    #     that is the whole point of the refusal telling you to go and tick the steps.
    Write-Plan -Root $repo -Body "- [x] Step 1`n- [ ] Step 2"
    $result = Get-ShippedPlanTickFailure -RepoRoot $repo -Item $shipped -TargetCommit $head
    Assert-Equal 0 $result.Failures.Count 'A tick on disk counts, because the plan lives outside this repository'

    # 29. An older commit can be judged on its own terms. The pushed commit is not always HEAD.
    Write-Plan -Root $repo -Body "- [ ] Step 1`n- [ ] Step 2"
    Write-Item -Root $repo -Number '073' -Folder 'backlog/done' -Stage '6-verify' `
        -PlanBullet '- Plan: `docs/superpowers/plans/probe-plan-073.md`'
    & git -C $repo add -A *> $null
    & git -C $repo commit -m 'walk 073 back to 6-verify' *> $null
    $later = Get-BaseSha -Root $repo
    Assert-Equal 0 @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit $later).Count `
        'The later commit no longer ships the item'
    Assert-Equal 1 @(Get-BranchShippedItem -RepoRoot $repo -MergeBase $base -TargetCommit $head).Count `
        'The earlier commit still ships it, judged on its own terms'

    # === the script itself, run as pre-push runs it ==========================
    # Everything above drives the functions in-process. None of it executes the script body: the
    # exit codes, the refusal message, and the result line. A suite that stops there stays green
    # while the script always exits 0, or stops calling a helper, or prints a broken diagnostic.
    # Pre-push reads the exit code and nothing else, so the exit code is the contract.
    #
    # The fixture root carries a space, because pre-push passes -RepoRoot and -MergeBase through
    # 'pwsh -NoProfile -File', and an unquoted path would split there.
    $entryRepo = New-Root -Prefix 'shipped plan entry'
    New-Item -ItemType Directory -Path (Join-Path $entryRepo 'backlog/done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $entryRepo 'docs/superpowers/plans') -Force | Out-Null
    & git -C $entryRepo init *> $null
    & git -C $entryRepo config user.email 'test@example.com' *> $null
    & git -C $entryRepo config user.name 'Shipped Plan Test' *> $null
    Set-Content -LiteralPath (Join-Path $entryRepo 'README.md') -Value 'seed' -Encoding utf8
    & git -C $entryRepo add -A *> $null
    & git -C $entryRepo commit -m 'seed' *> $null
    $entryBase = Get-BaseSha -Root $entryRepo

    $entryPlan = Join-Path $entryRepo 'docs/superpowers/plans/probe-plan-073.md'
    Set-Content -LiteralPath (Join-Path $entryRepo 'backlog/done/073-probe.md') -Encoding utf8 -Value (@(
        '# 073 - probe'
        ''
        '- **Stage**: 9-ship'
        ''
        '- Plan: `docs/superpowers/plans/probe-plan-073.md`'
    ) -join "`n")
    Set-Content -LiteralPath $entryPlan -Value "- [ ] Step 1`n- [ ] Step 2`n- [ ] Step 3" -Encoding utf8
    & git -C $entryRepo add -A *> $null
    & git -C $entryRepo commit -m 'ship 073' *> $null

    $checkScript = Join-Path $suiteRoot 'scripts/check-shipped-plan-ticked.ps1'
    $pwshPath = (Get-Process -Id $PID).Path

    function Invoke-CheckScript {
        param([string] $Root, [string] $Base)

        $output = & $pwshPath -NoProfile -File $checkScript -RepoRoot $Root -MergeBase $Base 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Text = (@($output) -join "`n")
        }
    }

    # 22. A shipped item whose plan has no ticked step: exit 1, and the refusal names the plan file
    #     and both counts. A refusal that does not say which plan is unactionable.
    $run = Invoke-CheckScript -Root $entryRepo -Base $entryBase
    Assert-Equal 1 $run.ExitCode 'An unticked shipped plan must exit 1'
    Assert-True ($run.Text -match 'Backlog item 073') "The refusal must name the item, got: $($run.Text)"
    Assert-True ($run.Text -match 'backlog/done/073-probe\.md') 'The refusal must name the item file'
    Assert-True ($run.Text -match 'probe-plan-073\.md') 'The refusal must name the plan file'
    Assert-True ($run.Text -match '3 unticked, 0 ticked') "The refusal must print both counts, got: $($run.Text)"
    Assert-True ($run.Text -match 'SKIP_PUSH_HOOK=1') 'The refusal must say how to skip the check'

    # 23. One ticked step: exit 0, and the result line names what it looked at.
    Set-Content -LiteralPath $entryPlan -Value "- [x] Step 1`n- [ ] Step 2`n- [ ] Step 3" -Encoding utf8
    $run = Invoke-CheckScript -Root $entryRepo -Base $entryBase
    Assert-Equal 0 $run.ExitCode "One ticked step must exit 0, got: $($run.Text)"
    Assert-True ($run.Text -match 'every shipped plan carries a ticked step') 'A clean run must print its result line'
    Assert-True ($run.Text -match 'ships 1') "The result line must say how many items this branch ships, got: $($run.Text)"

    # 24. A repository path holding a space reaches the script whole. The fixture root above already
    #     carries one, so this asserts the property rather than assuming it.
    Assert-True ($entryRepo -match ' ') 'The entry-point fixture root must carry a space'

    # 25. A branch that ships nothing: exit 0, and the result line reports zero.
    $quietRepo = New-TempGitRepo
    $quietBase = Get-BaseSha -Root $quietRepo
    Set-Content -LiteralPath (Join-Path $quietRepo 'README.md') -Value 'edited' -Encoding utf8
    & git -C $quietRepo add -A *> $null
    & git -C $quietRepo commit -m 'edit readme' *> $null
    $run = Invoke-CheckScript -Root $quietRepo -Base $quietBase
    Assert-Equal 0 $run.ExitCode "A branch that ships nothing must exit 0, got: $($run.Text)"
    Assert-True ($run.Text -match 'ships 0') 'The result line must report zero shipped items'

    # === the pre-push wiring, as written down ================================
    # This is a source assertion. It does not prove the step runs, because pre-push builds the
    # solution first and no unit test can afford that. It does stop a later edit from deleting the
    # step while this suite stays green. Task 5 of the plan supplies the one behavioural proof.
    $prePushSource = Get-Content -Raw -LiteralPath (Join-Path $suiteRoot 'scripts/pre-push-quick-checks.ps1')
    Assert-True ($prePushSource -match 'check-shipped-plan-ticked\.ps1') `
        'pre-push-quick-checks.ps1 must run check-shipped-plan-ticked.ps1'
    Assert-True ($prePushSource -match '\[string\[\]\]\$PushedCommit') `
        'pre-push-quick-checks.ps1 must accept the commits the hook read from stdin'
    Assert-True ($prePushSource -match '-TargetCommit \$target') `
        'pre-push must judge each pushed commit, not the working tree'
    Assert-True ($prePushSource -match 'merge-base \$target origin/main') `
        'pre-push must resolve each pushed commit''s own merge base'
    Assert-True ($prePushSource -match "if \(\`$PushedCommit\.Count -gt 0\) \{ \`$PushedCommit \} else \{ @\('HEAD'\) \}") `
        'a run by hand, with nothing on stdin, must fall back to HEAD'
    Assert-True ($prePushSource -match '(?s)check-shipped-plan-ticked\.ps1.*?\$LASTEXITCODE -ne 0.*?throw ') `
        'pre-push must throw when the check exits non-zero'

    # The hook is the half that reads stdin. tests/PrePushHook.Tests.ps1 runs it for real against
    # both PowerShell hosts; this only pins that the wiring is still written down here.
    $hookSource = Get-Content -Raw -LiteralPath (Join-Path $suiteRoot '.githooks/pre-push.ps1')
    Assert-True ($hookSource -match '\[Console\]::IsInputRedirected') `
        'the hook must guard the stdin read, or a run by hand blocks forever'
    Assert-True ($hookSource -match '-PushedCommit \$pushedCommit') `
        'the hook must hand the pushed commits to the quick-checks script'

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
