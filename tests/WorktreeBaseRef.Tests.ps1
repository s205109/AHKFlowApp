#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool] $Condition, [string] $Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-SourceRef {
    param(
        [string] $BranchName,
        [bool] $BranchExists,
        [string] $BaseRef,
        [string] $Expected
    )

    $actual = Resolve-WorktreeSourceRef -BranchName $BranchName -BranchExists $BranchExists -BaseRef $BaseRef
    Assert-True ($actual -ceq $Expected) "Resolve-WorktreeSourceRef('$BranchName', exists=$BranchExists, base='$BaseRef'): expected '$Expected', got '$actual'."
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $ExpectedSubstring, [string] $Message)

    try {
        & $Action
    } catch {
        Assert-True ($_.Exception.Message -like "*$ExpectedSubstring*") "$Message (message was '$($_.Exception.Message)')"
        return
    }

    throw "$Message (no exception was thrown)"
}

. (Join-Path $repoRoot 'scripts\worktree-git.common.ps1')

# Default: no base ref supplied and a new branch, so the main checkout's HEAD is the start point.
# This is the historical behavior and must not change when -BaseRef is absent.
Assert-SourceRef -BranchName 'fix/wt-thing' -BranchExists $false -BaseRef '' -Expected 'HEAD'

# Explicit base ref on a new branch: stack on that ref instead of whatever main is sitting on.
# This is the whole point of the parameter — the report's incident was branching from main while
# the required spec docs lived on an unmerged branch.
Assert-SourceRef -BranchName 'feature/wt-w2-ui' -BranchExists $false -BaseRef 'feature/wt-w1-backend' -Expected 'feature/wt-w1-backend'

# A base ref may be any committish, not just a local branch.
Assert-SourceRef -BranchName 'fix/wt-thing' -BranchExists $false -BaseRef 'origin/main' -Expected 'origin/main'
Assert-SourceRef -BranchName 'fix/wt-thing' -BranchExists $false -BaseRef 'v1.2.3' -Expected 'v1.2.3'
Assert-SourceRef -BranchName 'fix/wt-thing' -BranchExists $false -BaseRef '3b35668' -Expected '3b35668'

# Existing branch with no base ref: check it out as-is. Its history is already fixed.
Assert-SourceRef -BranchName 'fix/wt-existing' -BranchExists $true -BaseRef '' -Expected 'fix/wt-existing'

# Existing branch plus a base ref is a contradiction. It must fail loudly rather than silently
# ignore the flag, or the caller gets a worktree based on something they did not ask for.
Assert-Throws {
    Resolve-WorktreeSourceRef -BranchName 'fix/wt-existing' -BranchExists $true -BaseRef 'main'
} 'already exists' 'An existing branch combined with -BaseRef must throw.'

# Ref probing is broader than a branch probe: HEAD of this repo resolves, gibberish does not.
Assert-True (Test-RefExists $repoRoot 'HEAD') 'Test-RefExists should resolve HEAD.'
Assert-True (-not (Test-RefExists $repoRoot 'refs/heads/definitely-not-a-real-branch-xyz')) 'Test-RefExists should reject a nonexistent ref.'

Write-Host 'Worktree base-ref tests passed.'
