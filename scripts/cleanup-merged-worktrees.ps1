#Requires -Version 5.1
<#
.SYNOPSIS
    Detects worktrees whose branch is already merged into main and removes the finished
    (clean) ones when the per-repo preference or an explicit opt-in says so.
.DESCRIPTION
    Invoked by new-worktree.ps1 before it creates a new worktree, and runnable on its own.
    Precedence: -Cleanup flag > AHKFLOW_WORKTREE_CLEANUP env var (hook context only) >
    git config --local ahkflow.worktreeCleanup (true/false) > ask-once on an interactive
    console (unset) > report-only. Invalid/duplicated config fails closed to report-only.
    In hook context (-IsHook) all output stays on stderr so the hook's stdout contract is
    preserved; when config is unset it prints the one-liner to enable cleanup.

    With no -MainRef, the base is the remote-tracking branch of local main, fetched first:
    a merge performed on GitHub never advances a local ref. An explicitly passed -MainRef is
    the caller's choice and is used as given, with no fetch.
#>

[CmdletBinding()]
param(
    [string] $RepoRoot,
    [switch] $Cleanup,
    [switch] $IsHook,
    [string] $MainRef = 'main',
    [string] $ExcludePath,
    [int] $FetchTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-log.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-powershell.common.ps1')

# Parses `git worktree list --porcelain` into { Path; Branch; LockReason } records. Branch is the
# short name for a normal worktree, and $null for a detached-HEAD or bare entry.
#
# LockReason is $null when there is no 'locked' line, '' for a bare 'locked', and the text after
# 'locked ' otherwise. The three states are different: '' still means locked.
function ConvertFrom-WorktreePorcelain {
    param([string[]] $Lines)

    $worktrees = @()
    $current = $null
    foreach ($line in $Lines) {
        if ($line -like 'worktree *') {
            if ($current) { $worktrees += $current }
            $current = [pscustomobject]@{
                Path = $line.Substring('worktree '.Length); Branch = $null; LockReason = $null
            }
        } elseif ($current -and ($line -like 'branch refs/heads/*')) {
            $current.Branch = $line.Substring('branch refs/heads/'.Length)
        } elseif ($current -and ($line -eq 'locked')) {
            $current.LockReason = ''
        } elseif ($current -and ($line -like 'locked *')) {
            $current.LockReason = $line.Substring('locked '.Length)
        }
    }
    if ($current) { $worktrees += $current }

    return , $worktrees
}

# Returns the worktrees that are merged into $MainRef AND clean, excluding the main
# checkout, any detached/bare worktree, and $ExcludePath when given. Each item:
# { Path (normalized); Branch }.
function Get-EligibleMergedWorktrees {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $MainRef = 'main',
        [string] $ExcludePath,
        [object[]] $MergedPullRequests
    )

    $repoRootFull = ([System.IO.Path]::GetFullPath($RepoRoot)).TrimEnd('\', '/')
    $excludeFull = if ($ExcludePath) { ([System.IO.Path]::GetFullPath($ExcludePath)).TrimEnd('\', '/') } else { $null }

    # Resolve $MainRef to the local branch short name it denotes, so the main-ref exclusion
    # below matches regardless of the ref form the caller passed ('main' vs 'refs/heads/main').
    # Falls back to the raw value when $MainRef isn't a local branch (e.g. 'origin/main') --
    # then only the repoRootFull path check above can exclude the main checkout.
    $mainBranchShortName = $MainRef
    $mainSymbolicRef = & git -C $RepoRoot rev-parse --symbolic-full-name $MainRef 2>$null
    if ($LASTEXITCODE -eq 0 -and $mainSymbolicRef -like 'refs/heads/*') {
        $mainBranchShortName = $mainSymbolicRef.Substring('refs/heads/'.Length)
    }

    # No `git branch --merged` pre-filter any more. It is ancestry under another name, and it
    # rejected both shapes this sweep now has to judge: a rebase-merged branch, whose replayed
    # commits carry different SHAs, and a merged branch that later gained commits. The shared
    # decision below answers both, so a pre-filter could only overrule it -- wrongly, in the
    # direction that keeps finished worktrees forever.
    $listLines = & git -C $RepoRoot worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr 'cleanup: git worktree list failed; skipping merged-cleanup detection.'
        return , @()
    }

    $eligible = @()
    foreach ($wt in (ConvertFrom-WorktreePorcelain $listLines)) {
        if (-not $wt.Path) { continue }
        $wtFull = ([System.IO.Path]::GetFullPath($wt.Path)).TrimEnd('\', '/')

        if ([string]::Equals($wtFull, $repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        # The worktree this run is about to create/reuse: never sweep it out from under
        # itself. remove-worktree-local-dev.ps1's hook mode spawns a detached watcher and
        # returns immediately, so without this exclusion an async removal could still be
        # renaming/deleting this exact path while new-worktree.ps1 reuses/creates it.
        if ($excludeFull -and [string]::Equals($wtFull, $excludeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not $wt.Branch) { continue }

        # A human locked this worktree on purpose. Nothing here overrides that, and no environment
        # variable clears it -- git itself demands `-f -f`.
        if ($null -ne $wt.LockReason) {
            $lockReason = if ($wt.LockReason) { $wt.LockReason } else { 'no reason given' }
            Write-Stderr "cleanup: skipping locked worktree '$wtFull' ($lockReason)."
            Write-SweepOutcome -RepoRoot $RepoRoot -WorktreePath $wtFull `
                -Message "Kept: the worktree is locked ($(Format-WorktreeLogReason -Text $lockReason))."
            continue
        }
        # Belt-and-suspenders: a branch is always "merged" into itself, so the main-ref
        # worktree would otherwise pass the merged check below. The repoRootFull compare
        # above only excludes it when $RepoRoot happens to resolve to that exact worktree
        # (guaranteed via new-worktree.ps1's Assert-MainCheckout, NOT guaranteed for a
        # standalone run from inside a linked worktree) so this check must not depend on it.
        if ([string]::Equals($wt.Branch, $mainBranchShortName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        # The one merged decision, shared with remove-worktree-local-dev.ps1. It refuses a branch
        # nobody has committed on, a branch whose work only a `git reset` still holds, a branch
        # that gained commits after it merged, and a branch whose only merge proof is work the base
        # already held before the branch existed; it accepts a rebase merge when $MergedPullRequests
        # carries a pull request whose head SHA this branch recorded. Deciding here -- in
        # eligibility, ahead of every setting -- means no flag, env override, or config value can
        # remove one of those, and report-only mode never lists one either.
        if (-not (Test-BranchOwnWorkWasMerged -RepoRoot $RepoRoot -Branch $wt.Branch -MainRef $MainRef -MergedPullRequests $MergedPullRequests)) { continue }

        # A merged branch does not prove the work happened. Plans live in a second private
        # repository the public branch never carries, so a branch can merge holding only its
        # backlog stage stamps while no code was ever written.
        $planVerdict = Test-WorktreePlanWasImplemented -MainCheckout $RepoRoot -ItemNumber (Get-ManifestBacklogItem -WorktreePath $wtFull)
        if (-not $planVerdict.Allow) {
            Write-Stderr "cleanup: keeping '$wtFull' because $($planVerdict.Reason)."
            # The sweep never hands this one over, so the sweep owns its outcome line.
            Write-SweepOutcome -RepoRoot $RepoRoot -WorktreePath $wtFull `
                -Message 'Kept: the plan was never implemented.'
            continue
        }

        $status = & git -C $wtFull status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Stderr "cleanup: status check failed for '$wtFull'; skipping it."
            continue
        }
        if ($status) { continue }

        $eligible += [pscustomobject]@{ Path = $wtFull; Branch = $wt.Branch }
    }

    return , $eligible
}

# Returns the branches a half-finished removal left behind: merged into $MainRef, with their own
# work in it, and with no worktree registered for them any more.
#
# Get-EligibleMergedWorktrees cannot see these. It walks `git worktree list`, and the watcher
# prunes the worktree BEFORE it deletes the branch, so this is the state where the prune succeeded
# and `git branch -d` refused -- which is what happens whenever the merge is still only on the
# remote.
#
# Report only. Nothing here deletes a branch: removal is a separate decision, and the caller's line
# names `git branch -d`, which refuses a branch the base does not really contain.
#
# The rule is the sweep's own, minus the worktree parts:
#   - not $MainRef itself, and not checked out in any worktree -- a branch that still has one is
#     the other leftover, and Get-EligibleMergedWorktrees already reports it;
#   - Test-BranchOwnWorkWasMerged agrees, which is what keeps a branch nobody committed on out of
#     the report, and what accepts a rebase merge when $MergedPullRequests proves one.
#
# Every local branch is a candidate. `git branch --merged $MainRef` used to seed this list, and it
# never lists a rebase-merged branch, because those commits reached the base under different SHAs --
# so the single leftover a rebase merge produces was invisible here. The shared decision is stricter
# than that filter in every direction that matters, so nothing is lost by dropping it.
function Get-LeftoverMergedBranches {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $MainRef = 'main',
        [object[]] $MergedPullRequests
    )

    # Same resolution as Get-EligibleMergedWorktrees: the caller may pass 'main',
    # 'refs/heads/main' or 'origin/main', and only a local branch has a short name to exclude by.
    $mainBranchShortName = $MainRef
    $mainSymbolicRef = & git -C $RepoRoot rev-parse --symbolic-full-name $MainRef 2>$null
    if ($LASTEXITCODE -eq 0 -and $mainSymbolicRef -like 'refs/heads/*') {
        $mainBranchShortName = $mainSymbolicRef.Substring('refs/heads/'.Length)
    }

    $branchNames = & git -C $RepoRoot branch --format='%(refname:short)' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr 'cleanup: git branch listing failed; skipping leftover-branch detection.'
        return , @()
    }

    $listLines = & git -C $RepoRoot worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr 'cleanup: git worktree list failed; skipping leftover-branch detection.'
        return , @()
    }

    # A PowerShell hashtable compares string keys without case, which is how the rest of this
    # script compares branch names.
    $checkedOut = @{}
    foreach ($wt in (ConvertFrom-WorktreePorcelain $listLines)) {
        if ($wt.Branch) { $checkedOut[$wt.Branch] = $true }
    }

    $leftover = @()
    foreach ($name in $branchNames) {
        $branch = ([string] $name).Trim()
        if (-not $branch) { continue }
        if ([string]::Equals($branch, $mainBranchShortName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($checkedOut.ContainsKey($branch)) { continue }
        if (-not (Test-BranchOwnWorkWasMerged -RepoRoot $RepoRoot -Branch $branch -MainRef $MainRef -MergedPullRequests $MergedPullRequests)) { continue }

        $leftover += $branch
    }

    return , $leftover
}

# Reads the per-repo cleanup preference at --local scope only, so a global/system value
# can never enable cleanup here. --bool normalizes true/false/1/0/yes/no. Fail closed:
# a duplicated (multi-line) or non-boolean (git exit 128) value reads as 'invalid'.
# Confirmed git behavior: unset -> exit 1/no output; valid -> exit 0/one line;
# duplicated -> exit 0/multiple lines; bad boolean -> exit 128.
function Get-WorktreeCleanupConfig {
    param([Parameter(Mandatory)][string] $RepoRoot)

    $values = & git -C $RepoRoot config --local --bool --get-all ahkflow.worktreeCleanup 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 1) { return 'unset' }
    if ($exit -ne 0) { return 'invalid' }

    $lines = @($values | Where-Object { $null -ne $_ -and ([string] $_).Trim() -ne '' })
    if ($lines.Count -ne 1) { return 'invalid' }

    switch (([string] $lines[0]).Trim()) {
        'true'  { return 'true' }
        'false' { return 'false' }
        default { return 'invalid' }
    }
}

# Persists the preference at --local scope. Returns $true if git accepted the write,
# $false otherwise (e.g. $RepoRoot is not a git repo). Callers honor the current answer
# for the run even when the write fails; they just warn it was not remembered.
function Set-WorktreeCleanupConfig {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][bool] $Enabled
    )

    $value = if ($Enabled) { 'true' } else { 'false' }
    & git -C $RepoRoot config --local ahkflow.worktreeCleanup $value 2>$null
    return ($LASTEXITCODE -eq 0)
}

# Reads the hook-only env override. 'enable'/'disable'/'none'. Callers must only consult
# this in hook context; a leftover value in a shell must never affect a direct call.
function Get-EnvCleanupOverride {
    $value = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) { return 'none' }

    $v = $value.Trim()
    if ($v -match '^(1|true|yes|y)$') { return 'enable' }
    if ($v -match '^(0|false|no|n)$') { return 'disable' }
    return 'none'
}

