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

# This suite spawns new-worktree.ps1 inside a throwaway repository that holds none of this
# project's real worktrees. Without this variable, new-worktree.ps1's orphan Docker sweep would
# read every real checkout's running container as an orphan and remove it.
$env:AHKFLOW_SKIP_ORPHAN_PRUNE = '1'

. (Join-Path $PSScriptRoot 'WorktreeMergedCleanup.Common.ps1')

# A failed run must not leave the seed repositories in the temp folder. Backlog 201.
trap { Remove-TempGitRepoSeeds -NoCheck; break }

# --- Test: eligibility matrix -------------------------------------------------
$repo = New-TempGitRepo
try {
    $cleanPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-clean'
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty' -Dirty | Out-Null
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-unmerged' -Unmerged | Out-Null
    # Backlog 060: two brand-new worktrees must be able to exist at the same time. Both branches
    # point at main's tip, so both look merged; neither is finished work. The second one also
    # catches up with main by fast-forward and still holds no work of its own.
    $freshPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-one' -NoCommits
    $freshTwoPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-two' -NoCommits
    Invoke-TestGit $freshTwoPath @('merge', '--ff-only', 'main') | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-Equal 1 $eligible.Count 'Only the merged+clean worktree should be eligible.'
    Assert-True ($keys -contains (ConvertTo-Key $cleanPath)) 'The merged+clean worktree must be eligible.'
    Assert-True (-not ($keys -contains (ConvertTo-Key $freshPath))) 'A worktree with no commits of its own must never be eligible.'
    Assert-True (-not ($keys -contains (ConvertTo-Key $freshTwoPath))) 'A worktree fast-forwarded to main without its own commits must never be eligible.'
    Assert-Equal 'feat-clean' $eligible[0].Branch 'Eligible branch short name should be feat-clean.'
    $mainKey = ConvertTo-Key $repo
    Assert-True (-not ($keys -contains $mainKey)) 'The main checkout must never be eligible.'

    # ExcludePath protects the worktree this run is about to create/reuse. The matrix above
    # already proved feat-clean eligible, so passing it as -ExcludePath must remove it from the
    # eligible set: a run that is about to create/reuse this exact path can never race its own
    # async removal. Backlog 201 moved this check into the matrix fixture.
    $excluded = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -ExcludePath $cleanPath
    $excludedKeys = @($excluded | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($excludedKeys -contains (ConvertTo-Key $cleanPath))) '-ExcludePath must exclude the target worktree even though it is merged+clean.'

    # Redirected non-interactive runs skip removal without prompting. Backlog 201 moved this run
    # into the matrix fixture. It is report-only, so it changes nothing the checks above read.
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

    Assert-True (Test-Path -LiteralPath $cleanPath) 'Non-interactive cleanup without -Cleanup must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-clean')) -join "`n"
    Assert-True ($branches -match 'feat-clean') 'Non-interactive cleanup without -Cleanup must not delete the eligible branch.'
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
#
# Main is never eligible anyway: when the exclusion fails, the merged check refuses main by
# signal 2, and the sweep writes a 'Kept:' line for it to the outcome log under -RepoRoot. So
# the check that can fail is that the log holds no line for the main checkout, whose folder is
# named 'repo'. A log line reads '<date> <time>  <worktree leaf>  <message>'. Backlog 201.
#
# The second call proves -MainRef 'refs/heads/main' excludes main the same way -MainRef 'main'
# does. $wt.Branch is always a short name, so a naive string compare against an unresolved
# 'refs/heads/main' never matches.
$repo = New-TempGitRepo
try {
    $otherPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-other'
    $outcomeLog = Join-Path (Join-Path (Join-Path $otherPath '.claude') 'worktrees') 'worktree-removal.log'

    foreach ($mainRef in @('main', 'refs/heads/main')) {
        Remove-Item -LiteralPath $outcomeLog -Force -ErrorAction SilentlyContinue
        $eligible = Get-EligibleMergedWorktrees -RepoRoot $otherPath -MainRef $mainRef
        $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
        Assert-True (-not ($keys -contains (ConvertTo-Key $repo))) "The main-ref worktree must never be eligible, even when `$RepoRoot is a different (linked) worktree. -MainRef '$mainRef'."
        $mainLines = @(if (Test-Path -LiteralPath $outcomeLog) { Get-Content -LiteralPath $outcomeLog | Where-Object { $_ -match '^\S+ \S+  repo  ' } })
        Assert-Equal 0 $mainLines.Count "The main-ref exclusion must skip the main checkout before the merged check, so the log has no line for it. -MainRef '$mainRef'. Lines: $($mainLines -join ' | ')"
    }
} finally {
    Remove-TempTree $repo
}

