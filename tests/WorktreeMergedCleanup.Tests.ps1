# 7.0, not 5.1. This suite dot-sources scripts/cleanup-merged-worktrees.ps1 and calls it in
# process. That script makes bare native git calls, and under Windows PowerShell a native
# command's stderr becomes an error record that this file's 'Stop' preference turns terminating --
# so a git error the sweep handles on purpose ends the suite instead. Making those nine call sites
# host-independent is tracked separately; until then the floor here says what it really is.
# scripts/run-powershell-suites.ps1 runs every suite under pwsh, so nothing changes in CI.
#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# Import the cleanup functions (guard keeps the standalone entrypoint from running).
. (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')

# --- Test: Get-WorktreeCleanupConfig fail-closed state machine ------------------
$repo = New-TempGitRepo
try {
    Assert-Equal 'unset' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No config value must read as unset.'

    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A true value must read as true.'

    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'no') | Out-Null
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) '--bool must normalize no to false.'

    # Duplicated key: exit 0 with two lines -> invalid (fail closed).
    Invoke-TestGit $repo @('config', '--local', '--add', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    Assert-Equal 'invalid' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A duplicated value must read as invalid.'

    # Garbage value: git exits 128 (bad boolean) -> invalid.
    Invoke-TestGit $repo @('config', '--local', '--unset-all', 'ahkflow.worktreeCleanup') | Out-Null
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null
    Assert-Equal 'invalid' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A non-boolean value must read as invalid.'
} finally {
    Remove-TempTree $repo
}

# --- Test: Set-WorktreeCleanupConfig persists and reports success/failure -------
$repo = New-TempGitRepo
try {
    Assert-True (Set-WorktreeCleanupConfig -RepoRoot $repo -Enabled $true) 'Setting true must report success.'
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Set true must be readable as true.'

    Assert-True (Set-WorktreeCleanupConfig -RepoRoot $repo -Enabled $false) 'Setting false must report success.'
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Set false must be readable as false.'

    # Write-failure path: a non-repo directory makes `git config --local` fail.
    $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ('notrepo-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $notARepo -Force | Out-Null
    try {
        Assert-True (-not (Set-WorktreeCleanupConfig -RepoRoot $notARepo -Enabled $true)) 'A failed write must return $false.'
    } finally {
        Remove-Item -LiteralPath $notARepo -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-TempTree $repo
}

# --- Test: ConvertFrom-CleanupAnswer maps the ask-once answer --------------------
foreach ($yes in @('y', 'Y', 'yes', 'YES', '  y  ')) {
    $m = ConvertFrom-CleanupAnswer $yes
    Assert-True ($m.Clean -and $m.Enabled) "Answer '$yes' must map to clean+enable."
}
foreach ($no in @('', 'n', 'no', 'nope', 'x')) {
    $m = ConvertFrom-CleanupAnswer $no
    Assert-True ((-not $m.Clean) -and (-not $m.Enabled)) "Answer '$no' must map to skip+disable."
}

# --- Test: Resolve-CleanupDecision precedence matrix -----------------------------
# Each row: Cleanup, IsHook, ConfigState, EnvOverride, Interactive => Action, ShowHint
$cases = @(
    # -Cleanup wins everywhere.
    @{ C=$true;  H=$false; Cfg='false';  Env='none';    I=$false; A='Clean';      Hint=$false }
    @{ C=$true;  H=$true;  Cfg='false';  Env='disable'; I=$false; A='Clean';      Hint=$false }
    # Hook + env override (hook-only), overrides config.
    @{ C=$false; H=$true;  Cfg='false';  Env='enable';  I=$false; A='Clean';      Hint=$false }
    @{ C=$false; H=$true;  Cfg='true';   Env='disable'; I=$false; A='ReportOnly'; Hint=$false }
    # Hook + config (no env).
    @{ C=$false; H=$true;  Cfg='true';   Env='none';    I=$false; A='Clean';      Hint=$false }
    @{ C=$false; H=$true;  Cfg='false';  Env='none';    I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$true;  Cfg='invalid';Env='none';    I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$true;  Cfg='unset';  Env='none';    I=$false; A='ReportOnly'; Hint=$true  }
    # Hook + env disable + config unset: hint still fires (env is transient, config is the nudge).
    @{ C=$false; H=$true;  Cfg='unset';  Env='disable'; I=$false; A='ReportOnly'; Hint=$true  }
    # Direct calls ignore env entirely (EnvOverride is only read when hook; resolver still must
    # not act on it when IsHook is false, so pass 'enable' here to prove it is inert).
    @{ C=$false; H=$false; Cfg='unset';  Env='enable';  I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$false; Cfg='unset';  Env='enable';  I=$true;  A='Prompt';     Hint=$false }
    # Direct + config.
    @{ C=$false; H=$false; Cfg='true';   Env='none';    I=$true;  A='Clean';      Hint=$false }
    @{ C=$false; H=$false; Cfg='false';  Env='none';    I=$true;  A='Skip';       Hint=$false }
    @{ C=$false; H=$false; Cfg='invalid';Env='none';    I=$true;  A='ReportOnly'; Hint=$false }
    # Direct + unset, non-interactive -> report-only (no console to prompt).
    @{ C=$false; H=$false; Cfg='unset';  Env='none';    I=$false; A='ReportOnly'; Hint=$false }
)
foreach ($c in $cases) {
    $d = Resolve-CleanupDecision -Cleanup:$c.C -IsHook:$c.H -ConfigState $c.Cfg -EnvOverride $c.Env -Interactive $c.I
    $label = "C=$($c.C) H=$($c.H) Cfg=$($c.Cfg) Env=$($c.Env) I=$($c.I)"
    Assert-Equal $c.A $d.Action "Action mismatch for [$label]."
    Assert-Equal $c.Hint $d.ShowHint "ShowHint mismatch for [$label]."
}

# --- Test: Get-EnvCleanupOverride classifies the env var ------------------------
$oldEnv = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
try {
    foreach ($v in @('1', 'true', 'YES', ' y ')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'enable' (Get-EnvCleanupOverride) "Env '$v' must classify as enable."
    }
    foreach ($v in @('0', 'false', 'NO', ' n ')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'disable' (Get-EnvCleanupOverride) "Env '$v' must classify as disable."
    }
    foreach ($v in @('', 'maybe', '2')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'none' (Get-EnvCleanupOverride) "Env '$v' must classify as none."
    }
} finally {
    [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $oldEnv, 'Process')
}

# --- Test: Set-CleanupAnswer persists the answer and warns on write failure -----
# Covers the exact seam the Prompt branch calls, so removing the persistence call or the
# warning is caught here (the child-process integration tests can't reach the Prompt branch
# because they redirect stdin).
$repo = New-TempGitRepo
try {
    $yes = Set-CleanupAnswer -RepoRoot $repo -Answer 'y'
    Assert-True ($yes.Clean -and $yes.Persisted) 'Yes must clean and report persisted.'
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Yes must persist true.'

    $no = Set-CleanupAnswer -RepoRoot $repo -Answer 'n'
    Assert-True ((-not $no.Clean) -and $no.Persisted) 'No must skip but still report persisted.'
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No must persist false.'

    # Failed write (non-repo dir): must honor the answer for the run, report not-persisted,
    # and warn on stderr. Capture stderr in-process to assert the warning is emitted.
    $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ('notrepo-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $notARepo -Force | Out-Null
    $sw = New-Object System.IO.StringWriter
    $origErr = [Console]::Error
    [Console]::SetError($sw)
    try {
        $failed = Set-CleanupAnswer -RepoRoot $notARepo -Answer 'y'
    } finally {
        [Console]::SetError($origErr)
        Remove-Item -LiteralPath $notARepo -Recurse -Force -ErrorAction SilentlyContinue
    }
    Assert-True ($failed.Clean -and (-not $failed.Persisted)) 'Failed write must honor the answer but report not persisted.'
    Assert-True ($sw.ToString() -match 'could not persist') 'Failed write must warn on stderr.'
} finally {
    Remove-TempTree $repo
}

# --- Test: Test-BranchOwnWorkWasMerged separates unstarted branches from real merged work ---
# `git branch --merged main` says yes to a brand-new branch AND to a branch whose work main has
# absorbed. Entry counts do not separate them either: an untouched worktree that catches up with
# `git merge --ff-only main` has two entries and still holds no work. The probe needs BOTH a
# 'commit'-prefixed ref-log subject and structural proof (the tip is a non-first parent of a merge
# commit in main), because either signal alone can be fooled -- see the two cases at the end.
$repo = New-TempGitRepo
try {
    $freshPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh' -NoCommits
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-fresh')) 'A branch created with no commits must report no merged own work.'

    Add-TestWorktree -RepoDir $repo -BranchName 'feat-done' | Out-Null
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-done') 'A committed and merged branch must report merged own work.'

    # An unmerged branch holds real work, but the sweep must never touch it. `git branch --merged`
    # already excludes it, so the probe answering "no" here costs nothing and keeps the guarantee
    # one-directional: this probe only ever authorizes removal, never blocks a keep.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-wip' -Unmerged | Out-Null
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-wip')) 'A committed but unmerged branch must not report merged own work.'

    # A finished worktree that catches up with main after its pull request merged. `git merge
    # --ff-only main` moves the tip off the merge commit's second parent and onto the merge commit
    # itself, so the CURRENT tip no longer proves anything. The work really was merged, and backlog
    # 060 requires such a worktree to stay sweepable, so the proof must come from the ref-log
    # history rather than the tip alone.
    $catchupPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-catchup'
    Invoke-TestGit $catchupPath @('merge', '--ff-only', 'main') | Out-Null
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-catchup') 'A merged branch that then fast-forwarded to main must still report merged own work.'

    # A branch created off another branch (the -BaseRef shape) gets its own ref log with one
    # "branch: Created from <base>" entry. It holds no work of its own.
    Invoke-TestGit $repo @('branch', 'feat-child', 'feat-done') | Out-Null
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-child')) 'A branch created off another branch must report no own commits.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'no-such-branch')) 'An unknown branch must fail closed to no own commits.'

    # Ref logs can be switched off (core.logAllRefUpdates) or expired by gc. Unknown must read as
    # "no own commits" so the sweep keeps the worktree instead of deleting it.
    Invoke-TestGit $repo @('config', 'core.logAllRefUpdates', 'false') | Out-Null
    Invoke-TestGit $repo @('branch', 'feat-nolog', 'main') | Out-Null
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-nolog')) 'A branch with no ref log must fail closed to no own commits.'
    Invoke-TestGit $repo @('config', '--unset', 'core.logAllRefUpdates') | Out-Null

    # The regression this probe was rewritten for: main moves on, the untouched worktree catches
    # up. Two ref-log entries, no commit, so it must still count as unstarted.
    Set-Content -LiteralPath (Join-Path $repo 'later.txt') -Value 'main moves on' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'main moves on') | Out-Null
    Invoke-TestGit $freshPath @('merge', '--ff-only', 'main') | Out-Null
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-fresh')) 'A branch fast-forwarded to main without ever being committed to must report no own commits.'

    # Ref-log subjects are caller-controlled text, not provenance: GIT_REFLOG_ACTION (and
    # `git update-ref -m`) let anything write a "commit: ..." subject for an operation that
    # created no commit. Proven here -- a fast-forward under GIT_REFLOG_ACTION=commit leaves
    # "commit: Fast-forward" on a branch nobody has ever committed on. Trusting that text alone
    # would hand -Cleanup a brand-new worktree to delete, which is the whole bug.
    $spoofPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-spoof' -NoCommits
    Set-Content -LiteralPath (Join-Path $repo 'later2.txt') -Value 'main moves again' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'main moves again') | Out-Null
    Invoke-TestGitWithReflogAction -RepoDir $spoofPath -Action 'commit' -GitArgs @('merge', '--ff-only', 'main') | Out-Null
    $spoofSubjects = (Invoke-TestGit $repo @('reflog', 'show', '--format=%gs', 'refs/heads/feat-spoof')) -join "`n"
    Assert-True ($spoofSubjects -match '(?m)^commit:') 'Sanity check: GIT_REFLOG_ACTION must really have forged a "commit:" ref-log subject.'
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-spoof')) 'A forged "commit:" ref-log subject must not count as own commits.'

    # 'branch: Created from' must never supply the merge proof. `new-worktree.ps1 -BaseRef <branch>`
    # starts a branch at another branch's tip. When that base was merged with a merge commit, its
    # tip is a non-first parent, so that entry alone satisfies the structural half. Forging a
    # 'commit:' subject onto a later fast-forward then supplies the work half, and an unstarted
    # worktree gets deleted. Only commit entries and proven rebase entries may carry merge proof.
    $stackedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-stacked-spoof' -NoCommits -BaseRef 'feat-done'
    Invoke-TestGitWithReflogAction -RepoDir $stackedPath -Action 'commit' -GitArgs @('merge', '--ff-only', 'main') | Out-Null
    $stackedEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-stacked-spoof')) -join "`n"
    Assert-True ($stackedEntries -match '(?m)commit: Fast-forward') 'Sanity check: the stacked branch must carry a forged "commit:" entry.'
    Assert-True ($stackedEntries -match '(?m)branch: Created from') 'Sanity check: the stacked branch must have been created off an already-merged branch.'
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-stacked-spoof')) 'A forged "commit:" entry plus a merged base SHA from a different entry must not count as merged own work.'

    # The other half of the pair: structural proof alone is fooled by a branch created AT an
    # already-merged branch tip, which really is a non-first parent of a merge commit in main.
    # feat-child above covers that; it must stay unstarted because its ref log shows no commit.

    # A branch rebased before it merged (backlog 095). `git rebase` records the replayed tip under
    # 'rebase (finish)', and the 'commit' entry keeps the pre-rebase SHA, which never reaches main.
    # Reading 'commit' entries alone kept every such worktree forever.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebased' -Rebase | Out-Null
    $rebasedEntries = @(Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-rebased'))
    Assert-True ((($rebasedEntries) -join "`n") -match '(?m)rebase \(finish\):') 'Sanity check: the fixture must really have rebased.'

    $preRebaseSha = @($rebasedEntries | Where-Object { $_ -match '\scommit:' } | ForEach-Object { ($_ -split '\s+', 2)[0] })[0]
    $mergeParents = (Invoke-TestGit $repo @('rev-list', '--min-parents=2', '--format=%P', 'main')) -join ' '
    Assert-True (-not ($mergeParents -match [regex]::Escape($preRebaseSha))) 'Sanity check: the pre-rebase SHA must not be a merge parent, or the test would pass for the wrong reason.'

    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebased') 'A branch rebased before it merged must report merged own work.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted branch rebased onto an already-merged branch stays unstarted ---
# The class that accepting 'rebase (finish)' could open. Rebasing a branch that holds no commits
# onto an already-merged branch lands its tip exactly on a non-first parent of a merge commit, so
# the structural proof alone says "merged". Only the missing 'commit' entry keeps the worktree.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-merged-base' | Out-Null
    # 'main^' is the first parent of the merge commit, so this branch starts behind the merged tip
    # and the rebase really moves it.
    $unstartedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-rebase' -NoCommits -BaseRef 'main^'
    Invoke-TestGit $unstartedPath @('rebase', 'feat-merged-base') | Out-Null

    $unstartedEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-unstarted-rebase')) -join "`n"
    Assert-True ($unstartedEntries -match '(?m)rebase \(finish\):') 'Sanity check: the unstarted branch must really have rebased.'
    Assert-True (-not ($unstartedEntries -match '(?m)\scommit:')) 'Sanity check: the unstarted branch must hold no commit entry.'

    $tip = (Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-unstarted-rebase')) -join ''
    $mergeParents = (Invoke-TestGit $repo @('rev-list', '--min-parents=2', '--format=%P', 'main')) -join ' '
    Assert-True ($mergeParents -match [regex]::Escape($tip.Trim())) 'Sanity check: the rebased tip must really be a merge parent, or this test proves nothing.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-unstarted-rebase')) 'An unstarted branch rebased onto a merged branch must report no merged own work.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a reset branch cannot borrow an unrelated rebase as merge proof -------------
