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
. (Join-Path $suiteRoot 'scripts/backlog.common.ps1')

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

function New-Root {
    param([string] $Prefix)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $script:roots += $root
    return $root
}

# A throwaway repository with a local bare remote. Nothing leaves the machine, and 'origin' is a
# real remote, so a push assertion reads a real ref rather than a recorded intention.
function New-TransitionFixture {
    param(
        [string] $Stage = '2-design',
        [string] $Difficulty = 'complex',
        [string] $Branch = '',
        [string] $StackedOn = '',
        [switch] $AsWorktree,
        [switch] $AllBoxesTicked,
        [switch] $NoItem,
        # Every failure edge needs PLAN-PROGRESS.md to exist, because Task 5 refuses without it.
        # Pass this for any case whose stage is 4-execute or later.
        [switch] $WithProgress,
        # The item's linked plan, and whether it carries the freeze directive. 'none' writes no
        # '- Plan:' bullet and no file, which is what every case before the freeze rule used.
        [ValidateSet('none', 'unfrozen', 'frozen')]
        [string] $PlanState = 'none'
    )

    $bare = New-Root -Prefix 'transition-remote'
    & git init --bare $bare *> $null

    $root = New-Root -Prefix 'transition-work'
    # A named default branch, so 'origin/main' is a ref the marker check can really resolve.
    & git init -b main $root *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Transition Test' *> $null
    & git -C $root config core.hooksPath (Join-Path $root '.nohooks') *> $null

    New-Item -ItemType Directory -Path (Join-Path $root 'backlog') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs/development') -Force | Out-Null

    # The real workflow.md, copied in. The reader must read a document, and this is the document.
    Copy-Item -LiteralPath (Join-Path $suiteRoot 'docs/development/workflow.md') `
              -Destination (Join-Path $root 'docs/development/workflow.md')

    $itemName = 'backlog/081-automate-stage-transitions.md'
    $planName = 'docs/superpowers/plans/2026-09-20-stage-transition-plan-081.md'
    if (-not $NoItem) {
        $box = if ($AllBoxesTicked) { '- [x]' } else { '- [ ]' }
        $item = @(
            '# 081 - Automate stage transitions and PR mechanics'
            ''
            '## Metadata'
            ''
            "- **Difficulty**: $Difficulty"
            "- **Stage**: $Stage"
            ''
            '## Acceptance criteria'
            ''
            "$box One script performs a transition end to end."
        )
        if ($PlanState -ne 'none') {
            $item += @('', '## Notes / dependencies', '', "- Plan: ``$planName``")
        }
        Set-Content -LiteralPath (Join-Path $root $itemName) -Value ($item -join "`n") -Encoding utf8
    }

    if ($WithProgress) {
        Set-Content -LiteralPath (Join-Path $root 'PLAN-PROGRESS.md') -Value '- Task 1 done' -Encoding utf8
    }

    & git -C $root add -A *> $null
    & git -C $root commit -m 'seed' *> $null
    & git -C $root remote add origin $bare *> $null
    & git -C $root push -u origin HEAD *> $null

    # The happy paths need a LINKED worktree, because the script refuses the main checkout. The
    # main-checkout refusal case is the one that keeps the plain repository.
    # Stacked work branches from an unmerged branch, not from main. Publish that branch first, so
    # 'origin/<base>' resolves for both the marker check and the pull request.
    $from = 'HEAD'
    if ($StackedOn) {
        & git -C $root branch $StackedOn *> $null
        & git -C $root push -u origin $StackedOn *> $null
        $from = $StackedOn
    }

    $acting = $root
    if ($AsWorktree) {
        $acting = New-Root -Prefix 'transition-linked'
        Remove-Item -LiteralPath $acting -Recurse -Force
        $name = if ($Branch) { $Branch } else { 'feature/wt-transition-test' }
        & git -C $root worktree add -b $name $acting $from *> $null
        if (-not $StackedOn) { & git -C $acting push -u origin $name *> $null }
    }

    # The linked plan lives in the acting checkout, untracked, exactly like the real
    # docs/superpowers link. The freeze check reads the working tree, so untracked is enough,
    # and 'git add -- backlog PLAN-PROGRESS.md' can never sweep it into a commit.
    if ($PlanState -ne 'none') {
        $planPath = Join-Path $acting $planName
        New-Item -ItemType Directory -Path (Split-Path -Parent $planPath) -Force | Out-Null
        $plan = @()
        if ($PlanState -eq 'frozen') {
            $plan += '<!-- citation-check:ignore-file -->'
            $plan += '<!-- Frozen: the work this file planned has shipped. -->'
        }
        $plan += @(
            '# Plan 081'
            ''
            'The driver lives in (`scripts/take-stage-transition.ps1:1`, "#Requires -Version 7.0").'
        )
        Set-Content -LiteralPath $planPath -Value ($plan -join "`n") -Encoding utf8
    }

    return [pscustomobject]@{
        Root     = (Resolve-Path -LiteralPath $acting).Path
        Bare     = (Resolve-Path -LiteralPath $bare).Path
        ItemPath = (Join-Path (Resolve-Path -LiteralPath $acting).Path $itemName)
        PlanPath = (Join-Path (Resolve-Path -LiteralPath $acting).Path $planName)
    }
}

