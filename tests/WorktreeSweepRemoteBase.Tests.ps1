#Requires -Version 5.1

# Backlog 094. The merged-worktree sweep used to decide against the LOCAL main branch, and nothing
# fetched first. `gh pr merge` merges on GitHub and never advances a local ref, so a worktree whose
# pull request merged an hour ago still looked unmerged and survived until a human pulled.
#
# Every fixture here reproduces that exact state: the merge exists only in the remote, local `main`
# and the cached `refs/remotes/origin/main` both predate it, so only a fresh fetch can see it.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
$cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
$removeScript = Join-Path $scriptsDir 'remove-worktree-local-dev.ps1'

. (Join-Path $scriptsDir 'worktree-git.common.ps1')

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param([string] $Haystack, [string] $Needle, [string] $Message)
    if (($null -eq $Haystack) -or ($Haystack -notlike "*$Needle*")) {
        throw "$Message (expected to find '$Needle' in: $Haystack)"
    }
}

function Assert-NotContains {
    param([string] $Haystack, [string] $Needle, [string] $Message)
    if ($Haystack -and ($Haystack -like "*$Needle*")) {
        throw "$Message (did not expect '$Needle' in: $Haystack)"
    }
}

function Invoke-FixtureGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# A bare 'origin', a clone-shaped 'repo' whose main tracks it, and one worktree branch with a
# commit on it. -Merged performs the merge, pushes it, and then rewinds BOTH local refs, which is
# what a session sees right after `gh pr merge`: the work is on the remote and invisible locally.
function New-RemoteFixture {
    param([switch] $Merged, [switch] $KeepTrackingRef, [switch] $WithScripts)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtremote-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $origin = Join-Path $root 'origin.git'
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    New-Item -ItemType Directory -Path $origin -Force | Out-Null

    & git init --bare --quiet $origin
    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    & git -C $repo config user.email 'test@example.com'
    & git -C $repo config user.name 'Sweep Remote Base Test'

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    if ($WithScripts) {
        # The sweep spawns <repo>\scripts\remove-worktree-local-dev.ps1, so a fixture that must
        # really remove something needs the worktree scripts in place. Top-level *.ps1 only.
        $repoScripts = Join-Path $repo 'scripts'
        New-Item -ItemType Directory -Path $repoScripts -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptsDir '*.ps1') -Destination $repoScripts -Force
    }
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'seed') | Out-Null
    Invoke-FixtureGit $repo @('remote', 'add', 'origin', $origin) | Out-Null
    # -u writes branch.main.remote and branch.main.merge, which is what the resolver reads.
    Invoke-FixtureGit $repo @('push', '--quiet', '-u', 'origin', 'main') | Out-Null

    $branch = 'fix/wt-remote-base'
    $worktree = Join-Path $root 'wt-remote-base'
    Invoke-FixtureGit $repo @('worktree', 'add', '--quiet', '-b', $branch, $worktree, 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'work.txt') -Value 'work' -Encoding utf8
    Invoke-FixtureGit $worktree @('add', '-A') | Out-Null
    Invoke-FixtureGit $worktree @('commit', '--quiet', '-m', 'work on the branch') | Out-Null

    $preMerge = $null
    if ($Merged) {
        $preMerge = ([string] (Invoke-FixtureGit $repo @('rev-parse', 'main'))).Trim()
        # --no-ff is the shape a GitHub "Merge pull request" leaves behind.
        Invoke-FixtureGit $repo @('merge', '--no-ff', '-m', "Merge $branch", $branch) | Out-Null
        Invoke-FixtureGit $repo @('push', '--quiet', 'origin', 'main') | Out-Null
        Invoke-FixtureGit $repo @('reset', '--hard', '--quiet', $preMerge) | Out-Null
        if (-not $KeepTrackingRef) {
            # The push updated the tracking ref too. Rewind it, or the fixture proves nothing about
            # fetching: only the remote must hold the merge.
            Invoke-FixtureGit $repo @('update-ref', 'refs/remotes/origin/main', $preMerge) | Out-Null
        }
    }

    return [pscustomobject]@{
        Root     = $root
        Repo     = (Resolve-Path -LiteralPath $repo).Path
        Origin   = $origin
        Worktree = (Resolve-Path -LiteralPath $worktree).Path
        Branch   = $branch
        PreMerge = $preMerge
    }
}

