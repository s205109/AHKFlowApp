#Requires -Version 5.1
<#
.SYNOPSIS
End-to-end tests for the agent-scoped pre-commit backstop.

.DESCRIPTION
Each scenario builds a disposable git repository under the system temp directory, copies the
in-development pre-commit pair and policy scripts into it, points its core.hooksPath at the copied
.githooks, and makes a real commit attempt. The disposable repository - never the real AHKFlowApp
checkout - is the protected repository identity.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# The real AHKFlowApp checkout's own policy core - used only for the PreToolUse-layer pin below,
# which asserts against the guard's decision object directly rather than a real commit attempt.
# Every actual commit attempt in this suite still runs against a disposable fixture repository,
# never this checkout.
. (Join-Path $suiteRoot 'scripts\agents\agent-worktree-guard.common.ps1')

# $suiteRoot is this file's own location, which is the *main checkout* only when the suite is run
# from there - a run from inside a managed linked worktree (as agent sessions do) makes $suiteRoot
# a worktree instead, and Get-ManagedWorktreeState would then read it as ManagedWorktree, not
# MainCheckout. Same derivation AgentWorktreeGuard.Tests.ps1 uses for $script:RealMainCheckout:
# walk up from the git-common-dir, which always resolves to the true main checkout regardless of
# which worktree the suite happens to run from.
$script:RealMainCheckout = Split-Path -Parent (
    (& git -C $suiteRoot rev-parse --path-format=absolute --git-common-dir).Trim())
$script:RealMainCheckout = (Resolve-Path -LiteralPath $script:RealMainCheckout).Path

$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $GitArguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @GitArguments 2>&1 | Out-Null
        $script:LastGitExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# Copies the in-development hook pair and shared policy into a repository's expected relative
# layout, then points its core.hooksPath at the absolute copied .githooks directory.
function Install-GuardHooks {
    param([string] $RepoRoot)

    New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.githooks') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $RepoRoot 'scripts\agents') -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $suiteRoot '.githooks\pre-commit') -Destination (Join-Path $RepoRoot '.githooks\pre-commit') -Force
    Copy-Item -LiteralPath (Join-Path $suiteRoot '.githooks\pre-commit.ps1') -Destination (Join-Path $RepoRoot '.githooks\pre-commit.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $suiteRoot 'scripts\agents\agent-worktree-guard.common.ps1') -Destination (Join-Path $RepoRoot 'scripts\agents\agent-worktree-guard.common.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $suiteRoot 'scripts\worktree-git.common.ps1') -Destination (Join-Path $RepoRoot 'scripts\worktree-git.common.ps1') -Force

    Invoke-Git -C $RepoRoot config core.hooksPath (Join-Path $RepoRoot '.githooks')
}

function Write-ValidManifest {
    param([string] $WorktreeRoot, [int] $ApiPort = 5602, [int] $UiPort = 5603, [string] $Suffix = 'valid')

    New-Item -ItemType Directory -Path (Join-Path $WorktreeRoot 'scripts') -Force | Out-Null
    $lines = @(
        "AHKFLOW_API_PORT=$ApiPort",
        "AHKFLOW_UI_PORT=$UiPort",
        "AHKFLOW_API_URL=http://localhost:$ApiPort",
        "AHKFLOW_UI_URL=http://localhost:$UiPort",
        "AHKFLOW_DB_NAME=AHKFlowApp_$Suffix",
        'AHKFLOW_SQL_PORT=14330',
        "AHKFLOW_COMPOSE_PROJECT=ahkflow-$Suffix",
        "AHKFLOW_ROOT=$WorktreeRoot"
    )
    Set-Content -LiteralPath (Join-Path $WorktreeRoot 'scripts\.env.worktree') -Value ($lines -join "`n") -Encoding utf8
}