# Maps the ask-once console answer to an action. 'y'/'yes' -> clean now and enable;
# anything else (including the empty default) -> skip and disable. Pure; testable
# without Read-Host.
function ConvertFrom-CleanupAnswer {
    param([string] $Answer)

    $yes = ($Answer -match '^\s*(y|yes)\s*$')
    return [pscustomobject]@{ Clean = $yes; Enabled = $yes }
}

# The single source of precedence. Pure: no git, env, or console access -- callers gather
# those and pass them in. Precedence: -Cleanup > hook-only env > config > ask-once/report.
# ShowHint is true only in hook context while config is unset (the hint nudges toward
# setting the config; env is a transient per-run override, so it does not suppress it).
function Resolve-CleanupDecision {
    param(
        [switch] $Cleanup,
        [switch] $IsHook,
        [Parameter(Mandatory)][ValidateSet('true', 'false', 'unset', 'invalid')][string] $ConfigState,
        [ValidateSet('enable', 'disable', 'none')][string] $EnvOverride = 'none',
        [bool] $Interactive,
        [bool] $BaseIsStale
    )

    # A base that could not be refreshed outranks every setting, including an explicit -Cleanup.
    # The remote can lose history, so a stale cache can say "merged" about work the remote dropped.
    # Reporting on it is useful; deleting on it is not recoverable.
    if ($BaseIsStale) { return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = $false } }

    if ($Cleanup) { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }

    if ($IsHook -and $EnvOverride -eq 'enable') { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }
    $envDisable = ($IsHook -and $EnvOverride -eq 'disable')

    if (-not $envDisable -and $ConfigState -eq 'true') { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }
    if ($ConfigState -eq 'false') {
        $action = if ($IsHook) { 'ReportOnly' } else { 'Skip' }
        return [pscustomobject]@{ Action = $action; ShowHint = $false }
    }
    if ($ConfigState -eq 'invalid') { return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = $false } }

    # config unset (or env-disabled over a would-be-true/unset config)
    if ($IsHook) { return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = ($ConfigState -eq 'unset') } }
    if ($Interactive) { return [pscustomobject]@{ Action = 'Prompt'; ShowHint = $false } }
    return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = $false }
}