# The work proof and the merge proof are separate signals, so they must still describe the SAME
# work. Commit, reset the commit away, then rebase the now-empty branch onto an already-merged
# branch: the old 'commit' entry proves work that no longer exists anywhere, and the
# 'rebase (finish)' entry lands on another branch's merged tip. No branch contains the abandoned
# commit, so removing this worktree would take its last practical recovery path with it.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-merged-elsewhere' | Out-Null
    $resetPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-reset' -NoCommits -BaseRef 'main^'

    Set-Content -LiteralPath (Join-Path $resetPath 'abandoned.txt') -Value 'work nobody merged' -Encoding utf8
    Invoke-TestGit $resetPath @('add', '-A') | Out-Null
    Invoke-TestGit $resetPath @('commit', '-m', 'abandoned work') | Out-Null
    $abandonedSha = ((Invoke-TestGit $resetPath @('rev-parse', 'HEAD')) -join '').Trim()
    Invoke-TestGit $resetPath @('reset', '--hard', 'HEAD~1') | Out-Null
    Invoke-TestGit $resetPath @('rebase', 'feat-merged-elsewhere') | Out-Null

    $containing = ((Invoke-TestGit $repo @('branch', '--contains', $abandonedSha)) -join '').Trim()
    Assert-True (-not $containing) 'Sanity check: no branch may contain the abandoned commit, or the test proves nothing.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-reset')) 'A branch whose commit was reset away must not borrow an unrelated rebase as merge proof.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $resetPath))) 'A branch whose commit was reset away must never be eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an equivalent ancestor cannot stand in for abandoned work -------------------
# The branch made two commits. A copy of the first reached main by another route, so it has a
# patch-equivalent there; the second was reset away and exists nowhere else. Asking only whether
# SOME commit of the branch is patch-equivalent answers yes and deletes the second one's last
# copy. The question has to be asked of every commit the branch ever pointed at.
$repo = New-TempGitRepo
try {
    $lossPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-loss' -NoCommits
    Set-Content -LiteralPath (Join-Path $lossPath 'a.txt') -Value 'work A' -Encoding utf8
    Invoke-TestGit $lossPath @('add', '-A') | Out-Null
    Invoke-TestGit $lossPath @('commit', '-m', 'work A') | Out-Null
    $shaA = ((Invoke-TestGit $lossPath @('rev-parse', 'HEAD')) -join '').Trim()
    Set-Content -LiteralPath (Join-Path $lossPath 'b.txt') -Value 'work B' -Encoding utf8
    Invoke-TestGit $lossPath @('add', '-A') | Out-Null
    Invoke-TestGit $lossPath @('commit', '-m', 'work B') | Out-Null
    $shaB = ((Invoke-TestGit $lossPath @('rev-parse', 'HEAD')) -join '').Trim()

    # Main must move before the copy is made. A cherry-pick onto the SAME parent reproduces the
    # commit byte for byte, and an identical SHA would make this test prove nothing.
    Set-Content -LiteralPath (Join-Path $repo 'moved.txt') -Value 'main moves' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'main moves') | Out-Null

    $donePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-copy' -NoCommits
    Invoke-TestGit $donePath @('cherry-pick', $shaA) | Out-Null
    Set-Content -LiteralPath (Join-Path $donePath 'c.txt') -Value 'work C' -Encoding utf8
    Invoke-TestGit $donePath @('add', '-A') | Out-Null
    Invoke-TestGit $donePath @('commit', '-m', 'work C') | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-copy', 'feat-copy') | Out-Null

    Invoke-TestGit $lossPath @('reset', '--hard', 'main^') | Out-Null
    Invoke-TestGit $lossPath @('rebase', 'feat-copy') | Out-Null

    $copyOfA = ((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-copy~1')) -join '').Trim()
    Assert-True ($copyOfA -ne $shaA) 'Sanity check: the copy of the first commit must have its own SHA.'
    $containing = ((Invoke-TestGit $repo @('branch', '--contains', $shaB)) -join '').Trim()
    Assert-True (-not $containing) 'Sanity check: no branch may contain the abandoned second commit.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-loss')) 'A branch holding one abandoned commit must not be proved merged by an equivalent of another commit.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $lossPath))) 'A branch holding an abandoned commit must never be eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a forged commit subject cannot authorize deleting unmerged work --------------
# GIT_REFLOG_ACTION=commit on a fast-forward to an already-merged tip writes 'commit: Fast-forward'
# with a merged SHA, so both proofs read as satisfied. Ref-log text cannot be authenticated, so the
# guarantee is the one that matters: work the branch holds and main does not must keep the worktree.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-target' | Out-Null
    $forgedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-forged-ff' -NoCommits -BaseRef 'main^'

    Set-Content -LiteralPath (Join-Path $forgedPath 'unmerged.txt') -Value 'work nobody merged' -Encoding utf8
    Invoke-TestGit $forgedPath @('add', '-A') | Out-Null
    Invoke-TestGit $forgedPath @('commit', '-m', 'work nobody merged') | Out-Null
    $unmergedSha = ((Invoke-TestGit $forgedPath @('rev-parse', 'HEAD')) -join '').Trim()
    Invoke-TestGit $forgedPath @('reset', '--hard', 'main^') | Out-Null
    Invoke-TestGitWithReflogAction -RepoDir $forgedPath -Action 'commit' -GitArgs @('merge', '--ff-only', 'feat-ff-target') | Out-Null

    $forgedEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-forged-ff')) -join "`n"
    Assert-True ($forgedEntries -match '(?m)commit: Fast-forward') 'Sanity check: the fast-forward must really have written a forged "commit:" subject.'
    $tip = ((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-forged-ff')) -join '').Trim()
    $mergeParents = (Invoke-TestGit $repo @('rev-list', '--min-parents=2', '--format=%P', 'main')) -join ' '
    Assert-True ($mergeParents -match [regex]::Escape($tip)) 'Sanity check: the forged entry must carry a merged non-first parent.'
    $containing = ((Invoke-TestGit $repo @('branch', '--contains', $unmergedSha)) -join '').Trim()
    Assert-True (-not $containing) 'Sanity check: no branch may contain the unmerged commit.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-forged-ff')) 'A forged commit subject must not authorize deleting a branch that holds unmerged work.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $forgedPath))) 'A worktree holding unmerged work must never be eligible, whatever its ref-log says.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a cherry-pick counts as the branch's own work --------------------------------
