#Requires -Version 7.0

# Backlog 133. The shared SQL test container is found, restarted, reused, replaced once, or refused.
# Every one of those is a decision the run's correctness rests on, and driving them by hand proves
# each one once. This suite stubs the docker CLI and drives Start-AhkFlowTestSqlContainer through
# every branch instead.
#
# Run it by hand with:  pwsh ./tests/TestSqlContainerLifecycle.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
    } catch {
        $script:failures += "$Name threw: $($_.Exception.Message)"
    }
}

# --- the fixture -------------------------------------------------------------------------------
#
# The two scripts under test are copied, not dot-sourced in place, so a case can point PATH at stub
# commands without a real docker or a real git anywhere near it. The docker stub answers 'inspect'
# from a plan file, one entry per call, which is what lets a case say "missing, then healthy" and
# drive the create path, or "noport, then healthy" and drive the replacement path.

function New-SqlContainerFixture {
    param([string[]] $InspectPlan = @('healthy'), [string] $ComposeProject = 'ahkflowapp_probe_deadbeef')

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('testsql-lifecycle-' + [guid]::NewGuid().ToString('N'))
    $scriptFolder = Join-Path $root 'scripts'
    $stubFolder = Join-Path $root 'stub'
    New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $stubFolder -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stubFolder 'gitdir') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stubFolder 'gitcommon') -Force | Out-Null

    foreach ($name in @('worktree-docker.common.ps1', 'worktree-git.common.ps1', 'test-sql-container.common.ps1', 'worktree-log.common.ps1', 'prune-worktree-docker.ps1')) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'scripts') $name) -Destination (Join-Path $scriptFolder $name)
    }

    # The manifest is how Get-AhkFlowTestSqlComposeProject names a linked worktree, so the container
    # name is decided by the fixture rather than by whatever branch the suite happens to run on.
    Set-Content -LiteralPath (Join-Path $scriptFolder '.env.worktree') -Encoding utf8 `
        -Value "AHKFLOW_COMPOSE_PROJECT=$ComposeProject"

    Set-Content -LiteralPath (Join-Path $stubFolder 'inspect-plan.txt') -Encoding utf8 -Value $InspectPlan
    Set-Content -LiteralPath (Join-Path $stubFolder 'project-label.txt') -Encoding utf8 -Value $ComposeProject

    # What the repository label says when a case does not override it: this fixture's own clone.
    # Get-WorktreeRepositoryId reports the main checkout's path, normalised, and the git stub below
    # answers --git-common-dir with '<stub>/gitcommon', so that path is the stub folder itself. The
    # fixture can therefore write the exact value the sweep will compute, with no hash to duplicate.
    Set-Content -LiteralPath (Join-Path $stubFolder 'repository-id.txt') -Encoding utf8 `
        -Value $stubFolder.TrimEnd('\', '/').ToLowerInvariant()

    # What 'docker ps' answers when a case does not say. Both removals in the container script pass
    # -ExpectedProject, and that guard re-reads the host through this listing, so without a default
    # the guard would refuse every removal and half the cases below would fail for the wrong reason.
    # A case that cares about discovery overwrites this file, and one case writes an empty one.
    Set-Content -LiteralPath (Join-Path $stubFolder 'ps-lines.txt') -Encoding utf8 `
        -Value "$ComposeProject-testsql|$ComposeProject|running"

    # The stubs are .ps1 files, the way tests/CoverageRunnerProgress.Tests.ps1 already stubs docker.
    #
    # One thing that costs is worth stating, because it decides where the preference cases below
    # live. A .ps1 on PATH is not a native command, so a non-zero exit from it never raises
    # NativeCommandExitException, whatever $PSNativeCommandUseErrorActionPreference says. These
    # cases therefore prove the decisions the script makes, and never that it survives that
    # preference. A .cmd shim in front of the .ps1 would be a native command, and it was tried: it
    # cannot carry these arguments. cmd.exe reads the '^' in 'name=^ahkflow-testsql-' as its own
    # escape character, which unbalances the quoting around the next argument and turns the '|' in
    # the --format string into a pipe. The guarantee is covered instead by the scope case and the
    # source rule at the end of this file.
    Set-Content -LiteralPath (Join-Path $stubFolder 'git.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
Add-Content -LiteralPath (Join-Path $stubFolder 'git-calls.txt') -Value ($args -join ' ')

# A case drops this marker to make git unable to answer at all, which is the only way to reach the
# "cannot name the Compose project" throw.
if (Test-Path -LiteralPath (Join-Path $stubFolder 'git-fail.txt')) { exit 128 }

# And this one fails a single verb, so a case can break worktree discovery while leaving the rest of
# git working. That is the shape the sweep has to survive: 'rev-parse --show-toplevel' answers, and
# 'worktree list' does not.
$failVerb = ''
$failVerbPath = Join-Path $stubFolder 'git-fail-verb.txt'
if (Test-Path -LiteralPath $failVerbPath) { $failVerb = (Get-Content -LiteralPath $failVerbPath -Raw).Trim() }

if ($args -contains 'worktree') {
    if ($failVerb -eq 'worktree') { Write-Output 'fatal: could not read the worktree list'; exit 128 }
    $listPath = Join-Path $stubFolder 'worktree-list.txt'
    if (Test-Path -LiteralPath $listPath) { Get-Content -LiteralPath $listPath | Write-Output }
    exit 0
}

if ($args -contains '--show-toplevel') {
    Write-Output (Split-Path -Parent $stubFolder)
    exit 0
}

if ($args -contains '--abbrev-ref') {
    if ($failVerb -eq 'rev-parse-abbrev') { Write-Output 'fatal: ambiguous argument HEAD'; exit 128 }
    Write-Output 'stub-branch'
    exit 0
}

# Two different directories, so Test-LinkedWorktree reports a linked worktree. Both exist, because
# Resolve-GitPath resolves whatever it is given.
#
# A case drops 'git-main-checkout.txt' to make both answers the same path, which is what
# Test-LinkedWorktree compares, so the stub then reports the main checkout. That is the branch
# Get-AhkFlowTestSqlComposeProject used to answer with the bare base name for every clone on the
# machine, and it is where two clones collided on one container.
#
# --git-common-dir answers the same either way. It names the git directory every worktree of one
# clone shares, and Get-WorktreeRepositoryId reads its parent as the clone's identity.
if ($args -contains '--git-common-dir') { Write-Output (Join-Path $stubFolder 'gitcommon'); exit 0 }
if ($args -contains '--git-dir') {
    $ownDir = if (Test-Path -LiteralPath (Join-Path $stubFolder 'git-main-checkout.txt')) { 'gitcommon' } else { 'gitdir' }
    Write-Output (Join-Path $stubFolder $ownDir)
    exit 0
}
Write-Output 'stub-branch'
exit 0
'@

    Set-Content -LiteralPath (Join-Path $stubFolder 'docker.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
Add-Content -LiteralPath (Join-Path $stubFolder 'docker-calls.txt') -Value ($args -join ' ')

function Get-StubExit {
    param([string] $Verb)
    $path = Join-Path $stubFolder "$Verb-exit.txt"
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    return [int] (Get-Content -LiteralPath $path -Raw).Trim()
}

# The first N calls to a verb fail, and every call after that succeeds. The readiness poll needs
# this: a query that failed for ever would take the whole timeout, and the thing worth proving is
# that the loop carries on past a failure at all.
function Get-StubExitAfterFailures {
    param([string] $Verb)
    $path = Join-Path $stubFolder "$Verb-fail-count.txt"
    if (-not (Test-Path -LiteralPath $path)) { return (Get-StubExit $Verb) }

    $wanted = [int] (Get-Content -LiteralPath $path -Raw).Trim()
    $countPath = Join-Path $stubFolder "$Verb-count.txt"
    $count = 0
    if (Test-Path -LiteralPath $countPath) { $count = [int] (Get-Content -LiteralPath $countPath -Raw).Trim() }
    Set-Content -LiteralPath $countPath -Value ($count + 1)
    if ($count -lt $wanted) { return 1 }
    return 0
}

# 'inspect' walks a plan, one entry per call, and repeats the last entry once the plan runs out.
# The counter is a file because every docker call is its own process.
function Get-NextInspectShape {
    $plan = @(Get-Content -LiteralPath (Join-Path $stubFolder 'inspect-plan.txt'))
    $countPath = Join-Path $stubFolder 'inspect-count.txt'
    $count = 0
    if (Test-Path -LiteralPath $countPath) { $count = [int] (Get-Content -LiteralPath $countPath -Raw).Trim() }
    Set-Content -LiteralPath $countPath -Value ($count + 1)
    if ($count -ge $plan.Count) { return $plan[$plan.Count - 1] }
    return $plan[$count]
}

$project = (Get-Content -LiteralPath (Join-Path $stubFolder 'project-label.txt') -Raw).Trim()
$repository = (Get-Content -LiteralPath (Join-Path $stubFolder 'repository-id.txt') -Raw).Trim()
$image = 'mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04'

# JSON needs the path in the repository label escaped, because it is a Windows path and every
# separator in it is a backslash. Left unescaped, ConvertFrom-Json in the script under test either
# reads '\D' as an invalid escape or silently eats the separator, and the ownership check would then
# compare two strings that differ for a reason no case is about.
function ConvertTo-JsonText {
    param([string] $Value)
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Write-InspectJson {
    param([bool] $Running, [string] $Image, [string] $Role, [string] $Project, [string] $HostPort, [string] $Repository)
    $ports = if ($HostPort) { '{"1433/tcp":[{"HostIp":"127.0.0.1","HostPort":"' + $HostPort + '"}]}' } else { '{}' }
    Write-Output ('[{"Id":"' + ('a' * 64) + '",' +
        '"State":{"Running":' + $Running.ToString().ToLowerInvariant() + '},' +
        '"Config":{"Image":"' + $Image + '",' +
        '"Labels":{"com.ahkflowapp.role":"' + $Role + '","com.ahkflowapp.compose-project":"' + $Project + '"' +
        ',"com.ahkflowapp.repository":"' + (ConvertTo-JsonText $Repository) + '"}},' +
        '"NetworkSettings":{"Ports":' + $ports + '}}]')
}

switch ($args[0]) {
    'run' {
        $code = Get-StubExit 'run'
        if ($code -ne 0) { Write-Output 'stub docker: no such image'; exit $code }
        Write-Output 'stubcontainerid'
        exit 0
    }
    'inspect' {
        switch (Get-NextInspectShape) {
            'missing'      { Write-Output 'Error: No such object'; exit 1 }
            'healthy'      { Write-InspectJson -Running $true  -Image $image -Role 'test-sql' -Project $project -HostPort '14399' -Repository $repository; exit 0 }
            'stopped'      { Write-InspectJson -Running $false -Image $image -Role 'test-sql' -Project $project -HostPort '14399' -Repository $repository; exit 0 }
            'noport'       { Write-InspectJson -Running $true  -Image $image -Role 'test-sql' -Project $project -HostPort '' -Repository $repository; exit 0 }
            'wrongimage'   { Write-InspectJson -Running $true  -Image 'mcr.microsoft.com/mssql/server:2022-latest' -Role 'test-sql' -Project $project -HostPort '14399' -Repository $repository; exit 0 }
            'wrongrole'    { Write-InspectJson -Running $true  -Image $image -Role 'something-else' -Project $project -HostPort '14399' -Repository $repository; exit 0 }
            'wrongproject' { Write-InspectJson -Running $true  -Image $image -Role 'test-sql' -Project 'ahkflowapp_someone_else_c0ffee01' -HostPort '14399' -Repository $repository; exit 0 }
            # Same name, same Compose project, another clone. Two clones can hold a branch by the
            # same name, so the project label alone cannot tell them apart and the ownership check
            # has to read the repository label to refuse this one.
            'wrongrepository' { Write-InspectJson -Running $true -Image $image -Role 'test-sql' -Project $project -HostPort '14399' -Repository 'D:\another\clone'; exit 0 }
            # A container built before the repository label existed. This repository's own, from an
            # earlier run, and not another clone's.
            'nolabel'      { Write-InspectJson -Running $true  -Image $image -Role 'test-sql' -Project $project -HostPort '14399' -Repository ''; exit 0 }
            default        { Write-Output 'Error: No such object'; exit 1 }
        }
    }
    'ps' {
        # Call n reads ps-lines-<n>.txt when a case wrote one, and ps-lines.txt otherwise. That lets
        # a case change what the host looks like between the sweep's listing and its removal, which
        # is the only way to reach the check that stands between them.
        $psCountPath = Join-Path $stubFolder 'ps-count.txt'
        $psCount = 0
        if (Test-Path -LiteralPath $psCountPath) { $psCount = [int] (Get-Content -LiteralPath $psCountPath -Raw).Trim() }
        Set-Content -LiteralPath $psCountPath -Value ($psCount + 1)

        $path = Join-Path $stubFolder "ps-lines-$($psCount + 1).txt"
        if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $stubFolder 'ps-lines.txt' }
        if (-not (Test-Path -LiteralPath $path)) { exit 0 }

        # The name filter is applied, not ignored. Docker's is a regular expression with no implied
        # end anchor, and the legacy sweep's pattern is the only thing standing between it and a
        # container somebody else named with the same prefix. A stub that answered every filter the
        # same way could not tell a correct pattern from a careless one.
        $namePattern = $null
        for ($i = 0; $i -lt $args.Count - 1; $i++) {
            if ($args[$i] -eq '--filter' -and $args[$i + 1] -like 'name=*') {
                $namePattern = $args[$i + 1].Substring('name='.Length)
            }
        }

        foreach ($line in Get-Content -LiteralPath $path) {
            if (-not $line.Trim()) { continue }
            if ($namePattern -and $line.Split('|')[0] -notmatch $namePattern) { continue }

            # A ps-lines row is written as 'Name|Project|State', and the repository label is filled
            # in from this fixture's own clone. A case that needs a container belonging to a
            # different clone writes a fourth field and overrides it. Filling it in this way keeps
            # every case written before the repository label saying what it always said: this
            # container is ours.
            if ($line.Split('|').Count -lt 4) { $line = "$line|$repository" }
            Write-Output $line
        }
        exit 0
    }
    'start' { exit (Get-StubExit 'start') }
    'exec'  { exit (Get-StubExitAfterFailures 'exec') }
    'logs'  { Write-Output 'stub docker logs'; exit 0 }
    'rm'    { exit (Get-StubExit 'rm') }
    default { exit 0 }
}
'@

    return $root
}

function Remove-SqlContainerFixture {
    param([string] $Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Runs one expression in a child pwsh with the fixture's stubs first on PATH. A child process,
# because the script under test reads its image once when it is dot-sourced, and because a stub
# that leaked into this session would follow every later case.
#
# <ROOT> in the expression becomes the fixture's own path, quoted. A case that built the path by
# concatenation instead would be parsed in argument mode, where '+' is another argument rather than
# an operator, and the expression would arrive truncated.
#
# CmdletBinding is deliberate. Without it a plain function collects an unbound argument into $args
# and drops it in silence, which is exactly how a truncated expression reaches the child unnoticed.
function Invoke-InFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Expression,
        [switch] $NativeErrorsOn
    )

    $prelude = if ($NativeErrorsOn) {
        '$ErrorActionPreference = ''Stop''; $PSNativeCommandUseErrorActionPreference = $true; '
    } else {
        '$ErrorActionPreference = ''Stop''; $PSNativeCommandUseErrorActionPreference = $false; '
    }

    $body = $Expression.Replace('<ROOT>', "'$Root'")

    $command = "`$env:PATH = '$(Join-Path $Root 'stub')' + [System.IO.Path]::PathSeparator + `$env:PATH; " +
        $prelude +
        ". '$(Join-Path (Join-Path $Root 'scripts') 'test-sql-container.common.ps1')'; " +
        "try { $body } catch { Write-Output (""THREW: "" + `$_.Exception.Message) }"

    $output = & pwsh -NoProfile -Command $command 2>&1
    return ($output | Out-String)
}