# Applies the ask-once answer: persists the preference and reports whether removal should
# proceed. Warns on stderr when the write failed but still honors the answer for this run.
# Extracted from the Prompt branch so the persist+warn path is unit-testable without a live
# Read-Host/TTY. Returns [pscustomobject]@{ Clean=<bool>; Persisted=<bool> }.
function Set-CleanupAnswer {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $Answer
    )

    $mapped = ConvertFrom-CleanupAnswer $Answer
    $persisted = Set-WorktreeCleanupConfig -RepoRoot $RepoRoot -Enabled $mapped.Enabled
    if (-not $persisted) {
        Write-Stderr 'cleanup: could not persist your choice to git config; honoring it for this run only.'
    }
    return [pscustomobject]@{ Clean = $mapped.Clean; Persisted = $persisted }
}

# Spawns remove-worktree-local-dev.ps1 (Hook mode) for one worktree. Empty stdin is
# piped in: that script's hook path does an unbounded [Console]::In.ReadToEnd(), which
# would hang if THIS run's own stdin is redirected (agent/CI) and left open.
# The sweep writes the outcome line only for a worktree it decides about itself and never hands
# over. Once remove-worktree-local-dev.ps1 has started, that script owns the line, and a second
# writer here would put two lines on one attempt.
function Write-SweepOutcome {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $WorktreePath,
        [Parameter(Mandatory)][string] $Message
    )

    $logPath = Join-Path $RepoRoot '.claude\worktrees\worktree-removal.log'
    $leaf = Split-Path -Leaf $WorktreePath
    Write-WorktreeLog -LogPath $logPath -Worktree $leaf -Message $Message
}