# A fake gh. The ordering test needs 'pr create' to fail on demand, which no real call can be
# asked to do safely.
function New-FakeGh {
    param(
        [int] $CreateExitCode = 0,
        [string] $PrNumber = '421',
        [string] $Body = '',
        # The branch the pull request named by -Pr points at. The script refuses a number whose
        # head is some other branch, so a test proves that by handing back a different name.
        [string] $HeadRefName = 'feature/wt-transition-test',
        # What 'gh pr list --head <branch>' answers. Empty means no pull request is open yet.
        [string] $ExistingPr = '',
        # What 'gh pr view <n> --json isDraft' answers. Pickup reuses only a draft, and the round
        # resumes Ship only while the pull request is still a draft, so both read this.
        [string] $IsDraft = 'true',
        # What 'gh pr view <n> --json baseRefName' answers. Pickup refuses a pull request opened
        # against a base other than the one it was asked for.
        [string] $BaseRefName = 'main'
    )

    $dir = New-Root -Prefix 'fake-gh'
    $log = Join-Path $dir 'gh-calls.log'

    # The body lives in a file, so the read-modify-write and the read-back both work against
    # real state rather than a recording.
    $bodyFile = Join-Path $dir 'pr-body.txt'
    Set-Content -LiteralPath $bodyFile -Value $Body -Encoding utf8

    # Order matters twice over. 'headRefName', 'isDraft' and 'baseRefName' are tested before
    # 'view', because each of those queries is a 'gh pr view' too. 'view' and 'edit' are tested
    # before 'create', because 'gh pr create' also carries the word 'create' and an earlier
    # branch would swallow it.
    $script = @"
#!/usr/bin/env pwsh
`$args -join ' ' | Add-Content -LiteralPath '$log'
if (`$args -contains 'headRefName') { Write-Output '$HeadRefName'; exit 0 }
if (`$args -contains 'isDraft') { Write-Output '$IsDraft'; exit 0 }
if (`$args -contains 'baseRefName') { Write-Output '$BaseRefName'; exit 0 }
if (`$args -contains 'list') { Write-Output '$ExistingPr'; exit 0 }
if (`$args -contains 'view') { Get-Content -Raw -LiteralPath '$bodyFile'; exit 0 }
if (`$args -contains 'edit') {
    `$i = [array]::IndexOf(`$args, '--body-file')
    if (`$i -ge 0) { Copy-Item -LiteralPath `$args[`$i + 1] -Destination '$bodyFile' -Force }
    exit 0
}
if (`$args -contains 'create') {
    if ($CreateExitCode -ne 0) { Write-Error 'fake gh: pr create refused'; exit $CreateExitCode }
    Write-Output 'https://github.com/s205109/AHKFlowApp/pull/$PrNumber'
    exit 0
}
exit 0
"@
    Set-Content -LiteralPath (Join-Path $dir 'gh.ps1') -Value $script -Encoding utf8

    # The shim the shell will actually pick, which differs by platform. Both are written from the
    # one gh.ps1 above, so the fake's behaviour has a single definition.
    if ($IsWindows) {
        # Windows resolves gh.cmd before gh.ps1.
        Set-Content -LiteralPath (Join-Path $dir 'gh.cmd') `
            -Value "@echo off`r`npwsh -NoProfile -File `"%~dp0gh.ps1`" %*" -Encoding ascii
    } else {
        # Linux needs an extensionless executable named exactly 'gh'.
        $sh = Join-Path $dir 'gh'
        Set-Content -LiteralPath $sh -Value "#!/bin/sh`nexec pwsh -NoProfile -File `"`$(dirname `"`$0`")/gh.ps1`" `"`$@`"" -Encoding utf8
        & chmod +x $sh
    }

    return [pscustomobject]@{ Dir = $dir; Log = $log; BodyFile = $bodyFile }
}

# The exit code is captured INSIDE the block and kept in a script variable. Never read
# $LASTEXITCODE after this helper returns. It happens to survive the finally today, because
# restoring PATH is pure PowerShell, but one native call added to the cleanup later would
# overwrite it. The assertion would then read the cleanup's result, and a cleanup that
# succeeded would make a '-ne 0' assertion go red for a reason unrelated to the transition.
$script:LastTransitionExit = $null

