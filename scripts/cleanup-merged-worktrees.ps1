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