function Get-DockerCall {
    param([string] $Root, [string] $Verb)
    $path = Join-Path (Join-Path $Root 'stub') 'docker-calls.txt'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path | Where-Object { $_ -like "$Verb *" -or $_ -eq $Verb })
}

# Every count goes through here. Get-DockerCall returns a plain array, so an empty result reaches
# the caller as nothing at all and $null.Count throws under Set-StrictMode.
function Get-DockerCallCount {
    param([string] $Root, [string] $Verb)
    return @(Get-DockerCall -Root $Root -Verb $Verb).Count
}

# --- cases -------------------------------------------------------------------------------------

Invoke-TestCase 'A first run builds the container and does not call it reused' {
    $root = New-SqlContainerFixture -InspectPlan @('missing', 'healthy', 'healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "name=$($r.ContainerName) reused=$($r.Reused)"'
        Assert-True ($out -match 'name=ahkflowapp_probe_deadbeef-testsql') "Expected the manifest's name. Got: $out"
        Assert-True ($out -match 'reused=False') "A built container must not report reused. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) 'Expected exactly one docker run.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'A first run must remove nothing.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A healthy container is reused and nothing is built' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=True') "Expected reuse. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 0) 'Reuse must not call docker run.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'Reuse must not remove anything.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A stopped container is started, not replaced' {
    $root = New-SqlContainerFixture -InspectPlan @('stopped', 'healthy', 'healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=True') "A restart is still a reuse. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'start') -eq 1) 'Expected exactly one docker start.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'A stopped container must not be removed.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 0) 'A stopped container must not be rebuilt.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container that fails verification is replaced exactly once' {
    $root = New-SqlContainerFixture -InspectPlan @('noport', 'healthy', 'healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=False') "A replaced container must not report reused. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 1) 'Expected exactly one docker rm.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) 'Expected exactly one docker run.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container built from the wrong image is replaced, not restarted' {
    # The image check runs before the running/port/query checks in Test-AhkFlowTestSqlContainer, so
    # a container built from an old SQL Server tag must never be patched up in place. Restarting it
    # would leave a run testing the wrong server, silently.
    $root = New-SqlContainerFixture -InspectPlan @('wrongimage', 'healthy', 'healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=False') "A replaced container must not report reused. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 1) 'Expected exactly one docker rm.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) 'Expected exactly one docker run.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A replacement that fails verification too stops the run and says so' {
    $root = New-SqlContainerFixture -InspectPlan @('noport')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'after it was replaced') "Expected the replacement message. Got: $out"
        Assert-True ($out -match 'publishes no host port') "The message must carry the reason. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) 'Expected exactly one replacement build.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A build that fails verification is not reported as a second failure' {
    # The container never existed, so this run built it, and that build already fails verification.
    # It still gets the one replacement every path gets, so two builds happen in total, not three.
    $root = New-SqlContainerFixture -InspectPlan @('missing', 'noport', 'noport', 'noport')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'THREW') "Expected a failure. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 2) `
            "A build must still get its one replacement, so two builds. Got: $((Get-DockerCallCount -Root $root -Verb 'run'))"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container carrying the wrong role label is refused, not removed' {
    $root = New-SqlContainerFixture -InspectPlan @('wrongrole')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'com.ahkflowapp.role') "The message must name the label. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'A container this script did not build must survive.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container belonging to another checkout is refused, not removed' {
    $root = New-SqlContainerFixture -InspectPlan @('wrongproject')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'ahkflowapp_someone_else_c0ffee01') "The message must name the other checkout. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) "Another checkout's container must survive."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Fresh checks ownership before it removes anything' {
    $root = New-SqlContainerFixture -InspectPlan @('wrongproject')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -Fresh -RepoRoot <ROOT>'
        Assert-True ($out -match 'ahkflowapp_someone_else_c0ffee01') "Fresh must refuse another checkout's container. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'Fresh must not remove by name alone.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Fresh removes the checkout own container and builds a new one' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy', 'missing', 'healthy', 'healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -Fresh -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=False') "Fresh must never report reuse. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 1) 'Expected exactly one docker rm.'
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) 'Expected exactly one docker run.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Fresh stops the run when the removal fails, instead of reusing' {
    # The failure this case exists for: a removal that failed used to fall through to the reuse
    # path, verify the old container, find it healthy, and report Reused=True from a run that asked
    # for an empty server.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'rm-exit.txt') -Value '1'
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -Fresh -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'THREW') "A failed removal must stop the run. Got: $out"
        Assert-True ($out -notmatch 'reused=True') "A failed Fresh must never report reuse. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 0) 'Nothing should be built after a failed removal.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Fresh refuses a removal when the name changed hands after the inspect' {
    # The window -ExpectedProject exists for. The inspect says this checkout owns the container, and
    # by the moment the removal runs the host says the name belongs to somebody else. Removing on
    # the strength of the earlier inspect would take another checkout's server.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_probe_deadbeef-testsql|ahkflowapp_live_deadbeef|running'
        )
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -Fresh -RepoRoot <ROOT>'
        Assert-True ($out -match 'THREW') "A refused removal must stop the run. Got: $out"
        Assert-True ($out -match 'belongs to the checkout') "The message must say why. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "No docker rm may run. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A replacement refuses when the name changed hands after the inspect' {
    # Same window, one path down. The container was inspected, then failed verification, and the
    # host says the name is somebody else's by the time the replacement tries to remove it.
    $root = New-SqlContainerFixture -InspectPlan @('noport')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_probe_deadbeef-testsql|ahkflowapp_live_deadbeef|running'
        )
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'could not be removed') "The run must stop with the removal error. Got: $out"
        Assert-True ($out -match 'belongs to the checkout') "The message must say why. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 0) `
            'Nothing may be built after a refused removal.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A build that docker refuses names the container and the image' {
    $root = New-SqlContainerFixture -InspectPlan @('missing')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'run-exit.txt') -Value '1'
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'docker run failed for test SQL container') "Expected the script's own message. Got: $out"
        Assert-True ($out -match 'ahkflowapp_probe_deadbeef-testsql') 'The message must name the container.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A function-scoped preference shields its own native calls and leaks nothing' {
    # The technique every docker-running function relies on, proved against a real native command
    # rather than a stub. Two halves: inside the function the failing call is data, and after the
    # function returns the caller's own preference is exactly as it was.
    $probe = {
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $true

        function Invoke-Scoped {
            $PSNativeCommandUseErrorActionPreference = $false
            $null = & cmd /c 'exit 1' 2>&1
            return "inside=ok exit=$LASTEXITCODE"
        }

        try { Write-Output (Invoke-Scoped) } catch { Write-Output "inside=threw" }
        try { $null = & cmd /c 'exit 1' 2>&1; Write-Output 'outside=leaked' } catch { Write-Output 'outside=still-strict' }
    }
    $out = (& pwsh -NoProfile -Command $probe.ToString() 2>&1 | Out-String)
    Assert-True ($out -match 'inside=ok exit=1') "The scoped call must read the exit code, not throw. Got: $out"
    Assert-True ($out -match 'outside=still-strict') "The preference must not leak out of the function. Got: $out"
}

