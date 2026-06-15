#Requires -Version 5.1
<#
.SYNOPSIS
    Removes orphaned per-worktree Docker compose projects that have no live git
    worktree. Covers worktrees removed by plain git, Codex, or Copilot (which never
    fire Claude's WorktreeRemove hook) and projects left behind by a failed teardown.
    The main 'ahkflowapp' project is never removed.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch] $Quiet, [string] $LogPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-docker.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-log.common.ps1')

function Write-PruneEvent {
    param([string] $Message)
    if ($LogPath) { Write-WorktreeLog -LogPath $LogPath -Worktree 'prune-docker' -Message $Message }
    if (-not $Quiet) { Write-Host $Message }
}

function Get-RepoRoot {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($root) { $root = ([string] $root).Trim() }
    if (-not $root) { throw 'Not inside a git repository; cannot resolve worktree compose projects.' }
    return $root
}

# Every live worktree's recorded (or branch-derived) compose project. The main checkout
# is skipped entirely: it uses the bare 'ahkflowapp' base (no hash suffix), which
# Test-WorktreeComposeProject already refuses at the removal site, so it never needs a live
# entry. Deriving a branch-based name for it would instead mint 'ahkflowapp_main_<hash>'
# and wrongly shield a same-named orphan. git lists the main working tree first, so the first
# 'worktree' block is the main checkout. Returned via the comma operator so the HashSet
# survives the pipeline (a bare return unrolls it and breaks .Contains).
function Get-LiveComposeProjects {
    param([string] $Root)

    $names = New-Object 'System.Collections.Generic.HashSet[string]'
    $output = & git -C $Root worktree list --porcelain 2>$null
    $isMainCheckout = $true
    foreach ($line in $output) {
        if ($line -like 'worktree *') {
            if ($isMainCheckout) {
                $isMainCheckout = $false
                continue
            }
            $path = $line.Substring('worktree '.Length)
            $manifest = Join-Path $path 'scripts\.env.worktree'
            $recorded = $false
            if (Test-Path -LiteralPath $manifest) {
                foreach ($entry in Get-Content -LiteralPath $manifest) {
                    if ($entry -match '^\s*AHKFLOW_COMPOSE_PROJECT\s*=\s*(.+?)\s*$') {
                        [void] $names.Add($matches[1].Trim())
                        $recorded = $true
                    }
                }
            }
            if (-not $recorded) {
                try {
                    $branch = (& git -C $path rev-parse --abbrev-ref HEAD 2>$null)
                    if ($branch) { $branch = ([string] $branch).Trim() }
                    if ($branch -and $branch -ne 'HEAD') {
                        [void] $names.Add((Get-WorktreeComposeProjectForBranch -Branch $branch))
                    }
                } catch { }
            }
        }
    }
    return ,$names
}

$root = Get-RepoRoot
$composeFile = Join-Path $root 'docker-compose.yml'
$live = Get-LiveComposeProjects -Root $root

$removed = 0
$skipped = 0
foreach ($project in Get-WorktreeComposeProjectsOnHost) {
    if (-not (Test-WorktreeComposeProject -Name $project)) { continue }
    if ($live.Contains($project)) { continue }
    if ($PSCmdlet.ShouldProcess($project, 'docker compose down -v')) {
        $result = Remove-WorktreeDockerProject -Name $project -ComposeFilePath $composeFile
        if ($result.Removed) {
            $removed++
            Write-PruneEvent "Removed orphan compose project: $project"
        } else {
            $skipped++
            $reason = if ($result.Error) { $result.Error } else { 'guard refused the name' }
            Write-Warning "Could not remove '$project': $reason. Skipped; stop any running containers for it and rerun."
        }
    }
}

# Always emit the summary: Write-PruneEvent already gates console output on -Quiet, so
# wrapping it here would only drop the summary from the -LogPath file.
Write-PruneEvent "Docker prune complete. Removed: $removed. Skipped: $skipped."
