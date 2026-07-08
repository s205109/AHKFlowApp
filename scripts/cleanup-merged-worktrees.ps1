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

function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}

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
        if ([string]::Equals($wt.Branch, $MainRef, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
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
        Write-Stderr 'cleanup: hook context is report-only; nothing removed. (opt in with AHKFLOW_WORKTREE_CLEANUP=1, or run scripts/new-worktree.ps1 -Cleanup)'
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
