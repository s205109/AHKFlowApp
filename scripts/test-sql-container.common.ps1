#Requires -Version 5.1

# Ownership, the name rule, discovery and removal live in worktree-docker.common.ps1, beside the
# Compose project rule, because prune-worktree-docker.ps1 and remove-worktree-local-dev.ps1 need
# them and never load this file. Test-LinkedWorktree comes from worktree-git.common.ps1, so the
# main checkout is recognised by the same probe every other script uses.
#
# Both are loaded through a Join-Path variable, which is the shape scripts/test-fast.ps1 and
# scripts/run-coverage.ps1 already use for this file. tests/CoverageSliceSkip.Tests.ps1 walks the
# whole dot-source graph to derive the CI path filter, and it reads that shape and the
# "$PSScriptRoot\name.ps1" one. A bare '. (Join-Path ...)' is the shape it refuses by name.
$worktreeDockerCommonScript = Join-Path $PSScriptRoot 'worktree-docker.common.ps1'
$worktreeGitCommonScript = Join-Path $PSScriptRoot 'worktree-git.common.ps1'
. $worktreeDockerCommonScript
. $worktreeGitCommonScript

# The image the test container must be built from. AHKFLOW_TEST_SQL_IMAGE replaces it. That
# variable exists so a check can point the script at a tag that does not exist and read the
# failure. Never set it for a normal run: the tests would then run a different SQL Server version
# from every other run.
$script:AhkFlowTestSqlImage = if ([string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_SQL_IMAGE)) {
    'mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04'
} else {
    $env:AHKFLOW_TEST_SQL_IMAGE
}
$script:AhkFlowTestSqlPassword = 'AHKFlow!Test_2026'

# Reads one property without assuming it is there. docker inspect leaves fields out, and a caller
# with Set-StrictMode turned on would throw on a missing property rather than reading it as $null.
function Get-AhkFlowJsonMember {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    $member = $Object.PSObject.Properties[$Name]
    if (-not $member) { return $null }
    return $member.Value
}

# Which Compose project this checkout owns. The same resolution prune-worktree-docker.ps1 uses, in
# the same order: the worktree manifest first, the branch second. Two different resolutions would
# let a renamed branch orphan a container the sweep cannot match.
function Get-AhkFlowTestSqlComposeProject {
    [CmdletBinding()]
    param([string]$RepoRoot)

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
    }

    # The main checkout has no hash suffix and no manifest: its Compose project is the bare base.
    # prune-worktree-docker.ps1 refuses that name, so the main checkout's test container is never
    # swept, which is right, because the main checkout is always live.
    #
    # Test-LinkedWorktree throws when git cannot answer. Reading that as "this is the main checkout"
    # is not safe. It hands every checkout git cannot read the same bare base name, so two of them
    # would share one container. Their database names are identical, and each takes its own
    # test-run lock, so nothing would stop them writing to one server at the same time. The failure
    # would look like a broken test, not like a broken checkout. Say what is wrong instead.
    try {
        $isLinked = Test-LinkedWorktree $RepoRoot
    }
    catch {
        throw "Could not tell whether '$RepoRoot' is a linked worktree or the main checkout, so the test SQL container cannot be named: $($_.Exception.Message). Naming it anyway would let two checkouts share one container, and their database names are identical. Repair the git state, then run again."
    }

    if (-not $isLinked) {
        return $script:WorktreeComposeBaseName
    }

    $manifest = Join-Path $RepoRoot 'scripts\.env.worktree'
    if (Test-Path -LiteralPath $manifest) {
        foreach ($entry in Get-Content -LiteralPath $manifest) {
            if ($entry -match '^\s*AHKFLOW_COMPOSE_PROJECT\s*=\s*(.+?)\s*$') {
                return $matches[1].Trim()
            }
        }
    }

    # Scoped here, the same as the four docker functions in this file. Without it, a git that cannot
    # name the branch raises a terminating error under $ErrorActionPreference = 'Stop'. The throw
    # below explains what to repair, and it would never run.
    $PSNativeCommandUseErrorActionPreference = $false

    $branch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch) { $branch = ([string]$branch).Trim() }
    if ($branch -and $branch -ne 'HEAD') {
        return Get-WorktreeComposeProjectForBranch -Branch $branch
    }

    throw "Could not name the Compose project for '$RepoRoot'. The manifest scripts\.env.worktree holds no AHKFLOW_COMPOSE_PROJECT entry, and git could not name the branch."
}