# `git cherry-pick` writes 'cherry-pick: <subject>', not 'commit:'. It creates a commit on the
# branch, so a branch built that way and then merged is finished work like any other.
$repo = New-TempGitRepo
try {
    $srcPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-source' -Unmerged
    $pickedSha = ((Invoke-TestGit $srcPath @('rev-parse', 'HEAD')) -join '').Trim()

    $pickPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-picked' -NoCommits
    Invoke-TestGit $pickPath @('cherry-pick', $pickedSha) | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-picked', 'feat-picked') | Out-Null

    $pickEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-picked')) -join "`n"
    Assert-True ($pickEntries -match '(?m)cherry-pick:') 'Sanity check: the fixture must really have written a "cherry-pick:" subject.'

    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-picked') 'A merged branch whose commit came from a cherry-pick must report merged own work.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True ($keys -contains (ConvertTo-Key $pickPath)) 'A merged cherry-pick branch must be eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}

# --- Test: content that differs only in whitespace is still work ------------------------
# `git cherry` compares patches with whitespace and line numbers removed, so 'a b' and 'ab' read as
# the same commit. Signal 3 answers by reachability instead, and never asks whether two commits
# look alike.
$repo = New-TempGitRepo
try {
    $wsPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-whitespace' -NoCommits
    Set-Content -LiteralPath (Join-Path $wsPath 'w.txt') -Value 'a b' -Encoding utf8
    Invoke-TestGit $wsPath @('add', '-A') | Out-Null
    Invoke-TestGit $wsPath @('commit', '-m', 'spaced content') | Out-Null
    $abandonedSha = ((Invoke-TestGit $wsPath @('rev-parse', 'HEAD')) -join '').Trim()

    # Main gets the same text without the space, through a different branch.
    $otherPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unspaced' -NoCommits
    Set-Content -LiteralPath (Join-Path $otherPath 'w.txt') -Value 'ab' -Encoding utf8
    Invoke-TestGit $otherPath @('add', '-A') | Out-Null
    Invoke-TestGit $otherPath @('commit', '-m', 'spaced content') | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-unspaced', 'feat-unspaced') | Out-Null

    Invoke-TestGit $wsPath @('reset', '--hard', 'main^') | Out-Null
    Invoke-TestGit $wsPath @('rebase', 'feat-unspaced') | Out-Null

    $cherry = ((Invoke-TestGit $repo @('cherry', 'main', $abandonedSha)) -join '').Trim()
    Assert-True ($cherry -like '- *') 'Sanity check: git cherry must call the whitespace-different commit equivalent, or this test proves nothing.'
    $containing = ((Invoke-TestGit $repo @('branch', '--contains', $abandonedSha)) -join '').Trim()
    Assert-True (-not $containing) 'Sanity check: no branch may contain the abandoned commit.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-whitespace')) 'Content that differs only in whitespace must still count as discarded work.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $wsPath))) 'A worktree holding whitespace-different discarded work must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a discarded merge commit is work too -----------------------------------------
# `git cherry` prints nothing at all for a merge commit, so a conflict resolution that exists
# nowhere else was invisible to the old check. Reachability sees it like any other commit.
$repo = New-TempGitRepo
try {
    Set-Content -LiteralPath (Join-Path $repo 'f.txt') -Value 'base' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'base file') | Out-Null

    $sideAPath = Add-TestWorktree -RepoDir $repo -BranchName 'side-a' -NoCommits
    Set-Content -LiteralPath (Join-Path $sideAPath 'f.txt') -Value 'side A change' -Encoding utf8
    Invoke-TestGit $sideAPath @('add', '-A') | Out-Null
    Invoke-TestGit $sideAPath @('commit', '-m', 'side A') | Out-Null

    $sideBPath = Add-TestWorktree -RepoDir $repo -BranchName 'side-b' -NoCommits
    Set-Content -LiteralPath (Join-Path $sideBPath 'f.txt') -Value 'side B change' -Encoding utf8
    Invoke-TestGit $sideBPath @('add', '-A') | Out-Null
    Invoke-TestGit $sideBPath @('commit', '-m', 'side B') | Out-Null

    # The worktree resolves the conflict its own way, then throws that merge commit away.
    $mergePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-resolver' -NoCommits -BaseRef 'side-a'
    & git -C $mergePath merge --no-commit side-b *> $null
    Set-Content -LiteralPath (Join-Path $mergePath 'f.txt') -Value 'unique abandoned resolution' -Encoding utf8
    Invoke-TestGit $mergePath @('add', '-A') | Out-Null
    Invoke-TestGit $mergePath @('commit', '-m', 'abandoned merge resolution') | Out-Null
    $abandonedMerge = ((Invoke-TestGit $mergePath @('rev-parse', 'HEAD')) -join '').Trim()

    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge side-a', 'side-a') | Out-Null
    & git -C $repo merge --no-commit side-b *> $null
    Set-Content -LiteralPath (Join-Path $repo 'f.txt') -Value 'different main resolution' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'Merge side-b with main resolution') | Out-Null

    Invoke-TestGit $mergePath @('reset', '--hard', 'side-a') | Out-Null
    Set-Content -LiteralPath (Join-Path $mergePath 'later.txt') -Value 'later work' -Encoding utf8
    Invoke-TestGit $mergePath @('add', '-A') | Out-Null
    Invoke-TestGit $mergePath @('commit', '-m', 'later work') | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-resolver', 'feat-resolver') | Out-Null

    $cherry = ((Invoke-TestGit $repo @('cherry', 'main', $abandonedMerge)) -join '').Trim()
    Assert-True (-not $cherry) 'Sanity check: git cherry must say nothing about the merge commit, or this test proves nothing.'
    $containing = ((Invoke-TestGit $repo @('branch', '--contains', $abandonedMerge)) -join '').Trim()
    Assert-True (-not $containing) 'Sanity check: no branch may contain the abandoned merge commit.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-resolver')) 'A discarded merge commit holding a unique resolution must keep the worktree.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $mergePath))) 'A worktree holding a discarded merge commit must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a clean merge counts as the branch's own work --------------------------------
# A merge that needs no conflict resolution writes 'merge <ref>: Merge made by the ... strategy.'
# It creates a commit on the branch, so a branch built that way and then merged is finished work.
# A fast-forward writes 'merge <ref>: Fast-forward' and creates nothing, which must NOT count.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'side' -Unmerged | Out-Null

    $mergePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-cleanmerge' -NoCommits
    Invoke-TestGit $mergePath @('merge', '--no-ff', '-m', 'Merge side', 'side') | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-cleanmerge', 'feat-cleanmerge') | Out-Null

    $mergeEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-cleanmerge')) -join "`n"
    Assert-True ($mergeEntries -match "(?m)merge side: Merge made by") 'Sanity check: the fixture must really have written a clean-merge subject.'

    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-cleanmerge') 'A merged branch whose commit came from a clean merge must report merged own work.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True ($keys -contains (ConvertTo-Key $mergePath)) 'A merged clean-merge branch must be eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a fast-forward is not a commit ------------------------------------------------
# The other half of the clean-merge rule. `git merge --ff-only` writes a 'merge <ref>:' subject
# without creating anything, so an unstarted branch must not become sweepable by running it.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-source' | Out-Null
    $ffPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-rider' -NoCommits -BaseRef 'main^'
    Invoke-TestGit $ffPath @('merge', '--ff-only', 'feat-ff-source') | Out-Null

    $ffEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-ff-rider')) -join "`n"
    Assert-True ($ffEntries -match '(?m)merge feat-ff-source: Fast-forward') 'Sanity check: the fixture must really have written a fast-forward subject.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-ff-rider')) 'A fast-forward creates no commit, so it must not count as the branch own work.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a revert counts as the branch's own work -------------------------------------
# `git revert` writes 'revert: <subject>' and creates a commit, exactly like a cherry-pick.
$repo = New-TempGitRepo
try {
    $revertPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-revert' -NoCommits
    $target = ((Invoke-TestGit $revertPath @('rev-parse', 'HEAD')) -join '').Trim()
    Invoke-TestGit $revertPath @('revert', '--no-edit', $target) | Out-Null
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-revert', 'feat-revert') | Out-Null

    $revertEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-revert')) -join "`n"
    Assert-True ($revertEntries -match '(?m)revert:') 'Sanity check: the fixture must really have written a "revert:" subject.'

    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-revert') 'A merged branch whose commit came from a revert must report merged own work.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True ($keys -contains (ConvertTo-Key $revertPath)) 'A merged revert branch must be eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}


# --- Test: a squashing rebase is swept like any other rebase -----------------------------
# A squash strands the originals it replaced, exactly as a plain rebase strands the commits it
# replayed. Nothing discarded them, so the worktree goes.
$repo = New-TempGitRepo
try {
    $squashPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-squash' -NoCommits
    Set-Content -LiteralPath (Join-Path $squashPath 's.txt') -Value 'first' -Encoding utf8
    Invoke-TestGit $squashPath @('add', '-A') | Out-Null
    Invoke-TestGit $squashPath @('commit', '-m', 'squash base') | Out-Null
    Set-Content -LiteralPath (Join-Path $squashPath 's.txt') -Value 'first and second' -Encoding utf8
    Invoke-TestGit $squashPath @('add', '-A') | Out-Null
    Invoke-TestGit $squashPath @('commit', '-m', 'fixup! squash base') | Out-Null

    Set-Content -LiteralPath (Join-Path $repo 'moved.txt') -Value 'main moves' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'main moves') | Out-Null

    $env:GIT_EDITOR = 'true'
    try {
        Invoke-TestGit $squashPath @('rebase', '-i', '--autosquash', 'main') | Out-Null
    } finally {
        Remove-Item -LiteralPath 'Env:\GIT_EDITOR' -ErrorAction SilentlyContinue
    }
    Invoke-TestGit $repo @('merge', '--no-ff', '-m', 'Merge feat-squash', 'feat-squash') | Out-Null

    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-squash') 'A squashing rebase supersedes its originals like any rebase, so the merged worktree must be swept.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a forged 'commit (finish)' subject cannot prove work ------------------------
# GIT_REFLOG_ACTION rewrites the FIRST word of the subject, so a rebase can be made to read
# 'commit (finish): ...'. A prefix test on 'commit' accepts it, and the same entry carries the
# merged tip, so both proofs come from one forged entry. Git itself only ever writes 'commit:',
# 'commit (amend):', 'commit (merge):' and 'commit (initial):' with that first word.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-merged-target' | Out-Null
    $forgedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-forged-finish' -NoCommits -BaseRef 'main^'
    Invoke-TestGitWithReflogAction -RepoDir $forgedPath -Action 'commit' -GitArgs @('rebase', 'feat-merged-target') | Out-Null

    $forgedEntries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-forged-finish')) -join "`n"
    Assert-True ($forgedEntries -match '(?m)commit \(finish\):') 'Sanity check: the rebase must really have written a forged "commit (finish):" subject.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-forged-finish')) 'A forged "commit (finish):" subject must not count as own commits.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $forgedPath))) 'A forged "commit (finish):" subject must not make an unstarted worktree eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: eligibility matrix -------------------------------------------------