function Invoke-WorktreeRemoval {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $WorktreePath,
        [string] $MainRef = 'main'
    )

    $removeScript = Join-Path $RepoRoot 'scripts\remove-worktree-local-dev.ps1'
    if (-not (Test-Path -LiteralPath $removeScript)) {
        Write-Stderr "cleanup: remove-worktree-local-dev.ps1 not found; cannot remove '$WorktreePath'."
        Write-SweepOutcome -RepoRoot $RepoRoot -WorktreePath $WorktreePath -Message 'Failed: the removal script could not be found.'
        return
    }

    # Function-scoped, discarded on return. The removal script reports on stderr, and Windows
    # PowerShell 5.1 turns a native command's stderr into a terminating error while the preference
    # is 'Stop' -- which turned every removal into "removal failed" plus the first log line.
    $ErrorActionPreference = 'Continue'

    try {
        $psExe = Resolve-PowerShellExecutable
        # -MainRef hands over the base this run already resolved. The removal script re-decides
        # merged-ness for itself, and without this it would decide against the local branch again
        # -- and fetch a second time when it resolved its own.
        $output = '' | & $psExe -NoProfile -ExecutionPolicy Bypass -File $removeScript -WorktreePath $WorktreePath -MainRef $MainRef 2>&1
        foreach ($line in $output) {
            if ($line) { Write-Stderr ([string] $line) }
        }
    } catch {
        Write-Stderr "cleanup: removal of '$WorktreePath' failed: $($_.Exception.Message)"
        Write-SweepOutcome -RepoRoot $RepoRoot -WorktreePath $WorktreePath -Message 'Failed: the removal script could not be started.'
    }
}

