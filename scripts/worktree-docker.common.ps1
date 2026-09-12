#Requires -Version 5.1
<#
.SYNOPSIS
    Shared worktree-Docker helpers: the canonical per-worktree Compose project name
    rule (mirroring src/Backend/AHKFlowApp.API/Worktrees/WorktreeComposeProject.cs),
    a guard, a guarded teardown, and a host project enumerator. Dot-sourced by setup-,
    remove-, and prune-worktree-docker.ps1 so the rule lives in one place. The single
    docker-CLI dependency point (mirrors worktree-database.common.ps1's SQL-client role).
    Do not call Set-StrictMode here: dot-sourcing runs in the caller scope.

    The last section holds the reused SQL test container's name rule, its two ownership
    labels, its discovery helpers, and its guarded removal. They live here, and not in
    test-sql-container.common.ps1, because prune-worktree-docker.ps1 and
    remove-worktree-local-dev.ps1 need them and never load that file.
#>

# Lowercase base; Docker Compose requires lowercase project names.
$script:WorktreeComposeBaseName = 'ahkflowapp'

# Canonical rule: <base>_<slug>_<hash8>. Null/whitespace branch -> base.
# Hash over the trimmed raw branch; slug lowercased. Matches the C# helper exactly.
function Get-WorktreeComposeProjectForBranch {
    param([string] $Branch)

    $base = $script:WorktreeComposeBaseName
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $base }
    $trimmed = $Branch.Trim()

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($trimmed)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 8)
    } finally {
        $sha.Dispose()
    }

    $slug = ($trimmed.ToLowerInvariant() -replace '[^a-z0-9]', '_')
    while ($slug -match '__') { $slug = $slug -replace '__', '_' }
    $slug = $slug.Trim('_')

    $prefix = "${base}_"
    $suffix = "_$hash"
    $slugBudget = 63 - $prefix.Length - $suffix.Length
    if ($slug.Length -gt $slugBudget) { $slug = $slug.Substring(0, [Math]::Max(0, $slugBudget)).Trim('_') }

    if (-not $slug) { return "${base}_$hash" }
    return "$prefix$slug$suffix"
}

# True when a name is a canonical per-worktree project: <base>_<slug>_<hash8> or
# <base>_<hash8>. The trailing 8-hex hash refuses the main <base> and unrelated names.
function Test-WorktreeComposeProject {
    param([string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return [bool]($Name -match ('^' + [regex]::Escape($script:WorktreeComposeBaseName) + '_(?:[a-z0-9_]+_)?[0-9a-f]{8}$'))
}

# Every Compose project on the host (running and stopped). Returns names only.
# Returns an empty list when docker is missing/unreachable, so callers under
# $ErrorActionPreference='Stop' (the prune script) degrade instead of aborting:
# a missing 'docker' command would otherwise raise a terminating CommandNotFound.
function Get-WorktreeComposeProjectsOnHost {
    # Scoped to this function, so a docker that cannot reach its daemon stays an empty list rather
    # than a terminating error. The comment above promises that; without this line the promise only
    # holds where $PSNativeCommandUseErrorActionPreference happens to be $false.
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }
    try {
        $json = & docker compose ls --all --format json 2>$null
    } catch {
        return @()
    }
    if (-not $json) { return @() }
    try { $parsed = ($json | Out-String) | ConvertFrom-Json } catch { return @() }
    # PS 5.1: ConvertFrom-Json returns $null for '[]', and piping $null through
    # ForEach-Object iterates once (yielding ''), so guard before projecting names.
    if ($null -eq $parsed) { return @() }
    return @($parsed | ForEach-Object { [string] $_.Name })
}

# Guarded teardown. Returns { Removed; Skipped; Error } and never throws. Runs
# 'docker compose -f <file> -p <name> down -v', removing the project's container,
# network, and named data volume. The compose file is required so 'down' can resolve
# the volume to delete.
function Remove-WorktreeDockerProject {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $ComposeFilePath
    )

    # Same scoping as above: a failed teardown is reported through the returned object, never
    # raised. Set inside the function, so the caller keeps its own value.
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not (Test-WorktreeComposeProject -Name $Name)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $true; Error = $null }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = 'docker not found' }
    }
    if (-not (Test-Path -LiteralPath $ComposeFilePath)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = "compose file not found: $ComposeFilePath" }
    }

    try {
        & docker compose -f $ComposeFilePath -p $Name down -v 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Removed = $true; Skipped = $false; Error = $null }
        }
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = "docker compose down exited $LASTEXITCODE" }
    } catch {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = $_.Exception.Message }
    }
}