function Get-RefSha {
    param([string] $RepoDir, [string] $Ref)
    return ([string] (& git -C $RepoDir rev-parse $Ref 2>$null)).Trim()
}

function Remove-Fixture {
    param([string] $Root)
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 5) { return }
            Start-Sleep -Milliseconds 300
        }
    }
}

# Runs the real sweep as a child process. Stdin is redirected from an empty file, so the sweep is
# never interactive and stays in report-only mode while ahkflow.worktreeCleanup is unset.
function Invoke-Sweep {
    param([string] $RepoDir, [string[]] $ExtraArgs = @())

    $parent = Split-Path -Parent $RepoDir
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stdinFile = Join-Path $parent "sin-$suffix.txt"
    $stdoutFile = Join-Path $parent "sout-$suffix.txt"
    $stderrFile = Join-Path $parent "serr-$suffix.txt"
    Set-Content -LiteralPath $stdinFile -Value '' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $RepoDir) + $ExtraArgs

    $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
        -WorkingDirectory $suiteRoot `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    $result = [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stdout   = (Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
        Stderr   = (Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
    }
    Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    return $result
}

# Fires remove-worktree-local-dev.ps1 the way Claude's WorktreeRemove hook does: the worktree path
# arrives as JSON on stdin. Extra arguments go on the command line, which is how the sweep hands
# over the base it already resolved.
function Invoke-RemoveHook {
    param([string] $WorktreePath, [string[]] $ExtraArgs = @())

    $stdinFile = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        # No BOM. Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes one, and the hook's
        # JSON parse rejects it with "Invalid JSON primitive", so the hook would read no path at
        # all and the test would prove nothing. Claude Code sends BOM-less JSON.
        [System.IO.File]::WriteAllText(
            $stdinFile,
            (@{ worktree_path = $WorktreePath } | ConvertTo-Json -Compress),
            (New-Object System.Text.UTF8Encoding($false)))
        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $removeScript, '-Mode', 'Hook') + $ExtraArgs
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
            -WorkingDirectory $suiteRoot `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
        return [pscustomobject]@{ ExitCode = $proc.ExitCode }
    } finally {
        Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-RemovalLog {
    param([string] $RepoDir)
    $logPath = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    if (-not (Test-Path -LiteralPath $logPath)) { return '' }
    return (Get-Content -Raw -LiteralPath $logPath)
}

function Wait-ForWorktreeGone {
    param([string] $RepoDir, [string] $WorktreePath, [int] $TimeoutSeconds = 40)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $listed = @(& git -C $RepoDir worktree list --porcelain 2>$null) |
            Where-Object { $_ -like 'worktree *' } |
            ForEach-Object { ([System.IO.Path]::GetFullPath($_.Substring('worktree '.Length))).TrimEnd('\', '/').ToLowerInvariant() }
        $key = ([System.IO.Path]::GetFullPath($WorktreePath)).TrimEnd('\', '/').ToLowerInvariant()
        if (($listed -notcontains $key) -and -not (Test-Path -LiteralPath $WorktreePath)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

# --- Resolve-MergedBaseRef: the three answers it can give ----------------------

$fixture = New-RemoteFixture -Merged
try {
    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'origin/main') "Expected the remote-tracking ref as the base, got '$($base.Ref)'."
    Assert-True ($base.Remote -eq 'origin') "Expected remote 'origin', got '$($base.Remote)'."
    Assert-True $base.Fetched 'A reachable remote must be fetched.'
    Assert-True ($base.Reason -eq 'remote-fetched') "Expected reason 'remote-fetched', got '$($base.Reason)'."

    # The fetch is the point: after it, the merge the remote holds is visible locally.
    & git -C $fixture.Repo merge-base --is-ancestor $fixture.Branch 'origin/main'
    Assert-True ($LASTEXITCODE -eq 0) 'After the fetch, origin/main must contain the merge.'
    & git -C $fixture.Repo merge-base --is-ancestor $fixture.Branch 'main'
    Assert-True ($LASTEXITCODE -ne 0) 'Local main must still be behind, or the fixture proves nothing.'
} finally {
    Remove-Fixture $fixture.Root
}

# Unreachable remote: the cached tracking ref still answers, and the reason says it may be behind.
$fixture = New-RemoteFixture -Merged
try {
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'origin/main') "Offline, the cached tracking ref is still the base, got '$($base.Ref)'."
    Assert-True (-not $base.Fetched) 'An unreachable remote cannot report a successful fetch.'
    Assert-True ($base.Reason -eq 'remote-stale') "Expected reason 'remote-stale', got '$($base.Reason)'."
} finally {
    Remove-Fixture $fixture.Root
}

# No upstream at all: the local branch is the only base there is.
$fixture = New-RemoteFixture
try {
    Invoke-FixtureGit $fixture.Repo @('branch', '--unset-upstream', 'main') | Out-Null

    $base = Resolve-MergedBaseRef -RepoRoot $fixture.Repo
    Assert-True ($base.Ref -eq 'main') "Without an upstream the base is local main, got '$($base.Ref)'."
    Assert-True (-not $base.Fetched) 'Nothing can be fetched without an upstream.'
    Assert-True ($base.Reason -eq 'no-upstream') "Expected reason 'no-upstream', got '$($base.Reason)'."
} finally {
    Remove-Fixture $fixture.Root
}

# --- SSH transport ------------------------------------------------------------
#
# Batch mode stops ssh asking for a passphrase, but `GIT_SSH_COMMAND` is also how a caller points
# git at an identity file, a proxy, or a different ssh client. Overwriting it makes the fetch fail
# for those remotes, which leaves the sweep permanently in the stale-base, remove-nothing state.
# So it is set only when nobody else has chosen a transport.
$fixture = New-RemoteFixture
try {
    Assert-True ((Resolve-BatchModeSshCommand -RepoRoot $fixture.Repo -ExistingCommand '') -eq 'ssh -oBatchMode=yes') `
        'With no transport configured, batch mode must be applied.'
    Assert-True ($null -eq (Resolve-BatchModeSshCommand -RepoRoot $fixture.Repo -ExistingCommand 'ssh -i C:\keys\id_ed25519')) `
        "A caller's GIT_SSH_COMMAND must be left alone."

    Invoke-FixtureGit $fixture.Repo @('config', 'core.sshCommand', 'ssh -i C:\keys\id_ed25519') | Out-Null
    Assert-True ($null -eq (Resolve-BatchModeSshCommand -RepoRoot $fixture.Repo -ExistingCommand '')) `
        'A configured core.sshCommand must be left alone: the environment variable would override it.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- The message the caller writes --------------------------------------------

$fetched = [pscustomobject]@{ Ref = 'origin/main'; Remote = 'origin'; Fetched = $true; Reason = 'remote-fetched' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $fetched) "base 'origin/main' (fetched from origin)." 'The fetched message must name the base and the remote.'

$stale = [pscustomobject]@{ Ref = 'origin/main'; Remote = 'origin'; Fetched = $false; Reason = 'remote-stale' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $stale) 'may be behind the remote' 'A failed fetch must say the base may be behind the remote.'

$local = [pscustomobject]@{ Ref = 'main'; Remote = $null; Fetched = $false; Reason = 'no-upstream' }
Assert-Contains (Format-MergedBaseRefMessage -Prefix 'cleanup' -Base $local) "base 'main' (local only" 'The local-only message must name the local base.'

# --- The sweep: a stale local main no longer hides a merge ---------------------

$fixture = New-RemoteFixture -Merged
try {
    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "The sweep must exit 0, got $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr "base 'origin/main' (fetched from origin)." 'The sweep must report the base it decided against.'
    Assert-Contains $sweep.Stderr "eligible merged worktree: $($fixture.Worktree)" 'A worktree merged on the remote must be eligible while local main is stale.'

} finally {
    Remove-Fixture $fixture.Root
}

# An explicit -MainRef is the caller's choice: it must not fetch, and it must still say which base
# it decided against. A fresh fixture, because a fetch that already ran would hide a fetch here.
$fixture = New-RemoteFixture -Merged
try {
    $before = Get-RefSha $fixture.Repo 'refs/remotes/origin/main'

    $explicit = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-MainRef', 'main')
    Assert-True ($explicit.ExitCode -eq 0) "The sweep must exit 0, got $($explicit.ExitCode). Stderr: $($explicit.Stderr)"
    Assert-Contains $explicit.Stderr "base 'main' (given by the caller)." 'An explicit -MainRef must still report the base.'
    Assert-NotContains $explicit.Stderr 'fetched from origin' 'An explicit -MainRef must not trigger a fetch.'
    Assert-True ((Get-RefSha $fixture.Repo 'refs/remotes/origin/main') -eq $before) `
        'An explicit -MainRef must leave the remote-tracking ref where it was.'
    Assert-Contains $explicit.Stderr 'no merged worktrees eligible for cleanup.' 'Against the stale local base nothing is eligible.'
} finally {
    Remove-Fixture $fixture.Root
}

# The whole handover, end to end: the sweep fetches once, decides, and passes that base to the
# removal script. Against a stale local `main` the removal script's own gate would refuse, so a
# worktree that actually disappears is the only proof the base really crossed the process boundary.
$fixture = New-RemoteFixture -Merged -WithScripts
try {
    $sweep = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-Cleanup')
    Assert-True ($sweep.ExitCode -eq 0) "The sweep must exit 0, got $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr "removing merged worktree: $($fixture.Worktree)" 'The sweep must remove the eligible worktree.'
    Assert-NotContains $sweep.Stderr 'not found; cannot remove' 'The fixture must carry the removal script.'
    Assert-NotContains $sweep.Stderr 'is not merged into' 'The removal gate must accept the base the sweep handed it.'
    Assert-True (Wait-ForWorktreeGone -RepoDir $fixture.Repo -WorktreePath $fixture.Worktree) `
        'The worktree must actually be gone.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- A stale cache must not authorize removal ---------------------------------
#
# The remote can lose history: a force-update, a reverted merge, an amended branch. The cached
# tracking ref then holds a merge the remote no longer has, and deciding against it would remove a
# worktree whose work is no longer on the remote at all. Removal is destructive, so a base that
# could not be refreshed reports and stops.

$fixture = New-RemoteFixture -Merged -KeepTrackingRef
try {
    # The remote drops the merge; the cached tracking ref still holds it.
    Invoke-FixtureGit $fixture.Origin @('update-ref', 'refs/heads/main', $fixture.PreMerge) | Out-Null
    Assert-True ((Get-RefSha $fixture.Repo 'refs/remotes/origin/main') -ne $fixture.PreMerge) `
        'The cached tracking ref must still hold the merge, or the fixture proves nothing.'

    # Reachable remote: the fetch rewinds the cached ref, and the worktree stops being eligible.
    $fetched = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-Cleanup')
    Assert-True ($fetched.ExitCode -eq 0) "The sweep must exit 0, got $($fetched.ExitCode). Stderr: $($fetched.Stderr)"
    Assert-Contains $fetched.Stderr 'no merged worktrees eligible for cleanup.' 'After the fetch the dropped merge must not count.'
    Assert-True (Test-Path -LiteralPath $fixture.Worktree) 'The worktree must survive a remote that dropped the merge.'
} finally {
    Remove-Fixture $fixture.Root
}

$fixture = New-RemoteFixture -Merged -KeepTrackingRef -WithScripts
try {
    Invoke-FixtureGit $fixture.Origin @('update-ref', 'refs/heads/main', $fixture.PreMerge) | Out-Null
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    # Unreachable remote plus a cached ref that says "merged". The old code removed the worktree.
    $offline = Invoke-Sweep -RepoDir $fixture.Repo -ExtraArgs @('-Cleanup')
    Assert-True ($offline.ExitCode -eq 0) "The sweep must exit 0, got $($offline.ExitCode). Stderr: $($offline.Stderr)"
    Assert-Contains $offline.Stderr "eligible merged worktree: $($fixture.Worktree)" 'A stale base still reports what it sees.'
    Assert-Contains $offline.Stderr 'nothing removed' 'A stale base must refuse removal and say so.'
    Assert-NotContains $offline.Stderr 'removing merged worktree' 'A stale base must not remove anything.'
    Assert-NotContains (Get-RemovalLog $fixture.Repo) 'Merged-cleanup requested removal' 'A stale base must not ask for a removal.'
    Assert-True (Test-Path -LiteralPath $fixture.Worktree) 'The worktree must survive an unreachable remote.'
} finally {
    Remove-Fixture $fixture.Root
}

# The other direction: fetching must not make an unmerged worktree eligible.
$fixture = New-RemoteFixture
try {
    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "The sweep must exit 0, got $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr 'no merged worktrees eligible for cleanup.' 'An unmerged worktree must be preserved.'
} finally {
    Remove-Fixture $fixture.Root
}

# Offline: worktree creation runs the sweep first, so a failed fetch must never fail the run.
$fixture = New-RemoteFixture -Merged
try {
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    $sweep = Invoke-Sweep -RepoDir $fixture.Repo
    Assert-True ($sweep.ExitCode -eq 0) "A failed fetch must not fail the sweep, got exit $($sweep.ExitCode). Stderr: $($sweep.Stderr)"
    Assert-Contains $sweep.Stderr 'may be behind the remote' 'The sweep must say the base may be stale when the fetch fails.'
    Assert-Contains $sweep.Stderr 'no merged worktrees eligible for cleanup.' 'Offline, the stale base sees no merge, so nothing is removed.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- The removal gate decides against the same base ----------------------------
#
# Eligibility is not the last word: remove-worktree-local-dev.ps1 re-decides merged-ness before it
# spawns the watcher. If that gate keeps reading local main, the sweep reports a worktree and then
# preserves it.

$fixture = New-RemoteFixture -Merged
try {
    $withStaleBase = Invoke-RemoveHook -WorktreePath $fixture.Worktree -ExtraArgs @('-MainRef', 'main')
    Assert-True ($withStaleBase.ExitCode -eq 0) "The hook must exit 0, got $($withStaleBase.ExitCode)."
    Assert-Contains (Get-RemovalLog $fixture.Repo) "is not merged into main" 'Against the stale local base the gate must preserve the worktree.'
    Assert-True (Test-Path -LiteralPath $fixture.Worktree) 'A preserved worktree must still exist.'

    $resolved = Invoke-RemoveHook -WorktreePath $fixture.Worktree
    Assert-True ($resolved.ExitCode -eq 0) "The hook must exit 0, got $($resolved.ExitCode)."
    Assert-Contains (Get-RemovalLog $fixture.Repo) "base 'origin/main' (fetched from origin)." 'The hook must resolve and report its own base when none is passed.'
    Assert-True (Wait-ForWorktreeGone -RepoDir $fixture.Repo -WorktreePath $fixture.Worktree) `
        'With the fetched base the gate must pass and the watcher must remove the worktree.'
} finally {
    Remove-Fixture $fixture.Root
}

# The hook resolves its own base, so it inherits the same rule: a base it could not refresh is not
# proof of anything, and removal is destructive.
$fixture = New-RemoteFixture -Merged -KeepTrackingRef
try {
    Invoke-FixtureGit $fixture.Origin @('update-ref', 'refs/heads/main', $fixture.PreMerge) | Out-Null
    Invoke-FixtureGit $fixture.Repo @('remote', 'set-url', 'origin', (Join-Path $fixture.Root 'no-such-origin.git')) | Out-Null

    $offlineHook = Invoke-RemoveHook -WorktreePath $fixture.Worktree
    Assert-True ($offlineHook.ExitCode -eq 0) "The hook must exit 0, got $($offlineHook.ExitCode)."
    Assert-Contains (Get-RemovalLog $fixture.Repo) 'may be behind the remote' 'The hook must say why it refused to decide.'
    Assert-True (Test-Path -LiteralPath $fixture.Worktree) 'A base that could not be refreshed must preserve the worktree.'
} finally {
    Remove-Fixture $fixture.Root
}

# --- The fetch child process ---------------------------------------------------

# Windows PowerShell 5.1 is a declared target (`#Requires -Version 5.1`), and it reports
# Start-Process -PassThru exit codes as $null when -Wait was not used. The resolver read that as a
# failed fetch, so on 5.1 every base was reported stale — and with the rule above, that alone would
# stop every automatic removal. The resolver must answer the same on both hosts.
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $windowsPowerShell) {
    $fixture = New-RemoteFixture -Merged
    try {
        $command = "Set-StrictMode -Version Latest; . '$scriptsDir\worktree-git.common.ps1'; " +
            "`$b = Resolve-MergedBaseRef -RepoRoot '$($fixture.Repo)'; Write-Output `$b.Reason"
        $reason = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1 | Select-Object -Last 1)
        Assert-True ("$reason".Trim() -eq 'remote-fetched') `
            "Windows PowerShell 5.1 must report a successful fetch, got '$reason'."
    } finally {
        Remove-Fixture $fixture.Root
    }
} else {
    Write-Host "Skipped the Windows PowerShell 5.1 check: $windowsPowerShell not found."
}

# A timed-out fetch must take its helpers with it. Git starts askpass, SSH, and credential helpers
# as children, and killing only the parent leaves whichever one is waiting for input alive.
$parentMarker = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-treekill-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
$childScript = "Start-Process -FilePath '$([System.Diagnostics.Process]::GetCurrentProcess().Path)' " +
    "-ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 120' -PassThru -WindowStyle Hidden | " +
    "ForEach-Object { Set-Content -LiteralPath '$parentMarker' -Value `$_.Id }; Start-Sleep -Seconds 120"
$parent = Start-Process -FilePath ([System.Diagnostics.Process]::GetCurrentProcess().Path) `
    -ArgumentList @('-NoProfile', '-Command', $childScript) -PassThru -WindowStyle Hidden
try {
    $deadline = (Get-Date).AddSeconds(20)
    while (((Get-Date) -lt $deadline) -and -not (Test-Path -LiteralPath $parentMarker)) { Start-Sleep -Milliseconds 200 }
    Assert-True (Test-Path -LiteralPath $parentMarker) 'The fixture child process never started.'
    $childId = [int] ((Get-Content -Raw -LiteralPath $parentMarker).Trim())

    Assert-True (Stop-ProcessTree -ProcessId $parent.Id -WaitMilliseconds 10000) 'Stop-ProcessTree must report the tree gone.'

    foreach ($id in @($parent.Id, $childId)) {
        $alive = $true
        try { $null = [System.Diagnostics.Process]::GetProcessById($id) } catch { $alive = $false }
        Assert-True (-not $alive) "Process $id survived Stop-ProcessTree."
    }
} finally {
    foreach ($id in @($parent.Id)) {
        try { (Get-Process -Id $id -ErrorAction SilentlyContinue) | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    }
    Remove-Item -LiteralPath $parentMarker -Force -ErrorAction SilentlyContinue
}

Write-Host 'Worktree sweep remote-base tests passed.'