# The worktrees a human locked. Read on its own rather than returned by Get-EligibleMergedWorktrees,
# because a locked worktree is by definition not eligible and that function's contract is the list
# of worktrees the sweep may act on.
function Get-LockedWorktrees {
    param([Parameter(Mandatory)][string] $RepoRoot)

    $listLines = & git -C $RepoRoot worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { return , @() }

    $locked = @()
    foreach ($wt in (ConvertFrom-WorktreePorcelain $listLines)) {
        if ($wt.Path -and $null -ne $wt.LockReason) { $locked += $wt }
    }
    return , $locked
}

# Drives the decision matrix through Resolve-CleanupDecision. Detection/removal failures
# are logged to stderr and skipped so worktree creation is never blocked. Emits nothing on
# the success stream.
function Invoke-MergedWorktreeCleanup {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $Cleanup,
        [switch] $IsHook,
        [string] $MainRef = 'main',
        [string] $ExcludePath,
        [switch] $BaseIsStale,
        [object[]] $MergedPullRequests
    )

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $RepoRoot -MainRef $MainRef -ExcludePath $ExcludePath -MergedPullRequests $MergedPullRequests
    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: eligible merged worktree: $($wt.Path) [$($wt.Branch)]"
    }

    # Reported, marked, and never acted on. Hiding a locked worktree would look like the sweep
    # never noticed it, and send a reader hunting a bug that is not there.
    foreach ($locked in (Get-LockedWorktrees -RepoRoot $RepoRoot)) {
        $lockReason = if ($locked.LockReason) { $locked.LockReason } else { 'no reason given' }
        Write-Stderr "  $($locked.Path)  [locked - skipped: $lockReason]"
    }

    # The other leftover, reported by the same run. It comes before the early return below, because
    # a branch with no worktree is exactly the case where no worktree is eligible. It is reported
    # whatever the cleanup setting says, because a report removes nothing.
    foreach ($branch in (Get-LeftoverMergedBranches -RepoRoot $RepoRoot -MainRef $MainRef -MergedPullRequests $MergedPullRequests)) {
        Write-Stderr "cleanup: leftover branch, worktree already gone: $branch (delete it with: git -C '$RepoRoot' branch -d -- $branch)"
    }

    if ($eligible.Count -eq 0) {
        Write-Stderr 'cleanup: no merged worktrees eligible for cleanup.'
        return
    }

    $configState = Get-WorktreeCleanupConfig -RepoRoot $RepoRoot
    $envOverride = if ($IsHook) { Get-EnvCleanupOverride } else { 'none' }
    $interactive = -not [Console]::IsInputRedirected

    $decision = Resolve-CleanupDecision -Cleanup:$Cleanup -IsHook:$IsHook -ConfigState $configState -EnvOverride $envOverride -Interactive $interactive -BaseIsStale $BaseIsStale

    switch ($decision.Action) {
        'Prompt' {
            $answer = Read-Host "Found $($eligible.Count) merged, clean worktree(s). Remove them now and enable automatic cleanup for this repository? [y/N]"
            $applied = Set-CleanupAnswer -RepoRoot $RepoRoot -Answer $answer
            if (-not $applied.Clean) {
                Write-Stderr 'cleanup: declined; nothing removed.'
                return
            }
        }
        'Clean' { }
        'Skip' {
            Write-Stderr 'cleanup: ahkflow.worktreeCleanup=false; skipping.'
            return
        }
        default {
            # ReportOnly. The invalid-config warning is emitted here, not before the decision,
            # so an explicit override (-Cleanup / hook env enable) that legitimately cleans over
            # invalid config never gets a misleading "treating as report-only" line.
            if ($BaseIsStale) {
                Write-Stderr "cleanup: the base could not be refreshed, so it may be behind the remote; reporting only, nothing removed. Removal resumes once '$MainRef' can be fetched again."
            } elseif ($configState -eq 'invalid') {
                Write-Stderr 'cleanup: ahkflow.worktreeCleanup has an invalid or duplicated value; treating as report-only. Repair with: git config --local --unset-all ahkflow.worktreeCleanup'
            } elseif ($decision.ShowHint) {
                Write-Stderr 'cleanup: report-only. Enable automatic cleanup for this repository with: git config --local ahkflow.worktreeCleanup true'
            } else {
                Write-Stderr 'cleanup: report-only; nothing removed.'
            }
            return
        }
    }

    # Reached only for Clean or an accepted Prompt.
    $removalLog = Join-Path $RepoRoot '.claude\worktrees\worktree-removal.log'
    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: removing merged worktree: $($wt.Path) [$($wt.Branch)]"
        try {
            Write-WorktreeLog -LogPath $removalLog -Worktree (Split-Path -Leaf $wt.Path) -Message "Merged-cleanup requested removal (branch $($wt.Branch))."
        } catch { }
        Invoke-WorktreeRemoval -RepoRoot $RepoRoot -WorktreePath $wt.Path -MainRef $MainRef
    }
}