function Invoke-WithFakeGh {
    param([pscustomobject] $Gh, [scriptblock] $Action)
    $saved = $env:PATH
    try {
        $env:PATH = "$($Gh.Dir)$([System.IO.Path]::PathSeparator)$saved"
        & $Action
        $script:LastTransitionExit = $LASTEXITCODE
    } finally {
        $env:PATH = $saved
    }
}

# A transition refused before its first gh call leaves no log file at all. Reading it directly
# then throws and stops the suite, which hides the assertion that was about to report the real
# problem.
function Get-GhLog {
    param([pscustomobject] $Gh)
    if (-not (Test-Path -LiteralPath $Gh.Log)) { return '' }
    return ((Get-Content -LiteralPath $Gh.Log) -join "`n")
}

function Get-RemoteItemStage {
    param([string] $Bare, [string] $Branch)
    $text = & git -C $Bare show "${Branch}:backlog/081-automate-stage-transitions.md" 2>$null
    if (-not $text) { return '' }
    return (Get-SingleBacklogStage -Lines @($text))
}

# The item moves into backlog/done/ at Ship, so a case that may ship cannot read a fixed path.
function Get-FixtureStage {
    param([string] $Root)
    $found = @(Get-BacklogItem -BacklogRoot (Join-Path $Root 'backlog') | Where-Object { $_.Key -eq '081' })
    if ($found.Count -ne 1) { return '' }
    return (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $found[0].Path))
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

    # --- An ordinary transition writes the field, commits it, and pushes it ---
    $fx = New-TransitionFixture -Stage '2-design' -Difficulty 'complex' -AsWorktree
    $branch = (& git -C $fx.Root rev-parse --abbrev-ref HEAD).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx.Root -Item '081' -Edge 'success' *> $null
    Assert-Equal 0 $LASTEXITCODE 'An ordinary transition must succeed'

    $local = Get-SingleBacklogStage -Lines (Get-Content -LiteralPath (Join-Path $fx.Root 'backlog/081-automate-stage-transitions.md'))
    Assert-Equal '3-plan' $local 'Design success must write 3-plan into the item'
    Assert-Equal '3-plan' (Get-RemoteItemStage -Bare $fx.Bare -Branch $branch) `
        'The transition must be pushed, because the remote is what a reader of main sees'

    # --- A transition the source does not allow is refused at driver level ---
    # This is acceptance criterion 2, proven through the script rather than through the reader.
    # Design success has exactly one target, '3-plan', so '9-ship' is a target workflow.md does
    # not give this edge.
    $fx2 = New-TransitionFixture -Stage '2-design' -Difficulty 'complex' -AsWorktree
    $before = (& git -C $fx2.Root rev-parse HEAD).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx2.Root -Item '081' `
        -Edge 'success' -To '9-ship' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A target the source does not allow must be refused'

    $after = (& git -C $fx2.Root rev-parse HEAD).Trim()
    Assert-Equal $before $after 'A refused transition must leave the commit log untouched'
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath (Join-Path $fx2.Root 'backlog/081-automate-stage-transitions.md'))) `
        'A refused transition must leave the field untouched'

    # --- An edge that names no stage is a different refusal, and also changes nothing ---
    # Pickup's 'not applicable' edge targets 'none'. That is not an illegal edge; it is a legal
    # edge with no field to write, and the two must not be confused.
    $fx2b = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $beforeB = (& git -C $fx2b.Root rev-parse HEAD).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx2b.Root -Item '081' -Edge 'not applicable' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'An edge that names no stage must fail'
    Assert-Equal $beforeB (& git -C $fx2b.Root rev-parse HEAD).Trim() `
        'An edge that names no stage must leave the commit log untouched'

    # --- 'blocked' is not a transition this script performs ---
    # Moving an item into backlog/blocked/ is a manual git mv, so the parameter must refuse the
    # word rather than accept it and fail later with a message about a missing stage.
    $fx2c = New-TransitionFixture -Stage '2-design' -Difficulty 'complex' -AsWorktree
    $blockedRefused = $false
    try {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx2c.Root -Item '081' -Edge 'blocked' *> $null
    } catch {
        $blockedRefused = $true
    }
    Assert-True $blockedRefused 'The blocked edge must be refused by the parameter itself'

    # --- The main checkout is refused ---
    # Deliberately no -AsWorktree here. A plain repository is what Test-LinkedWorktree must reject.
    $fx3 = New-TransitionFixture
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx3.Root -Item '081' -Edge 'success' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'The main checkout must be refused'

    # --- Pickup opens the draft pull request, then stamps ---
    $pk = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $gh = New-FakeGh -CreateExitCode 0
    Invoke-WithFakeGh -Gh $gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pk.Root -Item '081' -Edge 'success' *> $null
    }
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $pk.ItemPath)) `
        'Pickup with complex must stamp 2-design'
    Assert-True ((Get-Content -Raw -LiteralPath $gh.Log) -match 'pr create') 'Pickup must call gh pr create'

    # --- The ordering: gh pr create fails, so nothing is stamped ---
    $pk2 = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $pkBefore = (& git -C $pk2.Root rev-parse HEAD).Trim()
    $gh2 = New-FakeGh -CreateExitCode 1
    Invoke-WithFakeGh -Gh $gh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pk2.Root -Item '081' -Edge 'success' *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A failed gh pr create must fail the transition'
    Assert-Equal '1-pickup' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $pk2.ItemPath)) `
        'A failed gh pr create must leave the Stage at 1-pickup'
    # -join matters: '-match' against an array filters it and returns an array, not a boolean.
    Assert-True (((& git -C $pk2.Root log --oneline "$pkBefore..HEAD") -join "`n") -notmatch 'at 2-design') `
        'A failed gh pr create must leave no stamp commit'

    # --- A base ref that does not resolve is refused before anything is written ---
    # git rev-list writes to stderr and returns non-zero for an unknown ref. Reading only its
    # stdout makes a misspelled -Base look like 'this branch has no commits of its own', so the
    # marker commit lands and the pull request is opened against a base that does not exist.
    $pkBad = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $pkBadHead = (& git -C $pkBad.Root rev-parse HEAD).Trim()
    $ghBad = New-FakeGh -CreateExitCode 0
    Invoke-WithFakeGh -Gh $ghBad -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pkBad.Root -Item '081' `
            -Edge 'success' -Base 'no-such-base' *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A base ref that does not resolve must be refused'
    Assert-Equal $pkBadHead (& git -C $pkBad.Root rev-parse HEAD).Trim() `
        'A refused base ref must leave no marker commit'
    Assert-Equal '1-pickup' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $pkBad.ItemPath)) `
        'A refused base ref must leave the Stage at 1-pickup'

    # --- Stacked work: the marker is judged against the real base, not against main ---
    # A worktree created with new-worktree.ps1 -BaseRef branches from an unmerged branch. Such a
    # branch already differs from origin/main by every commit of the branch below it, so a marker
    # check against main would see 'this branch has commits' and skip the marker. The pull request
    # would then be opened between two identical refs.
    $pk3 = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree -StackedOn 'feature/wt-below'
    $gh3 = New-FakeGh -CreateExitCode 0
    $countBefore = @(& git -C $pk3.Root rev-list "origin/feature/wt-below..HEAD").Count
    Assert-Equal 0 $countBefore 'The stacked branch must start with no commits of its own'

    Invoke-WithFakeGh -Gh $gh3 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pk3.Root -Item '081' `
            -Edge 'success' -Base 'feature/wt-below' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A stacked pickup must succeed'
    Assert-True (((& git -C $pk3.Root log --oneline "origin/feature/wt-below..HEAD") -join "`n") -match 'pickup, opening draft PR') `
        'A stacked pickup must still make the marker commit'
    Assert-True ((Get-Content -Raw -LiteralPath $gh3.Log) -match '--base feature/wt-below') `
        'The pull request must be opened against the real base, not main'

    # --- Ship pushes the closure commit before it flips the pull request ---
    $sh = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -AllBoxesTicked -WithProgress
    $shGh = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A ticked Ship must succeed'

    Assert-True (Test-Path -LiteralPath (Join-Path $sh.Root 'backlog/done/081-automate-stage-transitions.md')) `
        'Ship must move the item into backlog/done/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sh.Root 'PLAN-PROGRESS.md'))) `
        'Ship must delete PLAN-PROGRESS.md'

    # The ordering claim, read from the remote rather than from intent.
    $shBranch = (& git -C $sh.Root rev-parse --abbrev-ref HEAD).Trim()
    $remoteHead = (& git -C $sh.Bare rev-parse $shBranch).Trim()
    $localHead = (& git -C $sh.Root rev-parse HEAD).Trim()
    Assert-Equal $localHead $remoteHead 'The closure commit must be on the remote'

    Assert-True ((Get-Content -Raw -LiteralPath $shGh.Log) -match 'pr ready') 'Ship must flip the pull request to ready'

    # --- An unticked box refuses the flip ---
    $sh2 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -WithProgress
    $shGh2 = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh2.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'An unticked acceptance box must refuse Ship'
    # Ship does call gh before it refuses, to check the pull request belongs to this branch.
    # What it must never do is flip one.
    Assert-True (((Get-Content -Raw -LiteralPath $shGh2.Log) -join "`n") -notmatch 'pr ready') `
        'A refused Ship must not flip the pull request'

    # --- A failure edge refuses without its evidence ---
    $fl = New-TransitionFixture -Stage '6-verify' -Difficulty 'complex' -AsWorktree -WithProgress

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl.Root -Item '081' -Edge 'failure' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A failure edge without evidence must be refused'
    Assert-Equal '6-verify' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fl.ItemPath)) `
        'A refused failure edge must leave the Stage alone'

    # --- With evidence, the record and the Stage land in ONE commit ---
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl.Root -Item '081' -Edge 'failure' `
        -Evidence 'pwsh ./scripts/test-fast.ps1 -Mode Fast : 3 failed' `
        -RecoveryTask 'Task 8: fix the emitter escaping' *> $null
    Assert-Equal 0 $LASTEXITCODE 'A failure edge with evidence must succeed'
    Assert-Equal '4-execute' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fl.ItemPath)) `
        'Verify failure must target 4-execute'

    $progressText = Get-Content -Raw -LiteralPath (Join-Path $fl.Root 'PLAN-PROGRESS.md')
    Assert-True ($progressText -match 'fix the emitter escaping') 'The recovery task must be recorded'
    Assert-True ($progressText -match '3 failed') 'The red evidence must be recorded'

    # One commit, not two. A resume that read the Stage between two commits would find a failure
    # edge with no evidence behind it.
    $touched = @(& git -C $fl.Root show --name-only --pretty=format: HEAD | Where-Object { $_ })
    Assert-True ($touched -contains 'PLAN-PROGRESS.md') 'The record must be in the transition commit'
    Assert-True (($touched -join ' ') -match 'backlog/') 'The Stage change must be in the same commit'

    # --- No PLAN-PROGRESS.md means the work never reached Execute ---
    $fl2 = New-TransitionFixture -Stage '6-verify' -Difficulty 'complex' -AsWorktree
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl2.Root -Item '081' -Edge 'failure' `
        -Evidence 'x' -RecoveryTask 'y' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A failure edge with no PLAN-PROGRESS.md must be refused'

    # --- A round rewrites one line of its body and keeps the rest ---
    $rd = New-TransitionFixture -Stage '5-simplify' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $roundBody = "## What`n`nThree chores.`n`nStage: 5-simplify`n`nSessions:`n`n- abc (agent, 5-simplify)"
    $rdGh = New-FakeGh -Body $roundBody -HeadRefName 'chore/wt-backlog-housekeeping'

    Invoke-WithFakeGh -Gh $rdGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round transition must succeed'

    $written = Get-Content -Raw -LiteralPath $rdGh.BodyFile
    Assert-True ($written -match '(?m)^Stage: 6-verify\r?$') 'The round body must read the new stage'
    Assert-True ($written -match 'Three chores')           'The round body must keep its description'
    Assert-True ($written -match 'Sessions:')              'The round body must keep its Sessions list'
    Assert-Equal 1 ([regex]::Matches($written, '(?m)^Stage: ')).Count 'Exactly one Stage line must survive'

    # --- Two Stage lines is a refusal, not a guess ---
    $rdGh2 = New-FakeGh -Body "Stage: 5-simplify`nStage: 6-verify" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $rdGh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A body with two Stage lines must be refused'

    # ================= Copilot review round, PR 421 =================

    # --- A failure edge with no evidence must not publish anything (review finding 1) ---
    # The pre-flight push ran before the failure prerequisites were checked, so a refused
    # transition still pushed whatever the branch was carrying.
    $r1 = New-TransitionFixture -Stage '6-verify' -Difficulty 'complex' -AsWorktree -WithProgress
    $r1Branch = (& git -C $r1.Root rev-parse --abbrev-ref HEAD).Trim()
    Set-Content -LiteralPath (Join-Path $r1.Root 'unpushed.txt') -Value 'work' -Encoding utf8
    & git -C $r1.Root add -A *> $null
    & git -C $r1.Root commit -m 'unpushed work' *> $null
    $r1RemoteBefore = (& git -C $r1.Bare rev-parse $r1Branch).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r1.Root -Item '081' -Edge 'failure' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A failure edge with no evidence must still be refused'
    Assert-Equal $r1RemoteBefore (& git -C $r1.Bare rev-parse $r1Branch).Trim() `
        'A refused failure edge must not push the branch'

    # --- Ship refuses a pull request number pointing at another branch (review finding 2) ---
    $r2 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -AllBoxesTicked -WithProgress
    $r2Gh = New-FakeGh -HeadRefName 'feature/wt-somebody-else'
    Invoke-WithFakeGh -Gh $r2Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r2.Root -Item '081' -Edge 'success' -Pr 999 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Ship must refuse a pull request on another branch'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $r2.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A refused Ship must not move the item'
    Assert-True (((Get-Content -Raw -LiteralPath $r2Gh.Log) -join "`n") -notmatch 'pr ready') `
        'A refused Ship must not flip any pull request'

    # --- An item worktree with -Pr and no -Item is refused, not treated as a round (finding 3) ---
    $r3 = New-TransitionFixture -Stage '5-simplify' -Difficulty 'complex' -AsWorktree
    $r3Gh = New-FakeGh -Body "Stage: 5-simplify"
    Invoke-WithFakeGh -Gh $r3Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r3.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A missing -Item on an item branch must be refused'
    Assert-True ((Get-Content -Raw -LiteralPath $r3Gh.BodyFile) -match '(?m)^Stage: 5-simplify\r?$') `
        'A refused run must not rewrite any pull request body'

    # --- Pickup reuses a pull request that already exists (review finding 5) ---
    # gh pr create succeeded, then the session died before the stamp. A rerun must find that
    # pull request and stamp, rather than calling create again and failing forever.
    $r5 = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $r5Gh = New-FakeGh -CreateExitCode 1 -ExistingPr '421'
    Invoke-WithFakeGh -Gh $r5Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r5.Root -Item '081' -Edge 'success' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'Pickup must succeed when the pull request already exists'
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $r5.ItemPath)) `
        'A resumed Pickup must stamp the Stage'
    Assert-True (((Get-Content -Raw -LiteralPath $r5Gh.Log) -join "`n") -notmatch 'pr create') `
        'A resumed Pickup must not call gh pr create again'

    # --- A round flips to ready entering 9-ship, not leaving it (review finding 6) ---
    $r6 = New-TransitionFixture -Stage '8-review' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $r6Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 8-review" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $r6Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r6.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round entering Ship must succeed'
    Assert-True ((Get-Content -Raw -LiteralPath $r6Gh.BodyFile) -match '(?m)^Stage: 9-ship\r?$') `
        'The round body must read 9-ship'
    Assert-True (((Get-Content -Raw -LiteralPath $r6Gh.Log) -join "`n") -match 'pr ready') `
        'A round entering Ship must flip to ready'

    $r6b = New-TransitionFixture -Stage '9-ship' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    # -IsDraft 'false' is the merged case: the flip already happened. The draft case is the
    # resume, and round 2's finding 2 covers it.
    $r6bGh = New-FakeGh -Body "Stage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'false'
    Invoke-WithFakeGh -Gh $r6bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r6b.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-True (((Get-Content -Raw -LiteralPath $r6bGh.Log) -join "`n") -notmatch 'pr ready 500\s*$') `
        'A round leaving Ship must not flip again; it is already ready and merged'

    # --- A round failure edge records its evidence in the body (review finding 7) ---
    # workflow.md gives the round the same rule as tracked work, with the pull request body
    # standing in for PLAN-PROGRESS.md, which a round does not have.
    $r7 = New-TransitionFixture -Stage '6-verify' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $r7Gh = New-FakeGh -Body "Stage: 6-verify" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $r7Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r7.Root -Edge 'failure' -Pr 500 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A round failure edge with no evidence must be refused'
    Assert-True ((Get-Content -Raw -LiteralPath $r7Gh.BodyFile) -match '(?m)^Stage: 6-verify\r?$') `
        'A refused round failure must leave the body alone'

    $r7b = New-TransitionFixture -Stage '6-verify' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $r7bGh = New-FakeGh -Body "Stage: 6-verify" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $r7bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r7b.Root -Edge 'failure' -Pr 500 `
            -Evidence 'pwsh ./scripts/test-fast.ps1 -Mode Fast : 2 failed' `
            -RecoveryTask 'Chore 3: fix the parity check' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round failure edge with evidence must succeed'
    $r7Body = Get-Content -Raw -LiteralPath $r7bGh.BodyFile
    Assert-True ($r7Body -match '(?m)^Stage: 4-execute\r?$') 'The round body must read the failure target'
    Assert-True ($r7Body -match '2 failed')                'The round body must carry the red evidence'
    Assert-True ($r7Body -match 'fix the parity check')    'The round body must carry the recovery task'

    # --- A tracked item never writes Stage 10 (review finding 8) ---
    # 9-ship success happens after the merge, and workflow.md says the Stage field is never
    # written after merge. An item in backlog/done/ must keep reading 'Stage: 9-ship'.
    $r8 = New-TransitionFixture -Stage '9-ship' -Difficulty 'complex' -AsWorktree -AllBoxesTicked -WithProgress
    $r8Head = (& git -C $r8.Root rev-parse HEAD).Trim()
    $r8Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $r8Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $r8.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A tracked item must refuse the 10-cleanup transition'
    Assert-Equal '9-ship' (Get-FixtureStage -Root $r8.Root) 'A shipped item must keep reading 9-ship'
    Assert-Equal $r8Head (& git -C $r8.Root rev-parse HEAD).Trim() `
        'A refused cleanup transition must make no commit'

    # ================= Copilot review round 2, PR 421 =================

    # --- Ship refuses while the linked plan is still open to the citation check (finding 1) ---
    # Ship moves the item into backlog/done/, and scripts/check-archived-plan-frozen.ps1 then
    # demands the plan be frozen. That check runs in the pre-push hook, so an unfrozen plan made
    # Ship's own push fail AFTER the closure commit was already made. Refuse before anything moves.
    $f1 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                -AllBoxesTicked -WithProgress -PlanState 'unfrozen'
    $f1Head = (& git -C $f1.Root rev-parse HEAD).Trim()
    $f1Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $f1Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f1.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Ship must refuse an unfrozen plan'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $f1.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A Ship refused for an unfrozen plan must not move the item'
    Assert-Equal $f1Head (& git -C $f1.Root rev-parse HEAD).Trim() `
        'A Ship refused for an unfrozen plan must make no closure commit'
    Assert-True ((Get-GhLog -Gh $f1Gh) -notmatch 'pr ready') `
        'A Ship refused for an unfrozen plan must not flip the pull request'

    # The same fixture, frozen. The freeze is the only difference, so this proves the refusal
    # reads the directive rather than the presence of a plan.
    $f1b = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress -PlanState 'frozen'
    $f1bGh = New-FakeGh
    Invoke-WithFakeGh -Gh $f1bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f1b.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'Ship with a frozen plan must succeed'
    Assert-True (Test-Path -LiteralPath (Join-Path $f1b.Root 'backlog/done/081-automate-stage-transitions.md')) `
        'Ship with a frozen plan must move the item'

    # --- A tracked Ship failure reopens the records and the pull request (finding 5) ---
    # This edge starts from the state Ship leaves: the item in backlog/done/ and no
    # PLAN-PROGRESS.md. The ordinary path refuses it, because it demands a progress file that
    # Ship itself deleted, so the edge workflow.md documents could not be taken at all.
    $f5 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                -AllBoxesTicked -WithProgress -PlanState 'frozen'
    $f5Branch = (& git -C $f5.Root rev-parse --abbrev-ref HEAD).Trim()
    $f5Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $f5Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f5.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'The Ship that sets up the failure case must succeed'

    $f5Gh2 = New-FakeGh
    Invoke-WithFakeGh -Gh $f5Gh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f5.Root -Item '081' -Edge 'failure' -Pr 421 `
            -Evidence 'CI: 2 checks failed after the ready flip' `
            -RecoveryTask 'Task 9: fix the failing parity check' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A Ship failure edge must succeed'
    Assert-Equal '6-verify' (Get-FixtureStage -Root $f5.Root) 'A Ship failure must set 6-verify'
    Assert-True (Test-Path -LiteralPath (Join-Path $f5.Root 'backlog/081-automate-stage-transitions.md')) `
        'A Ship failure must move the item back out of backlog/done/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $f5.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A Ship failure must leave nothing behind in backlog/done/'

    # Tolerant on purpose: when the restore does not happen, the three assertions below must
    # report that, rather than a Get-Content error that stops the whole suite.
    $f5Progress = (Get-Content -Raw -LiteralPath (Join-Path $f5.Root 'PLAN-PROGRESS.md') -ErrorAction SilentlyContinue) ?? ''
    Assert-True ($f5Progress -match 'Task 1 done')   'A Ship failure must restore the progress file Ship deleted'
    Assert-True ($f5Progress -match '2 checks failed') 'A Ship failure must record its red evidence'
    Assert-True ($f5Progress -match 'fix the failing parity check') 'A Ship failure must record its recovery task'

    # The undo comes first: Review can only be re-entered with a draft pull request.
    Assert-True ((Get-GhLog -Gh $f5Gh2) -match 'ready 421 .*--undo') `
        'A Ship failure must convert the pull request back to draft'

    Assert-Equal (& git -C $f5.Root rev-parse HEAD).Trim() (& git -C $f5.Bare rev-parse $f5Branch).Trim() `
        'A Ship failure must push the reopened records'

    # --- A round Ship failure undoes the ready flip too (finding 4) ---
    $f4 = New-TransitionFixture -Stage '9-ship' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $f4Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'false'
    Invoke-WithFakeGh -Gh $f4Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f4.Root -Edge 'failure' -Pr 500 `
            -Evidence 'CI: 1 check failed' -RecoveryTask 'Chore 2: repair the suite' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round Ship failure must succeed'
    Assert-True ((Get-GhLog -Gh $f4Gh) -match 'ready 500 .*--undo') `
        'A round Ship failure must convert the pull request back to draft'
    Assert-True ((Get-Content -Raw -LiteralPath $f4Gh.BodyFile) -match '(?m)^Stage: 6-verify\r?$') `
        'A round Ship failure must record 6-verify in the body'

    # --- A round at 9-ship resumes the ready flip rather than advancing (finding 2) ---
    # The body is written to 9-ship before 'gh pr ready' runs, so a failed flip leaves the body
    # at 9-ship with a draft pull request. A rerun used to resolve 9-ship -> 10-cleanup and
    # record Cleanup on an unmerged draft.
    $f2 = New-TransitionFixture -Stage '9-ship' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $f2Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'true'
    Invoke-WithFakeGh -Gh $f2Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f2.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round resuming Ship must succeed'
    Assert-True ((Get-GhLog -Gh $f2Gh) -match 'pr ready 500') `
        'A round resuming Ship must retry the ready flip'
    Assert-True ((Get-Content -Raw -LiteralPath $f2Gh.BodyFile) -match '(?m)^Stage: 9-ship\r?$') `
        'A round resuming Ship must leave the body at 9-ship'
    Assert-True ((Get-Content -Raw -LiteralPath $f2Gh.BodyFile) -notmatch '10-cleanup') `
        'A round resuming Ship must never write 10-cleanup'

    # Already ready: there is nothing to resume, and Cleanup writes no Stage line for a round
    # either. The merged pull request is the record.
    $f2b = New-TransitionFixture -Stage '9-ship' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $f2bGh = New-FakeGh -Body "Stage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'false'
    Invoke-WithFakeGh -Gh $f2bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f2b.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A round leaving Ship must be refused'
    Assert-True ((Get-Content -Raw -LiteralPath $f2bGh.BodyFile) -match '(?m)^Stage: 9-ship\r?$') `
        'A refused round cleanup must leave the body at 9-ship'

    # --- Pickup refuses a pull request it cannot reuse (finding 3) ---
    # 'gh pr list --head' answers with any open pull request for the branch. One already flipped
    # to ready, or opened against another base, is not the draft Pickup asked for, and stamping
    # 1-pickup as done against it records a Pickup that never happened.
    $f3 = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $f3Gh = New-FakeGh -ExistingPr '421' -IsDraft 'false'
    Invoke-WithFakeGh -Gh $f3Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f3.Root -Item '081' -Edge 'success' *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Pickup must refuse a pull request that is no longer a draft'
    Assert-Equal '1-pickup' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $f3.ItemPath)) `
        'A refused Pickup must leave the Stage at 1-pickup'

    $f3b = New-TransitionFixture -Stage '1-pickup' -Difficulty 'complex' -AsWorktree
    $f3bGh = New-FakeGh -ExistingPr '421' -IsDraft 'true' -BaseRefName 'feature/wt-somewhere-else'
    Invoke-WithFakeGh -Gh $f3bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f3b.Root -Item '081' -Edge 'success' *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Pickup must refuse a pull request opened against another base'
    Assert-Equal '1-pickup' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $f3b.ItemPath)) `
        'A Pickup refused for the wrong base must leave the Stage at 1-pickup'

    # --- Every legal transition lands on the target workflow.md names ---
    $workflowPath = Join-Path $suiteRoot 'docs/development/workflow.md'
    $allStages = Get-WorkflowStage -Path $workflowPath

    foreach ($stageId in $allStages.Keys) {
        $bare = $stageId -replace '^stage-', ''
        foreach ($edge in @('success', 'failure', 'not applicable')) {
            if (-not $allStages[$stageId].Edges.Contains($edge)) { continue }

            $targets = @(Get-StageEdgeTarget -WorkflowPath $workflowPath -Stage $stageId -Edge $edge)
            if ($targets.Count -ne 1) { continue }   # Pickup's three targets are Task 3's case.

            # 10-cleanup is reached only after the merge, and the Stage field is never written
            # after merge. The script refuses that transition, and its own case above proves it.
            if ($targets[0] -eq '10-cleanup') { continue }

            # A failure edge refuses without PLAN-PROGRESS.md once Task 5 lands, so every stage
            # from 4-execute on gets one. The stage id carries its own number, so this reads the
            # number rather than matching against a list of stage names written here.
            $needsProgress = ([int]($bare -split '-')[0]) -ge 4

            # Every case runs under a fake gh and carries a pull request number. One of them,
            # the success edge of 8-review, lands on 9-ship and so takes the Ship path, which
            # calls 'gh pr ready'. The loop cannot know which case that is without copying the
            # dispatch rule here, so it gives every case what the heaviest path needs.
            $case = New-TransitionFixture -Stage $bare -Difficulty 'complex' -AsWorktree `
                                          -AllBoxesTicked -WithProgress:$needsProgress
            $caseGh = New-FakeGh
            Invoke-WithFakeGh -Gh $caseGh -Action {
                & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $case.Root -Item '081' `
                    -Edge $edge -Pr 421 -Evidence 'red' -RecoveryTask 'recover' *> $null
            }

            Assert-Equal $targets[0] (Get-FixtureStage -Root $case.Root) `
                "The '$edge' edge of '$stageId' must land on '$($targets[0])'"
        }
    }

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
