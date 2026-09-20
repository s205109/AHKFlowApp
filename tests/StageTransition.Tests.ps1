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
        [switch] $WithProgress
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
        ) -join "`n"
        Set-Content -LiteralPath (Join-Path $root $itemName) -Value $item -Encoding utf8
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

    return [pscustomobject]@{
        Root     = (Resolve-Path -LiteralPath $acting).Path
        Bare     = (Resolve-Path -LiteralPath $bare).Path
        ItemPath = (Join-Path (Resolve-Path -LiteralPath $acting).Path $itemName)
    }
}

# A fake gh. The ordering test needs 'pr create' to fail on demand, which no real call can be
# asked to do safely.
function New-FakeGh {
    param([int] $CreateExitCode = 0, [string] $PrNumber = '421')

    $dir = New-Root -Prefix 'fake-gh'
    $log = Join-Path $dir 'gh-calls.log'
    $script = @"
#!/usr/bin/env pwsh
`$args -join ' ' | Add-Content -LiteralPath '$log'
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

    return [pscustomobject]@{ Dir = $dir; Log = $log }
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

    # --- An edge that names no stage changes nothing at all ---
    # 'blocked' from Design targets 'blocked/', which is a folder and not a stage. The plan named
    # 'not applicable' here, but workflow.md gives that edge a real target, '3-plan'.
    $fx2 = New-TransitionFixture -Stage '2-design' -Difficulty 'complex' -AsWorktree
    $before = (& git -C $fx2.Root rev-parse HEAD).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx2.Root -Item '081' -Edge 'blocked' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'An edge that names no stage must fail'

    $after = (& git -C $fx2.Root rev-parse HEAD).Trim()
    Assert-Equal $before $after 'A refused transition must leave the commit log untouched'
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath (Join-Path $fx2.Root 'backlog/081-automate-stage-transitions.md'))) `
        'A refused transition must leave the field untouched'

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

    # --- Every legal transition lands on the target workflow.md names ---
    $workflowPath = Join-Path $suiteRoot 'docs/development/workflow.md'
    $allStages = Get-WorkflowStage -Path $workflowPath

    foreach ($stageId in $allStages.Keys) {
        $bare = $stageId -replace '^stage-', ''
        foreach ($edge in @('success', 'failure', 'not applicable')) {
            if (-not $allStages[$stageId].Edges.Contains($edge)) { continue }

            $targets = @(Get-StageEdgeTarget -WorkflowPath $workflowPath -Stage $stageId -Edge $edge)
            if ($targets.Count -ne 1) { continue }   # Pickup's three targets are Task 3's case.

            # A failure edge refuses without PLAN-PROGRESS.md once Task 5 lands, so every stage
            # from 4-execute on gets one. The stage id carries its own number, so this reads the
            # number rather than matching against a list of stage names written here.
            $needsProgress = ([int]($bare -split '-')[0]) -ge 4

            $case = New-TransitionFixture -Stage $bare -Difficulty 'complex' -AsWorktree `
                                          -AllBoxesTicked -WithProgress:$needsProgress
            & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $case.Root -Item '081' `
                -Edge $edge -Evidence 'red' -RecoveryTask 'recover' *> $null

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
