#Requires -Version 5.1

# Backlog 099. The removal watcher prunes the worktree before it deletes the branch, and stops in
# between whenever `git branch -d` refuses. That leaves a branch with no worktree, and the sweep
# enumerated worktrees only, so nothing found it.
#
# Every fixture here builds that end state directly: commit on a branch, merge it on the remote,
# remove the worktree, keep the branch.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
$cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param([string] $Haystack, [string] $Needle, [string] $Message)
    if (($null -eq $Haystack) -or ($Haystack -notlike "*$Needle*")) {
        throw "$Message (expected to find '$Needle' in: $Haystack)"
    }
}

function Assert-NotContains {
    param([string] $Haystack, [string] $Needle, [string] $Message)
    if ($Haystack -and ($Haystack -like "*$Needle*")) {
        throw "$Message (did not expect '$Needle' in: $Haystack)"
    }
}

function Invoke-FixtureGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# A bare 'origin' and a clone-shaped 'repo' whose main tracks it. Nothing else: each case adds the
# branches it needs.
function New-Fixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtleft-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    New-Item -ItemType Directory -Path $origin -Force | Out-Null

    & git init --bare --quiet $origin
    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    & git -C $repo config user.email 'test@example.com'
    & git -C $repo config user.name 'Leftover Branch Test'

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'seed') | Out-Null
    Invoke-FixtureGit $repo @('remote', 'add', 'origin', $origin) | Out-Null
    # -u writes branch.main.remote and branch.main.merge, which is what the base resolver reads.
    Invoke-FixtureGit $repo @('push', '--quiet', '-u', 'origin', 'main') | Out-Null

    return [pscustomobject]@{
        Root   = $root
        Repo   = (Resolve-Path -LiteralPath $repo).Path
        Origin = $origin
    }
}

# Adds one worktree and its branch. -Committed gives the branch a commit of its own; without it the
# branch keeps the unstarted shape that `git branch --merged` lists forever.
function Add-FixtureBranch {
    param(
        [Parameter(Mandatory)][object] $Fixture,
        [Parameter(Mandatory)][string] $Branch,
        [Parameter(Mandatory)][string] $Folder,
        [switch] $Committed
    )

    $worktree = Join-Path $Fixture.Root $Folder
    Invoke-FixtureGit $Fixture.Repo @('worktree', 'add', '--quiet', '-b', $Branch, $worktree, 'main') | Out-Null

    if ($Committed) {
        # One file per branch, named from the (slash-free) folder name. A shared filename across
        # branches makes the second branch's merge into main conflict with the first's.
        Set-Content -LiteralPath (Join-Path $worktree "$Folder.txt") -Value "work on $Branch" -Encoding utf8
        Invoke-FixtureGit $worktree @('add', '-A') | Out-Null
        Invoke-FixtureGit $worktree @('commit', '--quiet', '-m', "work on $Branch") | Out-Null
    }

    return $worktree
}

# Merges every named branch into main, pushes ONCE, then rewinds local main and the cached tracking
# ref. That is the state right after `gh pr merge`: the merges exist on the remote only.
#
# One push for all of them on purpose. Pushing after each merge and rewinding in between makes the
# next push non-fast-forward, and the fixture dies in setup.
function Complete-RemoteMerge {
    param(
        [Parameter(Mandatory)][object] $Fixture,
        [Parameter(Mandatory)][string[]] $Branches
    )

    $preMerge = ([string] (Invoke-FixtureGit $Fixture.Repo @('rev-parse', 'main'))).Trim()
    foreach ($branch in $Branches) {
        # --no-ff is the shape a GitHub "Merge pull request" leaves behind, and the merged check
        # reads the non-first parent of exactly that commit.
        Invoke-FixtureGit $Fixture.Repo @('merge', '--no-ff', '-m', "Merge $branch", $branch) | Out-Null
    }
    Invoke-FixtureGit $Fixture.Repo @('push', '--quiet', 'origin', 'main') | Out-Null
    Invoke-FixtureGit $Fixture.Repo @('reset', '--hard', '--quiet', $preMerge) | Out-Null
    # The push moved the tracking ref too. Rewind it, or a run that never fetches would still pass.
    Invoke-FixtureGit $Fixture.Repo @('update-ref', 'refs/remotes/origin/main', $preMerge) | Out-Null
}

