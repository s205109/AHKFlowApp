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

# Typed names keep their type and gain the marker.
Assert-BranchName 'feature/123-thing' 'feature/wt-123-thing'
Assert-BranchName 'hotfix/456-thing' 'hotfix/wt-456-thing'
Assert-BranchName 'chore/tidy' 'chore/wt-tidy'

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
Assert-True (([regex]::Matches($newWorktreeContent, 'ConvertTo-WorktreeBranchName')).Count -eq 1) 'new-worktree.ps1 should normalize the branch name in exactly one place.'

Write-Host 'Worktree branch name tests passed.'