$repo = New-TempGitRepo
try {
    $cleanPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-clean'
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty' -Dirty | Out-Null
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-unmerged' -Unmerged | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-Equal 1 $eligible.Count 'Only the merged+clean worktree should be eligible.'
    Assert-True ($keys -contains (ConvertTo-Key $cleanPath)) 'The merged+clean worktree must be eligible.'
    Assert-Equal 'feat-clean' $eligible[0].Branch 'Eligible branch short name should be feat-clean.'
    $mainKey = ConvertTo-Key $repo
    Assert-True (-not ($keys -contains $mainKey)) 'The main checkout must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a worktree whose branch has no commits is never eligible (backlog 060) ---
# Two brand-new worktrees must be able to exist at the same time. Both branches point at main's
# tip, so both look merged; neither is finished work. The third worktree here caught up with main
# by fast-forward and still holds no work of its own.
$repo = New-TempGitRepo
try {
    $freshPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-one' -NoCommits
    $freshTwoPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-two' -NoCommits
    $donePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-really-merged'

    # feat-fresh-two catches up with main, which now holds the merge commit for feat-really-merged.
    Invoke-TestGit $freshTwoPath @('merge', '--ff-only', 'main') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-Equal 1 $eligible.Count 'Only the branch with merged commits of its own should be eligible.'
    Assert-True ($keys -contains (ConvertTo-Key $donePath)) 'A branch really merged into main must stay eligible.'
    Assert-True (-not ($keys -contains (ConvertTo-Key $freshPath))) 'A worktree with no commits of its own must never be eligible.'
    Assert-True (-not ($keys -contains (ConvertTo-Key $freshTwoPath))) 'A worktree fast-forwarded to main without its own commits must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a merged worktree stays eligible after it catches up with main -------------
# The sweep's whole job. A worktree left open after its pull request merged, then updated with
# `git merge --ff-only main`, still holds finished work and must still be removed.
$repo = New-TempGitRepo
try {
    $caughtUpPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-caught-up'
    Invoke-TestGit $caughtUpPath @('merge', '--ff-only', 'main') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True ($keys -contains (ConvertTo-Key $caughtUpPath)) 'A merged worktree that fast-forwarded to main must stay eligible for cleanup.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebased worktree is eligible once it merges (backlog 095) ----------------
# Eligibility is where the deletion decision is made, so the rebase shape is pinned here too, not
# only at the probe. An unstarted branch rebased onto the merged branch must still survive.
$repo = New-TempGitRepo
try {
    $rebasedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebased-eligible' -Rebase
    $unstartedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-rebase-eligible' -NoCommits -BaseRef 'main^'
    Invoke-TestGit $unstartedPath @('rebase', 'feat-rebased-eligible') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True ($keys -contains (ConvertTo-Key $rebasedPath)) 'A worktree rebased before its merge must be eligible for cleanup.'
    Assert-True (-not ($keys -contains (ConvertTo-Key $unstartedPath))) 'An unstarted worktree rebased onto a merged branch must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a forged ref-log subject cannot make an unstarted worktree eligible --------
# Eligibility is where the deletion decision is made, so the spoof is pinned here too, not
# only at the probe. GIT_REFLOG_ACTION=commit + a fast-forward writes "commit: Fast-forward"
# onto a branch nobody committed on.
$repo = New-TempGitRepo
try {
    $spoofPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-spoof-eligible' -NoCommits
    $donePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-genuine'

    Invoke-TestGitWithReflogAction -RepoDir $spoofPath -Action 'commit' -GitArgs @('merge', '--ff-only', 'main') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True (-not ($keys -contains (ConvertTo-Key $spoofPath))) 'A forged "commit:" ref-log subject must not make an unstarted worktree eligible.'
    Assert-True ($keys -contains (ConvertTo-Key $donePath)) 'Genuinely merged work must stay eligible alongside the spoofed branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a stacked branch cannot combine the two signals into eligibility ------------
# The signals must correlate. A branch started at an already-merged branch's tip (the -BaseRef
# workflow) carries a merged SHA in its 'branch: Created from' entry. Forging a 'commit:' subject
# onto a later fast-forward supplies the other half from a different entry. Neither entry alone
# proves work, so this worktree must survive -Cleanup.
$repo = New-TempGitRepo
try {
    $basePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-stack-base'
    $stackedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-stack-child' -NoCommits -BaseRef 'feat-stack-base'
    Invoke-TestGitWithReflogAction -RepoDir $stackedPath -Action 'commit' -GitArgs @('merge', '--ff-only', 'main') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True (-not ($keys -contains (ConvertTo-Key $stackedPath))) 'A stacked branch with no commits of its own must never be eligible, even with a forged "commit:" entry.'
    Assert-True ($keys -contains (ConvertTo-Key $basePath)) 'The merged base branch must stay eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: main-ref worktree is excluded even when $RepoRoot points elsewhere ---
# Regression guard: a standalone run from inside a linked worktree (no new-worktree.ps1
# Assert-MainCheckout gate) resolves $RepoRoot to that linked worktree, not the real main
# checkout. Since `git branch --merged main` always includes `main` itself, the path-based
# exclusion alone previously let the main checkout slip into the eligible set.
$repo = New-TempGitRepo
try {
    $otherPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-other'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $otherPath -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True (-not ($keys -contains (ConvertTo-Key $repo))) 'The main-ref worktree must never be eligible, even when $RepoRoot is a different (linked) worktree.'
} finally {
    Remove-TempTree $repo
}

# --- Test: main-ref exclusion matches a fully-qualified -MainRef too ------------
# Regression guard: -MainRef 'refs/heads/main' must exclude the main checkout the same
# way -MainRef 'main' does. $wt.Branch is always a short name, so a naive string compare
# against an unresolved 'refs/heads/main' never matches.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-other' | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'refs/heads/main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-True (-not ($keys -contains (ConvertTo-Key $repo))) 'The main-ref worktree must never be eligible when -MainRef is the fully-qualified refs/heads/main form.'
} finally {
    Remove-TempTree $repo
}

# --- Test: ExcludePath protects the worktree this run is about to create/reuse ---
$repo = New-TempGitRepo
try {
    $targetPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-target'

    # Without exclusion the target itself would be eligible (merged + clean)...
    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-True ((@($eligible | ForEach-Object { ConvertTo-Key $_.Path })) -contains (ConvertTo-Key $targetPath)) 'Sanity check: the target worktree must be eligible before exclusion is applied.'

    # ...but passing -ExcludePath must remove it from the eligible set, so a run that is
    # about to create/reuse this exact path can never race its own async removal.
    $excluded = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -ExcludePath $targetPath
    $excludedKeys = @($excluded | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($excludedKeys -contains (ConvertTo-Key $targetPath))) '-ExcludePath must exclude the target worktree even though it is merged+clean.'
} finally {
    Remove-TempTree $repo
}

# --- Test: --format branch parsing (regression guard for the '+ ' marker) ------
$repo = New-TempGitRepo
try {
    $mergedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plusprefix'

    # A branch checked out in another worktree is prefixed with '+ ' by plain
    # `git branch --merged`; a naive parse would drop it. Prove the marker is there...
    $plain = (Invoke-TestGit $repo @('branch', '--merged', 'main')) -join "`n"
    Assert-True ($plain -match '(?m)^\+\s+feat-plusprefix$') 'Expected the plain --merged output to prefix the worktree branch with "+ ".'

    # ...then prove detection (which uses --format) still finds it.
    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True ($keys -contains (ConvertTo-Key $mergedPath)) 'A merged branch checked out in a worktree must be detected despite the "+ " marker.'
} finally {
    Remove-TempTree $repo
}

# --- Test: hook context is report-only (detects, never removes/prompts) --------
$repo = New-TempGitRepo
try {
    $hookPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-hook'

    Invoke-MergedWorktreeCleanup -RepoRoot $repo -IsHook -MainRef 'main'

    Assert-True (Test-Path -LiteralPath $hookPath) 'Hook context must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-hook')) -join "`n"
    Assert-True ($branches -match 'feat-hook') 'Hook context must not delete the eligible branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: redirected non-interactive runs skip removal without prompting -------
$repo = New-TempGitRepo
try {
    $skipPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-noninteractive'

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stdin.txt'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
    $proc = Start-Process -FilePath $psExe `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $repo, '-MainRef', 'main') `
        -WorkingDirectory $suiteRoot `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    Assert-Equal 0 $proc.ExitCode "cleanup-merged-worktrees.ps1 non-interactive path should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = Get-Content -Raw -LiteralPath $stdoutFile
    Assert-True ([string]::IsNullOrWhiteSpace($stdout)) "Non-interactive cleanup must not write to stdout. Got: $stdout"

    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected cleanup detection output on stderr. Stderr: $stderrText"
    Assert-True ($stderrText -match 'cleanup: report-only; nothing removed\.') "Expected non-interactive report-only output on stderr. Stderr: $stderrText"

    Assert-True (Test-Path -LiteralPath $skipPath) 'Non-interactive cleanup without -Cleanup must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-noninteractive')) -join "`n"
    Assert-True ($branches -match 'feat-noninteractive') 'Non-interactive cleanup without -Cleanup must not delete the eligible branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: hook path keeps stdout to exactly the new worktree path -------------
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

$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    # An eligible (merged + clean) worktree so cleanup has something to remove during the run.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-eligible' | Out-Null

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'hook-stdin.json'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'hook-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'hook-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '{"name":"brandnew"}' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $newWorktreeScript = Join-Path $repo 'scripts\new-worktree.ps1'
    $proc = Start-Process -FilePath $psExe `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $newWorktreeScript) `
        -WorkingDirectory $repo `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    Assert-Equal 0 $proc.ExitCode "new-worktree.ps1 hook path should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = (Get-Content -Raw -LiteralPath $stdoutFile)
    $stdoutLines = @(($stdout -split "`r?`n") | Where-Object { $_.Trim() })
    $expected = ([System.IO.Path]::GetFullPath((Join-Path $repo '.claude\worktrees\brandnew'))).TrimEnd('\', '/')

    Assert-Equal 1 $stdoutLines.Count "Hook stdout must be exactly one line. Got: $stdout"
    Assert-Equal $expected ($stdoutLines[0].Trim().TrimEnd('\', '/')) 'Hook stdout must be exactly the new worktree path.'

    # Default hook context (no env, no config) is now opt-in: report-only with the config hint,
    # nothing removed. Stdout stays exactly the new worktree path (asserted above).
    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected detection output on stderr. Stderr: $stderrText"
    Assert-True (-not ($stderrText -match 'cleanup: removing merged worktree')) "Default hook cleanup must not remove anything (opt-in). Stderr: $stderrText"
    Assert-True ($stderrText -match 'git config --local ahkflow\.worktreeCleanup true') "Default hook report-only must print the config hint. Stderr: $stderrText"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo '.claude\worktrees')) 'Worktree tooling dir should still exist.'
} finally {
    Remove-TempTree $repo
}

# --- Test: CLI env opt-out (0) keeps WorktreeCreate hook report-only -----------
# With opt-in as the default, env '0' is a redundant-but-honored disable in hook context.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    # An eligible merged + clean worktree that the opt-out must leave alone.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-env-noclean' | Out-Null

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stdin.json'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '{"name":"brandnew-env"}' -Encoding utf8

    $oldCleanupEnv = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
    [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', '0', 'Process')
    try {
        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        $newWorktreeScript = Join-Path $repo 'scripts\new-worktree.ps1'
        $proc = Start-Process -FilePath $psExe `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $newWorktreeScript) `
            -WorkingDirectory $repo `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
    } finally {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $oldCleanupEnv, 'Process')
    }

    Assert-Equal 0 $proc.ExitCode "new-worktree.ps1 hook path with env opt-out should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = Get-Content -Raw -LiteralPath $stdoutFile
    $stdoutLines = @(($stdout -split "`r?`n") | Where-Object { $_.Trim() })
    $expected = ([System.IO.Path]::GetFullPath((Join-Path $repo '.claude\worktrees\brandnew-env'))).TrimEnd('\', '/')

    Assert-Equal 1 $stdoutLines.Count "Hook stdout must remain exactly one line when env cleanup is disabled. Got: $stdout"
    Assert-Equal $expected ($stdoutLines[0].Trim().TrimEnd('\', '/')) 'Hook stdout must remain exactly the new worktree path when env cleanup is disabled.'

    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected cleanup detection output on stderr. Stderr: $stderrText"
    Assert-True ($stderrText -match 'cleanup: report-only') "Expected env opt-out to keep cleanup in report-only mode. Stderr: $stderrText"
    Assert-True (-not ($stderrText -match 'cleanup: removing merged worktree')) "Env opt-out must not remove anything. Stderr: $stderrText"
} finally {
    Remove-TempTree $repo
}

# --- Test: config false -> hook report-only (no hint), direct skip -------------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-cfgfalse'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null

    $hook = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook')
    Assert-Equal 0 $hook.ExitCode "Hook + config false should exit 0. Stderr: $($hook.Stderr)"
    Assert-True ($hook.Stderr -match 'cleanup: eligible merged worktree') 'Config-false hook must still detect.'
    Assert-True (-not ($hook.Stderr -match 'ahkflow\.worktreeCleanup true')) 'Config-false hook must NOT print the enable hint.'
    Assert-True (-not ($hook.Stderr -match 'cleanup: removing')) 'Config-false hook must not remove.'
    Assert-True (Test-Path -LiteralPath $kept) 'Config-false must leave the worktree folder.'

    $direct = Invoke-CleanupChild -RepoDir $repo
    Assert-True (-not ($direct.Stderr -match 'cleanup: removing')) 'Config-false direct call must skip.'
    Assert-True (Test-Path -LiteralPath $kept) 'Config-false direct call must leave the worktree folder.'
} finally {
    Remove-TempTree $repo
}

# --- Test: invalid config fails closed to report-only with a warning -----------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-invalidcfg'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook')
    Assert-Equal 0 $res.ExitCode "Invalid config should not crash. Stderr: $($res.Stderr)"
    Assert-True ($res.Stderr -match 'invalid or duplicated') 'Invalid config must warn.'
    Assert-True ($res.Stderr -match 'git config --local --unset-all ahkflow\.worktreeCleanup') 'Warning must include the repair command.'
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) 'Invalid config must not remove (fail closed).'
    Assert-True (Test-Path -LiteralPath $kept) 'Invalid config must leave the worktree folder.'
} finally {
    Remove-TempTree $repo
}

# --- Test: explicit override cleans over invalid config, without a misleading warning ---
# The invalid-config warning must fire only when the resolved action is report-only. An
# explicit -Cleanup (or hook env enable) that legitimately cleans must NOT claim report-only.
foreach ($override in @(
        @{ Args = @('-Cleanup'); Env = @{}; Label = '-Cleanup' }
        @{ Args = @('-IsHook'); Env = @{ 'AHKFLOW_WORKTREE_CLEANUP' = '1' }; Label = 'hook env enable' }
    )) {
    $repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
    try {
        $target = Add-TestWorktree -RepoDir $repo -BranchName "feat-invalid-$([guid]::NewGuid().ToString('N').Substring(0,6))"
        Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null

        $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs $override.Args -EnvVars $override.Env
        Assert-True (-not ($res.Stderr -match 'treating as report-only')) "$($override.Label) over invalid config must not print a report-only warning. Stderr: $($res.Stderr)"
        Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "$($override.Label) must clean over invalid config. Stderr: $($res.Stderr)"
    } finally {
        Remove-TempTree $repo
    }
}

# --- Test: direct call ignores the env var entirely ----------------------------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-envdirect'
    # Env '1' set, no config, non-interactive direct (no -IsHook) -> must NOT clean.
    $res = Invoke-CleanupChild -RepoDir $repo -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '1' }
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) 'Direct call must ignore AHKFLOW_WORKTREE_CLEANUP.'
    Assert-True (Test-Path -LiteralPath $kept) 'Env var must not trigger removal on a direct call.'
} finally {
    Remove-TempTree $repo
}

