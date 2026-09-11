#Requires -Version 5.1
<#
.SYNOPSIS
    Removes orphaned per-worktree Docker compose projects that have no live git
    worktree. Covers worktrees removed by plain git, Codex, or Copilot (which never
    fire Claude's WorktreeRemove hook) and projects left behind by a failed teardown.
    The main 'ahkflowapp' project is never removed.

    The script also reclaims the reused SQL test containers. A test container is not a
    Compose project, so the compose pass cannot see it. The second pass finds it by its
    ownership labels and removes it when no live worktree owns it. The third pass removes
    stopped containers left by the naming scheme this repository used before backlog 133.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch] $Quiet, [string] $LogPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A test fixture that builds a throwaway repository holds none of this project's real
# worktrees, so every real checkout's container would look orphaned and get removed. This
# variable lets such a fixture refuse the sweep outright. Two routes reach this script -- a
# spawned new-worktree.ps1 and a direct call -- so both carry this same guard.
if ($env:AHKFLOW_SKIP_ORPHAN_PRUNE) {
    if (-not $Quiet) { Write-Host 'Docker prune skipped: AHKFLOW_SKIP_ORPHAN_PRUNE is set.' }
    return
}

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

    $PSNativeCommandUseErrorActionPreference = $false

    $names = New-Object 'System.Collections.Generic.HashSet[string]'

    # An empty answer and a failed answer look identical once the exit code is thrown away, and they
    # mean opposite things. No live worktrees means every orphan is removable. A git that could not
    # answer means nothing is known, and then every live checkout's container looks like an orphan
    # and is removed while its tests are running. Stop instead.
    $output = & git -C $Root worktree list --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list the git worktrees under '$Root', so no Docker project or container can be called an orphan: $($output -join [Environment]::NewLine). Nothing was removed. Repair the git state, then run again."
    }

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
                # Same rule as above, one worktree down. A worktree with no manifest is named from
                # its branch, and a branch git cannot read leaves that worktree out of the live set.
                # Its container would then be swept while the worktree is still sitting there.
                $branch = (& git -C $path rev-parse --abbrev-ref HEAD 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "The worktree at '$path' records no compose project and git could not name its branch: $($branch -join [Environment]::NewLine). Its container cannot be told apart from an orphan, so nothing was removed. Repair that worktree, then run again."
                }

                $branch = ([string] $branch).Trim()
                if ($branch -and $branch -ne 'HEAD') {
                    [void] $names.Add((Get-WorktreeComposeProjectForBranch -Branch $branch))
                }
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

# Second pass: the reused SQL test containers. They are not Compose projects, so the loop above
# cannot see them and 'docker compose down' could not remove them. The role label finds them and
# the project label says which checkout owns each one, which is what makes an orphan decidable.
#
# A container whose project label is the bare 'ahkflowapp' base belongs to the main checkout, which
# is always live, so Test-WorktreeComposeProject refuses it here for the same reason it refuses the
# main Compose project.
#
# -ExpectedProject is passed even though the project came from this very listing. The listing and
# the removal are two moments, and prune can run while another session is starting a container, so
# the guard re-reads the labels at the moment it matters. It also keeps one rule with no exceptions:
# nothing is removed by name alone.
foreach ($container in Get-WorktreeTestSqlContainerOnHost) {
    $project = $container.ComposeProject
    if (-not (Test-WorktreeComposeProject -Name $project)) { continue }
    if ($live.Contains($project)) { continue }
    if ($PSCmdlet.ShouldProcess($container.Name, 'docker rm --force')) {
        $result = Remove-WorktreeTestSqlContainer -Name $container.Name -ExpectedProject $project
        if ($result.Removed) {
            $removed++
            Write-PruneEvent "Removed orphan test SQL container: $($container.Name)"
        } else {
            $skipped++
            $reason = if ($result.Error) { $result.Error } else { 'removal reported no change' }
            # The guard can refuse this removal because the container belongs to another checkout.
            # Rerunning never fixes that: the container is not this repository's to remove, so the
            # warning must not tell the reader to rerun. A real 'docker rm' failure is different; that
            # one can be worth a retry, so it keeps the old advice.
            $advice = if ($result.Skipped) {
                'it is not this checkout''s container to remove'
            } else {
                'stop it and rerun'
            }
            Write-Warning "Could not remove '$($container.Name)': $reason. Skipped; $advice."
        }
    }
}

# Third pass: containers left by the naming scheme this repository used before backlog 133. They
# carry no labels, so nothing above can see them, and nothing else ever reclaims them.
#
# Only containers in a terminal state are listed, and the removal is not forced. Those are two
# separate guards for two separate moments. The listing decides from a snapshot: it drops anything
# created, restarting, running, removing or paused, because each of those belongs to a checkout that
# has not picked up this change yet, or to a run that is still starting. Plain 'docker rm' then
# covers the gap between the snapshot and the removal, because Docker refuses a container that
# started in between rather than killing a live test run.
#
# No -ExpectedProject here, and this is the one exception to that rule: a legacy container carries
# no labels at all, so there is nothing to check it against. Its whole name is the evidence instead,
# which is why Get-WorktreeLegacyTestSqlContainerOnHost matches the complete historical format and
# not a prefix.
foreach ($legacy in Get-WorktreeLegacyTestSqlContainerOnHost) {
    if ($PSCmdlet.ShouldProcess($legacy, 'docker rm')) {
        $result = Remove-WorktreeTestSqlContainer -Name $legacy -OnlyIfStopped
        if ($result.Removed) {
            $removed++
            Write-PruneEvent "Removed stopped legacy test SQL container: $legacy"
        } else {
            $skipped++
            # Not forced, so this is the ordinary outcome when the container started again, or when
            # another sweep took it first. Neither is a fault, and neither needs a rerun.
            $reason = if ($result.Error) { $result.Error } else { 'removal reported no change' }
            Write-PruneEvent "Left legacy test SQL container '$legacy' alone: $reason"
        }
    }
}

# Always emit the summary: Write-PruneEvent already gates console output on -Quiet, so
# wrapping it here would only drop the summary from the -LogPath file.
Write-PruneEvent "Docker prune complete. Removed: $removed. Skipped: $skipped."
