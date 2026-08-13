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

function Assert-BranchName {
    param([string] $Value, [string] $Expected)

    $actual = ConvertTo-WorktreeBranchName $Value
    Assert-True ($actual -ceq $Expected) "ConvertTo-WorktreeBranchName '$Value': expected '$Expected', got '$actual'."
}

. (Join-Path $repoRoot 'scripts\worktree-git.common.ps1')

# Bare name: no type prefix to preserve, so it falls back to 'fix/'.
Assert-BranchName 'foo' 'fix/wt-foo'
Assert-BranchName 'worktree-hook-exec-form' 'fix/wt-worktree-hook-exec-form'

# Already carrying the wt- marker but untyped: keep the marker, add the fallback type once.
Assert-BranchName 'wt-foo' 'fix/wt-foo'

# The three branch prefixes from AGENTS.md keep their type and gain the marker.
Assert-BranchName 'feature/123-thing' 'feature/wt-123-thing'
Assert-BranchName 'fix/456-thing' 'fix/wt-456-thing'
Assert-BranchName 'hotfix/789-thing' 'hotfix/wt-789-thing'

# Conventional commit types are not branch prefixes: they name commits, not branches, so they
# are topic text and pick up the 'fix/' fallback like any other unrecognized leading segment.
Assert-BranchName 'chore/tidy' 'fix/wt-chore/tidy'
Assert-BranchName 'docs/readme' 'fix/wt-docs/readme'

# Fully conventional names are already correct and must round-trip unchanged.
Assert-BranchName 'fix/wt-foo' 'fix/wt-foo'
Assert-BranchName 'feature/wt-123-thing' 'feature/wt-123-thing'

# Unsafe characters collapse to '-', but '/' survives so the type prefix is not destroyed.
Assert-BranchName 'fix/some topic!' 'fix/wt-some-topic'
Assert-BranchName '  feature/spaced  ' 'feature/wt-spaced'

# git rejects '//' and a trailing '/', so both are normalized away.
Assert-BranchName 'fix//foo' 'fix/wt-foo'
Assert-BranchName 'fix/foo/' 'fix/wt-foo'

# An unrecognized leading segment is topic text, not a type.
Assert-BranchName 'bart/foo' 'fix/wt-bart/foo'

$threw = $false
try {
    ConvertTo-WorktreeBranchName '---' | Out-Null
} catch {
    $threw = $true
}
Assert-True $threw 'Expected a name with no usable characters to throw.'

# An explicit -BranchName must bypass normalization entirely; only the name-derived default
# is rewritten. Asserted on the source because exercising the parameter for real would
# require creating a worktree and mutating git state.
$newWorktreeContent = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\new-worktree.ps1') -Raw
Assert-True ($newWorktreeContent -match '(?m)if\s*\(-not\s+\$BranchName\)\s*\{[^}]*\$BranchName\s*=\s*ConvertTo-WorktreeBranchName\s+\$Name') 'new-worktree.ps1 must derive BranchName via ConvertTo-WorktreeBranchName only when -BranchName was not supplied.'
# This one count also guards the -Title block below: deriving the branch from the title
# directly would add a second call here.
Assert-True (([regex]::Matches($newWorktreeContent, 'ConvertTo-WorktreeBranchName')).Count -eq 1) 'new-worktree.ps1 should normalize the branch name in exactly one place.'

# --- -Title derives the worktree name through the shared slug rule ---
#
# Backlog 080: the worktree name and the backlog item file name have to agree, because the
# worktree is the pointer before a draft pull request exists. Deriving both from one title
# through one slug rule is what makes them agree by construction.

# The slug rule itself is proven in tests/BacklogNumbering.Tests.ps1. What this file adds is
# that the rule loads at all under a 5.1 host, which is the reason it lives in its own file.
. (Join-Path $repoRoot 'scripts\slug.common.ps1')

Assert-True ($null -ne (Get-Command ConvertTo-BacklogSlug -ErrorAction SilentlyContinue)) 'slug.common.ps1 must be dot-sourceable from a 5.1 test host'

Assert-True ($newWorktreeContent -match '(?m)\[string\]\s*\$Title') 'new-worktree.ps1 must accept -Title'
Assert-True ($newWorktreeContent -match 'slug\.common\.ps1') 'new-worktree.ps1 must dot-source slug.common.ps1 for the slug rule'
Assert-True ($newWorktreeContent -notmatch 'backlog\.common\.ps1') 'new-worktree.ps1 must NOT dot-source backlog.common.ps1: it requires PowerShell 7.0 and this script supports 5.1'
Assert-True ($newWorktreeContent -match '(?m)if\s*\(\$Title\s+-and\s+\$Name\)') 'new-worktree.ps1 must refuse -Title together with -Name'
Assert-True ($newWorktreeContent -match 'wt-\$\(ConvertTo-BacklogSlug') 'new-worktree.ps1 must derive the name as wt- plus the title slug'

Write-Host 'Worktree branch name tests passed.'