# --- Test: no eligible worktrees -> no prompt, nothing persisted ---------------
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty-only' -Dirty | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo
    Assert-True ($res.Stderr -match 'no merged worktrees eligible') 'With no eligible worktrees, cleanup must report none.'
    Assert-Equal 'unset' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No eligible worktrees must not persist any preference.'
} finally {
    Remove-TempTree $repo
}

# --- Test: config true cleans (hook and non-interactive direct) ----------------
foreach ($mode in @(@{ Args = @('-IsHook'); Label = 'hook' }, @{ Args = @(); Label = 'direct' })) {
    $repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
    try {
        $target = Add-TestWorktree -RepoDir $repo -BranchName "feat-cfgtrue-$($mode.Label)"
        Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null

        $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs $mode.Args
        Assert-Equal 0 $res.ExitCode "config true ($($mode.Label)) should exit 0. Stderr: $($res.Stderr)"
        Assert-True ($res.Stderr -match 'cleanup: removing merged worktree') "config true ($($mode.Label)) must request removal. Stderr: $($res.Stderr)"
        Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "config true ($($mode.Label)) worktree must actually be removed (deregistered + folder gone). Stderr: $($res.Stderr)"
    } finally {
        Remove-TempTree $repo
    }
}

# --- Test: env overrides config in hook context (hook-only) --------------------
# env '1' + config false -> cleans.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-env1-cfgfalse'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook') -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '1' }
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "env '1' must override config false in hook context. Stderr: $($res.Stderr)"
} finally {
    Remove-TempTree $repo
}

# env '0' + config true -> report-only (nothing removed).
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-env0-cfgtrue'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook') -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '0' }
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) "env '0' must override config true in hook context. Stderr: $($res.Stderr)"
    Assert-True (Test-Path -LiteralPath $kept) "env '0' must leave the worktree folder even with config true."
} finally {
    Remove-TempTree $repo
}

# --- Test: -Cleanup overrides config false (cleans, no prompt) ------------------
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-flag-over-false'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "-Cleanup must override config false. Stderr: $($res.Stderr)"
} finally {
    Remove-TempTree $repo
}

# --- Test: -Cleanup removes finished work and leaves unstarted worktrees (backlog 060) ---
# The strongest override still must not delete a worktree nobody has committed in.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $fresh = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-forced' -NoCommits
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-done-forced'

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "-Cleanup must still remove a genuinely merged worktree. Stderr: $($res.Stderr)"
    Assert-True (Test-Path -LiteralPath $fresh) '-Cleanup must not remove a worktree whose branch has no commits of its own.'
    Assert-True (-not ($res.Stderr -match 'feat-fresh-forced')) 'An unstarted worktree must not even be reported as eligible.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-fresh-forced')) -join "`n"
    Assert-True ($branches -match 'feat-fresh-forced') '-Cleanup must not delete the unstarted branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: signal 2 reports which SHA proved the merge --------------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-proof'
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    $facts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-proof'
    Assert-True ($null -ne $facts) 'A branch with a ref log must produce facts.'
    Assert-True ($facts.MergeProofShas.ContainsKey($tip)) 'The commit entry must be usable as merge proof.'

    # No @() around the call: the function returns ', @(...)' to keep an empty result an array, and
    # re-wrapping an empty array yields one element that is itself an empty array.
    $proofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $facts.MergeProofShas
    Assert-Equal 1 $proofs.Count 'A merged branch must yield exactly one local merge proof.'
    Assert-Equal $tip $proofs[0] 'The proof must be the SHA main merged.'

    Add-TestWorktree -RepoDir $repo -BranchName 'feat-open' -Unmerged | Out-Null
    $openFacts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-open'
    $openProofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $openFacts.MergeProofShas
    Assert-Equal 0 $openProofs.Count 'An unmerged branch must yield no proof.'
} finally {
    Remove-TempTree $repo
}

# --- Test: work made after the merge keeps the worktree (signal 4) --------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-after' -WorkAfterMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    $facts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-after'
    $proofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $facts.MergeProofShas
    Assert-Equal 1 $proofs.Count 'The merge proof must still be found.'
    Assert-True ($proofs[0] -ne $tip) 'Sanity check: the tip must have moved past the proof.'

    $after = Get-WorkAfterMergeProof -RepoRoot $repo -Branch 'feat-after' -ProofShas $proofs
    Assert-Equal 1 $after.Count 'The commit made after the merge must be reported.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-after')) `
        'A branch that gained a commit after its merge must NOT report merged own work.'

    # The idle case must keep working: merged, nothing after, removable.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-idle' | Out-Null
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-idle') `
        'A merged branch with no later work must still report merged own work.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the parser reads real gh output --------------------------------------
# Captured from this repository on 2026-08-19 with:
#   gh pr list --repo s205109/AHKFlowApp --state merged --base main --limit 3 #     --json number,headRefName,headRefOid
# and, for the pair that shares a head branch name:
#   gh pr list --repo s205109/AHKFlowApp --state merged --base main #     --head fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke #     --json number,headRefName,headRefOid
$capturedGhJson = @'
[{"headRefName":"fix/wt-nothing-finds-a-branch-left-behind-after-its-worktree-is-gone","headRefOid":"9bfc92bd7112bc432b54e93ce23e51725c25d353","number":325},
 {"headRefName":"fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke","headRefOid":"be250b7b06ba00a4202ae0538d441577d01e4cea","number":322},
 {"headRefName":"fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke","headRefOid":"bb8d90fed5377a3f87ec6b20d7e34c8324bbbb27","number":321}]
'@

