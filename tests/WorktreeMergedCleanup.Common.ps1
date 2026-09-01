#Requires -Version 7.0
# Shared harness for the three merged-cleanup suites. Backlog 126.
#
# One suite of 2149 lines took 125.6 seconds and set the floor for every parallel run, so it became
# three suites over this one harness:
#
#   WorktreeMergedCleanup.Tests.ps1             pure functions and merge proof
#   WorktreeMergedCleanupEligibility.Tests.ps1  eligibility and the WorktreeCreate hook
#   WorktreeMergedCleanupSweep.Tests.ps1        the GitHub query, the sweep, and the plan guard
#
# Dot-source it from a suite:  . (Join-Path $PSScriptRoot 'WorktreeMergedCleanup.Common.ps1')
#
# The name ends in .Common.ps1, not .Tests.ps1, so the runner's glob never discovers it as a suite.
#
# 7.0, not 5.1, for the reason the suites give: scripts/cleanup-merged-worktrees.ps1 makes bare
# native git calls, and under Windows PowerShell a native command's stderr becomes an error record
# that a 'Stop' preference turns terminating.
#
# It does not call Set-StrictMode. That call leaks from a dot-sourced file into the caller's scope,
# and each suite sets it itself.

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'

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

function ConvertTo-Key {
    param([string] $Value)
    return ([System.IO.Path]::GetFullPath($Value)).TrimEnd('\', '/').ToLowerInvariant()
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# Runs one git command with GIT_REFLOG_ACTION forced, then removes the variable again.
# It must be REMOVED, not set back to '': an empty GIT_REFLOG_ACTION makes git write ': <msg>'
# instead of 'commit: <msg>', which silently breaks every later test in this file.
function Invoke-TestGitWithReflogAction {
    param([string] $RepoDir, [string] $Action, [string[]] $GitArgs)

    $env:GIT_REFLOG_ACTION = $Action
    try {
        return (Invoke-TestGit $RepoDir $GitArgs)
    } finally {
        Remove-Item -LiteralPath 'Env:\GIT_REFLOG_ACTION' -ErrorAction SilentlyContinue
    }
}

# Fresh main-checkout repo under a throwaway root. Returns the repo path; its parent
# is the root to delete (worktrees are created as siblings of the repo).
function New-TempGitRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtclean-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    # Force the initial branch to 'main' independent of the host's init.defaultBranch.
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Cleanup Test' *> $null

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

# Adds a linked worktree on a new branch off main. By default the branch gets one commit and is
# then merged into main with a merge commit -- the shape a merged pull request leaves behind.
# -Unmerged keeps the commit out of main; -NoCommits leaves the branch where it was created, which
# is what a brand-new worktree looks like; -Dirty leaves an uncommitted change. -BaseRef starts the
# branch somewhere other than main, which is the stacked shape new-worktree.ps1 -BaseRef creates.
# -Rebase moves main on and rebases the branch before the merge, so the branch merges under a SHA
# that only a 'rebase (finish)' ref-log entry ever held.
function Add-TestWorktree {
    param(
        [string] $RepoDir,
        [string] $BranchName,
        [switch] $Unmerged,
        [switch] $Dirty,
        [switch] $NoCommits,
        [switch] $Rebase,
        [switch] $WorkAfterMerge,
        [switch] $RebaseMerge,
        [string] $BaseRef = 'main'
    )

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, $BaseRef) | Out-Null

    if (-not $NoCommits) {
        Set-Content -LiteralPath (Join-Path $wtPath 'work.txt') -Value "work on $BranchName" -Encoding utf8
        Invoke-TestGit $wtPath @('add', '-A') | Out-Null
        Invoke-TestGit $wtPath @('commit', '-m', "work on $BranchName") | Out-Null
        if ($Rebase) {
            # Main must move first, or the rebase replays nothing and writes no ref-log entry.
            Set-Content -LiteralPath (Join-Path $RepoDir "base-$BranchName.txt") -Value 'main moves on' -Encoding utf8
            Invoke-TestGit $RepoDir @('add', '-A') | Out-Null
            Invoke-TestGit $RepoDir @('commit', '-m', "main moves before $BranchName rebases") | Out-Null
            Invoke-TestGit $wtPath @('rebase', 'main') | Out-Null
        }
        if ($RebaseMerge) {
            # GitHub's "Rebase and merge" replays the branch commit onto the base and re-commits it
            # as itself, so the base carries the same patch under a DIFFERENT SHA and writes no merge
            # commit at all. A plain cherry-pick reproduces the IDENTICAL SHA -- same tree, same
            # parent, same author, same message -- and would hide the very case this fixture exists
            # for, so the committer has to change.
            Invoke-TestGit $RepoDir @('cherry-pick', $BranchName) | Out-Null
            $env:GIT_COMMITTER_NAME = 'GitHub'
            $env:GIT_COMMITTER_EMAIL = 'noreply@github.com'
            $env:GIT_COMMITTER_DATE = '2030-01-01T00:00:00+00:00'
            try {
                Invoke-TestGit $RepoDir @('commit', '--amend', '--no-edit') | Out-Null
            } finally {
                Remove-Item -LiteralPath 'Env:\GIT_COMMITTER_NAME', 'Env:\GIT_COMMITTER_EMAIL', 'Env:\GIT_COMMITTER_DATE' -ErrorAction SilentlyContinue
            }
        } elseif (-not $Unmerged) {
            # Merging a branch that is checked out in another worktree is allowed; only checking it
            # out twice is not. --no-ff is what a GitHub "Merge pull request" leaves behind.
            Invoke-TestGit $RepoDir @('merge', '--no-ff', '-m', "Merge $BranchName", $BranchName) | Out-Null
        }
    }
    if ($WorkAfterMerge) {
        # A branch whose pull request merged and which then gained a commit nothing else holds.
        # `git branch --merged` used to drop this branch, which is the protection signal 4 replaces.
        Set-Content -LiteralPath (Join-Path $wtPath 'after.txt') -Value 'work made after the merge' -Encoding utf8
        Invoke-TestGit $wtPath @('add', '-A') | Out-Null
        Invoke-TestGit $wtPath @('commit', '-m', "work after $BranchName merged") | Out-Null
    }
    if ($Dirty) {
        Set-Content -LiteralPath (Join-Path $wtPath 'dirty.txt') -Value 'uncommitted' -Encoding utf8
    }

    return (Resolve-Path -LiteralPath $wtPath).Path
}

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

# Removal is delegated to a detached watcher (remove-worktree-local-dev.ps1), so "cleaned"
# is only observable after the fact. Per the spec, "cleans means removed": success requires
# the worktree to actually be GONE -- dropped from `git worktree list` (deregistered) AND its
# folder deleted. A watcher log line is NOT proof of success: the watcher writes
# "Watcher done (worktree preserved)." when it KEPT the worktree (e.g. a locked folder), which
# must fail this poll, not pass it. The log is therefore consulted only to fail fast when the
# watcher explicitly preserved this worktree -- there is no point waiting out the timeout for a
# removal that will never happen. (Confirmed by reading remove-worktree-local-dev.ps1: Hook
# mode with -WorktreePath resolves the main checkout from the worktree's git-common-dir, passes
# the merged+clean gate for these test worktrees, skips DB/Docker when no .env.worktree
# manifest exists, prunes git and deletes the folder on success, and creates the log dir if
# missing. Each log line is "<stamp>  <leaf>  <message>", so the leaf tags the "preserved" line.)
function Wait-ForWorktreeCleaned {
    param([string] $RepoDir, [string] $WorktreePath, [int] $TimeoutMs = 30000)

    $key = ConvertTo-Key $WorktreePath
    $leaf = Split-Path -Leaf $WorktreePath
    $logPath = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $listed = @(& git -C $RepoDir worktree list --porcelain 2>$null) |
            Where-Object { $_ -like 'worktree *' } |
            ForEach-Object { ConvertTo-Key ($_.Substring('worktree '.Length)) }
        # Actually gone: deregistered AND folder deleted. This is the ONLY success signal.
        if (($listed -notcontains $key) -and -not (Test-Path -LiteralPath $WorktreePath)) { return $true }

        # Fail fast: the watcher explicitly preserved this worktree, so it will never be
        # removed. A "preserved" outcome must NOT count as cleaned.
        if (Test-Path -LiteralPath $logPath) {
            foreach ($line in (Get-Content -LiteralPath $logPath)) {
                if ($line -match [regex]::Escape($leaf) -and $line -match 'Watcher done \(worktree preserved\)') { return $false }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

# Runs the REAL cleanup script as a child process against $RepoDir, with optional extra args,
# a process-scoped env override (restored after), and redirected stdin/stdout/stderr.
function Invoke-CleanupChild {
    param(
        [string] $RepoDir,
        [string[]] $ExtraArgs = @(),
        [hashtable] $EnvVars = @{},
        [string] $Stdin = ''
    )

    $parent = Split-Path -Parent $RepoDir
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stdinFile = Join-Path $parent "cin-$suffix.txt"
    $stdoutFile = Join-Path $parent "cout-$suffix.txt"
    $stderrFile = Join-Path $parent "cerr-$suffix.txt"
    Set-Content -LiteralPath $stdinFile -Value $Stdin -Encoding utf8

    $cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $RepoDir, '-MainRef', 'main') + $ExtraArgs

    $restore = @{}
    foreach ($k in $EnvVars.Keys) {
        $restore[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $EnvVars[$k], 'Process')
    }
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
            -WorkingDirectory $suiteRoot `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
    } finally {
        foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $restore[$k], 'Process') }
    }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stdout   = (Get-Content -Raw -LiteralPath $stdoutFile)
        Stderr   = (Get-Content -Raw -LiteralPath $stderrFile)
    }
}

function New-WorktreeToolingRepo {
    param([string] $ScriptsSource)

    $repo = New-TempGitRepo

    $repoScripts = Join-Path $repo 'scripts'
    New-Item -ItemType Directory -Path $repoScripts -Force | Out-Null
    # Top-level *.ps1 only: the worktree contract files, without ci/ or a stray .env.worktree.
    Copy-Item -Path (Join-Path $ScriptsSource '*.ps1') -Destination $repoScripts -Force

    $appSettingsDir = Join-Path $repo 'src\Backend\AHKFlowApp.API'
    New-Item -ItemType Directory -Path $appSettingsDir -Force | Out-Null
    $appSettings = '{ "ConnectionStrings": { "DefaultConnection": "Server=localhost;Database=AHKFlowApp;Trusted_Connection=True;" }, "Cors": { "AllowedOrigins": [] } }'
    Set-Content -LiteralPath (Join-Path $appSettingsDir 'appsettings.json') -Value $appSettings -Encoding utf8

    Set-Content -LiteralPath (Join-Path $repo 'AHKFlowApp.slnx') -Value '<Solution />' -Encoding utf8

    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'worktree tooling') | Out-Null

    return $repo
}

# Import the cleanup functions (guard keeps the standalone entrypoint from running).
. (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')
