#Requires -Version 5.1
<#
.SYNOPSIS
Agent-scoped pre-commit backstop for the cross-agent Git guardrails.

.DESCRIPTION
A narrow second layer behind the PreToolUse command guard. It only acts when a recognized agent
session marker is present, so human commits are never touched. It denies commits made from the
protected main checkout, an unmanaged worktree, or a worktree with an invalid manifest, and
allows commits from a valid managed worktree.

This is deliberately not an unskippable control: `git commit --no-verify`, a replaced
core.hooksPath, or index-only operations bypass it. The native PreToolUse adapter is the primary
layer; this backstop reduces, not eliminates, the residual gap.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Test-AgentSessionMarker {
    if ($env:AHKFLOW_AGENT_SESSION -eq '1') { return $true }
    if ($env:CLAUDECODE -eq '1') { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_ENTRYPOINT)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) { return $true }
    return $false
}

# No agent marker: this is a human commit. Do nothing.
if (-not (Test-AgentSessionMarker)) {
    exit 0
}

# Derive the protected repository from the parent of the hook-owning .githooks directory, and load
# that root's policy copy. $PSScriptRoot is used only to find the policy - never to infer the
# active worktree, which git sets as the working directory instead.
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
        "[pre-commit] WARNING: agent worktree guard could not evaluate this commit; allowing. $($_.Exception.Message)")
    exit 0
}

if ($state -eq 'ManagedWorktree') {
    exit 0
}

if ($state -in @('NotRepository', 'OutsideProtectedRepository')) {
    # Not this repository's concern.
    exit 0
}

if ($env:AHKFLOW_ALLOW_MAIN -eq '1') {
    [Console]::Error.WriteLine(
        "[pre-commit] WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the managed-worktree rule ($state) for: $repoRoot")
    exit 0
}

[Console]::Error.WriteLine(@"
BLOCKED: agent Git mutations are allowed only in a managed linked worktree.
Current target: $repoRoot
Create one with scripts/new-worktree.ps1 or the agent WorktreeCreate tool.
Read-only Git and ordinary edit/build/test commands are unaffected.
Override the location check with AHKFLOW_ALLOW_MAIN=1.
"@)
exit 1
