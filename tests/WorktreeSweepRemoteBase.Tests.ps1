#Requires -Version 5.1

# Backlog 094. The merged-worktree sweep used to decide against the LOCAL main branch, and nothing
# fetched first. `gh pr merge` merges on GitHub and never advances a local ref, so a worktree whose
# pull request merged an hour ago still looked unmerged and survived until a human pulled.
#
# Every fixture here reproduces that exact state: the merge exists only in the remote, local `main`
# and the cached `refs/remotes/origin/main` both predate it, so only a fresh fetch can see it.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
$cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
$removeScript = Join-Path $scriptsDir 'remove-worktree-local-dev.ps1'

. (Join-Path $scriptsDir 'worktree-git.common.ps1')

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

# A bare 'origin', a clone-shaped 'repo' whose main tracks it, and one worktree branch with a
# commit on it. -Merged performs the merge, pushes it, and then rewinds BOTH local refs, which is
# what a session sees right after `gh pr merge`: the work is on the remote and invisible locally.
function New-RemoteFixture {
    param([switch] $Merged)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtremote-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    New-Item -ItemType Directory -Path $origin -Force | Out-Null

    & git init --bare --quiet $origin
    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    & git -C $repo config user.email 'test@example.com'
    & git -C $repo config user.name 'Sweep Remote Base Test'

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'seed') | Out-Null
    Invoke-FixtureGit $repo @('remote', 'add', 'origin', $origin) | Out-Null
    # -u writes branch.main.remote and branch.main.merge, which is what the resolver reads.
    Invoke-FixtureGit $repo @('push', '--quiet', '-u', 'origin', 'main') | Out-Null

    $branch = 'fix/wt-remote-base'
    $worktree = Join-Path $root 'wt-remote-base'
    Invoke-FixtureGit $repo @('worktree', 'add', '--quiet', '-b', $branch, $worktree, 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'work.txt') -Value 'work' -Encoding utf8
    Invoke-FixtureGit $worktree @('add', '-A') | Out-Null
    Invoke-FixtureGit $worktree @('commit', '--quiet', '-m', 'work on the branch') | Out-Null

    if ($Merged) {
        $preMerge = ([string] (Invoke-FixtureGit $repo @('rev-parse', 'main'))).Trim()
        # --no-ff is the shape a GitHub "Merge pull request" leaves behind.
        Invoke-FixtureGit $repo @('merge', '--no-ff', '-m', "Merge $branch", $branch) | Out-Null
        Invoke-FixtureGit $repo @('push', '--quiet', 'origin', 'main') | Out-Null
        Invoke-FixtureGit $repo @('reset', '--hard', '--quiet', $preMerge) | Out-Null
        # The push updated the tracking ref too. Rewind it, or the fixture proves nothing about
        # fetching: only the remote must hold the merge.
        Invoke-FixtureGit $repo @('update-ref', 'refs/remotes/origin/main', $preMerge) | Out-Null
    }

    return [pscustomobject]@{
        Root     = $root
        Repo     = (Resolve-Path -LiteralPath $repo).Path
        Origin   = $origin
        Worktree = (Resolve-Path -LiteralPath $worktree).Path
        Branch   = $branch
    }
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

# Runs the real sweep as a child process. Stdin is redirected from an empty file, so the sweep is
# never interactive and stays in report-only mode while ahkflow.worktreeCleanup is unset.
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