# One 'docker inspect' answers every check. --format is deliberately not used: the PowerShell
# suites that stub docker reply with this JSON shape, and one blob keeps a stub honest about all of
# it rather than about one field at a time. Returns $null when the container does not exist.
function Get-AhkFlowTestSqlContainerState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ContainerName)

    # A container that does not exist is the normal case on a first run, and docker says so with a
    # non-zero exit code. PowerShell 7.4 turns that into a terminating error while
    # $ErrorActionPreference is Stop and $PSNativeCommandUseErrorActionPreference is true, and
    # scripts/test-fast.ps1 only sets that preference inside its PowerShell mode branch. Setting it
    # here creates a copy scoped to this function, so the exit code stays data rather than an error
    # and the caller's own value is untouched when this returns. The variable does not exist in
    # 5.1, where setting it is harmless.
    $PSNativeCommandUseErrorActionPreference = $false

    $output = & docker inspect $ContainerName 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }

    try { $inspect = @($output | ConvertFrom-Json) } catch { return $null }
    if ($inspect.Count -lt 1 -or $null -eq $inspect[0]) { return $null }

    $entry = $inspect[0]
    $state = Get-AhkFlowJsonMember -Object $entry -Name 'State'
    $config = Get-AhkFlowJsonMember -Object $entry -Name 'Config'
    $labels = Get-AhkFlowJsonMember -Object $config -Name 'Labels'
    $network = Get-AhkFlowJsonMember -Object $entry -Name 'NetworkSettings'
    $ports = Get-AhkFlowJsonMember -Object $network -Name 'Ports'
    $bindings = @(Get-AhkFlowJsonMember -Object $ports -Name '1433/tcp')

    $hostPort = $null
    if ($bindings.Count -gt 0 -and $null -ne $bindings[0]) {
        $hostPort = [string](Get-AhkFlowJsonMember -Object $bindings[0] -Name 'HostPort')
    }

    [pscustomobject]@{
        Id       = [string](Get-AhkFlowJsonMember -Object $entry -Name 'Id')
        Running  = [bool](Get-AhkFlowJsonMember -Object $state -Name 'Running')
        Image    = [string](Get-AhkFlowJsonMember -Object $config -Name 'Image')
        Role     = [string](Get-AhkFlowJsonMember -Object $labels -Name $script:WorktreeTestSqlRoleLabel)
        # Which checkout the container says it belongs to. Both labels are checked before the
        # script restarts or removes anything, so a name collision cannot cost somebody else their
        # container.
        Project  = [string](Get-AhkFlowJsonMember -Object $labels -Name $script:WorktreeTestSqlProjectLabel)
        HostPort = $hostPort
    }
}

# Refuses a container that carries this checkout's name but not its ownership. Both labels are
# checked, not just the role: the name is derived from the Compose project, so a container whose
# project label says something else was built by a different rule and is not this script's to
# restart, replace, or remove. Throws, because there is no safe way to carry on.
function Assert-AhkFlowTestSqlOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$ComposeProject
    )

    if ($State.Role -ne $script:WorktreeTestSqlRoleValue) {
        throw "A container named '$ContainerName' already exists and does not carry the label $script:WorktreeTestSqlRoleLabel=$script:WorktreeTestSqlRoleValue, so this script did not create it. Rename or remove it, then run again."
    }

    if ($State.Project -ne $ComposeProject) {
        throw "The container named '$ContainerName' says it belongs to the checkout '$($State.Project)', and this checkout is '$ComposeProject'. Removing it would take another checkout's test server. Rename or remove it by hand, then run again."
    }
}