# --- the reused test SQL container -------------------------------------------------------------
#
# Backlog 133. One SQL Server container per checkout stays alive between test runs. It is started
# with plain 'docker run', so Compose does not know it exists and 'docker compose down' cannot
# remove it. Ownership is carried by these two labels instead: the role label says the container is
# a test server, and the project label says which checkout owns it, which is what makes an orphan
# decidable.
$script:WorktreeTestSqlRoleLabel = 'com.ahkflowapp.role'
$script:WorktreeTestSqlRoleValue = 'test-sql'
$script:WorktreeTestSqlProjectLabel = 'com.ahkflowapp.compose-project'

# Which clone the container belongs to. The project label names a branch, and every clone of this
# repository on the machine can hold a branch by that name, so the project alone cannot tell two
# clones apart. Two failures came from that, and this label is what closes both: a sweep run in one
# clone force-removed another clone's running container, and two clones shared one SQL server.
$script:WorktreeTestSqlRepositoryLabel = 'com.ahkflowapp.repository'

# One clone's identity: the path of its main checkout, lowercased, with no trailing separator.
#
# The git directory every worktree of a clone shares is what decides it. 'rev-parse
# --git-common-dir' answers with the main checkout's '.git' from any worktree of that clone, and
# with two different clones it answers with two different paths. So every worktree of one clone
# agrees on this value, and no two clones ever do.
#
# The path itself, not a hash of it. A reader running 'docker inspect' can then see whose container
# it is, which is the question this label exists to answer. Get-WorktreeRepositoryToken hashes it
# where a short token is needed instead.
#
# Throws when git cannot answer. Reading that as "some default clone" is what both failures above
# look like, so there is no safe value to fall back to.
function Get-WorktreeRepositoryId {
    param([Parameter(Mandatory)][string] $RepoRoot)

    # Scoped here, the same as every other function in this file that runs a native command: a git
    # that cannot answer must reach the throw below, not raise PowerShell's own error first.
    $PSNativeCommandUseErrorActionPreference = $false

    $output = & git -C $RepoRoot rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        throw "Could not resolve the git directory shared by every worktree of '$RepoRoot', so the clone its test SQL container belongs to cannot be named: $($output -join [Environment]::NewLine). Nothing was changed. Repair the git state, then run again."
    }

    # git answers with a relative path when it can, and it is relative to the checkout it was asked
    # about.
    $commonDir = ([string] $output).Trim()
    if (-not [System.IO.Path]::IsPathRooted($commonDir)) {
        $commonDir = Join-Path $RepoRoot $commonDir
    }

    $resolved = (Resolve-Path -LiteralPath $commonDir).Path
    $mainCheckout = Split-Path -Parent $resolved.TrimEnd('\', '/')
    if (-not $mainCheckout) {
        throw "The git directory '$resolved' has no parent directory, so the clone that owns '$RepoRoot' cannot be named."
    }

    return $mainCheckout.TrimEnd('\', '/').ToLowerInvariant()
}

# Eight hexadecimal characters standing for one clone, for the places that need a short token rather
# than a path: the main checkout's Compose project, and so the name of its container. Same hashing
# as Get-WorktreeComposeProjectForBranch, so both halves of a name are built the same way.
function Get-WorktreeRepositoryToken {
    param([Parameter(Mandatory)][string] $RepositoryId)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($RepositoryId)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 8)
    } finally {
        $sha.Dispose()
    }
}

# The deterministic name for one checkout's test container. One per checkout, and distinct enough
# that nothing reads it as a Compose service.
function Get-WorktreeTestSqlContainerName {
    param([Parameter(Mandatory)][string] $ComposeProject)
    return "$ComposeProject-testsql"
}

# The states Docker reports for a container: created, restarting, running, removing, paused, exited
# and dead. Only the last two are finished, and only a finished container is safe to reclaim. The
# other five all mean something is holding it: 'created' is a run that has not started yet,
# 'restarting' and 'paused' are live, and 'removing' is already going.
$script:WorktreeTestSqlTerminalState = @('exited', 'dead')

