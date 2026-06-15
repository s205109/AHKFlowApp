#Requires -Version 5.1
<#
.SYNOPSIS
    Drops orphaned per-worktree databases that have no live git worktree. Covers
    worktrees removed by plain git, Codex, or Copilot (which never fire Claude's
    WorktreeRemove hook) and databases left behind by a failed drop. The base
    database name and server are read from the tracked connection string via
    scripts/worktree-database.common.ps1; the main <base> database is never
    dropped.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch] $Quiet, [string] $LogPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-database.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-log.common.ps1')

function Write-PruneEvent {
    param([string] $Message)

    if ($LogPath) {
        Write-WorktreeLog -LogPath $LogPath -Worktree 'prune' -Message $Message
    }

    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Get-RepoRoot {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($root) { $root = ([string] $root).Trim() }
    if (-not $root) { throw 'Not inside a git repository; cannot resolve the worktree database settings.' }
    return $root
}

# Names that must be preserved: the main <base> plus every live worktree's
# database (recorded in its manifest, or derived from its branch for legacy
# worktrees whose manifest predates the DB-name key). Returned via the comma
# operator so the HashSet survives the pipeline (a bare return unrolls it and
# breaks .Contains).
function Get-LiveDatabaseNames {
    param([string] $Root, [string] $BaseName)

    $names = New-Object 'System.Collections.Generic.HashSet[string]'
    [void] $names.Add($BaseName)

    $output = & git -C $Root worktree list --porcelain 2>$null
    foreach ($line in $output) {
        if ($line -like 'worktree *') {
            $path = $line.Substring('worktree '.Length)
            $manifest = Join-Path $path 'scripts\.env.worktree'
            $recorded = $false
            if (Test-Path -LiteralPath $manifest) {
                foreach ($entry in Get-Content -LiteralPath $manifest) {
                    if ($entry -match '^\s*AHKFLOW_DB_NAME\s*=\s*(.+?)\s*$') {
                        [void] $names.Add($matches[1].Trim())
                        $recorded = $true
                    }
                }
            }
            if (-not $recorded) {
                # No DB name recorded (legacy manifest predating the key, or manifest
                # absent). Derive the name from the worktree's branch so prune never
                # drops a live worktree's database.
                try {
                    $branch = (& git -C $path rev-parse --abbrev-ref HEAD 2>$null)
                    if ($branch) { $branch = ([string] $branch).Trim() }
                    if ($branch -and $branch -ne 'HEAD') {
                        [void] $names.Add((Get-WorktreeDatabaseNameForBranch -BaseName $BaseName -Branch $branch))
                    }
                } catch { }
            }
        }
    }
    return ,$names
}

$root = Get-RepoRoot
$dbConfig = Get-WorktreeDatabaseConfig -RepoRoot $root
$masterConnectionString = Get-WorktreeMasterConnectionString $dbConfig.ConnectionString
$base = $dbConfig.BaseName

$live = Get-LiveDatabaseNames -Root $root -BaseName $base

$dropped = 0
$skipped = 0
foreach ($db in Get-WorktreeServerDatabaseName -MasterConnectionString $masterConnectionString) {
    if (-not (Test-WorktreeDatabaseName -BaseName $base -DbName $db)) { continue }
    if ($live.Contains($db)) { continue }
    if ($PSCmdlet.ShouldProcess($db, 'DROP DATABASE')) {
        $result = Remove-WorktreeDatabaseByName -DbName $db -BaseName $base -MasterConnectionString $masterConnectionString
        if ($result.Dropped) {
            $dropped++
            Write-PruneEvent "Dropped orphan database: $db"
        } else {
            $skipped++
            $reason = if ($result.Error) { $result.Error } else { 'guard refused the name' }
            Write-Warning "Could not drop '$db' (likely still in use): $reason. Skipped; rerun after closing connections."
        }
    }
}

# Always emit the summary: Write-PruneEvent already gates console output on
# -Quiet, so wrapping it here would only drop the summary from the -LogPath file.
Write-PruneEvent "Prune complete. Dropped: $dropped. Skipped (still in use): $skipped."
