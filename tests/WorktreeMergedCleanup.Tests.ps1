#Requires -Version 5.1

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

# Adds a linked worktree on a new branch off main (merged + clean by default).
# -Unmerged adds a commit not in main; -Dirty leaves an uncommitted change.
function Add-TestWorktree {
    param(
        [string] $RepoDir,
        [string] $BranchName,
        [switch] $Unmerged,
        [switch] $Dirty
    )

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null

    if ($Unmerged) {
        Set-Content -LiteralPath (Join-Path $wtPath 'extra.txt') -Value 'unmerged' -Encoding utf8
        Invoke-TestGit $wtPath @('add', '-A') | Out-Null
        Invoke-TestGit $wtPath @('commit', '-m', "work on $BranchName") | Out-Null
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

Write-Host 'Worktree merged-cleanup tests passed.'