# What the watcher leaves when `git branch -d` refuses: worktree deregistered, branch untouched.
function Remove-FixtureWorktree {
    param(
        [Parameter(Mandatory)][object] $Fixture,
        [Parameter(Mandatory)][string] $Worktree
    )

    Invoke-FixtureGit $Fixture.Repo @('worktree', 'remove', '--force', $Worktree) | Out-Null
    Invoke-FixtureGit $Fixture.Repo @('worktree', 'prune') | Out-Null
}

function Remove-Fixture {
    param([string] $Root)
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 5) { return }
            Start-Sleep -Milliseconds 300
        }
    }
}

# Runs the real sweep as a child process. Stdin comes from an empty file, so the sweep is never
# interactive and stays in report-only mode while ahkflow.worktreeCleanup is unset.
function Invoke-Sweep {
    param([string] $RepoDir, [string[]] $ExtraArgs = @())

    $parent = Split-Path -Parent $RepoDir
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stdinFile = Join-Path $parent "sin-$suffix.txt"
    $stdoutFile = Join-Path $parent "sout-$suffix.txt"
    $stderrFile = Join-Path $parent "serr-$suffix.txt"
    Set-Content -LiteralPath $stdinFile -Value '' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $RepoDir) + $ExtraArgs

    $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
        -WorkingDirectory $suiteRoot `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    $result = [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stdout   = (Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
        Stderr   = (Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
    }
    Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    return $result
}

# --- One run reports both leftovers -------------------------------------------
#
# 'fix/wt-left' is the branch whose worktree the watcher already pruned. 'fix/wt-here' still has
# its worktree, so the sweep's existing line must report it and the new line must not.

$fixture = New-Fixture
try {
    $left = Add-FixtureBranch -Fixture $fixture -Branch 'fix/wt-left' -Folder 'wt-left' -Committed
    $null = Add-FixtureBranch -Fixture $fixture -Branch 'fix/wt-here' -Folder 'wt-here' -Committed
    Complete-RemoteMerge -Fixture $fixture -Branches @('fix/wt-left', 'fix/wt-here')
    Remove-FixtureWorktree -Fixture $fixture -Worktree $left

    $run = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-Contains $run.Stderr 'cleanup: leftover branch, worktree already gone: fix/wt-left' `
        'The branch whose worktree is gone must be reported.'
    Assert-Contains $run.Stderr 'cleanup: eligible merged worktree:' `
        'The worktree that is still there must still be reported.'
    Assert-Contains $run.Stderr 'wt-here' `
        'The eligible line must name the worktree that is still there.'
    Assert-NotContains $run.Stderr 'cleanup: leftover branch, worktree already gone: fix/wt-here' `
        'A branch that still has a worktree is the other leftover, not this one.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- The base is the fetched remote one (backlog 094) -------------------------
#
# The merge exists on the remote only. Deciding against local 'main' finds nothing, so a report
# that appears only when the run resolves its own base is the proof.

$fixture = New-Fixture
try {
    $left = Add-FixtureBranch -Fixture $fixture -Branch 'fix/wt-left' -Folder 'wt-left' -Committed
    Complete-RemoteMerge -Fixture $fixture -Branches @('fix/wt-left')
    Remove-FixtureWorktree -Fixture $fixture -Worktree $left

    $withLocalBase = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-MainRef', 'main')
    Assert-NotContains $withLocalBase.Stderr 'cleanup: leftover branch' `
        'Local main does not hold the merge, so nothing is a leftover against it.'

    $withRemoteBase = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-Contains $withRemoteBase.Stderr 'cleanup: leftover branch, worktree already gone: fix/wt-left' `
        'Against the fetched base the merge is visible and the branch is a leftover.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- A branch nobody committed on is not a leftover ---------------------------
#
# It points at the base's tip, so `git branch --merged` lists it forever. Reporting it would teach
# the reader to ignore the report.

$fixture = New-Fixture
try {
    $unstarted = Add-FixtureBranch -Fixture $fixture -Branch 'fix/wt-unstarted' -Folder 'wt-unstarted'
    Remove-FixtureWorktree -Fixture $fixture -Worktree $unstarted

    $run = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-NotContains $run.Stderr 'cleanup: leftover branch' `
        'An unstarted branch has no work that could be left behind.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- A clean repository reports nothing ---------------------------------------

$fixture = New-Fixture
try {
    $run = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-NotContains $run.Stderr 'cleanup: leftover branch' `
        'A repository with no leftover must report none.'
    Assert-Contains $run.Stderr 'cleanup: no merged worktrees eligible for cleanup.' `
        'The run must still say it ran.'
} finally {
    Remove-Fixture $fixture.Root
}

Write-Host 'Worktree leftover-branch tests passed.'
