# 5.1, and it means it. This suite passes under powershell.exe and under pwsh.
# Two Windows PowerShell traps used to put it out of reach, and both are handled below.
# First, Invoke-TestGit runs `& git ... 2>&1`, and under Windows PowerShell a native command's
# stderr becomes an error record that this file's 'Stop' preference turns terminating -- so
# `git worktree add`, which reports progress on stderr, ended the suite. That helper now sets
# 'Continue' around the call and restores the preference afterwards.
# Second, Invoke-RemoveHook wrote the hook's stdin with Set-Content -Encoding utf8, which adds a
# byte order mark under 5.1 and none under 7.x. The hook then rejected its own payload and did
# nothing. That write is now byte-exact, and backlog 117 made the hook read stdin as UTF-8
# instead of through the console code page.
# The watcher itself was never host-dependent; issue #348 said otherwise and was wrong.
#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
$removeScript = Join-Path $scriptsDir 'remove-worktree-local-dev.ps1'

function Assert-True {
    param($Condition, [string] $Message)

    # The parameter used to be typed [bool]. An array argument then failed during parameter
    # binding, and a binding failure names no line, so backlog 068 could not find the call site.
    # The type is checked here instead. The suite still fails, but it says which line handed over
    # what.
    if ($Condition -isnot [bool]) {
        $caller = (Get-PSCallStack)[1]
        $typeName = if ($null -eq $Condition) { 'null' } else { $Condition.GetType().FullName }
        throw ("Assert-True needs a boolean. Got [$typeName] with $(@($Condition).Count) value(s) " +
            "from line $($caller.ScriptLineNumber): $(@($Condition) -join ' | '). Original message: $Message")
    }

    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)

    # Under Windows PowerShell a native command's stderr becomes an error record, and this file's
    # 'Stop' preference turns it terminating. git reports worktree progress on stderr, so without
    # this guard `git worktree add` ends the suite. The exit code below is the real check.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>&1
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# Fresh main-checkout repo under a throwaway root. Worktrees are created as siblings
# of the repo, matching the harness used by WorktreeMergedCleanup.Tests.ps1.
function New-TempGitRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtremove-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Remove Hook Test' *> $null

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

# Adds a linked worktree on a new branch off main (merged + clean by default).
# Adds a linked worktree on a new branch off main. By default the branch gets one commit and is
# then merged into main with a merge commit -- the shape a merged pull request leaves behind.
#
# The default used to make NO commit at all, so 'merged + clean' ran on a branch that had never
# committed. Ancestry accepted that, which is exactly the defect backlog 098 fixes, so the fixture
# had to start committing before the gate could be trusted by these tests.
#
# -Unmerged commits without merging; -NoCommits leaves the branch where it was created, which is
# what a brand-new worktree looks like; -Dirty leaves an uncommitted change.
function Add-TestWorktree {
    param(
        [string] $RepoDir,
        [string] $BranchName,
        [switch] $Unmerged,
        [switch] $Dirty,
        [switch] $NoCommits
    )

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null

    if (-not $NoCommits) {
        Set-Content -LiteralPath (Join-Path $wtPath 'work.txt') -Value "work on $BranchName" -Encoding utf8
        Invoke-TestGit $wtPath @('add', '-A') | Out-Null
        Invoke-TestGit $wtPath @('commit', '-m', "work on $BranchName") | Out-Null
        if (-not $Unmerged) {
            # --no-ff is what a GitHub "Merge pull request" leaves behind.
            Invoke-TestGit $RepoDir @('merge', '--no-ff', '-m', "Merge $BranchName", $BranchName) | Out-Null
        }
    }
    if ($Dirty) {
        Set-Content -LiteralPath (Join-Path $wtPath 'dirty.txt') -Value 'uncommitted' -Encoding utf8
    }

    return (Resolve-Path -LiteralPath $wtPath).Path
}

