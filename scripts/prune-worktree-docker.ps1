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
    stopped containers named by the scheme this repository used before backlog 133. A
    throwaway '-Ephemeral' container still uses that same scheme today, so this pass also
    reclaims one of those once it stops.
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

# Every live checkout's recorded (or branch-derived) compose project, the main checkout included.
#
# The main checkout used to be left out, because its test container carried the bare 'ahkflowapp'
# base with no hash suffix and Test-WorktreeComposeProject refused that name at the removal site. Its
# container name carries a clone token now -- 'ahkflowapp_<token>' -- so that refusal no longer
# covers it, and leaving it out would sweep a live main checkout's server. It is added by the same
# rule that names it, so the two cannot drift apart.
#
# Its Compose project proper is still the bare base, and that name is still refused at the removal
# site, so the main Compose project is as safe as it ever was. git lists the main working tree
# first, so the first 'worktree' block is it. Returned via the comma operator so the HashSet
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
                # The same name Get-AhkFlowTestSqlComposeProject gives the main checkout, built from
                # the same two functions, so a live main checkout is never read as an orphan.
                [void] $names.Add("$script:WorktreeComposeBaseName`_$(Get-WorktreeRepositoryToken -RepositoryId (Get-WorktreeRepositoryId -RepoRoot $Root))")
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

# Which clone is running this sweep. Resolved before anything is listed, because it decides what
# this sweep is allowed to touch, and it throws rather than guessing when git cannot answer.
$thisRepository = Get-WorktreeRepositoryId -RepoRoot $root

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
# The main checkout's container is spared by the live set, which Get-LiveComposeProjects adds it to
# by name. It used to be spared by the shape of that name instead: the name was the bare
# 'ahkflowapp' base, and Test-WorktreeComposeProject refuses a name with no hash suffix. The name
# carries a clone token now, so that refusal no longer reaches it.
#
# -ExpectedProject and -ExpectedRepository are passed even though both came from this very listing.
# The listing and the removal are two moments, and prune can run while another session is starting a
# container, so the guard re-reads the labels at the moment it matters. It also keeps one rule with
# no exceptions: nothing is removed by name alone.
foreach ($container in Get-WorktreeTestSqlContainerOnHost) {
    # This clone's containers only. Discovery asks the whole host, and the live set can only be
    # built from one repository's worktree list, so another clone's live container was absent from
    # the live set and looked exactly like an orphan. It passed the name-shape guard, because a
    # branch name produces the same shape in any clone, and it passed -ExpectedProject, because that
    # guard re-read the same label the listing had just reported. It was then force-removed while
    # its own tests were running.
    #
    # An unlabelled container is not this clone's either, as far as anything here can tell, so the
    # comparison leaves it alone. The third pass below reclaims the unlabelled containers this
    # repository does own, by name and only once they have stopped.
    if ($container.Repository -ne $thisRepository) { continue }

    $project = $container.ComposeProject
    if (-not (Test-WorktreeComposeProject -Name $project)) { continue }
    if ($live.Contains($project)) { continue }
    if ($PSCmdlet.ShouldProcess($container.Name, 'docker rm --force')) {
        $result = Remove-WorktreeTestSqlContainer -Name $container.Name -ExpectedProject $project -ExpectedRepository $thisRepository
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

# Third pass: containers named by the scheme this repository used before backlog 133, and
# containers named by that same scheme today. scripts/test-sql-container.common.ps1 builds a
# throwaway '-Ephemeral' container with this exact shape, and scripts/measure-tests.ps1 asks for one
# on every run. Neither kind carries a label, so nothing above can see either one. This pass is not
# only historical cleanup: it is also the live reclaim path for today's throwaway containers, once
# they stop.
#
# Only containers in a terminal state are listed, and the removal is not forced. Those two guards
# are what make this safe, even though a live throwaway container can share this exact name. A
# running or starting container never appears in the listing, so a 'measure-tests.ps1' run in
# progress is never touched. Plain 'docker rm' with no '--force' then refuses a container that
# started in the gap between the listing and the removal, instead of killing it. Dropping either
# guard would let this pass remove a running throwaway container, not only a stopped one.
#
# No -ExpectedProject here, and this is the one exception to that rule: neither a legacy container
# nor a throwaway one carries any label, so there is nothing to check either against. The whole name
# is the evidence instead, which is why Get-WorktreeLegacyTestSqlContainerOnHost matches the complete
# format and not a prefix.
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