# Run the sweep only when executed directly. When dot-sourced (e.g. by tests) to import
# the functions, $MyInvocation.InvocationName is '.', so the entrypoint is skipped.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RepoRoot) {
        $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    }

    # Resolving here, not inside Invoke-MergedWorktreeCleanup, keeps the function's signature and
    # its callers unchanged: a test that dot-sources this file and calls the function passes the
    # base it wants, and nothing fetches behind its back.
    $baseIsStale = $false
    if ($PSBoundParameters.ContainsKey('MainRef')) {
        # The caller vouches for this base, so it is never treated as stale -- and it is still
        # reported, because every run says which base it decided against.
        Write-Stderr "cleanup: base '$MainRef' (given by the caller)."
    } else {
        $base = Resolve-MergedBaseRef -RepoRoot $RepoRoot -LocalRef $MainRef -TimeoutSeconds $FetchTimeoutSeconds
        Write-Stderr (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $base)
        $MainRef = $base.Ref
        $baseIsStale = ($base.Reason -eq 'remote-stale')
    }

    # One GitHub lookup for the whole run, cached and handed to every decision. It asks about
    # $MainRef, never about a default: a run deciding against another base must not accept a pull
    # request that merged somewhere else. It answers the case
    # local git cannot: a rebase merge writes no merge commit and rewrites the SHA, so nothing local
    # ties the branch to the base. An answer that cannot be got costs a removal and never causes
    # one, so an unusable gh is reported and the run continues on local history alone.
    $mergedPullRequests = @()
    $prLookup = Get-MergedPullRequestRecords -RepoRoot $RepoRoot `
        -BaseBranch (Resolve-BaseBranchName -RepoRoot $RepoRoot -LocalRef $MainRef) -TimeoutSeconds $FetchTimeoutSeconds
    if ($prLookup.Available) {
        $mergedPullRequests = $prLookup.Records
        Write-Stderr "cleanup: GitHub reports $(@($mergedPullRequests).Count) merged pull request(s) for the base."
    } else {
        Write-Stderr "cleanup: GitHub lookup unavailable ($($prLookup.Reason)); deciding on local history only."
    }

    Invoke-MergedWorktreeCleanup -RepoRoot $RepoRoot -Cleanup:$Cleanup -IsHook:$IsHook -MainRef $MainRef -ExcludePath $ExcludePath -BaseIsStale:$baseIsStale -MergedPullRequests $mergedPullRequests | Out-Null
}