Invoke-TestCase 'Every function that runs docker scopes that preference itself' {
    # The case above proves the technique. This one proves it is applied everywhere, which is what a
    # stub cannot check: a .ps1 stub is not a native command, so no case driving the script through
    # one would ever notice a missing line.
    $sources = @(
        (Join-Path (Join-Path $repoRoot 'scripts') 'test-sql-container.common.ps1')
        (Join-Path (Join-Path $repoRoot 'scripts') 'worktree-docker.common.ps1')
    )

    foreach ($source in $sources) {
        $text = Get-Content -LiteralPath $source -Raw
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref] $null, [ref] $errors)
        Assert-True (-not $errors) "$(Split-Path -Leaf $source) must parse cleanly."

        $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        foreach ($function in $functions) {
            $body = $function.Extent.Text
            if ($body -notmatch '&\s*docker\b') { continue }
            Assert-True ($body -match '\$PSNativeCommandUseErrorActionPreference\s*=\s*\$false') `
                ("$($function.Name) runs docker and does not scope " +
                 '$PSNativeCommandUseErrorActionPreference to $false, so a non-zero exit becomes a ' +
                 'terminating error under $ErrorActionPreference = Stop.')
        }
    }
}

Invoke-TestCase 'The readiness poll keeps polling after a failing query' {
    # The first two queries fail, the way they do while SQL Server is still starting, and the third
    # succeeds. A poll that gave up on the first failure would report a healthy container as
    # unverifiable, and Test-AhkFlowTestSqlContainer would replace one that needed three seconds to
    # boot. This case covers the loop; the preference that also has to hold here is covered by the
    # two cases at the end of the file.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'exec-fail-count.txt') -Value '2'
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "reused=$($r.Reused)"'
        Assert-True ($out -match 'reused=True') "The poll must wait, then reuse. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'exec') -ge 3) `
            "The poll must keep trying past a failure. Got $((Get-DockerCallCount -Root $root -Verb 'exec')) exec call(s)."
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            'A container that only needed a moment must not be replaced.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A checkout git cannot name stops the run instead of guessing' {
    # The failure this case exists for: treating an unreadable checkout as the main checkout hands
    # it the bare base name, so two checkouts share one container and their database names match.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'git-fail.txt') -Value 'x'
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>; "name=$($r.ContainerName)"'
        # The message is asserted, not just the throw. Falling back to the base name also ends in a
        # throw here, from the ownership check further down, so "something failed" would pass either
        # way and prove nothing.
        Assert-True ($out -match 'is a linked worktree or the main checkout') `
            "The failure must name the git problem, not a later one. Got: $out"
        Assert-True ($out -notmatch 'name=ahkflowapp-testsql') "It must never fall back to the main checkout's name. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Ephemeral builds a throwaway container that carries no labels' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $out = Invoke-InFixture -Root $root -Expression '$r = Start-AhkFlowTestSqlContainer -Ephemeral; "name=$($r.ContainerName) reused=$($r.Reused)"'
        Assert-True ($out -match 'name=ahkflow-testsql-') "Expected a throwaway name. Got: $out"
        Assert-True ($out -match 'reused=False') 'A throwaway container is never reused.'
        $run = @(Get-DockerCall -Root $root -Verb 'run')
        Assert-True ($run.Count -eq 1) 'Expected exactly one docker run.'
        Assert-True ($run[0] -notmatch 'com.ahkflowapp.role') "A throwaway container must carry no labels. Got: $($run[0])"
    } finally { Remove-SqlContainerFixture -Root $root }
}

# --- the discovery helpers ---------------------------------------------------------------------

Invoke-TestCase 'Discovery walks every container, one at a time' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_one_11111111-testsql|ahkflowapp_one_11111111|running'
            'ahkflowapp_two_22222222-testsql|ahkflowapp_two_22222222|exited'
        )
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$n = 0; foreach ($c in Get-WorktreeTestSqlContainerOnHost) { $n++ }; ' +
            '"iterations=$n names=$((@(Get-WorktreeTestSqlContainerOnHost)).Count)"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        Assert-True ($out -match 'iterations=2') "foreach must walk both rows. Got: $out"
        Assert-True ($out -match 'names=2') "The count must read two. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The legacy sweep takes only containers in a terminal state' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflow-testsql-1-aaaaaaaa|exited'
            'ahkflow-testsql-2-bbbbbbbb|dead'
            'ahkflow-testsql-3-cccccccc|running'
            'ahkflow-testsql-4-dddddddd|paused'
            'ahkflow-testsql-5-eeeeeeee|restarting'
            'ahkflow-testsql-6-ffffffff|created'
            'ahkflow-testsql-7-99999999|removing'
        )
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$names = @(Get-WorktreeLegacyTestSqlContainerOnHost); "taken=[$($names -join '','')]"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        # The brackets matter. -match searches for a substring, so a sweep that also took the paused
        # and restarting containers would still contain the two-name text and the case would pass.
        Assert-True ($out -match 'taken=\[ahkflow-testsql-1-aaaaaaaa,ahkflow-testsql-2-bbbbbbbb\]') `
            "Only exited and dead may be reclaimed, and nothing else. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The legacy sweep matches the whole historical name, not a prefix' {
    # A terminal state says a container is finished. It says nothing about who owns it, and these
    # carry no label to ask, so the name is the only evidence there is. Docker's name filter adds no
    # end anchor, so a bare '^ahkflow-testsql-' prefix takes anything that starts the same way.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflow-testsql-24264-ad8817c9|exited'
            'ahkflow-testsql-unrelated-service|exited'
            'ahkflow-testsql-prod-db|exited'
            'ahkflow-testsql-8476-59d7b162|exited'
        )
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$names = @(Get-WorktreeLegacyTestSqlContainerOnHost); "taken=[$($names -join '','')]"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        Assert-True ($out -match 'taken=\[ahkflow-testsql-24264-ad8817c9,ahkflow-testsql-8476-59d7b162\]') `
            "Only the full <pid>-<8 hex> shape may be reclaimed. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A guarded removal refuses a container that carries no role label' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        # ps-lines.txt is what discovery sees, and discovery is filtered on the role label. An empty
        # listing is therefore how a container with no role label looks from here.
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @()
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$r = Remove-WorktreeTestSqlContainer -Name ''ahkflowapp_probe_deadbeef-testsql'' -ExpectedProject ''ahkflowapp_probe_deadbeef''; ' +
            '"removed=$($r.Removed) error=$($r.Error)"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        Assert-True ($out -match 'removed=False') "An unlabelled container must not be removed. Got: $out"
        Assert-True ($out -match 'com\.ahkflowapp\.role') "The message must name the missing label. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'No docker rm may run.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A guarded removal refuses another checkout''s container' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_probe_deadbeef-testsql|ahkflowapp_someone_else_c0ffee01|running'
        )
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$r = Remove-WorktreeTestSqlContainer -Name ''ahkflowapp_probe_deadbeef-testsql'' -ExpectedProject ''ahkflowapp_probe_deadbeef''; ' +
            '"removed=$($r.Removed) error=$($r.Error)"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        Assert-True ($out -match 'removed=False') "Another checkout's container must not be removed. Got: $out"
        Assert-True ($out -match 'ahkflowapp_someone_else_c0ffee01') "The message must name the owner. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'No docker rm may run.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A guarded removal proceeds when both labels agree' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_probe_deadbeef-testsql|ahkflowapp_probe_deadbeef|running'
        )
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$r = Remove-WorktreeTestSqlContainer -Name ''ahkflowapp_probe_deadbeef-testsql'' -ExpectedProject ''ahkflowapp_probe_deadbeef''; ' +
            '"removed=$($r.Removed)"'
        $out = Invoke-InFixture -Root $root -Expression $expression
        Assert-True ($out -match 'removed=True') "The checkout's own container must be removed. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 1) 'Expected exactly one docker rm.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The legacy sweep asks docker not to force the removal' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $expression = '. ''' + (Join-Path (Join-Path $root 'scripts') 'worktree-docker.common.ps1') + '''; ' +
            '$null = Remove-WorktreeTestSqlContainer -Name ''ahkflow-testsql-1-aaaaaaaa'' -OnlyIfStopped; ' +
            '$null = Remove-WorktreeTestSqlContainer -Name ''ahkflowapp_probe_deadbeef-testsql''; "done"'
        $null = Invoke-InFixture -Root $root -Expression $expression
        $rm = @(Get-DockerCall -Root $root -Verb 'rm')
        Assert-True ($rm.Count -eq 2) "Expected two removals. Got: $($rm -join ' | ')"
        Assert-True ($rm[0] -notmatch '--force') "-OnlyIfStopped must drop --force. Got: $($rm[0])"
        Assert-True ($rm[1] -match '--force') "The normal removal keeps --force. Got: $($rm[1])"
    } finally { Remove-SqlContainerFixture -Root $root }
}

# --- the sweep ---------------------------------------------------------------------------------
#
# prune-worktree-docker.ps1 decides what is an orphan from what git tells it about live checkouts.
# These cases run the real script against the fixture's stubs.

function Invoke-Prune {
    param([Parameter(Mandatory = $true)][string] $Root)

    $command = "`$env:PATH = '$(Join-Path $Root 'stub')' + [System.IO.Path]::PathSeparator + `$env:PATH; " +
        "Set-Location '$Root'; " +
        "try { & '$(Join-Path (Join-Path $Root 'scripts') 'prune-worktree-docker.ps1')' } " +
        "catch { Write-Output (""THREW: "" + `$_.Exception.Message) }"

    return ((& pwsh -NoProfile -Command $command 2>&1) | Out-String)
}