function New-CommitFixture {
    param([string] $PrimaryBranch)

    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-precommit-' + [guid]::NewGuid().ToString('N'))
    $main = Join-Path $testRoot 'repo'

    New-Item -ItemType Directory -Path $main -Force | Out-Null
    Invoke-Git init --initial-branch=main $main
    Invoke-Git -C $main config user.name 'Pre-Commit Test'
    Invoke-Git -C $main config user.email 'precommit@example.invalid'
    Set-Content -LiteralPath (Join-Path $main 'seed.txt') -Value 'seed' -Encoding utf8
    Invoke-Git -C $main add seed.txt
    Invoke-Git -C $main commit -m 'seed'

    # The seed commit lands before core.hooksPath is set, so it never meets either rule.
    # A fixture that must not stand on 'main' moves off it here, before the hooks go in.
    if (-not [string]::IsNullOrWhiteSpace($PrimaryBranch)) {
        Invoke-Git -C $main checkout -b $PrimaryBranch
    }

    Install-GuardHooks -RepoRoot $main

    return [pscustomobject]@{
        TestRoot = (Resolve-Path -LiteralPath $testRoot).Path
        Main     = (Resolve-Path -LiteralPath $main).Path
    }
}

function Add-Worktree {
    param(
        [object] $Fixture,
        [string] $RelativePath,
        [string] $Branch,
        # Checks out a branch that already exists instead of creating one. Needed for 'main',
        # which cannot be created twice.
        [switch] $UseExistingBranch
    )

    $path = Join-Path $Fixture.Main $RelativePath
    if ($UseExistingBranch) {
        Invoke-Git -C $Fixture.Main worktree add $path $Branch
    }
    else {
        Invoke-Git -C $Fixture.Main worktree add -b $Branch $path
    }
    return (Resolve-Path -LiteralPath $path).Path
}