$ghRecords = ConvertFrom-GhMergedPrJson -Json $capturedGhJson
Assert-Equal 3 $ghRecords.Count 'Three merged pull requests must parse.'
Assert-Equal 322 $ghRecords[1].Number 'The number must survive parsing.'
Assert-Equal 'be250b7b06ba00a4202ae0538d441577d01e4cea' $ghRecords[1].HeadRefOid 'The head SHA must survive parsing.'
# Two pull requests share one head branch name with different head SHAs. This is why the merge
# proof binds by SHA and never by branch name.
Assert-Equal $ghRecords[1].HeadRefName $ghRecords[2].HeadRefName 'The captured pair must share a branch name.'
Assert-True ($ghRecords[1].HeadRefOid -ne $ghRecords[2].HeadRefOid) 'The captured pair must differ by SHA.'

Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json 'not json').Count 'Unparsable output must read as no records.'
Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json '').Count 'Empty output must read as no records.'
Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json '[{"number":9}]').Count 'A record without a head SHA must be dropped.'

# --- Test: an absent gh reads as "cannot tell", never as "not merged" ------------
$repo = New-TempGitRepo
try {
    # A PATH holding git but not gh. The lookup must report gh-missing and stay unavailable, so the
    # decision falls back to local history instead of treating silence as a verdict.
    $savedPath = $env:PATH
    $env:PATH = (Split-Path -Parent (Get-Command git).Source)
    try {
        $result = Get-MergedPullRequestRecords -RepoRoot $repo -BaseBranch 'main' -TimeoutSeconds 5
        Assert-True (-not $result.Available) 'A missing gh must not be available.'
        Assert-Equal 'gh-missing' $result.Reason 'A missing gh must say so.'
        Assert-Equal 0 @($result.Records).Count 'A missing gh must yield no records.'
    } finally {
        $env:PATH = $savedPath
    }

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo) 'With no upstream the local ref name is the base branch name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged branch is merged when GitHub says so ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-merged' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    # Sanity: the base carries the patch under a different SHA, and no merge commit exists, so the
    # three local signals cannot prove this merge however hard they look.
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged')) `
        'Local git alone must not prove a rebase merge.'

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 1; HeadRefName = 'feat-rebase-merged'; HeadRefOid = $tip }) } }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghSays) `
        'A merged pull request whose head SHA the ref log holds must prove the merge.'

    $ghCannotTell = { [pscustomobject]@{ Available = $false; Reason = 'gh-missing'; Records = @() } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghCannotTell)) `
        'An unavailable lookup must keep the worktree.'

    # A recycled branch name: same name, a head SHA this branch never pointed at.
    $ghWrongSha = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 2; HeadRefName = 'feat-rebase-merged'; HeadRefOid = ('0' * 40) }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghWrongSha)) `
        'A pull request the ref log never recorded must not prove the merge.'

    # A merge-commit merge must never spend a network call: this lookup throws if it is consulted.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-local-proof' | Out-Null
    $ghMustNotRun = { throw 'The lookup must not run when local git already proved the merge.' }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-local-proof' -MergedPullRequestLookup $ghMustNotRun) `
        'A merge-commit merge must be proved locally, without asking GitHub.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted branch is never merged, whatever GitHub says -------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-pr' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 3; HeadRefName = 'feat-unstarted-pr'; HeadRefOid = $tip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-unstarted-pr' -MergedPullRequestLookup $ghSays)) `
        'Signal 1 must refuse a branch that never committed, even with a merged pull request.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase merge followed by new work keeps the worktree ----------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-then-work' -RebaseMerge
    $mergedTip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Set-Content -LiteralPath (Join-Path $wtPath 'after.txt') -Value 'later' -Encoding utf8
    Invoke-TestGit $wtPath @('add', '-A') | Out-Null
    Invoke-TestGit $wtPath @('commit', '-m', 'work after the rebase merge') | Out-Null

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 4; HeadRefName = 'feat-rebase-then-work'; HeadRefOid = $mergedTip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-then-work' -MergedPullRequestLookup $ghSays)) `
        'Signal 4 must refuse work made after a rebase merge.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep lists a rebase-merged worktree as eligible ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-sweep-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $records = @([pscustomobject]@{ Number = 5; HeadRefName = 'feat-sweep-rebase'; HeadRefOid = $tip })

    $eligible = @(Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records)
    Assert-Equal 1 $eligible.Count 'A rebase-merged worktree must be eligible when GitHub proves the merge.'
    Assert-Equal 'feat-sweep-rebase' $eligible[0].Branch 'The eligible worktree must be the rebase-merged one.'

    # No @() around this call either: the function returns ', $eligible', so re-wrapping an empty
    # result yields one element that is itself the empty array.
    $none = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $none.Count 'Without the GitHub records the same worktree must be preserved.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a child that never exits is killed at the timeout --------------------
# The lookup used to call ReadToEnd() on both streams BEFORE WaitForExit(). A blocking read only
# returns when the pipe closes, which a hung child never does, so the timeout was never reached and
# the whole sweep hung. Get-MergedPullRequestRecords now runs through Invoke-CapturedProcess, and
# this drives that helper with a child whose behavior the test controls completely.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$hung = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120') -TimeoutSeconds 3
$watch.Stop()

Assert-True $hung.Started 'The child must have started.'
Assert-True $hung.TimedOut 'A child that outlives the timeout must report TimedOut.'
Assert-True ($watch.Elapsed.TotalSeconds -lt 30) `
    "The helper must give up near its timeout, not wait for the child. Took $([int]$watch.Elapsed.TotalSeconds)s."

# The same helper must still return real output from a child that exits normally.
$quick = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', 'Write-Output ping-from-child') -TimeoutSeconds 30
Assert-True $quick.Started 'A normal child must start.'
Assert-True (-not $quick.TimedOut) 'A normal child must not report a timeout.'
Assert-Equal 0 $quick.ExitCode 'A normal child must report its exit code.'
Assert-True ($quick.StdOut -match 'ping-from-child') "Captured stdout must hold the child's output. Got: $($quick.StdOut)"

# Output larger than one pipe buffer must not deadlock, which is what the async drain buys.
$bulk = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', "'x' * 200000") -TimeoutSeconds 60
Assert-True (-not $bulk.TimedOut) 'A child writing more than one pipe buffer must not time out.'
Assert-True ($bulk.StdOut.Length -ge 200000) "All of the child's output must be captured. Got $($bulk.StdOut.Length) chars."

# An executable that cannot be launched is 'not started', never a silent success.
$missing = Invoke-CapturedProcess -FilePath (Join-Path $env:TEMP 'no-such-binary-98765.exe') `
    -Arguments @('--version') -TimeoutSeconds 5
Assert-True (-not $missing.Started) 'A missing executable must report Started = false.'

# --- Test: an absent gh reads as "cannot tell", never as "not merged" ------------
$repo = New-TempGitRepo
try {
    # A PATH holding git but not gh. The lookup must report gh-missing and stay unavailable, so the
    # decision falls back to local history instead of treating silence as a verdict.
    $savedPath = $env:PATH
    $env:PATH = (Split-Path -Parent (Get-Command git).Source)
    try {
        $result = Get-MergedPullRequestRecords -RepoRoot $repo -BaseBranch 'main' -TimeoutSeconds 5
        Assert-True (-not $result.Available) 'A missing gh must not be available.'
        Assert-Equal 'gh-missing' $result.Reason 'A missing gh must say so.'
        Assert-Equal 0 @($result.Records).Count 'A missing gh must yield no records.'
    } finally {
        $env:PATH = $savedPath
    }

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo) 'With no upstream the local ref name is the base branch name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged branch is merged when GitHub says so ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-merged' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    # Sanity: the base carries the patch under a different SHA, and no merge commit exists, so the
    # three local signals cannot prove this merge however hard they look.
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged')) `
        'Local git alone must not prove a rebase merge.'

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 1; HeadRefName = 'feat-rebase-merged'; HeadRefOid = $tip }) } }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghSays) `
        'A merged pull request whose head SHA the ref log holds must prove the merge.'

    $ghCannotTell = { [pscustomobject]@{ Available = $false; Reason = 'gh-missing'; Records = @() } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghCannotTell)) `
        'An unavailable lookup must keep the worktree.'

    # A recycled branch name: same name, a head SHA this branch never pointed at.
    $ghWrongSha = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 2; HeadRefName = 'feat-rebase-merged'; HeadRefOid = ('0' * 40) }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghWrongSha)) `
        'A pull request the ref log never recorded must not prove the merge.'

    # A merge-commit merge must never spend a network call: this lookup throws if it is consulted.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-local-proof' | Out-Null
    $ghMustNotRun = { throw 'The lookup must not run when local git already proved the merge.' }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-local-proof' -MergedPullRequestLookup $ghMustNotRun) `
        'A merge-commit merge must be proved locally, without asking GitHub.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted branch is never merged, whatever GitHub says -------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-pr' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 3; HeadRefName = 'feat-unstarted-pr'; HeadRefOid = $tip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-unstarted-pr' -MergedPullRequestLookup $ghSays)) `
        'Signal 1 must refuse a branch that never committed, even with a merged pull request.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase merge followed by new work keeps the worktree ----------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-then-work' -RebaseMerge
    $mergedTip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Set-Content -LiteralPath (Join-Path $wtPath 'after.txt') -Value 'later' -Encoding utf8
    Invoke-TestGit $wtPath @('add', '-A') | Out-Null
    Invoke-TestGit $wtPath @('commit', '-m', 'work after the rebase merge') | Out-Null

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 4; HeadRefName = 'feat-rebase-then-work'; HeadRefOid = $mergedTip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-then-work' -MergedPullRequestLookup $ghSays)) `
        'Signal 4 must refuse work made after a rebase merge.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep lists a rebase-merged worktree as eligible ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-sweep-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $records = @([pscustomobject]@{ Number = 5; HeadRefName = 'feat-sweep-rebase'; HeadRefOid = $tip })

    $eligible = @(Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records)
    Assert-Equal 1 $eligible.Count 'A rebase-merged worktree must be eligible when GitHub proves the merge.'
    Assert-Equal 'feat-sweep-rebase' $eligible[0].Branch 'The eligible worktree must be the rebase-merged one.'

    # No @() around this call either: the function returns ', $eligible', so re-wrapping an empty
    # result yields one element that is itself the empty array.
    $none = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $none.Count 'Without the GitHub records the same worktree must be preserved.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an absent gh reads as "cannot tell", never as "not merged" ------------
