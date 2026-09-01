# 7.0, not 5.1. This suite dot-sources scripts/cleanup-merged-worktrees.ps1 and calls it in
# process. That script makes bare native git calls, and under Windows PowerShell a native
# command's stderr becomes an error record that this file's 'Stop' preference turns terminating --
# so a git error the sweep handles on purpose ends the suite instead. Making those nine call sites
# host-independent is tracked separately; until then the floor here says what it really is.
# scripts/run-powershell-suites.ps1 runs every suite under pwsh, so nothing changes in CI.
#Requires -Version 7.0

# Pure functions and the merge proof. Backlog 126 split this file into three, because at 2149
# lines and 125.6 seconds it set the floor for every parallel run. Its two siblings are
# WorktreeMergedCleanupEligibility.Tests.ps1 and WorktreeMergedCleanupSweep.Tests.ps1, and the
# harness all three share is WorktreeMergedCleanup.Common.ps1.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WorktreeMergedCleanup.Common.ps1')

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


Write-Host 'Worktree merged-cleanup pure-function and merge-proof tests passed.'
