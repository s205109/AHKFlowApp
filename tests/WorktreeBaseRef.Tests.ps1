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

# The argv itself, not just the resolved string. A wiring change that dropped the start point
# would leave every assertion above passing, so assert the exact arguments git receives.
function Assert-AddArguments {
    param(
        [bool] $BranchExists,
        [string] $SourceRef,
        [string] $Expected
    )

    $actual = (Get-WorktreeAddArguments -WorktreePath 'C:\wt\x' -BranchName 'fix/wt-x' -BranchExists $BranchExists -SourceRef $SourceRef) -join ' '
    Assert-True ($actual -ceq $Expected) "Get-WorktreeAddArguments(exists=$BranchExists, source='$SourceRef'): expected '$Expected', got '$actual'."
}

Assert-AddArguments -BranchExists $false -SourceRef 'HEAD' -Expected 'worktree add C:\wt\x -b fix/wt-x HEAD'
Assert-AddArguments -BranchExists $false -SourceRef 'feature/wt-upstream' -Expected 'worktree add C:\wt\x -b fix/wt-x feature/wt-upstream'
# An existing branch takes no start point: git rejects 'add <path> <branch> <ref>'.
Assert-AddArguments -BranchExists $true -SourceRef 'HEAD' -Expected 'worktree add C:\wt\x fix/wt-x'

# End-to-end against real git. The unit assertions prove the argv is shaped as intended; only a
# real 'git worktree add' proves that shape yields the intended ancestry. Drives the same helper
# the script calls, in a throwaway repo, for both the default and the stacked case.
function New-AncestryFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtbase-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    & git -C $repo config user.email 'test@example.com'
    & git -C $repo config user.name 'Worktree BaseRef Test'

    Set-Content -LiteralPath (Join-Path $repo 'on-main.txt') -Value 'main' -Encoding utf8
    & git -C $repo add -A
    & git -C $repo commit --quiet -m 'seed main'

    # A file that exists only on the unmerged branch: its presence is the ancestry assertion.
    & git -C $repo checkout --quiet -b feature/upstream
    Set-Content -LiteralPath (Join-Path $repo 'only-upstream.txt') -Value 'upstream' -Encoding utf8
    & git -C $repo add -A
    & git -C $repo commit --quiet -m 'only on upstream'
    & git -C $repo checkout --quiet main

    return (Resolve-Path -LiteralPath $repo).Path
}

$fixtureRepo = New-AncestryFixture
try {
    $marker = 'only-upstream.txt'

    # Default: no base ref, so the new branch starts at main's HEAD and must NOT carry the marker.
    $defaultPath = Join-Path (Split-Path -Parent $fixtureRepo) 'wt-default'
    $defaultArgs = Get-WorktreeAddArguments -WorktreePath $defaultPath -BranchName 'fix/wt-default' -BranchExists $false -SourceRef (Resolve-WorktreeSourceRef -BranchName 'fix/wt-default' -BranchExists $false -BaseRef '')
    & git -C $fixtureRepo @defaultArgs *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Default worktree add should succeed.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $defaultPath $marker))) "Default base should be main's HEAD, so '$marker' must be absent."

    # Explicit base ref: the new branch stacks on the unmerged branch and MUST carry the marker.
    $stackedPath = Join-Path (Split-Path -Parent $fixtureRepo) 'wt-stacked'
    $stackedArgs = Get-WorktreeAddArguments -WorktreePath $stackedPath -BranchName 'feature/wt-stacked' -BranchExists $false -SourceRef (Resolve-WorktreeSourceRef -BranchName 'feature/wt-stacked' -BranchExists $false -BaseRef 'feature/upstream')
    & git -C $fixtureRepo @stackedArgs *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Stacked worktree add should succeed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $stackedPath $marker)) "-BaseRef should stack on feature/upstream, so '$marker' must be present."

    # Ancestry, not just file presence: the stacked branch descends from the base ref.
    & git -C $fixtureRepo merge-base --is-ancestor 'feature/upstream' 'feature/wt-stacked'
    Assert-True ($LASTEXITCODE -eq 0) 'feature/upstream must be an ancestor of the stacked branch.'
    & git -C $fixtureRepo merge-base --is-ancestor 'feature/upstream' 'fix/wt-default'
    Assert-True ($LASTEXITCODE -ne 0) 'feature/upstream must NOT be an ancestor of the default branch.'
} finally {
    $fixtureRoot = Split-Path -Parent $fixtureRepo
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction Stop
            break
        } catch {
            if ($attempt -eq 3) { break }
            Start-Sleep -Milliseconds 200
        }
    }
}

Write-Host 'Worktree base-ref tests passed.'