# Everything a container must prove before a run trusts it: the right image, running, a published
# port, and an answer to a trivial query. Returns $null when it passes, or a sentence saying what
# failed.
#
# A stopped container is repaired rather than replaced. Docker Desktop restarting, or the machine
# rebooting, leaves a good container in the exited state, and removing it would throw away the warm
# schema this reuse exists to keep.
#
# Nothing here covers a container that dies during a run. That boundary is deliberate: recovering
# would mean rebuilding the databases the run had already migrated and restarting the tests that
# had already started. The run fails instead, the way it fails today when Docker dies, and the next
# run builds a fresh container through the path below.
function Test-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][object]$State
    )

    # The image comes first. Restarting a container built from the wrong image fixes nothing.
    if ($State.Image -ne $script:AhkFlowTestSqlImage) {
        return "it was built from image '$($State.Image)' and this run expects '$script:AhkFlowTestSqlImage'"
    }

    # Scoped the same way Get-AhkFlowTestSqlContainerState scopes it: a failed 'docker start' is an
    # answer this function reports, not an error that ends the run.
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not $State.Running) {
        $output = & docker start $ContainerName 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "it was stopped and docker start failed: $($output -join [Environment]::NewLine)"
        }

        $State = Get-AhkFlowTestSqlContainerState -ContainerName $ContainerName
        if (-not $State -or -not $State.Running) {
            return 'it was stopped and did not come back up'
        }
    }

    if ([string]::IsNullOrWhiteSpace($State.HostPort)) {
        return 'it publishes no host port for 1433/tcp'
    }

    # 60 seconds. Every path through this function uses this same timeout, whether the container is
    # reused, restarted, or freshly built. A warm server answers at once, and a server that just
    # restarted or was just built still has to come up; either way, 60 seconds is enough. A
    # container that needs longer than this is one the run is better off replacing.
    try {
        Wait-AhkFlowTestSqlReady -ContainerName $ContainerName -Password $script:AhkFlowTestSqlPassword -TimeoutSeconds 60
    }
    catch {
        return "it did not answer a SELECT 1 query: $($_.Exception.Message)"
    }

    return $null
}

# Builds one container and returns its inspected state. An empty ComposeProject means a throwaway
# container: it carries no labels, nothing discovers it, and its caller removes it.
#
# The state comes back from here rather than from each call site. Every caller needs it straight
# afterwards, and "docker run said yes but the container is not there" is one failure this function
# owns instead of three call sites repeating it.
function New-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [string]$ComposeProject
    )

    # Scoped to this function. Without it, PowerShell 7.4 raises its own error for a failed
    # 'docker run' while $ErrorActionPreference is Stop, and the message below — the one that names
    # the container and the image — never reaches the reader.
    $PSNativeCommandUseErrorActionPreference = $false

    $arguments = @('run', '--detach', '--name', $ContainerName)

    if (-not [string]::IsNullOrWhiteSpace($ComposeProject)) {
        $arguments += @(
            '--label',
            "$script:WorktreeTestSqlRoleLabel=$script:WorktreeTestSqlRoleValue",
            '--label',
            "$script:WorktreeTestSqlProjectLabel=$ComposeProject"
        )
    }

    $arguments += @(
        '--env',
        'ACCEPT_EULA=Y',
        '--env',
        "MSSQL_SA_PASSWORD=$script:AhkFlowTestSqlPassword",
        '--env',
        'MSSQL_PID=Developer',
        '--publish',
        '127.0.0.1::1433',
        $script:AhkFlowTestSqlImage
    )

    $output = & docker @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "docker run failed for test SQL container '$ContainerName' from image '$script:AhkFlowTestSqlImage': $($output -join [Environment]::NewLine)"
    }

    $state = Get-AhkFlowTestSqlContainerState -ContainerName $ContainerName
    if (-not $state) {
        throw "The test SQL container '$ContainerName' does not exist after docker run reported success."
    }

    return $state
}

function New-AhkFlowTestSqlResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][bool]$Reused,
        [Parameter(Mandatory = $true)][System.Diagnostics.Stopwatch]$Stopwatch
    )

    if ([string]::IsNullOrWhiteSpace($State.HostPort)) {
        throw "Test SQL container '$ContainerName' publishes no host port for 1433/tcp."
    }

    [pscustomobject]@{
        ContainerName = $ContainerName
        # The full 64-character id. Two runs report the same id when they reused one container, and
        # a different one when the container was replaced, which is how the acceptance checks tell
        # reuse from a rebuild.
        ContainerId = $State.Id
        Reused = $Reused
        ConnectionString = "Server=127.0.0.1,$($State.HostPort);Database=master;User Id=sa;Password=$script:AhkFlowTestSqlPassword;TrustServerCertificate=True;MultipleActiveResultSets=true"
        ElapsedMilliseconds = [math]::Round($Stopwatch.Elapsed.TotalMilliseconds, 3)
        StartedAtUtc = [DateTimeOffset]::UtcNow
    }
}