# Adds a detached-HEAD worktree pinned at main (clean, ancestor of main, no branch).
function Add-DetachedTestWorktree {
    param([string] $RepoDir, [string] $Leaf)

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $Leaf)
    Invoke-TestGit $RepoDir @('worktree', 'add', '--detach', $wtPath, 'main') | Out-Null
    return (Resolve-Path -LiteralPath $wtPath).Path
}

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

# The outcome log. From backlog 073 it carries one line per removal attempt and nothing else.
function Get-RemovalLogPath {
    param([string] $RepoDir)
    return Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
}

# The diagnostics log beside it. Every reason, guidance line, and git result lands here.
function Get-RemovalDiagnosticsPath {
    param([string] $RepoDir)
    return Join-Path $RepoDir '.claude\worktrees\worktree-removal-diagnostics.log'
}

# Invokes the hook by piping {"worktree_path":"<path>"} JSON to remove-worktree-local-dev.ps1,
# exactly as Claude's WorktreeRemove hook does. Returns the process exit code; log content is
# read separately by the caller once the process has exited.
function Invoke-RemoveHook {
    param(
        [string] $WorktreePath,
        [hashtable] $EnvOverrides,

        # Sends the payload with a leading UTF-8 byte order mark. That is what Set-Content
        # -Encoding utf8 produces under Windows PowerShell 5.1, and it used to make the hook
        # reject its own stdin. Backlog 117 made Read-RawStdin decode stdin as UTF-8, which
        # consumes the mark.
        [switch] $WithByteOrderMark,

        # Sends this JSON instead of a worktree_path payload. Used to drive the empty-path branch.
        [string] $RawPayload,

        # Uses a copy of the hook from a fixture worktree. This checks how the real hook resolves
        # the main checkout when the payload supplies no path.
        [string] $HookScriptPath = $removeScript
    )

    $stdinFile = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $payload = if ($PSBoundParameters.ContainsKey('RawPayload')) {
            $RawPayload
        } else {
            (@{ worktree_path = $WorktreePath } | ConvertTo-Json -Compress)
        }

        # WriteAllText, not Set-Content: -Encoding utf8 adds a byte order mark under 5.1 and none
        # under 7.x, so the same suite would send different bytes on the two hosts.
        [System.IO.File]::WriteAllText($stdinFile, $payload,
            (New-Object System.Text.UTF8Encoding($WithByteOrderMark.IsPresent)))

        $previousValues = @{}
        if ($EnvOverrides) {
            foreach ($key in $EnvOverrides.Keys) {
                $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
                [Environment]::SetEnvironmentVariable($key, [string] $EnvOverrides[$key], 'Process')
            }
        }

        try {
            $hookArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $HookScriptPath, '-Mode', 'Hook')

            $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
            $proc = Start-Process -FilePath $psExe `
                -ArgumentList $hookArgs `
                -WorkingDirectory $suiteRoot `
                -RedirectStandardInput $stdinFile `
                -RedirectStandardOutput $stdoutFile `
                -RedirectStandardError $stderrFile `
                -NoNewWindow -PassThru -Wait
        } finally {
            foreach ($key in $previousValues.Keys) {
                [Environment]::SetEnvironmentVariable($key, $previousValues[$key], 'Process')
            }
        }

        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stdout   = Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
            Stderr   = Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-ForCondition {
    param([scriptblock] $Condition, [int] $TimeoutSeconds = 20)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return & $Condition
}

# The outcome line the WATCHER owns arrives after the folder is gone: the watcher deletes, prunes,
# deletes the branch, and writes its one line last. So a test that saw the folder disappear must
# still wait for the line, or it reads a log file that does not exist yet.
function Wait-ForOutcomeLine {
    param([string] $RepoDir, [int] $TimeoutSeconds = 20)

    $path = Get-RemovalLogPath $RepoDir
    $null = Wait-ForCondition -TimeoutSeconds $TimeoutSeconds -Condition {
        (Test-Path -LiteralPath $path) -and (@(Get-Content -LiteralPath $path)).Count -ge 1
    }
    return @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
}