Invoke-TestCase 'The sweep stops when git cannot list the worktrees, and removes nothing' {
    # The failure this case exists for. Get-LiveComposeProjects threw the exit code away, so a git
    # that could not answer produced an empty live set, and an empty live set means every container
    # on the host is an orphan. A live checkout's server would be removed mid-run.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_live_deadbeef-testsql|ahkflowapp_live_deadbeef|running'
        )
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'git-fail-verb.txt') -Value 'worktree'
        $out = Invoke-Prune -Root $root
        Assert-True ($out -match 'THREW') "The sweep must stop. Got: $out"
        Assert-True ($out -match 'Nothing was removed') "The message must say nothing was removed. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "No container may be removed when the live set is unknown. Got $((Get-DockerCallCount -Root $root -Verb 'rm')) docker rm call(s)."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The sweep spares a live checkout and reclaims an orphan' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_live_deadbeef-testsql|ahkflowapp_live_deadbeef|running'
            'ahkflowapp_gone_c0ffee01-testsql|ahkflowapp_gone_c0ffee01|running'
        )
        # git reports one live worktree, and its manifest names the project that must survive.
        $live = Join-Path $root 'live'
        $null = New-Item -ItemType Directory -Path (Join-Path $live 'scripts') -Force
        Set-Content -LiteralPath (Join-Path $live 'scripts/.env.worktree') -Encoding utf8 `
            -Value 'AHKFLOW_COMPOSE_PROJECT=ahkflowapp_live_deadbeef'
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'worktree-list.txt') -Encoding utf8 -Value @(
            "worktree $root"
            ''
            "worktree $live"
            ''
        )
        $out = Invoke-Prune -Root $root
        Assert-True ($out -notmatch 'THREW') "The sweep must run. Got: $out"
        Assert-True ($out -match 'Removed orphan test SQL container: ahkflowapp_gone_c0ffee01-testsql') `
            "The orphan must be reclaimed. Got: $out"
        Assert-True ($out -notmatch 'ahkflowapp_live_deadbeef-testsql') `
            "The live checkout's container must not be touched. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The sweep refuses a container that changed owner after it was listed' {
    # Why the sweep passes -ExpectedProject even though the project came from its own listing. The
    # listing and the removal are two moments, and prune can run while somebody else is starting a
    # container. Here the orphan is replaced between them by one belonging to a live checkout.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $stub = Join-Path $root 'stub'
        # Call 1 is discovery, and reports an orphan. Call 2 is the guard inside the removal, by
        # which time the name belongs to somebody else.
        Set-Content -LiteralPath (Join-Path $stub 'ps-lines-1.txt') -Encoding utf8 -Value @(
            'ahkflowapp_gone_c0ffee01-testsql|ahkflowapp_gone_c0ffee01|running'
        )
        Set-Content -LiteralPath (Join-Path $stub 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_gone_c0ffee01-testsql|ahkflowapp_live_deadbeef|running'
        )
        Set-Content -LiteralPath (Join-Path $stub 'worktree-list.txt') -Encoding utf8 -Value @("worktree $root", '')

        $out = Invoke-Prune -Root $root
        Assert-True ($out -notmatch 'THREW') "The sweep must run. Got: $out"
        Assert-True ($out -notmatch 'Removed orphan test SQL container') `
            "A container that changed owner must not be reported as removed. Got: $out"
        Assert-True ($out -match 'belongs to the checkout') "The warning must say why. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "No docker rm may run. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The sweep stops when a live worktree cannot be named' {
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_gone_c0ffee01-testsql|ahkflowapp_gone_c0ffee01|running'
        )
        # A worktree with no manifest falls back to its branch, and this git cannot name one.
        $live = Join-Path $root 'live'
        $null = New-Item -ItemType Directory -Path $live -Force
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'worktree-list.txt') -Encoding utf8 -Value @(
            "worktree $root"
            ''
            "worktree $live"
            ''
        )
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'git-fail-verb.txt') -Value 'rev-parse-abbrev'
        $out = Invoke-Prune -Root $root
        Assert-True ($out -match 'THREW') "The sweep must stop. Got: $out"
        Assert-True ($out -match 'could not name its branch') "The message must name the cause. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) 'No container may be removed.'
    } finally { Remove-SqlContainerFixture -Root $root }
}