function Start-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param(
        # Remove the container this checkout owns and build a new one. scripts/test-fast.ps1 passes
        # this for -FreshSql.
        [switch]$Fresh,

        # Build a throwaway container with a name nobody can find again, and never reuse one.
        # scripts/measure-tests.ps1 passes this: it takes no test-run lock, so it must not touch
        # the container the locked scripts share.
        [switch]$Ephemeral,

        # The checkout the container belongs to. Empty means the checkout this script lives in.
        [string]$RepoRoot
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'docker command not found. Install/start Docker Desktop before running SQL-backed tests.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Ephemeral) {
        $containerName = "ahkflow-testsql-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
        try {
            $state = New-AhkFlowTestSqlContainer -ContainerName $containerName
            $problem = Test-AhkFlowTestSqlContainer -ContainerName $containerName -State $state
            if ($problem) {
                throw "The throwaway test SQL container '$containerName' could not be verified: $problem"
            }
        }
        catch {
            Stop-AhkFlowTestSqlContainer -ContainerName $containerName
            throw
        }

        $state = Get-AhkFlowTestSqlContainerState -ContainerName $containerName
        $stopwatch.Stop()
        return (New-AhkFlowTestSqlResult -State $state -ContainerName $containerName -Reused $false -Stopwatch $stopwatch)
    }

    $composeProject = Get-AhkFlowTestSqlComposeProject -RepoRoot $RepoRoot
    $containerName = Get-WorktreeTestSqlContainerName -ComposeProject $composeProject

    # -Fresh must leave a new container behind or stop the run. Two things would break that if the
    # removal happened first and unchecked. A container carrying this name that this script did not
    # build would be force-removed on the strength of its name alone. And a removal that failed
    # would fall through to the reuse path below, which would verify the old container, find it
    # healthy, and report Reused=True from a run that asked for a fresh server.
    #
    # -ExpectedProject as well as the assert above, for the reason the sweep passes it: the inspect
    # and the removal are two moments, and the name can change hands in between. The assert reads
    # one inspect; the guard re-reads the labels inside the removal itself. One rule with no
    # exceptions, and the rule this file states: nothing is removed by name alone.
    if ($Fresh) {
        $state = Get-AhkFlowTestSqlContainerState -ContainerName $containerName
        if ($state) {
            Assert-AhkFlowTestSqlOwnership -ContainerName $containerName -State $state -ComposeProject $composeProject
            $removal = Remove-WorktreeTestSqlContainer -Name $containerName -ExpectedProject $composeProject
            if (-not $removal.Removed) {
                throw "A fresh test SQL container was asked for, and the existing container '$containerName' could not be removed: $($removal.Error). Remove it by hand, then run again."
            }
        }
    }

    # Find or build the container, then verify it once. Building is not a repair: a run that starts
    # from nothing still gets the one replacement below. The old loop spent an attempt on the build
    # and then reported "failed verification twice, the second time after it was replaced" about a
    # container it had created once and never replaced.
    $state = Get-AhkFlowTestSqlContainerState -ContainerName $containerName
    if ($state) {
        Assert-AhkFlowTestSqlOwnership -ContainerName $containerName -State $state -ComposeProject $composeProject
        $reused = $true
    }
    else {
        $state = New-AhkFlowTestSqlContainer -ContainerName $containerName -ComposeProject $composeProject
        $reused = $false
    }

    # One replacement, and only one. A verify-and-replace loop against a genuinely broken Docker
    # would spin instead of failing, so the second failure throws with the reason and the name.
    $problem = Test-AhkFlowTestSqlContainer -ContainerName $containerName -State $state
    if ($problem) {
        Write-Verbose "Replacing test SQL container '$containerName': $problem"

        # Guarded for the same reason as the -Fresh removal above. The container was inspected
        # before it was verified, and the removal is a later moment than either.
        $removal = Remove-WorktreeTestSqlContainer -Name $containerName -ExpectedProject $composeProject
        if (-not $removal.Removed) {
            throw "The test SQL container '$containerName' failed verification ($problem) and could not be removed: $($removal.Error). Remove it by hand, then run again."
        }

        $reused = $false
        $state = New-AhkFlowTestSqlContainer -ContainerName $containerName -ComposeProject $composeProject

        $problem = Test-AhkFlowTestSqlContainer -ContainerName $containerName -State $state
        if ($problem) {
            throw "The test SQL container '$containerName' failed verification after it was replaced with a new one: $problem"
        }
    }

    # Inspected again, and not carried over from above. The container publishes an ephemeral host
    # port, and Docker allocates a new one every time the container starts, so a container the
    # verification restarted answers on a different port from the one the earlier inspect reported.
    $state = Get-AhkFlowTestSqlContainerState -ContainerName $containerName
    if (-not $state) {
        throw "The test SQL container '$containerName' does not exist after the script tried to build it."
    }

    $stopwatch.Stop()
    return (New-AhkFlowTestSqlResult -State $state -ContainerName $containerName -Reused $reused -Stopwatch $stopwatch)
}