# --- Test: hook path keeps stdout to exactly the new worktree path -------------

$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    # An eligible (merged + clean) worktree so cleanup has something to remove during the run.
    $eligiblePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-eligible'

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
    # This repo carries the removal script, so a hook that wrongly cleaned would really delete.
    Assert-True (Test-Path -LiteralPath $eligiblePath) 'Hook context must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-eligible')) -join "`n"
    Assert-True ($branches -match 'feat-eligible') 'Hook context must not delete the eligible branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: config false -> hook report-only (no hint), direct skip -------------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-cfgfalse'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null

    # Only the direct child runs here. It is the only end-to-end proof of the Skip branch. The hook
    # side of config false is covered by the resolver row in WorktreeMergedCleanup.Tests.ps1, and
    # the hint branch by the non-interactive case above. Backlog 201.
    $direct = Invoke-CleanupChild -RepoDir $repo
    Assert-True (-not ($direct.Stderr -match 'cleanup: removing')) 'Config-false direct call must skip.'
    Assert-True (Test-Path -LiteralPath $kept) 'Config-false direct call must leave the worktree folder.'
} finally {
    Remove-TempTree $repo
}

# --- Test: explicit override cleans over invalid config, without a misleading warning ---
# The invalid-config warning must fire only when the resolved action is report-only. An
# explicit -Cleanup that legitimately cleans must NOT claim report-only. Hook env enable takes the
# same warning placement, and the env-overrides-config case below proves it cleans end to end.
foreach ($override in @(
        @{ Args = @('-Cleanup'); Env = @{}; Label = '-Cleanup' }
    )) {
    $repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
    try {
        $target = Add-TestWorktree -RepoDir $repo -BranchName "feat-invalid-$([guid]::NewGuid().ToString('N').Substring(0,6))"
        Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null

        # Invalid config fails closed to report-only with a warning. This hook run removes
        # nothing, so the override run below still finds the worktree. Backlog 201 moved it here.
        $invalid = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook')
        Assert-Equal 0 $invalid.ExitCode "Invalid config should not crash. Stderr: $($invalid.Stderr)"
        Assert-True ($invalid.Stderr -match 'invalid or duplicated') 'Invalid config must warn.'
        Assert-True ($invalid.Stderr -match 'git config --local --unset-all ahkflow\.worktreeCleanup') 'Warning must include the repair command.'
        Assert-True (-not ($invalid.Stderr -match 'cleanup: removing')) 'Invalid config must not remove (fail closed).'
        Assert-True (Test-Path -LiteralPath $target) 'Invalid config must leave the worktree folder.'

        $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs $override.Args -EnvVars $override.Env
        Assert-True (-not ($res.Stderr -match 'treating as report-only')) "$($override.Label) over invalid config must not print a report-only warning. Stderr: $($res.Stderr)"
        Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "$($override.Label) must clean over invalid config. Stderr: $($res.Stderr)"
    } finally {
        Remove-TempTree $repo
    }
}