# Fires remove-worktree-local-dev.ps1 the way Claude's WorktreeRemove hook does: the worktree path
# arrives as JSON on stdin. Extra arguments go on the command line, which is how the sweep hands
# over the base it already resolved.
function Invoke-RemoveHook {
    param([string] $WorktreePath, [string[]] $ExtraArgs = @())

    $stdinFile = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $stdinFile -Value (@{ worktree_path = $WorktreePath } | ConvertTo-Json -Compress) -Encoding utf8
        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $removeScript, '-Mode', 'Hook') + $ExtraArgs
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
            -WorkingDirectory $suiteRoot `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
        return [pscustomobject]@{ ExitCode = $proc.ExitCode }
    } finally {
        Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-RemovalLog {
    param([string] $RepoDir)
    $logPath = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    if (-not (Test-Path -LiteralPath $logPath)) { return '' }
    return (Get-Content -Raw -LiteralPath $logPath)
}

function Wait-ForWorktreeGone {
    param([string] $RepoDir, [string] $WorktreePath, [int] $TimeoutSeconds = 40)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $listed = @(& git -C $RepoDir worktree list --porcelain 2>$null) |
            Where-Object { $_ -like 'worktree *' } |
            ForEach-Object { ([System.IO.Path]::GetFullPath($_.Substring('worktree '.Length))).TrimEnd('\', '/').ToLowerInvariant() }
        $key = ([System.IO.Path]::GetFullPath($WorktreePath)).TrimEnd('\', '/').ToLowerInvariant()
        if (($listed -notcontains $key) -and -not (Test-Path -LiteralPath $WorktreePath)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

# --- Resolve-MergedBaseRef: the three answers it can give ----------------------

$fixture = New-RemoteFixture -Merged
try {
    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'origin/main') "Expected the remote-tracking ref as the base, got '$($base.Ref)'."
    Assert-True ($base.Remote -eq 'origin') "Expected remote 'origin', got '$($base.Remote)'."
    Assert-True $base.Fetched 'A reachable remote must be fetched.'
    Assert-True ($base.Reason -eq 'remote-fetched') "Expected reason 'remote-fetched', got '$($base.Reason)'."

    # The fetch is the point: after it, the merge the remote holds is visible locally.
    & git -C $fixture.Repo merge-base --is-ancestor $fixture.Branch 'origin/main'
    Assert-True ($LASTEXITCODE -eq 0) 'After the fetch, origin/main must contain the merge.'
    & git -C $fixture.Repo merge-base --is-ancestor $fixture.Branch 'main'
    Assert-True ($LASTEXITCODE -ne 0) 'Local main must still be behind, or the fixture proves nothing.'
} finally {
    Remove-Fixture $fixture.Root
}

# Unreachable remote: the cached tracking ref still answers, and the reason says it may be behind.
$fixture = New-RemoteFixture -Merged
try {
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'origin/main') "Offline, the cached tracking ref is still the base, got '$($base.Ref)'."
    Assert-True (-not $base.Fetched) 'An unreachable remote cannot report a successful fetch.'
    Assert-True ($base.Reason -eq 'remote-stale') "Expected reason 'remote-stale', got '$($base.Reason)'."
} finally {
    Remove-Fixture $fixture.Root
}

# No upstream at all: the local branch is the only base there is.
$fixture = New-RemoteFixture
try {
    Invoke-FixtureGit $fixture.Repo @('branch', '--unset-upstream', 'main') | Out-Null

    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'main') "Without an upstream the base is local main, got '$($base.Ref)'."
    Assert-True (-not $base.Fetched) 'Nothing can be fetched without an upstream.'
    Assert-True ($base.Reason -eq 'no-upstream') "Expected reason 'no-upstream', got '$($base.Reason)'."
} finally {
    Remove-Fixture $fixture.Root
}

# --- The message the caller writes --------------------------------------------

$fetched = [pscustomobject]@{ Ref = 'origin/main'; Remote = 'origin'; Fetched = $true; Reason = 'remote-fetched' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $fetched) "base 'origin/main' (fetched from origin)." 'The fetched message must name the base and the remote.'

$stale = [pscustomobject]@{ Ref = 'origin/main'; Remote = 'origin'; Fetched = $false; Reason = 'remote-stale' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $stale) 'may be behind the remote' 'A failed fetch must say the base may be behind the remote.'

$local = [pscustomobject]@{ Ref = 'main'; Remote = $null; Fetched = $false; Reason = 'no-upstream' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $local) "base 'main' (local only" 'The local-only message must name the local base.'

# --- The sweep: a stale local main no longer hides a merge ---------------------

$fixture = New-RemoteFixture -Merged
try {
    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "The sweep must exit 0, got $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr "base 'origin/main' (fetched from origin)." 'The sweep must report the base it decided against.'
    Assert-Contains $sweep.Stderr "eligible merged worktree: $($fixture.Worktree)" 'A worktree merged on the remote must be eligible while local main is stale.'

    # The same run, with the base named explicitly, is the caller's choice and must not fetch.
    $explicit = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-MainRef', 'main')
    Assert-NotContains $explicit.Stderr 'fetched from origin' 'An explicit -MainRef must not trigger a fetch.'
} finally {
    Remove-Fixture $fixture.Root
}

# The other direction: fetching must not make an unmerged worktree eligible.
$fixture = New-RemoteFixture
try {
    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "The sweep must exit 0, got $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr 'no merged worktrees eligible for cleanup.' 'An unmerged worktree must be preserved.'
} finally {
    Remove-Fixture $fixture.Root
}

# Offline: worktree creation runs the sweep first, so a failed fetch must never fail the run.
$fixture = New-RemoteFixture -Merged
try {
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "A failed fetch must not fail the sweep, got exit $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr 'may be behind the remote' 'The sweep must say the base may be stale when the fetch fails.'
    Assert-Contains $sweep.Stderr 'no merged worktrees eligible for cleanup.' 'Offline, the stale base sees no merge, so nothing is removed.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- The removal gate decides against the same base ----------------------------
#
# Eligibility is not the last word: remove-worktree-local-dev.ps1 re-decides merged-ness before it
# spawns the watcher. If that gate keeps reading local main, the sweep reports a worktree and then
# preserves it.

$fixture = New-RemoteFixture -Merged
try {
    $withStaleBase = Invoke-RemoveHook -WorktreePath $fixture.Worktree -ExtraArgs @('-MainRef', 'main')
    Assert-True ($withStaleBase.ExitCode -eq 0) "The hook must exit 0, got $($withStaleBase.ExitCode)."
    Assert-Contains (Get-RemovalLog $fixture.Repo) "is not merged into main" 'Against the stale local base the gate must preserve the worktree.'
    Assert-True (Test-Path -LiteralPath $fixture.Worktree) 'A preserved worktree must still exist.'

    $resolved = Invoke-RemoveHook -WorktreePath $fixture.Worktree
    Assert-True ($resolved.ExitCode -eq 0) "The hook must exit 0, got $($resolved.ExitCode)."
    Assert-Contains (Get-RemovalLog $fixture.Repo) "base 'origin/main' (fetched from origin)." 'The hook must resolve and report its own base when none is passed.'
    Assert-True (Wait-ForWorktreeGone -RepoDir $fixture.Repo -WorktreePath $fixture.Worktree) `
        'With the fetched base the gate must pass and the watcher must remove the worktree.'
} finally {
    Remove-Fixture $fixture.Root
}

Write-Host 'Worktree sweep remote-base tests passed.'