# --- one clone must not touch another -----------------------------------------------------------
#
# Every case above has one clone of this repository on the host. These four have two. The Compose
# project names a branch, and the sweep listed every container on the machine, so a second clone's
# live container looked exactly like an orphan of the first. The repository label is what tells them
# apart, and it is read at both moments that matter: the sweep, and the ownership check.

Invoke-TestCase 'The sweep spares a live container belonging to another clone' {
    # The failure this case exists for. Discovery is host-wide and the live set came from one
    # repository's worktree list, so another clone's running container was absent from the live set,
    # passed the name-shape guard, and was removed with 'docker rm --force' while its tests ran. The
    # -ExpectedProject guard could not catch it: it re-read the same label the listing had just
    # reported, so it always agreed.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $stub = Join-Path $root 'stub'
        # A fourth field overrides the repository label. This container belongs to a clone that is
        # not the one running the sweep, and no worktree list this sweep can read will ever mention
        # it.
        Set-Content -LiteralPath (Join-Path $stub 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_foreign_deadbeef-testsql|ahkflowapp_foreign_deadbeef|running|D:\another\clone'
        )
        Set-Content -LiteralPath (Join-Path $stub 'worktree-list.txt') -Encoding utf8 -Value @("worktree $root", '')

        $out = Invoke-Prune -Root $root
        Assert-True ($out -notmatch 'THREW') "The sweep must run. Got: $out"
        Assert-True ($out -notmatch 'Removed orphan test SQL container') `
            "Another clone's container must never be reported as removed. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "No docker rm may run against another clone's container. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'The sweep still reclaims an orphan of its own clone' {
    # The control for the case above. A filter that spared everything would pass that one and break
    # the sweep, so this proves the repository check refuses a foreign container without refusing
    # this clone's own dead worktrees.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $stub = Join-Path $root 'stub'
        # Three fields, so the fixture fills in this clone's own repository label.
        Set-Content -LiteralPath (Join-Path $stub 'ps-lines.txt') -Encoding utf8 -Value @(
            'ahkflowapp_gone_c0ffee01-testsql|ahkflowapp_gone_c0ffee01|running'
        )
        Set-Content -LiteralPath (Join-Path $stub 'worktree-list.txt') -Encoding utf8 -Value @("worktree $root", '')

        $out = Invoke-Prune -Root $root
        Assert-True ($out -notmatch 'THREW') "The sweep must run. Got: $out"
        Assert-True ($out -match 'Removed orphan test SQL container: ahkflowapp_gone_c0ffee01-testsql') `
            "This clone's own orphan must still be reclaimed. Got: $out"
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'Two independent main checkouts get different container names' {
    # The second failure. Get-AhkFlowTestSqlComposeProject answered with the bare base name for
    # every checkout that is not a linked worktree, so two clones of this repository both used
    # 'ahkflowapp-testsql'. Their database names are identical and their test-run locks are
    # separate, so concurrent runs dropped each other's databases, and -FreshSql removed the other
    # run's server.
    $first = New-SqlContainerFixture -InspectPlan @('healthy')
    $second = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        foreach ($root in @($first, $second)) {
            Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'git-main-checkout.txt') -Value 'main'
        }

        $expression = 'Write-Output (Get-WorktreeTestSqlContainerName -ComposeProject (Get-AhkFlowTestSqlComposeProject -RepoRoot <ROOT>))'
        $firstName = (Invoke-InFixture -Root $first -Expression $expression).Trim()
        $secondName = (Invoke-InFixture -Root $second -Expression $expression).Trim()

        Assert-True ($firstName -notmatch 'THREW') "Naming the first checkout's container must work. Got: $firstName"
        Assert-True ($secondName -notmatch 'THREW') "Naming the second checkout's container must work. Got: $secondName"
        Assert-True ($firstName -ne 'ahkflowapp-testsql') `
            "A main checkout must not use the bare shared name. Got: $firstName"
        Assert-True ($firstName -ne $secondName) `
            "Two independent checkouts must not share one container. Both got: $firstName"
        Assert-True ($firstName -match '^ahkflowapp_[0-9a-f]{8}-testsql$') `
            "The name must be the base, this clone's id, and the suffix. Got: $firstName"
    } finally {
        Remove-SqlContainerFixture -Root $first
        Remove-SqlContainerFixture -Root $second
    }
}

Invoke-TestCase 'The sweep spares the main checkout own container' {
    # The main checkout used to be spared by the shape of its name: it had no hash suffix, so
    # Test-WorktreeComposeProject refused it and the sweep never reached it. Its name carries a hash
    # now, so that refusal no longer applies and the sweep has to know the main checkout is live.
    $root = New-SqlContainerFixture -InspectPlan @('healthy')
    try {
        $stub = Join-Path $root 'stub'
        Set-Content -LiteralPath (Join-Path $stub 'git-main-checkout.txt') -Value 'main'

        # Asked of the code rather than written out, so this case proves the sweep spares whatever
        # the naming rule produces instead of agreeing with a hash copied into the test.
        $project = (Invoke-InFixture -Root $root -Expression 'Write-Output (Get-AhkFlowTestSqlComposeProject -RepoRoot <ROOT>)').Trim()
        Assert-True ($project -match '^ahkflowapp_[0-9a-f]{8}$') "The main checkout's project must carry its clone id. Got: $project"

        Set-Content -LiteralPath (Join-Path $stub 'ps-lines.txt') -Encoding utf8 -Value @(
            "$project-testsql|$project|running"
        )
        Set-Content -LiteralPath (Join-Path $stub 'worktree-list.txt') -Encoding utf8 -Value @("worktree $root", '')

        $out = Invoke-Prune -Root $root
        Assert-True ($out -notmatch 'THREW') "The sweep must run. Got: $out"
        Assert-True ($out -notmatch 'Removed orphan test SQL container') `
            "The main checkout's own container must never be swept. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "No docker rm may run. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container from another clone is refused, not reused' {
    # Two clones can hold a branch by the same name, so both derive the same Compose project and the
    # same container name. The project label agrees in that case and says nothing useful. Only the
    # repository label can refuse it, and refusing is right: taking it would hand one clone the
    # other's running server.
    $root = New-SqlContainerFixture -InspectPlan @('wrongrepository')
    try {
        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -match 'THREW') "The run must stop. Got: $out"
        Assert-True ($out -match 'another clone') "The message must say the container belongs to another clone. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 0) `
            "Another clone's container must not be removed. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
    } finally { Remove-SqlContainerFixture -Root $root }
}