# --- Test: config true cleans (hook) -------------------------------------------
# The resolver returns Clean for config true with or without -IsHook, and the resolver rows in
# WorktreeMergedCleanup.Tests.ps1 pin both. The Sweep suite proves the direct removal path.
foreach ($mode in @(@{ Args = @('-IsHook'); Label = 'hook' })) {
    $repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
    try {
        $target = Add-TestWorktree -RepoDir $repo -BranchName "feat-cfgtrue-$($mode.Label)"
        Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null

        # env '0' + config true -> report-only in hook context, so nothing is removed and the run
        # below still finds the worktree. Backlog 201 moved this check into this fixture.
        $disabled = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook') -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '0' }
        Assert-True (-not ($disabled.Stderr -match 'cleanup: removing')) "env '0' must override config true in hook context. Stderr: $($disabled.Stderr)"
        Assert-True (Test-Path -LiteralPath $target) "env '0' must leave the worktree folder even with config true."

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



# --- Test: a merged worktree kept for uncommitted changes is named, not dropped (backlog 147) ---
# The two skip paths above this one in Get-EligibleMergedWorktrees both write a stderr line and a
# Kept: log line. Without them a reader cannot tell a worktree the sweep kept from one it never saw.
$repo = New-TempGitRepo
try {
    $dirtyPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty-reported' -Dirty

    $res = Invoke-CleanupChild -RepoDir $repo
    # A dirty worktree is the only one here, so nothing is eligible. Backlog 188 merged the
    # no-eligible case into this one. The 'unset' check is load-bearing: a preference written on
    # this path would otherwise go unseen, because persistence can happen outside the prompt.
    Assert-True ($res.Stderr -match 'no merged worktrees eligible') 'With no eligible worktrees, cleanup must report none.'
    Assert-Equal 'unset' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No eligible worktrees must not persist any preference.'
    Assert-True ($res.Stderr -match 'because the worktree has uncommitted changes \(dirty\.txt\)\.') `
        "The sweep must name the dirty worktree on stderr, got: $($res.Stderr)"
    # The path, not just the reason. Naming the wrong worktree would otherwise pass every
    # assertion here, and the whole point of the line is telling one worktree from another.
    Assert-True ($res.Stderr -match [regex]::Escape($dirtyPath)) `
        "The stderr line must carry the worktree path, got: $($res.Stderr)"
    # The cure has to be safe for the state that produced the message. The fixture's dirty.txt is
    # untracked, and 'git diff' reports neither untracked nor staged work, so a reader following a
    # bare 'git add' would stage real work while believing they were clearing a stale stat entry.
    Assert-True ($res.Stderr -match 'run git update-index --refresh') `
        "The stderr line must name the safe cure, got: $($res.Stderr)"
    Assert-True (-not ($res.Stderr -match 'git add clears')) `
        "The stderr line must not tell a reader to run git add, got: $($res.Stderr)"
    Assert-True (Test-Path -LiteralPath $dirtyPath) 'Reporting must not remove the dirty worktree'

    $log = Join-Path $repo '.claude\worktrees\worktree-removal.log'
    Assert-True (Test-Path -LiteralPath $log) 'Keeping a dirty worktree must write an outcome line'
    $outcome = @(Get-Content -LiteralPath $log)
    Assert-Equal 1 $outcome.Count "One dirty worktree writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match [regex]::Escape((Split-Path -Leaf $dirtyPath))) `
        "The outcome line must name the worktree, got '$($outcome[0])'"
    Assert-True ($outcome[0] -match ('Kept: the worktree has uncommitted changes \(dirty\.txt\)\. ' +
            'Run git status there\. If git diff and git diff --cached are both empty and nothing ' +
            'is untracked, run git update-index --refresh\.$')) `
        "Expected the dirty line, got '$($outcome[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: more than one record is counted, and the first entry is named (backlog 147) ---
# Without this case a message that only ever named one entry would pass every assertion above.
$repo = New-TempGitRepo
try {
    $dirtyPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty-many' -Dirty
    Set-Content -LiteralPath (Join-Path $dirtyPath 'extra.txt') -Value 'also uncommitted' -Encoding utf8

    Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' | Out-Null

    $outcome = @(Get-Content -LiteralPath (Join-Path $repo '.claude\worktrees\worktree-removal.log'))
    Assert-Equal 1 $outcome.Count "One dirty worktree writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match 'uncommitted changes \(2 changes, first entry dirty\.txt\)') `
        "Two records must be counted and the first entry named, got '$($outcome[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: a rename is one record holding two paths, so the count says changes (backlog 147) ---
# `git status --porcelain` writes a rename as a single 'R  old -> new' record. Calling that one
# entry a path made the count wrong and put an arrow where a file name belonged.
$repo = New-TempGitRepo
try {
    $renamePath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty-rename'
    # A staged rename plus one untracked file: two records, four paths named between them.
    # Porcelain lists the staged record before the untracked one, so the rename is entry one.
    Invoke-TestGit $renamePath @('mv', 'work.txt', 'renamed.txt') | Out-Null
    Set-Content -LiteralPath (Join-Path $renamePath 'extra.txt') -Value 'also uncommitted' -Encoding utf8

    Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' | Out-Null

    $outcome = @(Get-Content -LiteralPath (Join-Path $repo '.claude\worktrees\worktree-removal.log'))
    Assert-Equal 1 $outcome.Count "One dirty worktree writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match 'uncommitted changes \(2 changes, first entry work\.txt -> renamed\.txt\)') `
        "A rename record must be reported as one change, got '$($outcome[0])'"
    Assert-True (-not ($outcome[0] -match 'paths')) `
        "A rename record holds two paths, so the count must not claim paths, got '$($outcome[0])'"
} finally {
    Remove-TempTree $repo
}

Remove-TempGitRepoSeeds
Write-Host 'Worktree merged-cleanup eligibility tests passed.'
