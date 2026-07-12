#Requires -Version 5.1
<#
.SYNOPSIS
    Detects worktrees whose branch is already merged into main and, on an explicit
    opt-in, removes the finished (clean) ones via remove-worktree-local-dev.ps1.
.DESCRIPTION
    Invoked by new-worktree.ps1 before it creates a new worktree, and runnable on its
    own. Removal never happens without an explicit opt-in: the single interactive
    question on a real console, or the -Cleanup switch. In a WorktreeCreate hook
    context (-IsHook) detection runs but nothing is prompted or removed, and all
    output stays on stderr so the hook's stdout contract is preserved.
#>

[CmdletBinding()]
param(
    [string] $RepoRoot,
    [switch] $Cleanup,
    [switch] $IsHook,
    [string] $MainRef = 'main',
    [string] $ExcludePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-log.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-powershell.common.ps1')

# Parses `git worktree list --porcelain` into { Path; Branch } records. Branch is the
# short name for a normal worktree, and $null for a detached-HEAD or bare entry.
function ConvertFrom-WorktreePorcelain {
    param([string[]] $Lines)

    $worktrees = @()
    $current = $null
    foreach ($line in $Lines) {
        if ($line -like 'worktree *') {
            if ($current) { $worktrees += $current }
            $current = [pscustomobject]@{ Path = $line.Substring('worktree '.Length); Branch = $null }
        } elseif ($current -and ($line -like 'branch refs/heads/*')) {
            $current.Branch = $line.Substring('branch refs/heads/'.Length)
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
        [string] $ExcludePath
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

    # Bare, marker-free short names. Plain `git branch --merged` prefixes '* '/'+ ',
    # so --format is required or a naive compare skips every eligible worktree.
    $mergedNames = & git -C $RepoRoot branch --format='%(refname:short)' --merged $MainRef 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr "cleanup: 'git branch --merged $MainRef' failed; skipping merged-cleanup detection."
        return , @()
    }
    $mergedSet = @{}
    foreach ($name in $mergedNames) {
        $trimmed = ([string] $name).Trim()
        if ($trimmed) { $mergedSet[$trimmed] = $true }
    }

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
        # Belt-and-suspenders: a branch is always "merged" into itself, so the main-ref
        # worktree would otherwise pass the merged check below. The repoRootFull compare
        # above only excludes it when $RepoRoot happens to resolve to that exact worktree
        # (guaranteed via new-worktree.ps1's Assert-MainCheckout, NOT guaranteed for a
        # standalone run from inside a linked worktree) so this check must not depend on it.
        if ([string]::Equals($wt.Branch, $mainBranchShortName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not $mergedSet.ContainsKey($wt.Branch)) { continue }

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
        [bool] $Interactive
    )

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
function Invoke-WorktreeRemoval {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $WorktreePath
    )

    $removeScript = Join-Path $RepoRoot 'scripts\remove-worktree-local-dev.ps1'
    if (-not (Test-Path -LiteralPath $removeScript)) {
        Write-Stderr "cleanup: remove-worktree-local-dev.ps1 not found; cannot remove '$WorktreePath'."
        return
    }

    try {
        $psExe = Resolve-PowerShellExecutable
        $output = '' | & $psExe -NoProfile -ExecutionPolicy Bypass -File $removeScript -WorktreePath $WorktreePath 2>&1
        foreach ($line in $output) {
            if ($line) { Write-Stderr ([string] $line) }
        }
    } catch {
        Write-Stderr "cleanup: removal of '$WorktreePath' failed: $($_.Exception.Message)"
    }
}

# Drives the decision matrix. Detection/removal failures are logged to stderr and
# skipped so worktree creation is never blocked. Emits nothing on the success stream.
function Invoke-MergedWorktreeCleanup {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $Cleanup,
        [switch] $IsHook,
        [string] $MainRef = 'main',
        [string] $ExcludePath
    )

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $RepoRoot -MainRef $MainRef -ExcludePath $ExcludePath
    if ($eligible.Count -eq 0) {
        Write-Stderr 'cleanup: no merged worktrees eligible for cleanup.'
        return
    }

    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: eligible merged worktree: $($wt.Path) [$($wt.Branch)]"
    }

    if ($IsHook) {
        Write-Stderr 'cleanup: hook context is report-only; nothing removed. (cleanup runs by default in hook mode; opt out with AHKFLOW_WORKTREE_CLEANUP=0)'
        return
    }

    $authorized = $false
    if ($Cleanup) {
        $authorized = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $answer = Read-Host 'Clean up merged worktrees? (y/n)'
        $authorized = ($answer -match '^\s*(y|yes)\s*$')
    } else {
        Write-Stderr 'cleanup: non-interactive and no -Cleanup; skipping (removal needs an explicit opt-in).'
        return
    }

    if (-not $authorized) {
        Write-Stderr 'cleanup: declined; nothing removed.'
        return
    }

    $removalLog = Join-Path $RepoRoot '.claude\worktrees\worktree-removal.log'
    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: removing merged worktree: $($wt.Path) [$($wt.Branch)]"
        try {
            Write-WorktreeLog -LogPath $removalLog -Worktree (Split-Path -Leaf $wt.Path) -Message "Merged-cleanup requested removal (branch $($wt.Branch))."
        } catch { }
        Invoke-WorktreeRemoval -RepoRoot $RepoRoot -WorktreePath $wt.Path
    }
}

# Run the sweep only when executed directly. When dot-sourced (e.g. by tests) to import
# the functions, $MyInvocation.InvocationName is '.', so the entrypoint is skipped.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RepoRoot) {
        $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    }
    Invoke-MergedWorktreeCleanup -RepoRoot $RepoRoot -Cleanup:$Cleanup -IsHook:$IsHook -MainRef $MainRef -ExcludePath $ExcludePath | Out-Null
}
