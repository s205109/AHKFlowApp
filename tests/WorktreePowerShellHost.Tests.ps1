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

Write-Host 'Worktree PowerShell host tests passed.'
