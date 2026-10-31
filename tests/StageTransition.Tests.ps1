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
# The driver itself, for the one function a case calls directly. '-AsModule' returns before the
# script runs anything, so dot-sourcing it defines the functions and performs no transition.
. (Join-Path $suiteRoot 'scripts/take-stage-transition.ps1') -AsModule

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

# Builds the seed commit of a transition fixture and pushes it to the bare remote.
function New-TransitionSeed {
    param(
        [string] $Bare, [string] $Root, [string] $ItemName, [string] $PlanName,
        [string] $Stage, [string] $Difficulty, [switch] $NoItem, [switch] $AllBoxesTicked,
        [switch] $WithProgress, [switch] $WithForeignProgress, [string] $PlanState
    )

    $bare = $Bare; $root = $Root; $itemName = $ItemName; $planName = $PlanName
    & git init --bare $bare *> $null

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

    if ($WithForeignProgress) {
        # Both switches write the same path on the same branch, so the second would erase the first.
        if ($WithProgress) { throw 'Pass -WithForeignProgress or -WithProgress, not both.' }
        Set-Content -LiteralPath (Join-Path $root 'PLAN-PROGRESS.md') -Value '- item 999 Task 1 done' -Encoding utf8
        & git -C $root add -- PLAN-PROGRESS.md *> $null
        & git -C $root commit -m 'docs: 999 progress' *> $null
        & git -C $root rm -q -- PLAN-PROGRESS.md *> $null
        & git -C $root commit -m 'docs: 999 close the records' *> $null
    }
    & git -C $root remote add origin $bare *> $null
    & git -C $root push -u origin HEAD *> $null
}

# Seeded main clones and their bare remotes, one pair per seed shape. Backlog 188: building the
# seed took about ten git processes per case, and many cases share a shape. A copy of a cached
# pair needs only its hooks path and its remote pointed at the copy.
$script:FixtureSeeds = @{}

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
        # Another item's PLAN-PROGRESS.md, committed and then deleted by that item's own closure,
        # on main before this branch starts. Every real branch inherits commits like these, and a
        # fresh fixture has none, so without this switch no case can see what they do to a lookup.
        [switch] $WithForeignProgress,
        # The item's linked plan, and whether it carries the freeze directive. 'none' writes no
        # '- Plan:' bullet and no file, which is what every case before the freeze rule used.
        [ValidateSet('none', 'unfrozen', 'frozen')]
        [string] $PlanState = 'none'
    )

    $bare = New-Root -Prefix 'transition-remote'
    $root = New-Root -Prefix 'transition-work'
    $itemName = 'backlog/081-automate-stage-transitions.md'
    $planName = 'docs/superpowers/plans/2026-09-20-stage-transition-plan-081.md'

    # Everything that changes the seed commit, and nothing else.
    $seedKey = @($Stage, $Difficulty, [bool] $NoItem, [bool] $AllBoxesTicked, [bool] $WithProgress,
        [bool] $WithForeignProgress, ($PlanState -ne 'none')) -join '|'
    if ($script:FixtureSeeds.ContainsKey($seedKey)) {
        $seed = $script:FixtureSeeds[$seedKey]
        Copy-Item -Path (Join-Path $seed.Bare '*') -Destination $bare -Recurse -Force
        Copy-Item -Path (Join-Path $seed.Root '*') -Destination $root -Recurse -Force
        & git -C $root config core.hooksPath (Join-Path $root '.nohooks') *> $null
        & git -C $root remote set-url origin $bare *> $null
    }
    else {
        New-TransitionSeed -Bare $bare -Root $root -ItemName $itemName -PlanName $planName `
            -Stage $Stage -Difficulty $Difficulty -NoItem:$NoItem -AllBoxesTicked:$AllBoxesTicked `
            -WithProgress:$WithProgress -WithForeignProgress:$WithForeignProgress -PlanState $PlanState
        $seedBare = New-Root -Prefix 'transition-seed-remote'
        $seedRoot = New-Root -Prefix 'transition-seed-work'
        Copy-Item -Path (Join-Path $bare '*') -Destination $seedBare -Recurse -Force
        Copy-Item -Path (Join-Path $root '*') -Destination $seedRoot -Recurse -Force
        $script:FixtureSeeds[$seedKey] = [pscustomobject]@{ Bare = $seedBare; Root = $seedRoot }
    }

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
    # and the closure pathspec - the two sides of the item's move, plus PLAN-PROGRESS.md when git
    # can match it - can never sweep it into a commit.
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
        Main     = (Resolve-Path -LiteralPath $root).Path
        # Where core.hooksPath points. A case that needs a commit to fail writes a pre-commit hook
        # here, after its own setup commits are safely in.
        HookDir  = (Join-Path $root '.nohooks')
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

# Make every later commit or push in a fixture fail. The hook refuses, and git reports the
# refusal as a non-zero exit code, which is what a closure meets when a real pre-commit hook says
# no, and what a pre-flight meets when this repository's own pre-push checks refuse.
function Block-FixtureHook {
    param([string] $HookDir, [ValidateSet('pre-commit', 'pre-push')] [string] $Name)

    New-Item -ItemType Directory -Path $HookDir -Force | Out-Null
    $hook = Join-Path $HookDir $Name
    # Backtick-n, not a here-string: sh on Windows rejects a script whose first line ends with a
    # carriage return, and the refusal would then look like a hook that did not run at all.
    Set-Content -LiteralPath $hook -Value "#!/bin/sh`necho 'fixture $Name refuses' >&2`nexit 1" -Encoding ascii
    if (-not $IsWindows) { & chmod +x $hook }
}

# The bytes of a file, or $null when it is not there. Restoration is asserted byte for byte: a
# substring match cannot tell an exact restore from a close one, and the undo promises exact.
function Get-FileByte {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    # The comma matters. A bare 'return [byte[]]' enumerates, and an empty array then enumerates
    # to nothing, so a zero-byte file would read back as $null and compare unequal to itself.
    return , [System.IO.File]::ReadAllBytes($Path)
}