Invoke-TestCase 'A container built before the repository label is replaced, not refused' {
    # Found by running the real script, not by a stub. Every container already on a machine when
    # this change lands carries no repository label, and reading that as "another clone" stopped the
    # first run outright and told the reader to delete a container by hand. It is this repository's
    # own container from an earlier run, so it is replaced once and rebuilt with all three labels.
    # The unlabelled container the run finds, then the labelled one it builds to replace it.
    $root = New-SqlContainerFixture -InspectPlan @('nolabel', 'healthy')
    try {
        $stub = Join-Path $root 'stub'
        # A fourth field left empty, so the removal guard sees the same missing label the inspect
        # reports. Without it the guard would refuse the removal and the run would deadlock: unable
        # to reuse the container, and unable to replace it either.
        Set-Content -LiteralPath (Join-Path $stub 'ps-lines.txt') -Encoding utf8 `
            -Value 'ahkflowapp_probe_deadbeef-testsql|ahkflowapp_probe_deadbeef|running|'

        $out = Invoke-InFixture -Root $root -Expression 'Start-AhkFlowTestSqlContainer -RepoRoot <ROOT>'
        Assert-True ($out -notmatch 'THREW') "The run must not stop. Got: $out"
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'rm') -eq 1) `
            "The old container must be removed exactly once. Got $((Get-DockerCallCount -Root $root -Verb 'rm'))."
        Assert-True ((Get-DockerCallCount -Root $root -Verb 'run') -eq 1) `
            "A replacement must be built. Got $((Get-DockerCallCount -Root $root -Verb 'run'))."

        # The replacement must carry the label whose absence caused the rebuild, or every run after
        # this one would rebuild the container again.
        $runCall = @(Get-DockerCall -Root $root -Verb 'run')[0]
        Assert-True ($runCall -match 'com\.ahkflowapp\.repository=') `
            "The new container must carry the repository label. Got: $runCall"
    } finally { Remove-SqlContainerFixture -Root $root }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    Write-Host ''
    throw "Test SQL container lifecycle rules failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Test SQL container lifecycle rules passed. 37 cases.'
