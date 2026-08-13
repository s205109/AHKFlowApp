#Requires -Version 5.1
<#
.SYNOPSIS
Pre-commit backstop: the agent worktree rule, then the main-branch rule for every session.

.DESCRIPTION
Two rules run here, in this order.

1. The agent worktree rule. It acts only when a recognized agent session marker is present, so a
   human commit never meets it. It denies a commit made from the protected main checkout, an
   unmanaged worktree, or a worktree with an invalid manifest, and allows one from a valid managed
   worktree. It is a narrow second layer behind the PreToolUse command guard.
2. The main-branch rule. It applies to every session, human and agent alike. It denies a change
   that would land directly on the main branch, so every change reaches main through a pull
   request.

.githooks/pre-merge-commit runs this same file, because git runs that hook - not pre-commit - when
a merge succeeds automatically.

This is deliberately not an unskippable control. `git commit --no-verify`, a replaced
core.hooksPath, and `git cherry-pick` / `git revert` / `git rebase` (which run no pre-commit hook
at all) bypass it. The native PreToolUse adapter is the primary layer for agents; this backstop
reduces, not eliminates, the residual gap.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:ProtectedBranchName = 'main'

function Test-AgentSessionMarker {
    if ($env:AHKFLOW_AGENT_SESSION -eq '1') { return $true }
    if ($env:CLAUDECODE -eq '1') { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_ENTRYPOINT)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) { return $true }
    return $false
}

# Returns the short name of the branch HEAD points at, or $null when HEAD is detached or the name
# cannot be read. A detached HEAD is an ordinary state, not a fault, so git's 'ref HEAD is not a
# symbolic ref' message is discarded and $null simply means no branch rule applies. The error
# preference is relaxed for the call because PowerShell 7.4 turns a non-zero native exit code into
# a terminating error when the preference is 'Stop'.
function Get-CurrentBranchName {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $branch = & git symbolic-ref --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
            return $null
        }
        return ([string] $branch).Trim()
    }
    catch {
        # Fail open, as the agent rule does: a defect here must not stop the commit.
        [Console]::Error.WriteLine(
            "[pre-commit] WARNING: could not read the current branch; skipping the main-branch rule. $($_.Exception.Message)")
        return $null
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

# Denies the commit when an agent session runs it outside a valid managed worktree. Returns in
# every other case, so the main-branch rule below still runs.
function Invoke-AgentWorktreeRule {
    if (-not (Test-AgentSessionMarker)) { return }

    # Derive the protected repository from the parent of the hook-owning .githooks directory, and
    # load that root's policy copy. $PSScriptRoot is used only to find the policy - never to infer
    # the active worktree, which git sets as the working directory instead.
    $protectedRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $policyScript = Join-Path $protectedRepoRoot 'scripts\agents\agent-worktree-guard.common.ps1'

    try {
        . $policyScript

        $repoRoot = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
            throw "Could not determine the repository being committed ('git rev-parse --show-toplevel' failed)."
        }
        $repoRoot = $repoRoot.Trim()

        $state = Get-ManagedWorktreeState -Cwd $repoRoot -ProtectedRepoRoot $protectedRepoRoot
    }
    catch {
        # Fail open: a policy-load or classification defect must not brick every agent commit,
        # including a main-policy/older-worktree version mismatch after merge.
        [Console]::Error.WriteLine(
            "[pre-commit] WARNING: agent worktree guard could not evaluate this commit; skipping the worktree rule. $($_.Exception.Message)")
        return
    }

    if ($state -eq 'ManagedWorktree') { return }

    if ($state -in @('NotRepository', 'OutsideProtectedRepository')) {
        # Not this repository's concern.
        return
    }

    if ($env:AHKFLOW_ALLOW_MAIN -eq '1') {
        [Console]::Error.WriteLine(
            "[pre-commit] WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the managed-worktree rule ($state) for: $repoRoot")
        return
    }

    [Console]::Error.WriteLine(@"
BLOCKED: agent Git mutations are allowed only in a managed linked worktree.
Current target: $repoRoot
Create one with scripts/new-worktree.ps1 or the agent WorktreeCreate tool.
Read-only Git and ordinary edit/build/test commands are unaffected.
Override the location check with AHKFLOW_ALLOW_MAIN=1.
"@)
    exit 1
}

Invoke-AgentWorktreeRule

$branch = Get-CurrentBranchName
if ($null -eq $branch -or
    -not [string]::Equals($branch, $script:ProtectedBranchName, [System.StringComparison]::OrdinalIgnoreCase)) {
    exit 0
}

if ($env:AHKFLOW_ALLOW_MAIN -eq '1') {
    [Console]::Error.WriteLine(
        "[pre-commit] WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the main-branch rule for branch: $branch")
    exit 0
}

[Console]::Error.WriteLine(@"
BLOCKED: this change would land directly on the main branch.
Every change reaches main through a pull request.
Make the change in a worktree instead:
  pwsh ./scripts/new-worktree.ps1 -Name <short-name>
Small changes belong in the housekeeping worktree.
To commit here on purpose, set the override for this one command:
  `$env:AHKFLOW_ALLOW_MAIN='1'; git commit -m "..."; Remove-Item Env:AHKFLOW_ALLOW_MAIN
"@)
exit 1