function Test-SameByte {
    param([byte[]] $Expected, [byte[]] $Actual)
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    if ($Expected.Length -ne $Actual.Length) { return $false }
    if ($Expected.Length -eq 0) { return $true }
    return -not (Compare-Object $Expected $Actual -SyncWindow 0)
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

    # The next four cases run on $fx before its own transition. Each one is refused before any
    # write, so $fx is still at 2-design, with the same commit log, when the transition runs.

    # --- A transition the source does not allow is refused at driver level ---
    # This is acceptance criterion 2, proven through the script rather than through the reader.
    # Design success has exactly one target, '3-plan', so '9-ship' is a target workflow.md does
    # not give this edge.
    $before = (& git -C $fx.Root rev-parse HEAD).Trim()

    $illegalOutput = (& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx.Root -Item '081' `
        -Edge 'success' -To '9-ship' *>&1) -join "`n"
    Assert-True ($LASTEXITCODE -ne 0) 'A target the source does not allow must be refused'
    Assert-True ($illegalOutput.Contains("REFUSED: -To '9-ship' is not a target of 'success' from '2-design'. The only target is '3-plan'.")) `
        "The refusal must name the one target workflow.md allows. Output: $illegalOutput"

    $after = (& git -C $fx.Root rev-parse HEAD).Trim()
    Assert-Equal $before $after 'A refused transition must leave the commit log untouched'
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath (Join-Path $fx.Root 'backlog/081-automate-stage-transitions.md'))) `
        'A refused transition must leave the field untouched'

    # --- 'blocked' is not a transition this script performs ---
    # Moving an item into backlog/blocked/ is a manual git mv, so the parameter must refuse the
    # word rather than accept it and fail later with a message about a missing stage.
    $blockedErrorId = ''
    try {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx.Root -Item '081' -Edge 'blocked' *> $null
    } catch {
        $blockedErrorId = $_.FullyQualifiedErrorId
    }
    Assert-True ($blockedErrorId -like 'ParameterArgumentValidationError*') `
        "The blocked edge must be refused by the parameter itself. Got: $blockedErrorId"
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fx.ItemPath)) `
        'Parameter validation must leave the Stage unchanged'
    Assert-Equal $before ((& git -C $fx.Root rev-parse HEAD).Trim()) `
        'The blocked refusal must leave the commit log untouched'

    # --- The main checkout is refused ---
    # $fx's main clone is a plain repository, which is what Test-LinkedWorktree must reject.
    $fxMain = $fx.Main
    $mainOutput = (& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fxMain -Item '081' -Edge 'success' *>&1) -join "`n"
    Assert-True ($LASTEXITCODE -ne 0) 'The main checkout must be refused'
    Assert-True ($mainOutput.Contains("REFUSED: '$fxMain' is the main checkout, not a linked worktree.")) `
        "The refusal must say the path is the main checkout. Output: $mainOutput"
    Assert-Equal $before ((& git -C $fx.Root rev-parse HEAD).Trim()) `
        'The main-checkout refusal must leave the worktree commit log untouched'

    # --- A retired stage is refused with the way forward ---
    # ADR 0022 folded 5, 6 and 7 into Execute. A branch that still reads one of them got
    # "has no stage", which names no stage to move to.
    $retiredFx = New-TransitionFixture -Stage '6-verify' -Difficulty 'complex' -AsWorktree
    $retiredOutput = (& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $retiredFx.Root -Item '081' -Edge 'success' *>&1) -join "`n"
    Assert-True ($LASTEXITCODE -ne 0) 'A transition from a retired stage must be refused'
    Assert-True ($retiredOutput.Contains("Stage '6-verify' was retired and folded into '4-execute'")) `
        "The refusal must name the stage that replaced it. Output: $retiredOutput"
    Assert-Equal '6-verify' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $retiredFx.ItemPath)) `
        'A refused retired-stage transition must leave the field untouched'

    # --- An item worktree with -Pr and no -Item is refused, not treated as a round (finding 3) ---
    # The refusal reads only the branch name, so $fx's item branch is enough.
    $r3Gh = New-FakeGh -Body "Stage: 4-execute"
    $r3Output = Invoke-WithFakeGh -Gh $r3Gh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx.Root -Edge 'success' -Pr 500 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A missing -Item on an item branch must be refused'
    Assert-True ($r3Output.Contains("REFUSED: This worktree is on 'feature/wt-transition-test', which is not the housekeeping round branch 'chore/wt-backlog-housekeeping'. A tracked transition needs -Item.")) `
        "The refusal must ask for -Item. Output: $($r3Output)"
    Assert-True ((Get-Content -Raw -LiteralPath $r3Gh.BodyFile) -match '(?m)^Stage: 4-execute\r?$') `
        'A refused run must not rewrite any pull request body'
    Assert-Equal $before ((& git -C $fx.Root rev-parse HEAD).Trim()) `
        'The missing -Item refusal must leave the commit log untouched'
    Assert-Equal '2-design' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fx.ItemPath)) `
        'The missing -Item refusal must leave the Stage unchanged'

    # The ordinary transition itself, on the $fx the four refusals above left unchanged.
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fx.Root -Item '081' -Edge 'success' *> $null
    Assert-Equal 0 $LASTEXITCODE 'An ordinary transition must succeed'

    $local = Get-SingleBacklogStage -Lines (Get-Content -LiteralPath (Join-Path $fx.Root 'backlog/081-automate-stage-transitions.md'))
    Assert-Equal '3-plan' $local 'Design success must write 3-plan into the item'
    Assert-Equal '3-plan' (Get-RemoteItemStage -Bare $fx.Bare -Branch $branch) `
        'The transition must be pushed, because the remote is what a reader of main sees'

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

    # --- An edge that names no stage is a different refusal, and also changes nothing ---
    # Pickup's 'not applicable' edge targets 'none'. That is not an illegal edge; it is a legal
    # edge with no field to write, and the two must not be confused. The refused Pickup above left
    # $pk2 at 1-pickup, so the edge runs on it.
    $beforeB = (& git -C $pk2.Root rev-parse HEAD).Trim()

    $noStageOutput = (& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pk2.Root -Item '081' `
        -Edge 'not applicable' *>&1) -join "`n"
    Assert-True ($LASTEXITCODE -ne 0) 'An edge that names no stage must fail'
    Assert-True ($noStageOutput.Contains("REFUSED: The 'not applicable' edge of '1-pickup' names no stage, so there is no field to write.")) `
        "The refusal must say the edge names no stage. Output: $noStageOutput"
    Assert-Equal $beforeB (& git -C $pk2.Root rev-parse HEAD).Trim() `
        'An edge that names no stage must leave the commit log untouched'

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

    # --- Ship refuses a pull request number pointing at another branch (review finding 2) ---
    # Assert-PrOnBranch refuses before any write or push, so this runs on $sh before its own Ship.
    $r2Gh = New-FakeGh -HeadRefName 'feature/wt-somebody-else'
    $r2Output = Invoke-WithFakeGh -Gh $r2Gh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh.Root -Item '081' `
            -Edge 'success' -Pr 999 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Ship must refuse a pull request on another branch'
    Assert-True ($r2Output.Contains("REFUSED: Pull request 999 belongs to branch 'feature/wt-somebody-else', but this worktree is on 'feature/wt-transition-test'. Nothing was changed.")) `
        "The refusal must name the other branch. Output: $($r2Output)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sh.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A refused Ship must not move the item'
    Assert-True (((Get-Content -Raw -LiteralPath $r2Gh.Log) -join "`n") -notmatch 'pr ready') `
        'A refused Ship must not flip any pull request'

    # $sh's own Ship.
    $shGh = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A ticked Ship must succeed'

    Assert-True (Test-Path -LiteralPath (Join-Path $sh.Root 'backlog/done/081-automate-stage-transitions.md')) `
        'Ship must move the item into backlog/done/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sh.Root 'PLAN-PROGRESS.md'))) `
        'Ship must delete PLAN-PROGRESS.md'

    # Criterion 2: the deletion is not only on disk, it is in the same commit.
    $shTouched = @(& git -C $sh.Root show --name-only --pretty=format: HEAD | Where-Object { $_ })
    Assert-True ($shTouched -contains 'PLAN-PROGRESS.md') `
        'The closure commit must record the deletion of PLAN-PROGRESS.md'

    # The ordering claim, read from the remote rather than from intent.
    $shBranch = (& git -C $sh.Root rev-parse --abbrev-ref HEAD).Trim()
    $remoteHead = (& git -C $sh.Bare rev-parse $shBranch).Trim()
    $localHead = (& git -C $sh.Root rev-parse HEAD).Trim()
    Assert-Equal $localHead $remoteHead 'The closure commit must be on the remote'

    Assert-True ((Get-Content -Raw -LiteralPath $shGh.Log) -match 'pr ready') 'Ship must flip the pull request to ready'

    # --- An unticked box refuses the flip ---
    $sh2 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -WithProgress
    $sh2Head = (& git -C $sh2.Root rev-parse HEAD).Trim()
    $shGh2 = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh2.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'An unticked acceptance box must refuse Ship'
    # Ship does call gh before it refuses, to check the pull request belongs to this branch.
    # What it must never do is flip one.
    Assert-True (((Get-Content -Raw -LiteralPath $shGh2.Log) -join "`n") -notmatch 'pr ready') `
        'A refused Ship must not flip the pull request'
    # The undo cases below reuse $sh2, so the refusal must leave it exactly as it was.
    Assert-Equal $sh2Head ((& git -C $sh2.Root rev-parse HEAD).Trim()) 'A refused Ship must not commit'
    Assert-Equal '8-review' (Get-FixtureStage -Root $sh2.Root) 'A refused Ship must leave the Stage at 8-review'
    Assert-True (Test-Path -LiteralPath (Join-Path $sh2.Root 'backlog/081-automate-stage-transitions.md')) `
        'A refused Ship must leave the item in backlog/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sh2.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A refused Ship must not put a copy of the item in backlog/done/'
    # Scoped to the closure paths: the fixture's linked plan is untracked on purpose.
    Assert-Equal '' ((& git -C $sh2.Root status --porcelain -- backlog PLAN-PROGRESS.md) -join '') `
        'A refused Ship must leave the closure paths unchanged'

    # --- A branch that never wrote PLAN-PROGRESS.md still closes (backlog 164) ---
    # git treats a pathspec that matches nothing as fatal and stages NOTHING, so one 'git add'
    # naming a path that may be absent cannot close such a branch. Ship has already moved the item
    # and written the Stage by then, and neither is committed. The item has the reported run.
    $sh3 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -AllBoxesTicked
    $shGh3 = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh3 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh3.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A Ship with no PLAN-PROGRESS.md must succeed'
    Assert-True (Test-Path -LiteralPath (Join-Path $sh3.Root 'backlog/done/081-automate-stage-transitions.md')) `
        'A Ship with no PLAN-PROGRESS.md must move the item into backlog/done/'
    Assert-Equal '9-ship' (Get-FixtureStage -Root $sh3.Root) `
        'A Ship with no PLAN-PROGRESS.md must write 9-ship'

    # One commit holds the move and the Stage, and nothing is left uncommitted.
    $sh3Touched = @(& git -C $sh3.Root show --name-only --pretty=format: HEAD | Where-Object { $_ })
    Assert-True (($sh3Touched -join ' ') -match 'backlog/done/081') 'The closure commit must hold the move'
    Assert-Equal '' ((& git -C $sh3.Root status --porcelain -- backlog) -join '') `
        'The closure must leave nothing uncommitted under backlog/'

    # --- An empty PLAN-PROGRESS.md is deleted too, and the deletion is committed ---
    # Review Focus 4 on the success path. Reading the bytes through an 'if' used as an expression
    # sends them down the pipeline, which enumerates the array, and an empty array enumerates to
    # nothing. The variable is then $null, the delete is skipped, and Ship commits the empty
    # progress file onto the branch that merges into main.
    $sh5 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    [System.IO.File]::WriteAllBytes((Join-Path $sh5.Root 'PLAN-PROGRESS.md'), [byte[]]::new(0))
    $shGh5 = New-FakeGh
    Invoke-WithFakeGh -Gh $shGh5 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $sh5.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A Ship with an empty PLAN-PROGRESS.md must succeed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sh5.Root 'PLAN-PROGRESS.md'))) `
        'Ship must delete an empty PLAN-PROGRESS.md too'
    $sh5Status = @(& git -C $sh5.Root show --name-status --pretty=format: HEAD | Where-Object { $_ })
    Assert-True ((($sh5Status -join ' ') -match 'D\s+PLAN-PROGRESS\.md')) `
        'The closure commit must record the deletion of an empty PLAN-PROGRESS.md'

    # The whole worktree, not just backlog/. Scoped to backlog/ this cannot see a progress file
    # the closure left behind, which is exactly the state above.
    Assert-Equal '' ((& git -C $sh5.Root status --porcelain) -join '') `
        'A Ship with an empty PLAN-PROGRESS.md must leave the worktree clean'

    # --- The pathspec names a progress path only when the index holds one ---
    # Three states, because only the index is read. A file git never tracked is never named. The
    # closure deletes it first, and a path in neither the index nor the working tree is the fatal
    # pathspec this item exists to fix.
    # Only the index is read, so $sh3 serves. It shipped without ever tracking PLAN-PROGRESS.md,
    # which is the first state below.
    $psFix = $sh3
    $psProgress = Join-Path $psFix.Root 'PLAN-PROGRESS.md'
    $psFrom = 'backlog/081-automate-stage-transitions.md'
    $psTo = 'backlog/done/081-automate-stage-transitions.md'
    $psCall = { (Get-ClosurePathspec -Worktree $psFix.Root -From $psFrom -To $psTo) -join ',' }

    # Prove the first state from git itself, not through the function under test.
    Assert-Equal '' ((& git -C $psFix.Root ls-files -- PLAN-PROGRESS.md) -join '') `
        'The reused Ship fixture must not track PLAN-PROGRESS.md'
    Assert-True (-not (Test-Path -LiteralPath $psProgress)) `
        'The reused Ship fixture must hold no PLAN-PROGRESS.md on disk'

    Assert-Equal "$psFrom,$psTo" (& $psCall) `
        'No progress path anywhere must give the two item paths alone'

    Set-Content -LiteralPath $psProgress -Value '- untracked work' -Encoding utf8
    Assert-Equal "$psFrom,$psTo" (& $psCall) `
        'A progress file on disk that git never tracked must not be named'

    & git -C $psFix.Root add -- PLAN-PROGRESS.md *> $null
    & git -C $psFix.Root commit -m 'test: progress file' *> $null
    Assert-Equal "$psFrom,$psTo,PLAN-PROGRESS.md" (& $psCall) `
        'A tracked progress file must be named'

    Remove-Item -LiteralPath $psProgress -Force
    Assert-Equal "$psFrom,$psTo,PLAN-PROGRESS.md" (& $psCall) `
        'A tracked progress file deleted from disk must still be named, so its deletion is staged'

    # --- The undo says what it could not put back (backlog 164) ---
    # No end-to-end case reaches the half-done message. A stale index.lock fails the reset but
    # stages nothing, so the undo correctly reports success there. The contract is checked here.
    # Undo-RecordClosure needs an 8-review item with a tracked progress file. $sh2 is one, and its
    # Ship was refused for the unticked box, so it is unchanged.
    $udFix = $sh2
    $udRecord = @(Get-BacklogItem -BacklogRoot (Join-Path $udFix.Root 'backlog') |
                  Where-Object { $_.Key -eq '081' })[0]
    $udDestination = Join-Path $udFix.Root 'backlog/done/081-automate-stage-transitions.md'
    $udPathspec = @($udRecord.RelativePath, 'backlog/done/081-automate-stage-transitions.md', 'PLAN-PROGRESS.md')
    $udItemByte = Get-FileByte -Path $udRecord.Path

    $udOk = Undo-RecordClosure -Worktree $udFix.Root -Record $udRecord -Destination $udDestination `
                               -Pathspec $udPathspec -ItemByte $udItemByte -ProgressByte $null
    Assert-True ($udOk -match 'The records are back on disk') `
        'An undo that puts everything back must say so'
    # And must not overstate it. 'git reset' sends the three closure paths back to HEAD, so a blob
    # the human had staged on one of them is gone from the index. Saying 'back as they were' hid
    # that.
    Assert-True ($udOk -match 'unstaged') `
        'The success sentence must say the closure paths are unstaged'

    # Hold the item open so the write back cannot land. 'Read' share lets the snapshot above be
    # read and still refuses the write, which is the state being tested.
    $udLock = [System.IO.File]::Open($udRecord.Path, 'Open', 'Read', 'Read')
    try {
        $udLeft = Undo-RecordClosure -Worktree $udFix.Root -Record $udRecord -Destination $udDestination `
                                     -Pathspec $udPathspec -ItemByte $udItemByte -ProgressByte $null
    } finally {
        $udLock.Dispose()
    }
    Assert-True ($udLeft -match 'the item is not back at backlog/081-automate-stage-transitions\.md') `
        'An undo that cannot write the item back must name it'
    Assert-True ($udLeft -match 'Repair them by hand') `
        'A half-done undo must tell the human to repair by hand'

    # A removal that fails is its own problem. The item IS back, and a second copy is left in
    # backlog/done/, so the message must not say the item is missing.
    New-Item -ItemType Directory -Path (Join-Path $udFix.Root 'backlog/done') -Force | Out-Null
    [System.IO.File]::WriteAllBytes($udDestination, $udItemByte)
    $udDestLock = [System.IO.File]::Open($udDestination, 'Open', 'Read', 'Read')
    try {
        $udTwo = Undo-RecordClosure -Worktree $udFix.Root -Record $udRecord -Destination $udDestination `
                                    -Pathspec $udPathspec -ItemByte $udItemByte -ProgressByte $null
    } finally {
        $udDestLock.Dispose()
    }
    Assert-True ($udTwo -match 'a second copy of the item is still at backlog/done/081-automate-stage-transitions\.md') `
        'An undo that cannot remove the copy in backlog/done/ must say there are two'
    Assert-True ($udTwo -notmatch 'the item is not back') `
        'Two copies must not be reported as a missing item'
    Remove-Item -LiteralPath $udDestination -Force

    # --- A closure that cannot commit puts every record back (backlog 164) ---
    # Case 1: the tracked progress file, plus an unrelated item that is part staged and part not.
    # The index-state contract says the closure stages three named paths and the undo resets those
    # same three, so this file's index state must survive both.
    $un1 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    $un1Item = Join-Path $un1.Root 'backlog/081-automate-stage-transitions.md'
    $un1Other = Join-Path $un1.Root 'backlog/099-another-item.md'

    Set-Content -LiteralPath $un1Other -Value "# 099 - Another item`n`n- **Stage**: 4-execute" -Encoding utf8
    & git -C $un1.Root add -- backlog/099-another-item.md *> $null
    & git -C $un1.Root commit -m 'test: a second item' *> $null
    Add-Content -LiteralPath $un1Other -Value 'staged by the human' -Encoding utf8
    & git -C $un1.Root add -- backlog/099-another-item.md *> $null
    Add-Content -LiteralPath $un1Other -Value 'and left unstaged' -Encoding utf8

    $un1Item0 = Get-FileByte -Path $un1Item
    $un1Progress = Get-FileByte -Path (Join-Path $un1.Root 'PLAN-PROGRESS.md')
    $un1Other0 = Get-FileByte -Path $un1Other
    $un1Status0 = ((& git -C $un1.Root status --porcelain -- backlog/099-another-item.md) -join '').Trim()
    # The index entry itself, not just the porcelain letters. 'MM' says a staged change exists,
    # not which one. Every mutation tried so far reddens this and the porcelain check together,
    # so read it as the sharper failure message - it names the blob instead of two letters.
    $un1Index0 = ((& git -C $un1.Root ls-files -s -- backlog/099-another-item.md) -join '').Trim()

    Block-FixtureHook -Name 'pre-commit' -HookDir $un1.HookDir
    $un1Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $un1Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un1.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A closure whose commit fails must be refused'

    Assert-True (Test-Path -LiteralPath $un1Item) 'A refused closure must put the item back in backlog/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $un1.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A refused closure must leave nothing in backlog/done/'
    Assert-Equal '8-review' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $un1Item)) `
        'A refused closure must leave the Stage line unchanged'
    Assert-True (Test-SameByte -Expected $un1Item0 -Actual (Get-FileByte -Path $un1Item)) `
        'A refused closure must put the item back byte for byte, not rebuild it'
    Assert-True (Test-SameByte -Expected $un1Progress -Actual (Get-FileByte -Path (Join-Path $un1.Root 'PLAN-PROGRESS.md'))) `
        'A refused closure must put PLAN-PROGRESS.md back byte for byte'
    Assert-Equal '' ((& git -C $un1.Root diff --cached --name-only -- backlog/081-automate-stage-transitions.md backlog/done/081-automate-stage-transitions.md PLAN-PROGRESS.md) -join '') `
        'A refused closure must leave none of its own paths staged'

    # The unrelated file, in both halves: its bytes and its index state.
    Assert-True (Test-SameByte -Expected $un1Other0 -Actual (Get-FileByte -Path $un1Other)) `
        'A refused closure must not change an unrelated item on disk'
    Assert-Equal $un1Status0 ((& git -C $un1.Root status --porcelain -- backlog/099-another-item.md) -join '').Trim() `
        'A refused closure must leave a part-staged unrelated item exactly as it was'
    Assert-Equal $un1Index0 ((& git -C $un1.Root ls-files -s -- backlog/099-another-item.md) -join '').Trim() `
        'A refused closure must leave an unrelated staged blob byte for byte in the index'
    Assert-True ((Get-GhLog -Gh $un1Gh) -notmatch 'pr ready') 'A refused closure must not flip the pull request'

    # Case 3: a progress file git never tracked. Nothing can be read back out of git for this one,
    # so only the text the closure saved before the delete can restore it.
    $un3 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -AllBoxesTicked
    Set-Content -LiteralPath (Join-Path $un3.Root 'PLAN-PROGRESS.md') -Value '- never committed' -Encoding utf8
    $un3Progress = Get-FileByte -Path (Join-Path $un3.Root 'PLAN-PROGRESS.md')
    Block-FixtureHook -Name 'pre-commit' -HookDir $un3.HookDir
    $un3Gh = New-FakeGh
    $un3Output = Invoke-WithFakeGh -Gh $un3Gh -Action {
        # Captured, because this is the only refused case whose pathspec is two paths: git never
        # tracked PLAN-PROGRESS.md, so the closure never names it.
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un3.Root -Item '081' -Edge 'success' -Pr 421 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A refused closure with an untracked progress file must be refused'
    Assert-True (Test-SameByte -Expected $un3Progress -Actual (Get-FileByte -Path (Join-Path $un3.Root 'PLAN-PROGRESS.md'))) `
        'A refused closure must put back a progress file git never tracked'
    Assert-True ($un3Output -match 'The records are back on disk') `
        'A two-path closure must still report that the records are back'
    # The count was hardcoded as 'three'. On this branch the pathspec is two paths, so the human
    # was sent looking for staged work on a PLAN-PROGRESS.md the closure never named.
    Assert-True ($un3Output -notmatch 'three') `
        'The refusal must not name a path count the closure did not use'

    # Case 4: a zero-byte progress file. 'Get-Content -Raw' answers $null for it, so existence has
    # to travel in its own flag or the file never comes back.
    $un4 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    [System.IO.File]::WriteAllBytes((Join-Path $un4.Root 'PLAN-PROGRESS.md'), @())
    $un4Progress = Join-Path $un4.Root 'PLAN-PROGRESS.md'
    $un4Progress0 = Get-FileByte -Path $un4Progress
    Block-FixtureHook -Name 'pre-commit' -HookDir $un4.HookDir
    $un4Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $un4Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un4.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A refused closure with an empty progress file must be refused'
    Assert-True (Test-Path -LiteralPath (Join-Path $un4.Root 'PLAN-PROGRESS.md')) `
        'A refused closure must put back an empty progress file'
    Assert-Equal 0 ((Get-Item -LiteralPath (Join-Path $un4.Root 'PLAN-PROGRESS.md')).Length) `
        'The restored empty progress file must still be empty'
    # Bytes, not just the length. 'return [byte[]]' enumerates on the way out of a function, so an
    # empty file reads back as $null unless the return is unrolled with a comma. That trap is the
    # same one that made the closure skip the delete, and this assertion is what catches it.
    Assert-True (Test-SameByte -Expected $un4Progress0 -Actual (Get-FileByte -Path $un4Progress)) `
        'A refused closure must put an empty progress file back byte for byte'

    # Case 5: a write that fails after the move, before any staging. Another process holds the
    # progress file open, so Remove-Item throws and $ErrorActionPreference = 'Stop' makes it an
    # exception. No git call has run yet at that point.
    #
    # The share mode is the whole case. 'Read' lets the closure read the file and still refuses the
    # delete, which is the state being tested. 'None' would refuse the closure's own first read:
    # the run would die before it moved anything, every assertion below would pass with no undo in
    # the script at all, and the case would be worthless. The premise assertion below is what
    # keeps a future change to the share mode loud instead of quiet.
    $un5 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    $un5Item = Join-Path $un5.Root 'backlog/081-automate-stage-transitions.md'
    $un5Item0 = Get-FileByte -Path $un5Item
    $un5Progress = Get-FileByte -Path (Join-Path $un5.Root 'PLAN-PROGRESS.md')
    $un5Gh = New-FakeGh
    $un5Lock = [System.IO.File]::Open((Join-Path $un5.Root 'PLAN-PROGRESS.md'), 'Open', 'Read', 'Read')
    try {
        # Prove the premise before trusting the result: the closure's own read must still work.
        Assert-True ($null -ne (Get-FileByte -Path (Join-Path $un5.Root 'PLAN-PROGRESS.md'))) `
            'The locked progress file must still be readable, or this case tests nothing'

        Invoke-WithFakeGh -Gh $un5Gh -Action {
            & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un5.Root -Item '081' -Edge 'success' -Pr 421 *> $null
        }
    } finally {
        $un5Lock.Dispose()
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A closure that cannot delete the progress file must be refused'
    Assert-True (Test-Path -LiteralPath $un5Item) 'A failed delete must still put the item back in backlog/'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $un5.Root 'backlog/done/081-automate-stage-transitions.md'))) `
        'A failed delete must leave nothing in backlog/done/'
    Assert-Equal '8-review' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $un5Item)) `
        'A failed delete must leave the Stage line unchanged'
    Assert-True (Test-SameByte -Expected $un5Item0 -Actual (Get-FileByte -Path $un5Item)) `
        'A failed delete must put the item back byte for byte'
    Assert-True (Test-SameByte -Expected $un5Progress -Actual (Get-FileByte -Path (Join-Path $un5.Root 'PLAN-PROGRESS.md'))) `
        'A locked progress file must be left exactly as it was'
    Assert-True ((Get-GhLog -Gh $un5Gh) -notmatch 'pr ready') 'A failed delete must not flip the pull request'

    # Case 6: the staging itself fails. A stale index.lock in this worktree's own git dir makes
    # 'git add' exit 128 - and the undo's own 'git reset' too. Nothing was staged, so the undo
    # looks at the index rather than guessing, and it still reports success. This case reads that
    # sentence. The half-done sentence is proved by the undo-message case further up.
    $un6 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    $un6Item = Join-Path $un6.Root 'backlog/081-automate-stage-transitions.md'
    $un6GitDir = ((& git -C $un6.Root rev-parse --absolute-git-dir) -join '').Trim()
    $un6Lock = Join-Path $un6GitDir 'index.lock'
    $un6Gh = New-FakeGh
    Set-Content -LiteralPath $un6Lock -Value '' -Encoding ascii
    try {
        $un6Output = Invoke-WithFakeGh -Gh $un6Gh -Action {
            # '*>&1' and not '*> $null', because this case also reads the refusal text.
            ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un6.Root -Item '081' -Edge 'success' -Pr 421 *>&1) -join "`n")
        }
    } finally {
        Remove-Item -LiteralPath $un6Lock -Force -ErrorAction SilentlyContinue
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A closure that cannot stage must be refused'
    Assert-True (Test-Path -LiteralPath $un6Item) 'A failed staging must still put the item back in backlog/'
    Assert-Equal '8-review' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $un6Item)) `
        'A failed staging must leave the Stage line unchanged'
    Assert-True (Test-Path -LiteralPath (Join-Path $un6.Root 'PLAN-PROGRESS.md')) `
        'A failed staging must put PLAN-PROGRESS.md back'
    Assert-True ((Get-GhLog -Gh $un6Gh) -notmatch 'pr ready') 'A failed staging must not flip the pull request'
    # The sentence the human reads. The reset above failed too, and the undo looked at the index
    # rather than guessing, found nothing staged, and so reports success. Nothing else in this
    # suite reads the refusal text, and without this the whole message contract is untested.
    Assert-True ($un6Output -match 'The closure could not be staged') `
        'The refusal must name what failed'
    Assert-True ($un6Output -match 'The records are back on disk') `
        'The refusal must tell the human the records are back'

    # Case 7: bytes a text round trip cannot carry. The progress file is UTF-16 with a byte order
    # mark, and the item has LF endings and no final newline. Reading text and writing it back
    # loses 17 of the progress file's 32 bytes, and rewriting the item's Stage line would give it
    # CRLF endings and a final newline it never had. Both must come back exactly. The progress
    # file is tracked and edited, so this case also proves the undo puts back the uncommitted
    # text, not the text in HEAD.
    $un7 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                 -AllBoxesTicked -WithProgress
    $un7Item = Join-Path $un7.Root 'backlog/081-automate-stage-transitions.md'
    $un7Progress = Join-Path $un7.Root 'PLAN-PROGRESS.md'

    [System.IO.File]::WriteAllBytes($un7Item,
        [System.Text.UTF8Encoding]::new($false).GetBytes("# 081 - Automate stage transitions`n`n## Metadata`n`n- **Difficulty**: complex`n- **Stage**: 8-review`n`n## Acceptance criteria`n`n- [x] One script performs a transition end to end."))
    [System.IO.File]::WriteAllBytes($un7Progress,
        ([byte[]] @(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("- Task 1 done`r`n")))

    $un7Item0 = Get-FileByte -Path $un7Item
    $un7Progress0 = Get-FileByte -Path $un7Progress
    Block-FixtureHook -Name 'pre-commit' -HookDir $un7.HookDir
    $un7Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $un7Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $un7.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A refused closure on odd bytes must be refused'
    Assert-True (Test-SameByte -Expected $un7Item0 -Actual (Get-FileByte -Path $un7Item)) `
        'A refused closure must keep LF endings and a missing final newline in the item'
    Assert-True (Test-SameByte -Expected $un7Progress0 -Actual (Get-FileByte -Path $un7Progress)) `
        'A refused closure must keep a UTF-16 progress file and its byte order mark'

    # --- A failure edge refuses without its evidence ---
    $fl = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -WithProgress
    # Review finding 1: the pre-flight push ran before the failure prerequisites were checked, so
    # a refused transition still pushed whatever the branch was carrying.
    $flBranch = (& git -C $fl.Root rev-parse --abbrev-ref HEAD).Trim()
    Set-Content -LiteralPath (Join-Path $fl.Root 'unpushed.txt') -Value 'work' -Encoding utf8
    & git -C $fl.Root add -A *> $null
    & git -C $fl.Root commit -m 'unpushed work' *> $null
    $flRemoteBefore = (& git -C $fl.Bare rev-parse $flBranch).Trim()

    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl.Root -Item '081' -Edge 'failure' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A failure edge without evidence must be refused'
    Assert-Equal $flRemoteBefore (& git -C $fl.Bare rev-parse $flBranch).Trim() `
        'A refused failure edge must not push the branch'
    Assert-Equal '8-review' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fl.ItemPath)) `
        'A refused failure edge must leave the Stage alone'

    # --- With evidence, the record and the Stage land in ONE commit ---
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl.Root -Item '081' -Edge 'failure' `
        -Evidence 'pwsh ./scripts/test-fast.ps1 -Mode Fast : 3 failed' `
        -RecoveryTask 'Task 8: fix the emitter escaping' *> $null
    Assert-Equal 0 $LASTEXITCODE 'A failure edge with evidence must succeed'
    Assert-Equal '4-execute' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $fl.ItemPath)) `
        'Review failure must target 4-execute'

    $progressText = Get-Content -Raw -LiteralPath (Join-Path $fl.Root 'PLAN-PROGRESS.md')
    Assert-True ($progressText -match 'fix the emitter escaping') 'The recovery task must be recorded'
    Assert-True ($progressText -match '3 failed') 'The red evidence must be recorded'

    # One commit, not two. A resume that read the Stage between two commits would find a failure
    # edge with no evidence behind it.
    $touched = @(& git -C $fl.Root show --name-only --pretty=format: HEAD | Where-Object { $_ })
    Assert-True ($touched -contains 'PLAN-PROGRESS.md') 'The record must be in the transition commit'
    Assert-True (($touched -join ' ') -match 'backlog/') 'The Stage change must be in the same commit'

    # --- No PLAN-PROGRESS.md means the work never reached Execute ---
    $fl2 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree
    & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $fl2.Root -Item '081' -Edge 'failure' `
        -Evidence 'x' -RecoveryTask 'y' *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'A failure edge with no PLAN-PROGRESS.md must be refused'

    # --- A round rewrites one line of its body and keeps the rest ---
    $rd = New-TransitionFixture -Stage '4-execute' -AsWorktree -Branch 'chore/wt-backlog-housekeeping' -NoItem
    $roundBody = "## What`n`nThree chores.`n`nStage: 4-execute`n`nSessions:`n`n- abc (agent, 4-execute)"
    $rdGh = New-FakeGh -Body $roundBody -HeadRefName 'chore/wt-backlog-housekeeping'

    Invoke-WithFakeGh -Gh $rdGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round transition must succeed'

    $written = Get-Content -Raw -LiteralPath $rdGh.BodyFile
    Assert-True ($written -match '(?m)^Stage: 8-review\r?$') 'The round body must read the new stage'
    Assert-True ($written -match 'Three chores')           'The round body must keep its description'
    Assert-True ($written -match 'Sessions:')              'The round body must keep its Sessions list'
    Assert-Equal 1 ([regex]::Matches($written, '(?m)^Stage: ')).Count 'Exactly one Stage line must survive'

    # --- Two Stage lines is a refusal, not a guess ---
    $rdGh2 = New-FakeGh -Body "Stage: 4-execute`nStage: 8-review" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $rdGh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A body with two Stage lines must be refused'

    # ================= Copilot review round, PR 421 =================

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
    # A round reads its Stage from the pull request body and writes no git state. So this case
    # and the two after it run on $rd, each with a fake gh of its own.
    $r6Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 8-review" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $r6Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round entering Ship must succeed'
    Assert-True ((Get-Content -Raw -LiteralPath $r6Gh.BodyFile) -match '(?m)^Stage: 9-ship\r?$') `
        'The round body must read 9-ship'
    Assert-True (((Get-Content -Raw -LiteralPath $r6Gh.Log) -join "`n") -match 'pr ready') `
        'A round entering Ship must flip to ready'

    # --- A round failure edge records its evidence in the body (review finding 7) ---
    # workflow.md gives the round the same rule as tracked work, with the pull request body
    # standing in for PLAN-PROGRESS.md, which a round does not have.
    $r7Gh = New-FakeGh -Body "Stage: 8-review" -HeadRefName 'chore/wt-backlog-housekeeping'
    $r7Output = Invoke-WithFakeGh -Gh $r7Gh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'failure' `
            -Pr 500 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A round failure edge with no evidence must be refused'
    Assert-True ($r7Output.Contains('REFUSED: A failure edge needs -Evidence: the failing command and its output.')) `
        "The refusal must ask for -Evidence. Output: $($r7Output)"
    Assert-True ((Get-Content -Raw -LiteralPath $r7Gh.BodyFile) -match '(?m)^Stage: 8-review\r?$') `
        'A refused round failure must leave the body alone'

    $r7bGh = New-FakeGh -Body "Stage: 8-review" -HeadRefName 'chore/wt-backlog-housekeeping'
    Invoke-WithFakeGh -Gh $r7bGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'failure' -Pr 500 `
            -Evidence 'pwsh ./scripts/test-fast.ps1 -Mode Fast : 2 failed' `
            -RecoveryTask 'Chore 3: fix the parity check' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round failure edge with evidence must succeed'
    $r7Body = Get-Content -Raw -LiteralPath $r7bGh.BodyFile
    Assert-True ($r7Body -match '(?m)^Stage: 4-execute\r?$') 'The round body must read the failure target'
    Assert-True ($r7Body -match '2 failed')                'The round body must carry the red evidence'
    Assert-True ($r7Body -match 'fix the parity check')    'The round body must carry the recovery task'

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

    # --- A tracked Ship failure reopens the records and the pull request (finding 5) ---
    # This edge starts from the state Ship leaves: the item in backlog/done/ and no
    # PLAN-PROGRESS.md. The ordinary path refuses it, because it demands a progress file that
    # Ship itself deleted, so the edge workflow.md documents could not be taken at all.
    $f5 = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                -AllBoxesTicked -WithProgress -PlanState 'frozen'
    $f5Branch = (& git -C $f5.Root rev-parse --abbrev-ref HEAD).Trim()
    # Backlog 178: the restore must give back the bytes git holds. PowerShell decodes a native
    # command's output with the console code page, so reading the file back through 'git show'
    # turned an em dash into three wrong characters and a CRLF into LF. No line-ending
    # conversion here, so the bytes on disk are the bytes git stores.
    & git -C $f5.Root config core.autocrlf false
    $f5ProgressPath = Join-Path $f5.Root 'PLAN-PROGRESS.md'
    [System.IO.File]::WriteAllText($f5ProgressPath, "- Task 1 done $([char]0x2014) caf$([char]0xE9)`r`n- Task 2`r`n",
                                   [System.Text.UTF8Encoding]::new($false))
    $f5Bytes = Get-FileByte -Path $f5ProgressPath
    & git -C $f5.Root add -- PLAN-PROGRESS.md *> $null
    & git -C $f5.Root commit -m 'docs: 081 progress' *> $null
    $f5Gh = New-FakeGh
    Invoke-WithFakeGh -Gh $f5Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f5.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'The Ship that sets up the failure case must succeed'
    # $f5 is frozen, so this Ship is also the proof that a frozen plan is not refused.
    Assert-True (Test-Path -LiteralPath (Join-Path $f5.Root 'backlog/done/081-automate-stage-transitions.md')) `
        'Ship with a frozen plan must move the item'

    $f5Gh2 = New-FakeGh
    Invoke-WithFakeGh -Gh $f5Gh2 -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f5.Root -Item '081' -Edge 'failure' -Pr 421 `
            -Evidence 'CI: 2 checks failed after the ready flip' `
            -RecoveryTask 'Task 9: fix the failing parity check' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A Ship failure edge must succeed'
    Assert-Equal '4-execute' (Get-FixtureStage -Root $f5.Root) 'A Ship failure must set 4-execute'
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
    # The failure record goes under the restored text, so compare only the front of the file.
    $f5After = Get-FileByte -Path $f5ProgressPath
    $f5Front = if ($null -ne $f5After -and $f5After.Length -ge $f5Bytes.Length) {
        [byte[]] $f5After[0..($f5Bytes.Length - 1)]
    } else { $f5After }
    Assert-True (Test-SameByte -Expected $f5Bytes -Actual $f5Front) `
        'A Ship failure must restore the progress file byte for byte'

    # The undo comes first: Review can only be re-entered with a draft pull request.
    Assert-True ((Get-GhLog -Gh $f5Gh2) -match 'ready 421 .*--undo') `
        'A Ship failure must convert the pull request back to draft'

    Assert-Equal (& git -C $f5.Root rev-parse HEAD).Trim() (& git -C $f5.Bare rev-parse $f5Branch).Trim() `
        'A Ship failure must push the reopened records'

    # --- A refusal about the progress file changes nothing (backlog 178) ---
    # The failure edge used to flip the pull request to draft and move the item out of
    # backlog/done/, and only then look for the progress file. A refusal there left both half
    # reopened. This item is in backlog/done/, but no commit moved it there, so the edge cannot
    # read what PLAN-PROGRESS.md held at Ship. It must refuse before it changes anything.
    $rf = New-TransitionFixture -Stage '9-ship' -Difficulty 'complex' -AsWorktree

    # --- A tracked item never writes Stage 10 (review finding 8) ---
    # 9-ship success happens after the merge, and workflow.md says the Stage field is never
    # written after merge. An item in backlog/done/ must keep reading 'Stage: 9-ship'. The refusal
    # comes before any write or gh call, so it runs on $rf before $rf's item moves below.
    $r8Head = (& git -C $rf.Root rev-parse HEAD).Trim()
    $r8Gh = New-FakeGh
    $r8Output = Invoke-WithFakeGh -Gh $r8Gh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rf.Root -Item '081' `
            -Edge 'success' -Pr 421 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A tracked item must refuse the 10-cleanup transition'
    Assert-True ($r8Output.Contains('REFUSED: Cleanup writes no Stage field. The item stays at 9-ship in backlog/done/, and the merged pull request is the record.')) `
        "The refusal must say Cleanup writes no Stage field. Output: $($r8Output)"
    Assert-Equal '9-ship' (Get-FixtureStage -Root $rf.Root) 'A shipped item must keep reading 9-ship'
    Assert-Equal $r8Head (& git -C $rf.Root rev-parse HEAD).Trim() `
        'A refused cleanup transition must make no commit'

    # $rf's own case: the item moves into backlog/done/ with no commit behind the move.
    $rfDone = Join-Path $rf.Root 'backlog/done/081-automate-stage-transitions.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $rfDone) -Force | Out-Null
    Move-Item -LiteralPath $rf.ItemPath -Destination $rfDone
    $rfHead = (& git -C $rf.Root rev-parse HEAD).Trim()
    $rfGh = New-FakeGh
    $rfOutput = Invoke-WithFakeGh -Gh $rfGh -Action {
        # '*>&1', because this case also reads the refusal text.
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rf.Root -Item '081' -Edge 'failure' -Pr 421 `
            -Evidence 'CI: 1 check failed' -RecoveryTask 'Task 9: fix the check' *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A Ship failure that cannot read the progress file must be refused'
    # The reason, so a refusal for some other cause cannot pass this case by accident.
    Assert-True ($rfOutput -match 'PLAN-PROGRESS\.md') 'The refusal must be about the progress file'
    Assert-True ($rfOutput -match 'Nothing was changed') 'The refusal must say that nothing was changed'
    Assert-True ((Get-GhLog -Gh $rfGh) -notmatch '--undo') 'A refused Ship failure must leave the pull request ready'
    Assert-True (Test-Path -LiteralPath $rfDone) 'A refused Ship failure must leave the item in backlog/done/'
    Assert-True (-not (Test-Path -LiteralPath $rf.ItemPath)) 'A refused Ship failure must not move the item back'
    Assert-Equal '9-ship' (Get-FixtureStage -Root $rf.Root) 'A refused Ship failure must leave the Stage at 9-ship'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $rf.Root 'PLAN-PROGRESS.md'))) `
        'A refused Ship failure must not write a progress file'
    Assert-Equal $rfHead (& git -C $rf.Root rev-parse HEAD).Trim() 'A refused Ship failure must make no commit'

    # --- A refused pre-flight push changes nothing either (backlog 178) ---
    # The pre-flight push ran after the undo, so a refused push left a draft pull request behind a
    # refusal that said nothing was changed. One commit is unpushed, so the pre-flight has work to
    # push, and the hook refuses it the way this repository's own pre-push checks can.
    $pf = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree -AllBoxesTicked -WithProgress
    $pfGh = New-FakeGh
    Invoke-WithFakeGh -Gh $pfGh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pf.Root -Item '081' -Edge 'success' -Pr 421 *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'The Ship that sets up the refused-push case must succeed'

    Set-Content -LiteralPath (Join-Path $pf.Root 'unpushed.txt') -Value 'work' -Encoding utf8
    & git -C $pf.Root add -- unpushed.txt *> $null
    & git -C $pf.Root commit -m 'test: unpushed work' *> $null
    Block-FixtureHook -Name 'pre-push' -HookDir $pf.HookDir
    $pfHead = (& git -C $pf.Root rev-parse HEAD).Trim()
    $pfDone = Join-Path $pf.Root 'backlog/done/081-automate-stage-transitions.md'

    $pfGh2 = New-FakeGh
    $pfOutput = Invoke-WithFakeGh -Gh $pfGh2 -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $pf.Root -Item '081' -Edge 'failure' -Pr 421 `
            -Evidence 'CI: 2 checks failed' -RecoveryTask 'Task 9: fix the check' *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A Ship failure whose push is refused must be refused'
    Assert-True ($pfOutput -match 'pre-flight push failed') 'The refusal must name the refused push'
    Assert-True ((Get-GhLog -Gh $pfGh2) -notmatch '--undo') 'A Ship failure whose push is refused must leave the pull request ready'
    Assert-True (Test-Path -LiteralPath $pfDone) 'A Ship failure whose push is refused must leave the item in backlog/done/'
    Assert-Equal '9-ship' (Get-FixtureStage -Root $pf.Root) 'A Ship failure whose push is refused must leave the Stage at 9-ship'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $pf.Root 'PLAN-PROGRESS.md'))) `
        'A Ship failure whose push is refused must not write the progress file back'
    Assert-Equal $pfHead (& git -C $pf.Root rev-parse HEAD).Trim() 'A Ship failure whose push is refused must make no commit'

    # --- A branch that never tracked PLAN-PROGRESS.md can fail out of Ship (backlog 178) ---
    # Ship deletes an untracked progress file and records nothing, because git has nothing to
    # record. Run twice. With no other history, the old lookup found no deleted file and refused.
    # With another item's closure on main, which every real branch inherits, it restored that
    # item's progress file into this one and exited 0.
    foreach ($foreign in @($false, $true)) {
        $label = if ($foreign) { 'with another item''s closure in history' } else { 'with no other history' }
        $nt = New-TransitionFixture -Stage '8-review' -Difficulty 'complex' -AsWorktree `
                                    -AllBoxesTicked -WithForeignProgress:$foreign
        Set-Content -LiteralPath (Join-Path $nt.Root 'PLAN-PROGRESS.md') -Value '- never committed' -Encoding utf8
        $ntBranch = (& git -C $nt.Root rev-parse --abbrev-ref HEAD).Trim()
        $ntGh = New-FakeGh
        Invoke-WithFakeGh -Gh $ntGh -Action {
            & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $nt.Root -Item '081' -Edge 'success' -Pr 421 *> $null
        }
        Assert-Equal 0 $script:LastTransitionExit "The Ship that sets up the never-tracked case must succeed, $label"
        if (-not $foreign) {
            # Review Focus 1. The delete runs first, so the pathspec names a path in neither the
            # working tree nor the index. Ship still deletes the file and commits only the move.
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $nt.Root 'PLAN-PROGRESS.md'))) `
                'Ship must delete an uncommitted PLAN-PROGRESS.md too'
            $ntTouched = @(& git -C $nt.Root show --name-only --pretty=format: HEAD | Where-Object { $_ })
            Assert-True ($ntTouched -notcontains 'PLAN-PROGRESS.md') `
                'A file git never tracked cannot be recorded as deleted'
        }

        $ntGh2 = New-FakeGh
        Invoke-WithFakeGh -Gh $ntGh2 -Action {
            & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $nt.Root -Item '081' -Edge 'failure' -Pr 421 `
                -Evidence 'CI: 3 checks failed' -RecoveryTask 'Task 7: repair the parity check' *> $null
        }
        Assert-Equal 0 $script:LastTransitionExit "A never-tracked Ship failure must succeed, $label"
        Assert-Equal '4-execute' (Get-FixtureStage -Root $nt.Root) "A never-tracked Ship failure must set 4-execute, $label"
        Assert-True (Test-Path -LiteralPath $nt.ItemPath) "A never-tracked Ship failure must move the item back, $label"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $nt.Root 'backlog/done/081-automate-stage-transitions.md'))) `
            "A never-tracked Ship failure must leave nothing in backlog/done/, $label"

        # Tolerant on purpose, as in the $f5 case: a missing file must fail these assertions, not
        # stop the suite with a Get-Content error.
        $ntProgress = (Get-Content -Raw -LiteralPath (Join-Path $nt.Root 'PLAN-PROGRESS.md') -ErrorAction SilentlyContinue) ?? ''
        Assert-True ($ntProgress -match '3 checks failed') "The progress file must hold the red evidence, $label"
        Assert-True ($ntProgress -match 'repair the parity check') "The progress file must hold the recovery task, $label"
        Assert-True ($ntProgress -notmatch 'item 999') "The progress file must not hold another item's lines, $label"

        Assert-Equal 'PLAN-PROGRESS.md' ((& git -C $nt.Root ls-files -- PLAN-PROGRESS.md) -join '').Trim() `
            "The reopening commit must track the progress file, $label"
        Assert-Equal '' ((& git -C $nt.Root status --porcelain) -join '') `
            "A never-tracked Ship failure must leave nothing uncommitted, $label"
        Assert-True ((Get-GhLog -Gh $ntGh2) -match 'ready 421 .*--undo') `
            "A never-tracked Ship failure must convert the pull request back to draft, $label"
        Assert-Equal (& git -C $nt.Root rev-parse HEAD).Trim() (& git -C $nt.Bare rev-parse $ntBranch).Trim() `
            "A never-tracked Ship failure must push the reopened records, $label"
    }

    # --- A round Ship failure undoes the ready flip too (finding 4) ---
    # This case and the two after it run on $rd as well. Each fake gh body holds the Stage.
    $f4Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'false'
    Invoke-WithFakeGh -Gh $f4Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'failure' -Pr 500 `
            -Evidence 'CI: 1 check failed' -RecoveryTask 'Chore 2: repair the suite' *> $null
    }
    Assert-Equal 0 $script:LastTransitionExit 'A round Ship failure must succeed'
    Assert-True ((Get-GhLog -Gh $f4Gh) -match 'ready 500 .*--undo') `
        'A round Ship failure must convert the pull request back to draft'
    Assert-True ((Get-Content -Raw -LiteralPath $f4Gh.BodyFile) -match '(?m)^Stage: 4-execute\r?$') `
        'A round Ship failure must record 4-execute in the body'

    # --- A round at 9-ship resumes the ready flip rather than advancing (finding 2) ---
    # The body is written to 9-ship before 'gh pr ready' runs, so a failed flip leaves the body
    # at 9-ship with a draft pull request. A rerun used to resolve 9-ship -> 10-cleanup and
    # record Cleanup on an unmerged draft.
    $f2Gh = New-FakeGh -Body "## What`n`nChores.`n`nStage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'true'
    Invoke-WithFakeGh -Gh $f2Gh -Action {
        & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' -Pr 500 *> $null
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
    $f2bGh = New-FakeGh -Body "Stage: 9-ship" -HeadRefName 'chore/wt-backlog-housekeeping' -IsDraft 'false'
    $f2bOutput = Invoke-WithFakeGh -Gh $f2bGh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $rd.Root -Edge 'success' `
            -Pr 500 *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'A round leaving Ship must be refused'
    Assert-True ($f2bOutput.Contains('REFUSED: Cleanup writes no Stage line. The round stays at 9-ship in its pull request body, and the merged pull request is the record.')) `
        "The refusal must say Cleanup writes no Stage line. Output: $($f2bOutput)"
    Assert-True ((Get-Content -Raw -LiteralPath $f2bGh.BodyFile) -match '(?m)^Stage: 9-ship\r?$') `
        'A refused round cleanup must leave the body at 9-ship'
    Assert-True (((Get-Content -Raw -LiteralPath $f2bGh.Log) -join "`n") -notmatch 'pr ready 500\s*$') `
        'A round leaving Ship must not flip again; it is already ready and merged'

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

    # The refusal above left $f3 at 1-pickup with its marker pushed, so a second Pickup on it
    # reaches 'gh pr list' and the base check again.
    $f3bGh = New-FakeGh -ExistingPr '421' -IsDraft 'true' -BaseRefName 'feature/wt-somewhere-else'
    $f3bOutput = Invoke-WithFakeGh -Gh $f3bGh -Action {
        ((& "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $f3.Root -Item '081' `
            -Edge 'success' *>&1) -join "`n")
    }
    Assert-True ($script:LastTransitionExit -ne 0) 'Pickup must refuse a pull request opened against another base'
    Assert-True ($f3bOutput.Contains("REFUSED: Pull request 421 targets 'feature/wt-somewhere-else', but this Pickup was asked for 'main'. Nothing was stamped.")) `
        "The refusal must name the other base. Output: $($f3bOutput)"
    Assert-Equal '1-pickup' (Get-SingleBacklogStage -Lines (Get-Content -LiteralPath $f3.ItemPath)) `
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
            # Ship failure with existing progress has no closure history to restore from.
            # Keep it distinct from the named post-closure recovery case above.
            $existingProgress = if ($bare -eq '9-ship' -and $edge -eq 'failure') {
                Get-Content -Raw -LiteralPath (Join-Path $case.Root 'PLAN-PROGRESS.md')
            } else { $null }
            $caseGh = New-FakeGh
            Invoke-WithFakeGh -Gh $caseGh -Action {
                & "$suiteRoot/scripts/take-stage-transition.ps1" -Worktree $case.Root -Item '081' `
                    -Edge $edge -Pr 421 -Evidence 'red' -RecoveryTask 'recover' *> $null
            }

            if ($null -ne $existingProgress) {
                Assert-Equal 0 $script:LastTransitionExit 'Ship failure must succeed without closure history'
                $recoveredProgress = Get-Content -Raw -LiteralPath (Join-Path $case.Root 'PLAN-PROGRESS.md')
                Assert-True ($recoveredProgress.StartsWith($existingProgress)) `
                    'Existing progress must survive Ship failure before the new recovery record'
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