# --- Test: Assert-True names the call site when handed a non-boolean -----------
# Backlog 068 saw an array reach Assert-True once, and never found which line sent it. A typed
# [bool] parameter fails during parameter binding, and a binding failure names no line. This test
# is the only thing that exercises the replacement check, because a passing suite never reaches it.
$diagnosticFired = $false
$diagnosticMessage = ''
try {
    # Test-Path with two paths returns System.Object[], which is the shape that was reported.
    Assert-True (Test-Path -LiteralPath @($suiteRoot, $scriptsDir)) 'array argument' # ARRAY-CALL-SITE
} catch {
    $diagnosticFired = $true
    $diagnosticMessage = $_.Exception.Message
}

# The line the message must name, read out of this file rather than typed in, so editing the suite
# cannot leave a stale number behind. The token is joined at run time, so the search below does not
# find itself - only the tagged call above carries the whole string.
$callSiteToken = 'ARRAY-CALL' + '-SITE'
$expectedLine = (Select-String -LiteralPath $PSCommandPath -SimpleMatch -Pattern $callSiteToken |
    Select-Object -First 1).LineNumber

Assert-True $diagnosticFired 'Assert-True must refuse a non-boolean argument instead of accepting it.'
Assert-True ($diagnosticMessage -match 'System\.Object\[\]') `
    "Expected the runtime type in the message. Got: $diagnosticMessage"

# Checking for any number here would pass on a message reporting Assert-True's own line, which is
# the exact bug this test exists to catch. The number has to be the caller's.
Assert-True ($null -ne $expectedLine) 'Could not find the tagged call site in this file.'
Assert-True ($diagnosticMessage -match "from line ${expectedLine}:") `
    "Expected the message to name line $expectedLine. Got: $diagnosticMessage"

# --- Test: merged + clean -> folder removed (unchanged behavior) ---------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-merged-clean'

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed "Merged + clean worktree should be removed by the watcher. Log: $(Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo) -ErrorAction SilentlyContinue)"
} finally {
    Remove-TempTree $repo
}