# Adds one commit with hooks skipped. Setup history must never trip the rule under test.
function Add-SetupCommit {
    param([string] $RepoRoot, [string] $Message)

    $file = Join-Path $RepoRoot ('setup-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    Set-Content -LiteralPath $file -Value $Message -Encoding utf8
    Invoke-Git -C $RepoRoot add ($file)
    Invoke-Git -C $RepoRoot commit --no-verify -m $Message
}

# Runs one git command in a child PowerShell whose agent-marker and override variables are
# cleared, so each scenario decides its own environment. Reports whether HEAD moved.
function Invoke-IsolatedGitCommand {
    param(
        [string] $RepoRoot,
        [string] $GitCommand,
        [hashtable] $EnvOverrides = @{}
    )

    $before = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $arguments = @('-NoProfile', '-NonInteractive', '-Command')
    $arguments += "Set-Location -LiteralPath '$RepoRoot'; $GitCommand; exit `$LASTEXITCODE"

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $previous = @{}
    foreach ($key in @('AHKFLOW_AGENT_SESSION', 'CLAUDECODE', 'CLAUDE_CODE_ENTRYPOINT', 'CODEX_THREAD_ID', 'AHKFLOW_ALLOW_MAIN')) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, '', 'Process')
    }
    foreach ($key in $EnvOverrides.Keys) {
        [Environment]::SetEnvironmentVariable($key, [string] $EnvOverrides[$key], 'Process')
    }

    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $arguments `
            -WorkingDirectory $RepoRoot -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile -NoNewWindow -PassThru -Wait
        $stderr = Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    }
    finally {
        foreach ($key in $previous.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
        }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }

    $after = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()

    return [pscustomobject]@{
        HeadMoved = ($after -ne $before)
        ExitCode  = $proc.ExitCode
        Stderr    = $stderr
    }
}

function Remove-CommitFixture {
    param([object] $Fixture)
    if ($null -eq $Fixture) { return }

    $tempRoot = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path.TrimEnd('\', '/')
    $target = $Fixture.TestRoot.TrimEnd('\', '/')
    if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a fixture outside the temp directory: $target"
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop; return }
        catch { if ($attempt -eq 3) { return }; Start-Sleep -Milliseconds 200 }
    }
}

# Stages a unique change in $RepoRoot and attempts a commit, returning whether the commit landed.
function Invoke-CommitAttempt {
    param(
        [string] $RepoRoot,
        [hashtable] $EnvOverrides = @{},
        [switch] $NoVerify
    )

    $file = Join-Path $RepoRoot ('change-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    Set-Content -LiteralPath $file -Value 'change' -Encoding utf8
    Invoke-Git -C $RepoRoot add ($file)

    $commitCmd = if ($NoVerify) { 'git commit --no-verify -m test' } else { 'git commit -m test' }
    $result = Invoke-IsolatedGitCommand -RepoRoot $RepoRoot -GitCommand $commitCmd -EnvOverrides $EnvOverrides

    return [pscustomobject]@{
        Committed = $result.HeadMoved
        ExitCode  = $result.ExitCode
        Stderr    = $result.Stderr
    }
}

# ── Scenarios ───────────────────────────────────────────────────────────────────────────────

$markers = @(
    @{ Name = 'CLAUDECODE=1'; Env = @{ CLAUDECODE = '1' } },
    @{ Name = 'CLAUDE_CODE_ENTRYPOINT set'; Env = @{ CLAUDE_CODE_ENTRYPOINT = 'cli' } },
    @{ Name = 'CODEX_THREAD_ID set'; Env = @{ CODEX_THREAD_ID = 'abc123' } },
    @{ Name = 'AHKFLOW_AGENT_SESSION=1'; Env = @{ AHKFLOW_AGENT_SESSION = '1' } }
)

$fixture = $null
$humanFixture = $null
$worktreeMainFixture = $null
try {
    $fixture = New-CommitFixture
    # Stands on a feature branch, so the branch rule never fires for its own commits.
    $humanFixture = New-CommitFixture -PrimaryBranch 'chore/human-work'
    # Stands off 'main' so a linked worktree can check 'main' out. Git refuses the same branch
    # in two working trees at once.
    $worktreeMainFixture = New-CommitFixture -PrimaryBranch 'chore/holds-no-main'

    # Pins that the PreToolUse layer denies commit from main before the pre-commit backstop this
    # file otherwise tests is ever reached. Uses the real AHKFlowApp checkout
    # ($script:RealMainCheckout) as both -Cwd and -ProtectedRepoRoot, the same pattern
    # AgentWorktreeGuard.Tests.ps1 uses for its Claude/Codex/Copilot adapter-output tests.
    Invoke-TestCase 'PreToolUse denies commit from main before the backstop is ever reached' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $script:RealMainCheckout -ProtectedRepoRoot $script:RealMainCheckout
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Human commit on main is blocked, and the message names the escape and the route' {
        $result = Invoke-CommitAttempt -RepoRoot $fixture.Main
        Assert-True (-not $result.Committed) "commit should have been blocked; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'would land directly on the main branch') "expected the branch message; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'AHKFLOW_ALLOW_MAIN') "expected the override to be named; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'new-worktree\.ps1') "expected the worktree route; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'housekeeping worktree') "expected the housekeeping route; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Human commit on main with AHKFLOW_ALLOW_MAIN=1 succeeds with a warning' {
        $result = Invoke-CommitAttempt -RepoRoot $fixture.Main -EnvOverrides @{ AHKFLOW_ALLOW_MAIN = '1' }
        Assert-True $result.Committed "commit should have landed; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'AHKFLOW_ALLOW_MAIN=1 overrode the main-branch rule') "expected the override warning; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Human commit on a feature branch succeeds' {
        $result = Invoke-CommitAttempt -RepoRoot $humanFixture.Main
        Assert-True $result.Committed "commit should have landed; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Human commit with a detached HEAD succeeds' {
        Invoke-Git -C $humanFixture.Main checkout --detach HEAD
        $result = Invoke-CommitAttempt -RepoRoot $humanFixture.Main
        Assert-True $result.Committed "commit should have landed; stderr: $($result.Stderr)"
    }

    foreach ($marker in $markers) {
        Invoke-TestCase "Agent commit in main with $($marker.Name) is blocked" {
            $result = Invoke-CommitAttempt -RepoRoot $fixture.Main -EnvOverrides $marker.Env
            Assert-True (-not $result.Committed) "commit should have been blocked; stderr: $($result.Stderr)"
            Assert-True ($result.Stderr -match 'BLOCKED: agent Git mutations') "expected the shared denial message; stderr: $($result.Stderr)"
        }
    }

    Invoke-TestCase 'Agent commit in a valid managed worktree succeeds' {
        $managed = Add-Worktree -Fixture $fixture -RelativePath '.claude\worktrees\valid' -Branch 'feature/wt-valid'
        Write-ValidManifest -WorktreeRoot $managed
        $result = Invoke-CommitAttempt -RepoRoot $managed -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1' }
        Assert-True $result.Committed "commit should have landed; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Agent commit in an unmanaged linked worktree is blocked' {
        $unmanaged = Add-Worktree -Fixture $fixture -RelativePath 'sibling-unmanaged' -Branch 'feature/wt-unmanaged'
        $result = Invoke-CommitAttempt -RepoRoot $unmanaged -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1' }
        Assert-True (-not $result.Committed) "commit should have been blocked; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Agent commit in an approved location with an invalid manifest is blocked' {
        $bad = Add-Worktree -Fixture $fixture -RelativePath '.claude\worktrees\badmanifest' -Branch 'feature/wt-badmanifest'
        Write-ValidManifest -WorktreeRoot $bad -Suffix 'bad'
        # Corrupt the manifest: API URL port no longer matches the API port key.
        $manifestPath = Join-Path $bad 'scripts\.env.worktree'
        $content = Get-Content -LiteralPath $manifestPath -Raw
        Set-Content -LiteralPath $manifestPath -Value ($content -replace 'AHKFLOW_API_URL=.*', 'AHKFLOW_API_URL=http://localhost:9999') -Encoding utf8
        $result = Invoke-CommitAttempt -RepoRoot $bad -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1' }
        Assert-True (-not $result.Committed) "commit should have been blocked; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Agent commit in a managed worktree on main is blocked by the branch rule' {
        $onMain = Add-Worktree -Fixture $worktreeMainFixture -RelativePath '.claude\worktrees\onmain' `
            -Branch 'main' -UseExistingBranch
        Write-ValidManifest -WorktreeRoot $onMain -Suffix 'onmain'
        $result = Invoke-CommitAttempt -RepoRoot $onMain -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1' }
        Assert-True (-not $result.Committed) "commit should have been blocked; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'would land directly on the main branch') "expected the branch message, not the agent message; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'AHKFLOW_ALLOW_MAIN=1 lets an agent commit in main with a visible warning' {
        $result = Invoke-CommitAttempt -RepoRoot $fixture.Main -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1'; AHKFLOW_ALLOW_MAIN = '1' }
        Assert-True $result.Committed "commit should have landed; stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'AHKFLOW_ALLOW_MAIN') "expected a visible override warning; stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'git commit --no-verify bypasses the backstop (documented gap)' {
        $result = Invoke-CommitAttempt -RepoRoot $fixture.Main -EnvOverrides @{ AHKFLOW_AGENT_SESSION = '1' } -NoVerify
        Assert-True $result.Committed "the --no-verify bypass must succeed; stderr: $($result.Stderr)"
    }
}
finally {
    Remove-CommitFixture -Fixture $fixture
    Remove-CommitFixture -Fixture $humanFixture
    Remove-CommitFixture -Fixture $worktreeMainFixture
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All agent pre-commit hook tests passed.' -ForegroundColor Green
exit 0