$repo = New-TempGitRepo
try {
    # A PATH holding git but not gh. The lookup must report gh-missing and stay unavailable, so the
    # decision falls back to local history instead of treating silence as a verdict.
    $savedPath = $env:PATH
    $env:PATH = (Split-Path -Parent (Get-Command git).Source)
    try {
        $result = Get-MergedPullRequestRecords -RepoRoot $repo -BaseBranch 'main' -TimeoutSeconds 5
        Assert-True (-not $result.Available) 'A missing gh must not be available.'
        Assert-Equal 'gh-missing' $result.Reason 'A missing gh must say so.'
        Assert-Equal 0 @($result.Records).Count 'A missing gh must yield no records.'
    } finally {
        $env:PATH = $savedPath
    }

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo) 'With no upstream the local ref name is the base branch name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged branch is merged when GitHub says so ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-merged' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    # Sanity: the base carries the patch under a different SHA, and no merge commit exists, so the
    # three local signals cannot prove this merge however hard they look.
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged')) `
        'Local git alone must not prove a rebase merge.'

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 1; HeadRefName = 'feat-rebase-merged'; HeadRefOid = $tip }) } }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghSays) `
        'A merged pull request whose head SHA the ref log holds must prove the merge.'

    $ghCannotTell = { [pscustomobject]@{ Available = $false; Reason = 'gh-missing'; Records = @() } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghCannotTell)) `
        'An unavailable lookup must keep the worktree.'

    # A recycled branch name: same name, a head SHA this branch never pointed at.
    $ghWrongSha = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 2; HeadRefName = 'feat-rebase-merged'; HeadRefOid = ('0' * 40) }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghWrongSha)) `
        'A pull request the ref log never recorded must not prove the merge.'

    # A merge-commit merge must never spend a network call: this lookup throws if it is consulted.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-local-proof' | Out-Null
    $ghMustNotRun = { throw 'The lookup must not run when local git already proved the merge.' }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-local-proof' -MergedPullRequestLookup $ghMustNotRun) `
        'A merge-commit merge must be proved locally, without asking GitHub.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted branch is never merged, whatever GitHub says -------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-pr' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 3; HeadRefName = 'feat-unstarted-pr'; HeadRefOid = $tip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-unstarted-pr' -MergedPullRequestLookup $ghSays)) `
        'Signal 1 must refuse a branch that never committed, even with a merged pull request.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase merge followed by new work keeps the worktree ----------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-then-work' -RebaseMerge
    $mergedTip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Set-Content -LiteralPath (Join-Path $wtPath 'after.txt') -Value 'later' -Encoding utf8
    Invoke-TestGit $wtPath @('add', '-A') | Out-Null
    Invoke-TestGit $wtPath @('commit', '-m', 'work after the rebase merge') | Out-Null

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 4; HeadRefName = 'feat-rebase-then-work'; HeadRefOid = $mergedTip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-then-work' -MergedPullRequestLookup $ghSays)) `
        'Signal 4 must refuse work made after a rebase merge.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep lists a rebase-merged worktree as eligible ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-sweep-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $records = @([pscustomobject]@{ Number = 5; HeadRefName = 'feat-sweep-rebase'; HeadRefOid = $tip })

    $eligible = @(Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records)
    Assert-Equal 1 $eligible.Count 'A rebase-merged worktree must be eligible when GitHub proves the merge.'
    Assert-Equal 'feat-sweep-rebase' $eligible[0].Branch 'The eligible worktree must be the rebase-merged one.'

    # No @() around this call either: the function returns ', $eligible', so re-wrapping an empty
    # result yields one element that is itself the empty array.
    $none = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $none.Count 'Without the GitHub records the same worktree must be preserved.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the GitHub query base follows the base actually being decided against ---
# Resolve-BaseBranchName used to default to 'main' whatever base the caller chose, so a run with
# -MainRef release asked GitHub for pull requests merged into main. One of those could then satisfy
# the SHA lookup and allow a removal, though the branch never reached release.
$repo = New-TempGitRepo
try {
    Invoke-TestGit $repo @('branch', 'release') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.release.merge', 'refs/heads/release-line') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.release.remote', 'origin') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.main.merge', 'refs/heads/main') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.main.remote', 'origin') | Out-Null
    Invoke-TestGit $repo @('remote', 'add', 'origin', 'https://example.invalid/repo.git') | Out-Null

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'main') 'main must map to its own remote branch.'
    Assert-Equal 'release-line' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'release') `
        'A non-main local base must map to ITS remote branch, not to main.'

    # The base a run decides against is often the remote-tracking ref, so that form must resolve too.
    Assert-Equal 'release-line' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'origin/release') `
        'A remote-tracking base must resolve through its remote name, not by splitting on the slash.'

    # A base with no configuration at all still answers with something usable.
    Assert-Equal 'topic' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'topic') `
        'An unconfigured base must fall back to its own name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged leftover branch is reported ---------------------------
# Get-LeftoverMergedBranches seeded its candidates from `git branch --merged`, which never lists a
# rebase-merged branch, and it called the decision without the run's GitHub records. So the one
# leftover that a rebase merge produces was invisible.
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-leftover-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    # The state a half-finished removal leaves: the worktree is pruned, the branch survives.
    Invoke-TestGit $repo @('worktree', 'remove', '--force', $wtPath) | Out-Null

    $records = @([pscustomobject]@{ Number = 7; HeadRefName = 'feat-leftover-rebase'; HeadRefOid = $tip })

    $leftover = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records
    Assert-Equal 1 $leftover.Count 'A rebase-merged branch whose worktree is gone must be reported.'
    Assert-Equal 'feat-leftover-rebase' $leftover[0] 'The reported branch must be the rebase-merged one.'

    $withoutRecords = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $withoutRecords.Count 'Without the GitHub records the same branch must stay unreported.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted leftover branch is still never reported -------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-leftover-fresh' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Invoke-TestGit $repo @('worktree', 'remove', '--force', $wtPath) | Out-Null

    $records = @([pscustomobject]@{ Number = 8; HeadRefName = 'feat-leftover-fresh'; HeadRefOid = $tip })
    $leftover = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records
    Assert-Equal 0 $leftover.Count 'A branch nobody committed on must never be reported as leftover.'
} finally {
    Remove-TempTree $repo
}


# --- Test: Get-BaseRefAtBranchCreation ---------------------------------------------------
# The branch's oldest ref-log entry carries its creation time. The base ref's own ref log carries
# every position it has held. The answer is the newest base position STRICTLY EARLIER than that
# creation time. Anything it cannot establish must come back as $null, so the caller skips
# signal 5 instead of refusing on a guess.
$repo = New-TempGitRepo
try {
    # main's position before anything else happens. The sleep makes that entry strictly earlier
    # than the branch created next; without it every stamp lands in the same second and the
    # function correctly reports that it cannot answer.
    $mainBefore = ((Invoke-TestGit $repo @('rev-parse', 'main')) -join '').Trim()
    Start-Sleep -Seconds 2

    Add-TestWorktree -RepoDir $repo -BranchName 'feat-base-probe' | Out-Null

    $resolved = Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'main'
    Assert-True ($resolved -eq $mainBefore) 'The base position must be where main stood before the branch was created, not after.'

    # The merge that Add-TestWorktree performed came after the branch existed, so it must NOT be
    # the answer. This is the collision that '<base>@{<time>}' gets wrong.
    $mainAfter = ((Invoke-TestGit $repo @('rev-parse', 'main')) -join '').Trim()
    Assert-True ($resolved -ne $mainAfter) 'A base move that happened after the branch was created must never be the base position.'

    # Signal 5's allow path, on the same fixture. The base position resolves, so signal 5 really
    # runs, and the branch's own commit was not reachable from that position. Signal 5 may only
    # refuse, so it must let this through. Without this assertion a signal 5 that refuses
    # everything it can resolve would still pass the suite.
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'main') `
        'A resolved base at creation must allow a proof that was not already reachable from that base.'

    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'no-such-branch' -MainRef 'main')) 'An unknown branch must resolve to $null.'
    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'no-such-ref')) 'An unknown base ref must resolve to $null.'
} finally {
    Remove-TempTree $repo
}

# The case of a base ref with no ref log at all is covered further down, by the fixture that
# proves an unresolvable creation position skips signal 5. That one asserts the same $null and
# then asserts what the caller does with it, so a separate fixture here would only repeat setup.