function Wait-AhkFlowTestSqlReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [int]$TimeoutSeconds = 60
    )

    # A failing query is what this loop is built to expect: SQL Server takes seconds to accept
    # connections, and every poll before it does exits non-zero. PowerShell 7.4 turns that into a
    # terminating error while $ErrorActionPreference is Stop and
    # $PSNativeCommandUseErrorActionPreference is true, so the first poll would throw and the
    # timeout would never be reached. Setting the preference here creates a copy scoped to this
    # function, so the caller's value is untouched when it returns, and the variable does not exist
    # in 5.1, where setting it is harmless.
    #
    # Test-AhkFlowTestSqlContainer catches whatever escapes this function and calls the container
    # unverifiable, so without this line a healthy container that needed three seconds to boot
    # would be replaced instead of waited for.
    $PSNativeCommandUseErrorActionPreference = $false

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastOutput = ''
    $sqlcmdPaths = @('/opt/mssql-tools18/bin/sqlcmd', '/opt/mssql-tools/bin/sqlcmd')

    while ((Get-Date) -lt $deadline) {
        foreach ($sqlcmdPath in $sqlcmdPaths) {
            $sqlcmdOutput = & docker exec $ContainerName $sqlcmdPath -S localhost -U sa -P $Password -Q 'SELECT 1' -C -b 2>&1
            if ($LASTEXITCODE -eq 0) {
                return
            }

            if ($sqlcmdOutput) {
                $lastOutput = $sqlcmdOutput -join [Environment]::NewLine
            }
        }

        Start-Sleep -Seconds 1
    }

    $logs = & docker logs --tail 80 $ContainerName 2>&1
    throw "Shared SQL test container '$ContainerName' did not become ready within $TimeoutSeconds seconds. Last sqlcmd output: $lastOutput$([Environment]::NewLine)Docker logs:$([Environment]::NewLine)$($logs -join [Environment]::NewLine)"
}

# Removes one container by name. A throwaway container carries no ownership labels, so a caller
# that owns one passes no -ExpectedProject, and the removal runs on the name alone.
#
# scripts/measure-tests.ps1 calls this today, to remove the throwaway container it built with
# -Ephemeral. scripts/test-fast.ps1 and scripts/run-coverage.ps1 no longer call this function: they
# share one container between runs and leave it running, so nothing they do removes it by name.
# -ExpectedProject stays optional, so a future caller can ask for that check without breaking one
# that does not.
function Stop-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param(
        [string]$ContainerName,
        [string]$ExpectedProject
    )

    if ([string]::IsNullOrWhiteSpace($ContainerName)) { return }

    $removeArgs = @{ Name = $ContainerName }
    if ($PSBoundParameters.ContainsKey('ExpectedProject')) {
        $removeArgs['ExpectedProject'] = $ExpectedProject
    }

    $result = Remove-WorktreeTestSqlContainer @removeArgs
    if (-not $result.Removed -and $result.Error) {
        Write-Warning "Failed to remove test SQL container '$ContainerName': $($result.Error)"
    }
}
