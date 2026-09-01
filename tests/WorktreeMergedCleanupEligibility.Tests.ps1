#Requires -Version 7.0
# Eligibility and the WorktreeCreate hook. Backlog 126 split these out of
# WorktreeMergedCleanup.Tests.ps1, which took 125.6 seconds and set the floor for every parallel
# run. The harness they share lives in WorktreeMergedCleanup.Common.ps1.
#
# Run it by hand with:  pwsh ./tests/WorktreeMergedCleanupEligibility.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WorktreeMergedCleanup.Common.ps1')

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



Write-Host 'Worktree merged-cleanup eligibility tests passed.'