# --- Test: a forged commit subject on a never-committed branch (backlog 096) --------------
# The shape backlog 095 could not refuse. GIT_REFLOG_ACTION=commit on a fast-forward onto an
# already-merged tip satisfies signal 1 with text and signal 2 with real history. The branch holds
# no commit, so signal 3 has nothing stranded to refuse and signal 4 finds no later work.
# Signal 5 is what refuses it: the proof SHA was already in the base before this branch existed.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-donor' | Out-Null
    $donorTip = ((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-ff-donor')) -join '').Trim()

    # The donor must already be merged, and main must already point past it, BEFORE the victim
    # branch is created. That ordering is the whole point of signal 5.
    $mergeParents = (Invoke-TestGit $repo @('rev-list', '--min-parents=2', '--format=%P', 'main')) -join ' '
    Assert-True ($mergeParents -match [regex]::Escape($donorTip)) 'Sanity check: the donor branch must already be a merged non-first parent.'

    # Two seconds of separation, so the victim's creation stamp is strictly later than main's move.
    # Ref-log stamps have one-second resolution. Without this the fixture can build everything
    # inside one second, Get-BaseRefAtBranchCreation correctly reports that it cannot answer, and
    # signal 5 is skipped -- so the test would fail while proving nothing.
    Start-Sleep -Seconds 2

    $victimPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-victim' -NoCommits -BaseRef 'main^'
    Invoke-TestGitWithReflogAction -RepoDir $victimPath -Action 'commit' -GitArgs @('merge', '--ff-only', $donorTip) | Out-Null

    $entries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-ff-victim')) -join "`n"
    Assert-True ($entries -match '(?m)commit: Fast-forward') 'Sanity check: the fast-forward must really have written a forged "commit:" subject.'

    # Signal 5 must actually be engaged. Without this the test could go green because the function
    # could not resolve a base position, which proves nothing about the forgery.
    Assert-True ($null -ne (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-ff-victim' -MainRef 'main')) 'Sanity check: signal 5 must have a base position to judge against, or this test proves nothing.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-ff-victim' -MainRef 'main')) 'A forged "commit:" subject on a never-committed branch must not make it eligible.'

    # Kept from the backlog 095 block this test replaces. It bounds what the refusal costs: the
    # branch strands nothing, so refusing it loses no work. Signal 5 buys safety here for free.
    $stranded = Get-StrandedCommits -RepoRoot $repo -Branch 'feat-ff-victim' -Shas @(((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-ff-victim')) -join '').Trim())
    Assert-Equal 0 $stranded.Count 'The forged case must strand nothing, which is what bounds it.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $victimPath))) 'A worktree whose only proof is work the base already had must never be eligible.'
} finally {
    Remove-TempTree $repo
}


# --- Test: an unresolvable creation position skips signal 5, it never refuses -------------
# Signal 5 may only refuse. When Get-BaseRefAtBranchCreation cannot answer, the decision must be
# exactly what the other four signals say.
#
# The base ref log is removed to make that state exact. Relying on the fixture building inside one
# second would work on a fast machine and break on a loaded one, because ref-log stamps have
# one-second resolution. Get-BaseRefAtBranchCreation is the only function that reads the base ref
# log, so removing it changes nothing else in the decision.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-skipped' | Out-Null
    Remove-Item -LiteralPath (Join-Path $repo '.git/logs/refs/heads/main') -Force
    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-skipped' -MainRef 'main')) 'Sanity check: a base ref with no ref log must give no usable base position.'
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-skipped' -MainRef 'main') 'A skipped signal 5 must leave the decision to the other four signals.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a real sweep writes exactly one outcome line per worktree it removes ---
# The source scans elsewhere check call sites. This checks the thing itself: two merged worktrees,
# one sweep, two detached watchers running at the same time, and afterwards one outcome line each.
#
# It covers two defects at once. The sweep used to write "Merged-cleanup requested removal" to the
# outcome log and then hand over to a watcher that wrote "Removed.", which is two lines for one
# attempt. And the watcher's temp copy had no reliable logger, so two watchers colliding on the
# same file could drop a line entirely.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $first = Add-TestWorktree -RepoDir $repo -BranchName 'feat-outcome-one'
    $second = Add-TestWorktree -RepoDir $repo -BranchName 'feat-outcome-two'

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $first) "The first worktree must be removed. Stderr: $($res.Stderr)"
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $second) "The second worktree must be removed. Stderr: $($res.Stderr)"

    # The watcher writes its outcome after the folder is gone, so waiting on the folder is not
    # waiting on the line. Poll until both leaves have one, then read once.
    $outcomeLog = Join-Path $repo '.claude\worktrees\worktree-removal.log'
    $leaves = @((Split-Path -Leaf $first), (Split-Path -Leaf $second))
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $outcomeLines = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $outcomeLog) {
            $outcomeLines = @(Get-Content -LiteralPath $outcomeLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
            $covered = @($leaves | Where-Object { $leaf = $_; @($outcomeLines | Where-Object { $_ -match ('\s' + [regex]::Escape($leaf) + '\s') }).Count -ge 1 })
            if ($covered.Count -eq $leaves.Count) { break }
        }
        Start-Sleep -Milliseconds 250
    }

    Assert-True (Test-Path -LiteralPath $outcomeLog) 'The sweep must write an outcome log.'
    foreach ($leaf in $leaves) {
        $mine = @($outcomeLines | Where-Object { $_ -match ('\s' + [regex]::Escape($leaf) + '\s') })
        Assert-Equal 1 $mine.Count "'$leaf' must have exactly one outcome line, got $($mine.Count): $($mine -join ' || ')"
        Assert-True ($mine[0] -match '\sRemoved\.$') "'$leaf' must end with the Removed. outcome, got '$($mine[0])'"
    }

    # Every line in this file is an outcome. Anything else belongs in the diagnostics file beside it.
    foreach ($line in $outcomeLines) {
        Assert-True ($line -match '\s(Removed\.|Kept: |Failed: )') `
            "The outcome log may hold only outcomes, found '$line'"
    }

    # And the diagnostics really did land somewhere, so the split is not just an empty promise.
    $diagnosticsLog = Join-Path $repo '.claude\worktrees\worktree-removal-diagnostics.log'
    Assert-True (Test-Path -LiteralPath $diagnosticsLog) 'The diagnostics log must sit beside the outcome log.'
    Assert-True ((Get-Content -Raw -LiteralPath $diagnosticsLog) -match 'Merged-cleanup requested removal') `
        'The hand-over line belongs in diagnostics, not in the outcome log.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a kept worktree's outcome line carries the guard's own reason ------------------
# A source scan can show that a call site looks right. It cannot show that the log a human reads
# holds the reason that applied. Both writers used to log one fixed sentence, "Kept: the plan was
# never implemented.", whatever the verdict was, and that sentence sent an investigation to the
# wrong backlog item. So this drives the real sweep and reads the real log.

# A repo whose worktree manifests are ignored, so writing one does not make the worktree dirty.
# The plan gate runs before the clean check, but the removal path after it needs a clean tree.
function New-PlanGuardRepo {
    param([string] $ScriptsSource)

    $repo = New-WorktreeToolingRepo -ScriptsSource $ScriptsSource
    Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value 'scripts/.env.worktree' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs\superpowers\plans') -Force | Out-Null
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'ignore worktree manifests') | Out-Null
    return $repo
}

# Seeds the backlog item a worktree's own name points at, and records a different number in the
# worktree's manifest. That is the shape a renumber leaves behind.
#
# The item is committed on main because the sweep reads it from the resolved base. The plan file
# is written to disk only: the guard resolves it against the main checkout, not against a ref.
function Set-PlanGuardFixture {
    param(
        [string] $RepoDir,
        [string] $WorktreePath,
        [string] $RecordedNumber,
        [string] $ItemNumber,
        [string] $ItemFolder = 'backlog',
        [string] $PlanBullet,
        [string] $PlanBody
    )

    $slug = (Split-Path -Leaf $WorktreePath).Substring(3)
    $itemDir = Join-Path $RepoDir $ItemFolder
    New-Item -ItemType Directory -Path $itemDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $itemDir "$ItemNumber-$slug.md") `
        -Value "# $ItemNumber - $slug`n`n- Plan: $PlanBullet" -Encoding utf8

    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $RepoDir "docs\superpowers\plans\plan-$ItemNumber.md") -Value $PlanBody -Encoding utf8
    }

    Invoke-TestGit $RepoDir @('add', '-A') | Out-Null
    Invoke-TestGit $RepoDir @('commit', '-m', "seed backlog item $ItemNumber") | Out-Null

    $scriptsDirInWorktree = Join-Path $WorktreePath 'scripts'
    New-Item -ItemType Directory -Path $scriptsDirInWorktree -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scriptsDirInWorktree '.env.worktree') `
        -Value "AHKFLOW_BACKLOG_ITEM=$RecordedNumber" -Encoding utf8
}

# Reads the outcome lines for one worktree leaf, waiting until at least one exists.
function Get-OutcomeLinesFor {
    param([string] $RepoDir, [string] $Leaf, [int] $TimeoutMs = 20000)

    $log = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $mine = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $log) {
            $mine = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue |
                Where-Object { $_ -match ('\s' + [regex]::Escape($Leaf) + '\s') })
            if ($mine.Count -ge 1) { break }
        }
        Start-Sleep -Milliseconds 250
    }
    return , $mine
}

$repo = New-PlanGuardRepo -ScriptsSource $scriptsDir
try {
    # Two kept worktrees, two different refusal reasons, one sweep.
    $outside = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plan-outside'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $outside -RecordedNumber '118' -ItemNumber '140' `
        -PlanBullet '<path, or "none - reason">'

    $untouched = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plan-untouched'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $untouched -RecordedNumber '118' -ItemNumber '141' `
        -PlanBullet '`docs/superpowers/plans/plan-141.md`' -PlanBody "- [ ] Step 1`n- [ ] Step 2"

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')

    $outsideLeaf = Split-Path -Leaf $outside
    $outsideLines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $outsideLeaf
    Assert-Equal 1 $outsideLines.Count "'$outsideLeaf' must have exactly one outcome line, got: $($outsideLines -join ' || '). Stderr: $($res.Stderr)"
    Assert-True ($outsideLines[0] -match 'Kept: backlog item 140 names a plan outside docs/superpowers/plans') `
        "The kept line must carry the guard's own reason, got '$($outsideLines[0])'"
    Assert-True ($outsideLines[0] -match 'records item 118') `
        "The kept line must name the stale recorded number too, got '$($outsideLines[0])'"

    $untouchedLeaf = Split-Path -Leaf $untouched
    $untouchedLines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $untouchedLeaf
    Assert-Equal 1 $untouchedLines.Count "'$untouchedLeaf' must have exactly one outcome line, got: $($untouchedLines -join ' || ')"
    Assert-True ($untouchedLines[0] -match 'the plan for item 141 was never implemented \(2 steps, none ticked\)') `
        "A second refusal must read differently, got '$($untouchedLines[0])'"

    # The two reasons must not collapse back into one sentence.
    Assert-True ($outsideLines[0] -ne $untouchedLines[0]) 'Two different refusals must produce two different lines'
    foreach ($line in @($outsideLines[0], $untouchedLines[0])) {
        Assert-True (-not ($line -match 'Kept: the plan was never implemented\.')) `
            "The old fixed sentence must be gone, got '$line'"
    }

    Assert-True (Test-Path -LiteralPath $outside) 'A refused worktree stays on disk'
    Assert-True (Test-Path -LiteralPath $untouched) 'A refused worktree stays on disk'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep removes a worktree whose recorded number is stale --------------------
# This is the worktree that started backlog 122: its manifest records somebody else's open item,
# its own item shipped into backlog/done with an implemented plan, and every sweep refused it.
# Nothing edits the manifest -- the guard stops believing it instead.
$repo = New-PlanGuardRepo -ScriptsSource $scriptsDir
try {
    $stale = Add-TestWorktree -RepoDir $repo -BranchName 'feat-renumbered'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $stale -RecordedNumber '118' -ItemNumber '120' `
        -ItemFolder 'backlog\done' -PlanBullet '`docs/superpowers/plans/plan-120.md`' -PlanBody "- [x] Step 1"

    # The item the stale number names: still open, and its pointer is the unfilled template. Judging
    # it refuses, so a removal here proves the guard judged the other one.
    Set-Content -LiteralPath (Join-Path $repo 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: <path, or ""none - reason"">" -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed the item the stale number names') | Out-Null

    $manifestPath = Join-Path $stale 'scripts\.env.worktree'
    $manifestBefore = Get-Content -Raw -LiteralPath $manifestPath

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $stale) `
        "A worktree whose own item shipped must be removed. Stderr: $($res.Stderr)"

    # The manifest is never repaired. Reading it correctly is the whole fix.
    Assert-True (-not (Test-Path -LiteralPath $manifestPath)) 'The worktree folder is gone, manifest and all'
    Assert-True ($manifestBefore -match 'AHKFLOW_BACKLOG_ITEM=118') 'The fixture really did record the stale number'

    $leaf = Split-Path -Leaf $stale
    $lines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $leaf
    Assert-Equal 1 $lines.Count "'$leaf' must have exactly one outcome line, got: $($lines -join ' || ')"
    Assert-True ($lines[0] -match '\sRemoved\.$') "The outcome line must be the normal removal line, got '$($lines[0])'"

    # The disagreement is a diagnostic, never an outcome. A human who wonders why 118 was in the
    # manifest can find both numbers there.
    $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $repo '.claude\worktrees\worktree-removal-diagnostics.log')
    Assert-True ($diagnostics -match 'Plan guard judged backlog item 120') `
        "The diagnostics must name the item that was judged. Log: $diagnostics"
    Assert-True ($diagnostics -match 'records item 118') `
        "The diagnostics must name the recorded number too. Log: $diagnostics"
} finally {
    Remove-TempTree $repo
}

# A handover that cannot start must still say what happened to the worktree.
$sweepSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')
Assert-True ($sweepSource -match '(?m)^function Write-SweepOutcome \{') 'cleanup-merged-worktrees.ps1 must define Write-SweepOutcome'
Assert-True ($sweepSource -match "Failed: the removal script could not be found\.") 'A missing removal script writes a Failed outcome'
Assert-True ($sweepSource -match "Failed: the removal script could not be started\.") 'A spawn failure writes a Failed outcome'

Write-Host 'Worktree merged-cleanup tests passed.'
