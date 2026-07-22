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

function Assert-DoesNotMatch {
    param([string] $Actual, [string] $Pattern, [string] $Message)

    if ($Actual -match $Pattern) {
        throw $Message
    }
}

$hostResolverPath = Join-Path $repoRoot 'scripts\worktree-powershell.common.ps1'
Assert-True (Test-Path -LiteralPath $hostResolverPath) 'Expected shared PowerShell host resolver to exist.'

. $hostResolverPath
$resolvedHost = Resolve-PowerShellExecutable
$currentHost = [System.Diagnostics.Process]::GetCurrentProcess().Path

Assert-True (Test-Path -LiteralPath $resolvedHost) "Resolved PowerShell host does not exist: $resolvedHost"
Assert-True ([string]::Equals($resolvedHost, $currentHost, [System.StringComparison]::OrdinalIgnoreCase)) "Expected resolver to prefer the current host. Expected '$currentHost', got '$resolvedHost'."

$newWorktreePath = Join-Path $repoRoot 'scripts\new-worktree.ps1'
$newWorktreeContent = Get-Content -LiteralPath $newWorktreePath -Raw
Assert-DoesNotMatch $newWorktreeContent '(?m)&\s+powershell(\.exe)?\s+-NoProfile' 'new-worktree.ps1 must not launch child setup/prune scripts through bare powershell.'
Assert-True ($newWorktreeContent -match [regex]::Escape("worktree-powershell.common.ps1")) 'new-worktree.ps1 should use the shared PowerShell host resolver.'

$removeWorktreePath = Join-Path $repoRoot 'scripts\remove-worktree-local-dev.ps1'
$removeWorktreeContent = Get-Content -LiteralPath $removeWorktreePath -Raw
Assert-DoesNotMatch $removeWorktreeContent 'Join-Path\s+\$PSHOME\s+''powershell\.exe''' 'remove-worktree-local-dev.ps1 must not assume powershell.exe lives under $PSHOME.'
Assert-True ($removeWorktreeContent -match 'Resolve-PowerShellExecutable') 'remove-worktree-local-dev.ps1 should use the shared PowerShell host resolver.'

$cleanupPath = Join-Path $repoRoot 'scripts\cleanup-merged-worktrees.ps1'
Assert-True (Test-Path -LiteralPath $cleanupPath) 'Expected cleanup-merged-worktrees.ps1 to exist.'
$cleanupContent = Get-Content -LiteralPath $cleanupPath -Raw
Assert-DoesNotMatch $cleanupContent '(?m)&\s+powershell(\.exe)?\s+-NoProfile' 'cleanup-merged-worktrees.ps1 must not launch remove-worktree-local-dev.ps1 through bare powershell.'
Assert-True ($cleanupContent -match [regex]::Escape('worktree-powershell.common.ps1')) 'cleanup-merged-worktrees.ps1 should use the shared PowerShell host resolver.'
Assert-True ($cleanupContent -match 'Resolve-PowerShellExecutable') 'cleanup-merged-worktrees.ps1 should resolve the PowerShell host via the shared resolver.'

$claudeSettingsPath = Join-Path $repoRoot '.claude\settings.json'
$claudeSettingsContent = Get-Content -LiteralPath $claudeSettingsPath -Raw
Assert-DoesNotMatch $claudeSettingsContent '"command":\s*"powershell\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+\\"?\$\{CLAUDE_PROJECT_DIR\}\\scripts\\(?:new-worktree|remove-worktree-local-dev)\.ps1' 'Claude Worktree hooks should not hard-code Windows PowerShell.'

# Shell form leaves ${CLAUDE_PROJECT_DIR} unsubstituted on the Claude Desktop worktree path,
# so pwsh receives the literal placeholder as -File. Assert the documented exec form
# structurally: shape, not just the absence of one bad spelling.
$claudeSettings = $claudeSettingsContent | ConvertFrom-Json

function Assert-ExecFormWorktreeHook {
    param([string] $EventName, [string] $ScriptName)

    Assert-True ($claudeSettings.hooks.PSObject.Properties.Name -contains $EventName) "Expected a $EventName hook in .claude/settings.json."

    $entries = @($claudeSettings.hooks.$EventName.hooks)
    Assert-True ($entries.Count -eq 1) "Expected exactly one $EventName hook handler, got $($entries.Count)."

    $handler = $entries[0]
    Assert-True ($handler.type -eq 'command') "$EventName handler must be a command hook."
    Assert-True ($handler.command -eq 'pwsh') "$EventName must invoke 'pwsh' as the bare command in exec form, got '$($handler.command)'."
    Assert-True ($handler.PSObject.Properties.Name -contains 'args') "$EventName must use exec form (command plus args): shell form leaves the path placeholder unsubstituted."

    $hookArgs = @($handler.args)
    $fileIndex = [array]::IndexOf($hookArgs, '-File')
    Assert-True ($fileIndex -ge 0) "$EventName args must pass -File."
    Assert-True ($fileIndex + 1 -lt $hookArgs.Count) "$EventName args must pass a script path after -File."

    # The placeholder must be present and spelled exactly; a malformed one would resolve to a
    # path that does not exist, which the substitution check below catches.
    $scriptArg = [string] $hookArgs[$fileIndex + 1]
    $placeholder = '${CLAUDE_PROJECT_DIR}'
    Assert-True ($scriptArg.StartsWith($placeholder)) "$EventName -File argument must start with $placeholder, got '$scriptArg'."

    $resolved = $scriptArg.Replace($placeholder, $repoRoot)
    Assert-True (Test-Path -LiteralPath $resolved) "$EventName -File argument does not resolve to an existing script: '$resolved'."
    Assert-True ((Split-Path -Leaf $resolved) -eq $ScriptName) "$EventName must run $ScriptName, got '$(Split-Path -Leaf $resolved)'."
}

Assert-ExecFormWorktreeHook -EventName 'WorktreeCreate' -ScriptName 'new-worktree.ps1'
Assert-ExecFormWorktreeHook -EventName 'WorktreeRemove' -ScriptName 'remove-worktree-local-dev.ps1'

Write-Host 'Worktree PowerShell host tests passed.'