# The name this repository gave a test container before backlog 133, and the name it still gives a
# throwaway '-Ephemeral' container today: 'ahkflow-testsql-<process id>-<eight hexadecimal
# characters>'. scripts/test-sql-container.common.ps1 builds that exact shape for every ephemeral
# container, and scripts/measure-tests.ps1 asks for one on every run. Anchored at both ends, because
# Docker's name filter is a regular expression and adds no end anchor of its own.
$script:WorktreeLegacyTestSqlNamePattern = '^ahkflow-testsql-[0-9]+-[0-9a-f]{8}$'

# Every test SQL container on the host, running and stopped, as { Name; ComposeProject; State }.
# Returns an empty list when docker is missing or unreachable, so callers under
# $ErrorActionPreference='Stop' degrade instead of aborting, exactly as
# Get-WorktreeComposeProjectsOnHost does.
#
# A plain @(...) return, so 'foreach ($c in Get-WorktreeTestSqlContainerOnHost)' walks the
# containers. 'return , $result' would bind the whole list to $c and run the loop once, and the
# sweep would then skip every orphan it found. A caller that needs .Count wraps the call in @().
function Get-WorktreeTestSqlContainerOnHost {
    # docker exits non-zero when the daemon is not reachable, and PowerShell 7.4 turns that into a
    # terminating error while $ErrorActionPreference is 'Stop'. Setting the preference here creates
    # a copy scoped to this function, so the caller's value is untouched when it returns. The
    # variable does not exist in 5.1, where setting it is harmless.
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }

    # The repository label comes last, so the three fields that were here before keep their
    # positions. A container built before that label existed reports an empty fourth field, and the
    # sweep reads that as "not this clone's" and leaves it alone, which is the safe reading.
    $format = '{{.Names}}|{{.Label "' + $script:WorktreeTestSqlProjectLabel + '"}}|{{.State}}' +
        '|{{.Label "' + $script:WorktreeTestSqlRepositoryLabel + '"}}'
    $filter = "label=$script:WorktreeTestSqlRoleLabel=$script:WorktreeTestSqlRoleValue"
    try {
        $lines = & docker ps --all --filter $filter --format $format 2>$null
    } catch {
        return @()
    }
    if (-not $lines) { return @() }

    $result = @()
    foreach ($line in $lines) {
        $text = ([string] $line).Trim()
        if (-not $text) { continue }
        $parts = $text.Split('|')
        if ($parts.Count -lt 3) { continue }
        $repository = if ($parts.Count -ge 4) { $parts[3].Trim() } else { '' }
        $result += [pscustomobject]@{
            Name = $parts[0].Trim()
            ComposeProject = $parts[1].Trim()
            State = $parts[2].Trim()
            Repository = $repository
        }
    }
    return @($result)
}

# Containers named by the scheme this repository used before backlog 133, and containers named by
# that same scheme today. scripts/test-sql-container.common.ps1 builds a '-Ephemeral' container with
# this exact shape, and scripts/measure-tests.ps1 asks for one on every run. Neither the pre-133
# containers nor today's throwaway ones carry a label, so the role filter above cannot see either
# kind, and nothing else ever reclaims them.
#
# The name pattern is anchored at both ends and spells out that whole shape: the process id that
# built it, then exactly eight hexadecimal characters. Docker's name filter is a regular expression
# with no implied end anchor, so a bare '^ahkflow-testsql-' prefix would also take a container
# somebody else named 'ahkflow-testsql-unrelated-service'. These carry no label to ask, so the name
# is the only evidence of ownership there is. A terminal state says a container is finished; it says
# nothing about whose it is.
#
# Only containers in a terminal state are returned here, and the removal below never passes
# '--force'. Those two guards are what makes reclaiming by name alone safe today, because a live
# '-Ephemeral' container shares this same name shape: a running or starting container never appears
# in this listing, so a 'measure-tests.ps1' run in progress is never touched. Dropping either guard
# would let this pass kill one.
function Get-WorktreeLegacyTestSqlContainerOnHost {
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }

    try {
        $lines = & docker ps --all --filter "name=$script:WorktreeLegacyTestSqlNamePattern" --format '{{.Names}}|{{.State}}' 2>$null
    } catch {
        return @()
    }
    if (-not $lines) { return @() }

    $result = @()
    foreach ($line in $lines) {
        $text = ([string] $line).Trim()
        if (-not $text) { continue }
        $parts = $text.Split('|')
        if ($parts.Count -lt 2) { continue }
        $state = $parts[1].Trim().ToLowerInvariant()
        if ($script:WorktreeTestSqlTerminalState -notcontains $state) { continue }
        $result += $parts[0].Trim()
    }
    return @($result)
}