# --- Test: non-ASCII worktree path -> still removed ----------------------------
# This payload has no byte order mark. The old console-code-page reader changed the UTF-8 path
# bytes before JSON conversion, so the hook looked for a different folder and kept the real one.
$repo = New-TempGitRepo
try {
    $branchName = 'feat-unicode-' + [char]0x00E9
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName $branchName

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed "A non-ASCII worktree path must survive UTF-8 stdin decoding. Stderr: $($result.Stderr)"

    $outcomeLines = @(Wait-ForOutcomeLine -RepoDir $repo)
    Assert-Equal 1 $outcomeLines.Count "A non-ASCII path removal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Removed\.$') "Expected the removed line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: BOM on stdin -> still removed --------------------------------------
# Windows PowerShell 5.1 writes a UTF-8 byte order mark from Set-Content -Encoding utf8. Read
# through [Console]::In those three bytes arrive as three characters from the console code page,
# not as one U+FEFF, so ConvertFrom-Json rejects the document. Before backlog 117 the hook then
# exited 0 with the worktree untouched and no log file at all, and issue #348 read that silence
# as a broken watcher. Read-RawStdin decodes stdin as UTF-8 now, which consumes the mark.
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-bom-stdin'

    $result = Invoke-RemoveHook -WorktreePath $wtPath -WithByteOrderMark
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed "A byte order mark on stdin must not stop the removal. Stderr: $($result.Stderr)"

    $outcomeLines = @(Wait-ForOutcomeLine -RepoDir $repo)
    Assert-Equal 1 $outcomeLines.Count "A BOM-prefixed removal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Removed\.$') "Expected the removed line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: no worktree_path -> one central outcome line, not silence -----------
# Every other refusal writes one line. This branch used to return without one, so the log file
# was never created and a worktree left behind had nothing on disk explaining why. The real hook
# runs the script copy inside the linked worktree, but the outcome belongs in the main checkout.
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-no-path'
    $hookScriptsDir = Join-Path $wtPath 'scripts'
    New-Item -ItemType Directory -Path $hookScriptsDir -Force | Out-Null
    $fixtureRemoveScript = Join-Path $hookScriptsDir 'remove-worktree-local-dev.ps1'
    Copy-Item -LiteralPath $removeScript -Destination $fixtureRemoveScript
    Copy-Item -LiteralPath (Join-Path $scriptsDir 'worktree-log.common.ps1') -Destination $hookScriptsDir

    $result = Invoke-RemoveHook -RawPayload '{}' -HookScriptPath $fixtureRemoveScript
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'A payload with no worktree_path must touch nothing.'

    $outcomeLines = @(Wait-ForOutcomeLine -RepoDir $repo)
    Assert-Equal 1 $outcomeLines.Count "A no-path hook writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Kept: the hook received no worktree path\.$') `
        "Expected the no-path line, got '$($outcomeLines[0])'"
    Assert-True (-not (Test-Path -LiteralPath (Get-RemovalLogPath $wtPath))) `
        'A no-path hook must not leave the outcome in the linked worktree copy.'
} finally {
    Remove-TempTree $repo
}

# --- Test: unmerged -> folder preserved, reason + guidance logged --------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unmerged' -Unmerged

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'Unmerged worktree must be preserved (no watcher removal).'

    # The reason and the guidance are diagnostics now.
    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    Assert-True ($diagnostics -match '(?i)not merged') "Expected the diagnostics to name the unmerged reason. Log: $diagnostics"
    Assert-True ($diagnostics -match 'AHKFLOW_WORKTREE_FORCE_REMOVE') "Expected the diagnostics to mention the force override opt-out. Log: $diagnostics"

    # The hook refuses an unmerged worktree before it spawns anything, so the hook owns the line.
    $outcomeLines = @(Get-Content -LiteralPath (Get-RemovalLogPath $repo))
    Assert-Equal 1 $outcomeLines.Count "An unmerged refusal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Kept: the branch is not merged\.$') "Expected the not-merged line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: merged + dirty -> folder preserved -----------------------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty' -Dirty

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'Merged but dirty worktree must be preserved.'

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    Assert-True ($diagnostics -match '(?i)uncommitted') "Expected the diagnostics to name the dirty-tree reason. Log: $diagnostics"

    $outcomeLines = @(Get-Content -LiteralPath (Get-RemovalLogPath $repo))
    Assert-Equal 1 $outcomeLines.Count "A dirty-tree refusal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Kept: the worktree has uncommitted changes\.$') "Expected the dirty line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: detached HEAD (clean, ancestor of main) -> folder preserved ---------
$repo = New-TempGitRepo
try {
    $wtPath = Add-DetachedTestWorktree -RepoDir $repo -Leaf 'detached'

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'Detached HEAD worktree must be preserved even though it is clean and an ancestor of main.'

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    Assert-True ($diagnostics -match '(?i)detached') "Expected the diagnostics to name the detached-HEAD reason. Log: $diagnostics"

    $outcomeLines = @(Get-Content -LiteralPath (Get-RemovalLogPath $repo))
    Assert-Equal 1 $outcomeLines.Count "A detached-HEAD refusal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Kept: the worktree has a detached HEAD\.$') "Expected the detached line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: unmerged + AHKFLOW_WORKTREE_FORCE_REMOVE=1 -> removed, force logged --
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-forced' -Unmerged

    $result = Invoke-RemoveHook -WorktreePath $wtPath -EnvOverrides @{ AHKFLOW_WORKTREE_FORCE_REMOVE = '1' }
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed "Forced removal of an unmerged worktree should still remove the folder. Log: $(Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo) -ErrorAction SilentlyContinue)"

    # The genuine proof this test exercises the gate: without it, an unmerged worktree would
    # also be removed on today's script (that assertion alone is green on old and new code).
    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    Assert-True ($diagnostics -match '(?i)force override.*bypassing merge/clean gate') "Expected a force-override diagnostic proving the gate was consulted and bypassed. Log: $diagnostics"

    # The watcher owns the line on this path, and it removed the folder.
    $outcomeLines = @(Wait-ForOutcomeLine -RepoDir $repo)
    Assert-Equal 1 $outcomeLines.Count "A forced removal writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Removed\.$') "Expected the removed line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: the hook gate takes the sweep's verdicts ------------------------------
# Dot-sourcing runs no removal: the entry point is guarded on $MyInvocation.InvocationName.
. $removeScript

$repo = New-TempGitRepo
try {
    $mergedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-gate-merged'
    Assert-True (Test-WorktreeMergedIntoMain -WorktreeFull $mergedPath -BranchName 'feat-gate-merged' -BaseRef 'main' -MainCheckout $repo) `
        'A merged branch must pass the hook gate.'

    $freshPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-gate-fresh' -NoCommits
    Assert-True (-not (Test-WorktreeMergedIntoMain -WorktreeFull $freshPath -BranchName 'feat-gate-fresh' -BaseRef 'main' -MainCheckout $repo)) `
        'A branch with no commit of its own must NOT pass the hook gate, though ancestry calls it merged.'

    $openPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-gate-open' -Unmerged
    Assert-True (-not (Test-WorktreeMergedIntoMain -WorktreeFull $openPath -BranchName 'feat-gate-open' -BaseRef 'main' -MainCheckout $repo)) `
        'An unmerged branch must not pass the hook gate.'

    # Work made after the merge keeps the worktree, which is what signal 4 exists for.
    $laterPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-gate-later'
    Set-Content -LiteralPath (Join-Path $laterPath 'after.txt') -Value 'later' -Encoding utf8
    Invoke-TestGit $laterPath @('add', '-A') | Out-Null
    Invoke-TestGit $laterPath @('commit', '-m', 'work after the merge') | Out-Null
    Assert-True (-not (Test-WorktreeMergedIntoMain -WorktreeFull $laterPath -BranchName 'feat-gate-later' -BaseRef 'main' -MainCheckout $repo)) `
        'A branch that gained a commit after its merge must not pass the hook gate.'
} finally {
    Remove-TempTree $repo
}

# --- Test: unstarted worktree -> preserved (was removed before backlog 098) ------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-hook' -NoCommits

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'A worktree whose branch holds no commit of its own must be preserved.'

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    Assert-True ($diagnostics -match '(?i)not merged') "Expected the diagnostics to name the reason. Log: $diagnostics"

    $outcomeLines = @(Get-Content -LiteralPath (Get-RemovalLogPath $repo))
    Assert-Equal 1 $outcomeLines.Count "An unstarted worktree writes exactly one outcome line, got $($outcomeLines.Count)"
    Assert-True ($outcomeLines[0] -match 'Kept: the branch is not merged\.$') "Expected the not-merged line, got '$($outcomeLines[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: a locked helper in the shared temp folder no longer breaks the copy ----
# Backlog 118 / GitHub issue #339. The hook used to copy both helpers onto one fixed name each in
# the bare %TEMP%. One merged-cleanup sweep starts several watchers at once, so watcher B copied
# over the exact file watcher A held open for dot-sourcing, the copy failed, and B ran on its
# inline fallbacks. Holding the old destination open is what that collision looks like.
#
# scripts/run-powershell-suites.ps1 runs suites one after another, so this lock on a file in the
# shared %TEMP% cannot collide with another suite.
#
# Both helper destinations are locked, not just one. With only the log helper locked, putting the
# holder probe's destination back to the shared path still passed: nothing held that name open.
$repo = New-TempGitRepo
$lockedHelperNames = @('worktree-log.common.ps1', 'worktree-holder.common.ps1')
$lockedHelpers = @()
$lockStreams = @()
try {
    foreach ($helperName in $lockedHelperNames) {
        $lockedHelper = Join-Path ([System.IO.Path]::GetTempPath()) $helperName
        Copy-Item -LiteralPath (Join-Path $scriptsDir $helperName) -Destination $lockedHelper -Force
        $lockedHelpers += $lockedHelper
        $lockStreams += [System.IO.File]::Open(
            $lockedHelper,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
    }

    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-locked-helper'

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed 'The watcher should still remove the worktree while the old shared helper path is locked.'

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)

    # Without this the test passes when the hook fails before it ever reaches the copy, which is a
    # false green.
    Assert-True ($diagnostics -match 'Watcher spawned') "Expected the hook to reach the spawn. Log: $diagnostics"

    Assert-True (-not ($diagnostics -match 'Could not copy the log helper')) `
        "The log helper must be copied into this attempt's own directory, not onto the shared name. Log: $diagnostics"
    Assert-True (-not ($diagnostics -match 'Could not copy the holder probe')) `
        "The holder probe must be copied into this attempt's own directory. Log: $diagnostics"
} finally {
    foreach ($stream in $lockStreams) { $stream.Dispose() }
    foreach ($helper in $lockedHelpers) {
        Remove-Item -LiteralPath $helper -Force -ErrorAction SilentlyContinue
    }
    Remove-TempTree $repo
}

# --- Test: the attempt gets its own temp directory, and it is deleted afterwards ---
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-run-temp-dir'

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }
    Assert-True $removed 'Merged + clean worktree should be removed by the watcher.'

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)
    $spawned = [regex]::Match($diagnostics, 'ParamFile=(?<path>.+?)\s*$', 'Multiline')
    Assert-True $spawned.Success "Expected a 'Watcher spawned' line naming the param file. Log: $diagnostics"

    $runDir = Split-Path -Parent $spawned.Groups['path'].Value.Trim()
    $runLeaf = Split-Path -Leaf $runDir
    Assert-True ($runLeaf -like 'ahkflowapp-wt-remove-*') `
        "The param file must sit in a per-attempt directory, got '$runDir'."
    Assert-True ($runLeaf.Length -gt 'ahkflowapp-wt-remove-'.Length) `
        "The directory name must carry a run id, got '$runLeaf'."

    # The watcher deletes the directory as one unit, so it goes at the same time the outcome lands.
    $runDirGone = Wait-ForCondition { -not (Test-Path -LiteralPath $runDir) }
    Assert-True $runDirGone "The watcher should delete its whole temp directory '$runDir'."
} finally {
    Remove-TempTree $repo
}

# --- Test: the deletion guard accepts only a real run directory -------------------
# Dot-sourcing keeps the entry point from running, the same guard the other suites rely on.
. $removeScript

$tempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\', '/')

Assert-True (Test-RemovalRunTempDirPath -Path (Join-Path $tempRoot 'ahkflowapp-wt-remove-hook-20260827-abc123')) `
    'A run directory directly under the temp root must be accepted.'

Assert-True (-not (Test-RemovalRunTempDirPath -Path $tempRoot)) `
    'The temp root itself must never be accepted.'

Assert-True (-not (Test-RemovalRunTempDirPath -Path (Join-Path $tempRoot 'ahkflowapp-wt-remove-'))) `
    'The bare prefix names no attempt and must be refused.'

Assert-True (-not (Test-RemovalRunTempDirPath -Path (Join-Path $tempRoot 'nested\ahkflowapp-wt-remove-hook-1'))) `
    'A matching name one level deeper is not a run directory and must be refused.'

Assert-True (-not (Test-RemovalRunTempDirPath -Path 'C:\ahkflowapp-wt-remove-hook-1')) `
    'A matching name outside the temp root must be refused.'

Assert-True (-not (Test-RemovalRunTempDirPath -Path '')) `
    'An empty path must be refused.'

# --- Test: a failed watcher snapshot leaves no run directory behind ---------------
# The hook creates the run directory, then copies itself into it as watcher.ps1. When that copy
# fails the hook aborts, and before this test it returned without deleting the directory it had
# just made. A sweep that keeps failing then grows one dead directory per attempt.
#
# The copy is made to fail with a deny entry on a private temp root: creating a folder stays
# allowed, creating a file inside it does not. So the run directory is created and the snapshot
# then fails, which is the exact path under test.
function New-NoFileCreationTempRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wt-nofile-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $root
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $me, 'CreateFiles', 'ContainerInherit,ObjectInherit', 'None', 'Deny')))
    Set-Acl -LiteralPath $root -AclObject $acl

    return $root
}

function Remove-NoFileCreationTempRoot {
    param([string] $Root)

    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) {
        return
    }

    try {
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = Get-Acl -LiteralPath $Root
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void] $acl.RemoveAccessRule($rule) }
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $Root -AclObject $acl
    } catch { }

    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

$repo = New-TempGitRepo
$deniedRoot = New-NoFileCreationTempRoot
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-snapshot-fails'

    # .NET reads TMP before TEMP, so both are pointed at the private root.
    $result = Invoke-RemoveHook -WorktreePath $wtPath -EnvOverrides @{ TEMP = $deniedRoot; TMP = $deniedRoot }
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    $diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)

    # Without this the test passes when the hook failed earlier than the snapshot, which is a
    # false green: no run directory would exist to leak.
    Assert-True ($diagnostics -match 'Failed to snapshot watcher script') `
        "Expected the watcher snapshot to be the step that failed. Log: $diagnostics"

    Assert-True (Test-Path -LiteralPath $wtPath) 'A hook that could not prepare the watcher must leave the worktree intact.'

    $leftBehind = @(Get-ChildItem -LiteralPath $deniedRoot -Directory -Filter 'ahkflowapp-wt-remove-*' -ErrorAction SilentlyContinue)

    # Built with ForEach-Object, not $leftBehind.FullName. This suite runs under
    # Set-StrictMode -Version Latest, where reading a property off an empty array raises an error,
    # so the passing case printed a false alarm every run.
    $leftBehindNames = ($leftBehind | ForEach-Object { $_.FullName }) -join ', '
    Assert-Equal 0 $leftBehind.Count `
        "A failed watcher snapshot must delete its own run directory, found: $leftBehindNames"
} finally {
    Remove-NoFileCreationTempRoot $deniedRoot
    Remove-TempTree $repo
}

# --- Test: the watcher cleans up after malformed params in a different TEMP -------
# A Win32_Process.Create child does not inherit the caller's TEMP, so the watcher can read a
# different temp root than the hook wrote to. The watcher recovers the hook's root from
# params.json, but a malformed params.json is exactly the case where it cannot. Then the deletion
# guard compared the run directory against the watcher's own root, refused it, and the directory
# stayed forever. The hook root now arrives on the command line, before any parsing.
$hookRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wt-hookroot-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$watcherRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wt-wroot-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $hookRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $watcherRoot -Force | Out-Null

    $runDir = Join-Path $hookRoot ('ahkflowapp-wt-remove-badparams-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    # The watcher runs from its own snapshot, so $PSCommandPath sits inside the run directory --
    # the same anchor production uses to find the directory it must delete.
    $watcherSnapshot = Join-Path $runDir 'watcher.ps1'
    Copy-Item -LiteralPath $removeScript -Destination $watcherSnapshot -Force

    $badParams = Join-Path $runDir 'params.json'
    Set-Content -LiteralPath $badParams -Value '{ this is not json' -Encoding utf8

    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        $env:TEMP = $watcherRoot
        $env:TMP = $watcherRoot
        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        Start-Process -FilePath $psExe -NoNewWindow -Wait -PassThru -WorkingDirectory $watcherRoot -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watcherSnapshot,
            '-Mode', 'Watcher', '-ParamFile', $badParams, '-HookTempRoot', $hookRoot) | Out-Null
    } finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
    }

    Assert-True (-not (Test-Path -LiteralPath $runDir)) `
        "A watcher that cannot parse its params must still delete its run directory '$runDir'."
} finally {
    Remove-Item -LiteralPath $hookRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $watcherRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Worktree remove-hook gate tests passed.'