# Guarded removal, shaped like Remove-WorktreeDockerProject: returns { Removed; Skipped; Error }
# and never throws.
#
# -ExpectedProject is the ownership guard, and it lives here rather than at each call site so no
# caller can forget it. A name is a guess: it is derived from a Compose project, and any container
# on the host may already hold it. The labels are what the container says about itself. Discovery
# does the asking, because its listing is already filtered on the role label, so a name it does not
# return either carries no role label or does not exist. Neither is this repository's to delete.
#
# -OnlyIfStopped drops the --force flag, so Docker refuses a container that is running. The legacy
# sweep passes it, because it decides from a listing taken a moment earlier and a container can
# start in between. It changes what a missing name means: 'docker rm --force' exits zero for a name
# that does not exist, so calling it twice is harmless, while plain 'docker rm' exits one. The sweep
# reads that as "somebody else got there first", not as a fault.
function Remove-WorktreeTestSqlContainer {
    param(
        [string] $Name,
        [string] $ExpectedProject,
        [string] $ExpectedRepository,
        [switch] $OnlyIfStopped
    )

    $PSNativeCommandUseErrorActionPreference = $false

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $true; Error = $null }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = 'docker not found' }
    }

    if ($PSBoundParameters.ContainsKey('ExpectedProject')) {
        $owned = @(Get-WorktreeTestSqlContainerOnHost | Where-Object { $_.Name -eq $Name })

        if ($owned.Count -eq 0) {
            return [pscustomobject]@{
                Removed = $false
                Skipped = $true
                Error = "no container named '$Name' carries the label $script:WorktreeTestSqlRoleLabel=$script:WorktreeTestSqlRoleValue, so it is not this repository's to remove"
            }
        }

        if ($owned[0].ComposeProject -ne $ExpectedProject) {
            return [pscustomobject]@{
                Removed = $false
                Skipped = $true
                Error = "the container '$Name' belongs to the checkout '$($owned[0].ComposeProject)', not '$ExpectedProject'"
            }
        }
    }

    # Checked separately from the project, because it answers a different question. The project says
    # which branch; this says which clone. Two clones can hold a branch by the same name, and then
    # the project check above agrees while the container still belongs to somebody else.
    if ($PSBoundParameters.ContainsKey('ExpectedRepository')) {
        $owned = @(Get-WorktreeTestSqlContainerOnHost | Where-Object { $_.Name -eq $Name })

        if ($owned.Count -eq 0) {
            return [pscustomobject]@{
                Removed = $false
                Skipped = $true
                Error = "no container named '$Name' carries the label $script:WorktreeTestSqlRoleLabel=$script:WorktreeTestSqlRoleValue, so it is not this repository's to remove"
            }
        }

        if ($owned[0].Repository -and $owned[0].Repository -ne $ExpectedRepository) {
            return [pscustomobject]@{
                Removed = $false
                Skipped = $true
                Error = "the container '$Name' belongs to another clone -- the clone at '$($owned[0].Repository)' -- and this clone is '$ExpectedRepository'"
            }
        }

        # No label at all is refused as well. An earlier version let it through, on the reasoning
        # that a matching project name made it this clone's own from before the label existed. A
        # project name cannot establish that. It is derived from a branch name, and two clones can
        # each hold a branch by that name, so the container may belong to another clone that is
        # running its tests right now. This line then reached 'docker rm --force' and took it.
        #
        # Refusing costs the caller a clear stop instead of a silent loss, and it takes only one
        # upgraded caller plus one older container elsewhere to tell the two apart wrongly.
        if ([string]::IsNullOrWhiteSpace($owned[0].Repository)) {
            return [pscustomobject]@{
                Removed = $false
                Skipped = $true
                Error = "the container '$Name' does not say which clone owns it, so it cannot be told apart from another clone's container that is still in use. Check that no other checkout is running tests against it, then remove it by hand with: docker rm --force $Name"
            }
        }
    }

    $arguments = if ($OnlyIfStopped) { @('rm', $Name) } else { @('rm', '--force', $Name) }

    try {
        $output = & docker @arguments 2>&1
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Removed = $true; Skipped = $false; Error = $null }
        }
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = ($output -join [Environment]::NewLine) }
    } catch {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = $_.Exception.Message }
    }
}
