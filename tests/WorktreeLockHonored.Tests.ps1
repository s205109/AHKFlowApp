#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
$cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
$removeScript = Join-Path $scriptsDir 'remove-worktree-local-dev.ps1'

function Assert-True {
    param($Condition, [string] $Message)
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

function ConvertTo-Key {
    param([string] $Value)
    return ([System.IO.Path]::GetFullPath($Value)).TrimEnd('\', '/').ToLowerInvariant()
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    # Windows PowerShell turns a native command's stderr into error records, and the file-wide
    # 'Stop' preference makes them terminating. Git writes progress to stderr on success, so
    # 'worktree add' would fail this suite under powershell.exe while passing under pwsh. The
    # exit code is the only success signal that means anything here.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>&1
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

function New-TempGitRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtlock-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Lock Test' *> $null

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

# A linked worktree on a new branch, with one commit merged into main by a merge commit: the
# shape a merged pull request leaves behind, and the only shape the sweep will act on.
function Add-MergedWorktree {
    param([string] $RepoDir, [string] $BranchName)

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $wtPath 'work.txt') -Value "work on $BranchName" -Encoding utf8
    Invoke-TestGit $wtPath @('add', '-A') | Out-Null
    Invoke-TestGit $wtPath @('commit', '-m', "work on $BranchName") | Out-Null
    Invoke-TestGit $RepoDir @('merge', '--no-ff', '-m', "Merge $BranchName", $BranchName) | Out-Null
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

# The sweep writes its report to stderr, so it has to run as its own process to be read back.
function Invoke-CleanupScript {
    param([string] $RepoRoot, [string[]] $ExtraArgs = @())

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $psExe = (Get-Process -Id $PID).Path
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript,
            '-RepoRoot', $RepoRoot, '-MainRef', 'main') + $ExtraArgs
        $proc = Start-Process -FilePath $psExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stderr   = (Get-Content -Raw -LiteralPath $stderrFile)
        }
    } finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

# Stages what the hook stages before it spawns a watcher: a per-attempt directory in the temp
# folder holding a copy of the removal script and a sidecar param file. Watcher mode reads every
# value from that file, so passing -WorktreePath on the command line alone would not reach it.
# The directory name has to match the generated pattern, or the watcher refuses to clean it up
# afterwards.
function New-WatcherInvocation {
    param(
        [string] $RepoDir,
        [string] $WorktreePath,
        [string] $BranchName,
        [string] $LogPath,
        [int] $TimeoutSeconds = 10
    )

    $runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $tempDir = [System.IO.Path]::GetTempPath()
    $runDir = Join-Path $tempDir "ahkflowapp-wt-remove-$runId"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $watcherScript = Join-Path $runDir 'watcher.ps1'
    $paramFile = Join-Path $runDir 'params.json'

    Copy-Item -LiteralPath $removeScript -Destination $watcherScript -Force
    $params = [ordered]@{
        RunId          = $runId
        TempRoot       = $tempDir
        WorktreePath   = $WorktreePath
        BranchName     = $BranchName
        MainCheckout   = $RepoDir
        LogPath        = $LogPath
        TimeoutSeconds = $TimeoutSeconds
        WatcherScript  = $watcherScript
    }
    Set-Content -LiteralPath $paramFile -Value ($params | ConvertTo-Json) -Encoding utf8

    return [pscustomobject]@{ WatcherScript = $watcherScript; ParamFile = $paramFile; RunDir = $runDir }
}

# Runs the watcher to completion and waits for it.
function Invoke-Watcher {
    param(
        [string] $RepoDir,
        [string] $WorktreePath,
        [string] $BranchName,
        [string] $LogPath,
        [int] $TimeoutSeconds = 10
    )

    $staged = New-WatcherInvocation -RepoDir $RepoDir -WorktreePath $WorktreePath `
        -BranchName $BranchName -LogPath $LogPath -TimeoutSeconds $TimeoutSeconds

    $psExe = (Get-Process -Id $PID).Path
    # Same reason as Invoke-TestGit: the watcher writes its diagnostics to stderr, and Windows
    # PowerShell would turn them into a terminating error. The outcome log is what this asserts on.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $staged.WatcherScript `
            -Mode Watcher -ParamFile $staged.ParamFile 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $previous
    }
    # The watcher deletes the directory itself on every path that cleans up. This covers the paths
    # that do not, and makes the helper safe to call when the watcher never started.
    Remove-Item -LiteralPath $staged.RunDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Import the cleanup functions (the guard keeps the standalone entrypoint from running).
. $cleanupScript

# --- Test: the porcelain parser reads all three lock states ---------------------
# `git worktree list --porcelain` writes 'locked <reason>' with a reason and bare 'locked'
# without one. Both were observed with git 2.55.0.windows.3.
$lines = @(
    'worktree C:/repo'
    'HEAD 0000000000000000000000000000000000000000'
    'branch refs/heads/main'
    ''
    'worktree C:/repo/wt-a'
    'HEAD 0000000000000000000000000000000000000000'
    'branch refs/heads/a'
    'locked held by an agent'
    ''
    'worktree C:/repo/wt-b'
    'HEAD 0000000000000000000000000000000000000000'
    'branch refs/heads/b'
    'locked'
    ''
    'worktree C:/repo/wt-c'
    'HEAD 0000000000000000000000000000000000000000'
    'branch refs/heads/c'
)

# No @() around the call: the parser returns its array with the comma idiom, and @() would
# re-wrap that one object into a one-element array instead of unrolling it.
$records = ConvertFrom-WorktreePorcelain $lines
Assert-Equal 4 $records.Count "Expected 4 records, got $($records.Count)"
Assert-Equal 'held by an agent' $records[1].LockReason 'A reasoned lock keeps its reason'
Assert-Equal '' $records[2].LockReason 'A bare lock reads as an empty reason, not null'
Assert-True ($null -eq $records[3].LockReason) 'An unlocked worktree has a null LockReason'
Assert-True ($null -eq $records[0].LockReason) 'The main checkout has a null LockReason'

# --- Test: a locked worktree is never eligible, and the sweep says so ------------
$repo = New-TempGitRepo
try {
    $lockedPath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-locked'
    $freePath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-free'
    Invoke-TestGit $repo @('worktree', 'lock', '--reason', 'held by a human', $lockedPath) | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $lockedPath))) 'A locked worktree must never be eligible'
    Assert-True ($keys -contains (ConvertTo-Key $freePath)) 'An unlocked merged worktree stays eligible'

    # The sweep never hands a locked worktree over, so the sweep owns its outcome line.
    $log = Join-Path $repo '.claude\worktrees\worktree-removal.log'
    Assert-True (Test-Path -LiteralPath $log) 'Skipping a locked worktree must write an outcome line'
    $outcome = @(Get-Content -LiteralPath $log)
    Assert-Equal 1 $outcome.Count "One locked worktree writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match 'Kept: the worktree is locked \(held by a human\)\.$') `
        "Expected the locked line, got '$($outcome[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: a bare lock is skipped too, and reads as "no reason given" ------------
$repo = New-TempGitRepo
try {
    $lockedPath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-bare-lock'
    Invoke-TestGit $repo @('worktree', 'lock', $lockedPath) | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 (@($eligible).Count) 'A worktree locked without a reason must never be eligible'

    $outcome = @(Get-Content -LiteralPath (Join-Path $repo '.claude\worktrees\worktree-removal.log'))
    Assert-True ($outcome[0] -match 'Kept: the worktree is locked \(no reason given\)\.$') `
        "A bare lock must still name the state, got '$($outcome[0])'"
} finally {
    Remove-TempTree $repo
}

# --- Test: report-only names the locked worktree instead of hiding it ------------
# Hiding it would look like the sweep never noticed the worktree, and send a reader hunting a
# bug that is not there.
$repo = New-TempGitRepo
try {
    $lockedPath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-reported'
    Invoke-TestGit $repo @('worktree', 'lock', '--reason', 'a human is using it', $lockedPath) | Out-Null

    $result = Invoke-CleanupScript -RepoRoot $repo
    Assert-True ($result.Stderr -match '\[locked - skipped: a human is using it\]') `
        "Report-only must list the locked worktree, got: $($result.Stderr)"
    Assert-True (Test-Path -LiteralPath $lockedPath) 'Report-only must leave the locked worktree alone'
} finally {
    Remove-TempTree $repo
}

# --- Test: the watcher refuses a locked worktree, and force does not clear a lock ---
# Not a source scan: only a real run proves that git's own check, and not a read-then-act check
# this script writes, is what stops the removal.
$repo = New-TempGitRepo
try {
    $lockedPath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-watcher-lock'
    Invoke-TestGit $repo @('worktree', 'lock', '--reason', 'held by a human', $lockedPath) | Out-Null

    $lockLog = Join-Path (Split-Path -Parent $repo) 'watcher-lock.log'
    Invoke-Watcher -RepoDir $repo -WorktreePath $lockedPath -BranchName 'feat-watcher-lock' -LogPath $lockLog

    Assert-True (Test-Path -LiteralPath $lockedPath) 'A locked worktree must survive the watcher'
    $outcome = @(Get-Content -LiteralPath $lockLog)
    Assert-Equal 1 $outcome.Count "A locked removal writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match 'Kept: the worktree is locked \(held by a human\)\.$') `
        "Expected the locked line, got '$($outcome[0])'"

    # The override clears the merge gate. It must NOT clear a lock. The lock check sits inside the
    # watcher's rename loop, past the gate the override bypasses, so this needs no extra code --
    # and if it ever fails, the fix is to find what let the flow past the lock, not to add a
    # force branch beside the lock.
    $forceLog = Join-Path (Split-Path -Parent $repo) 'watcher-force-lock.log'
    $env:AHKFLOW_WORKTREE_FORCE_REMOVE = '1'
    try {
        Invoke-Watcher -RepoDir $repo -WorktreePath $lockedPath -BranchName 'feat-watcher-lock' -LogPath $forceLog
        Assert-True (Test-Path -LiteralPath $lockedPath) 'Force must not remove a locked worktree'
        $forced = @(Get-Content -LiteralPath $forceLog)
        Assert-True ($forced[0] -match 'Kept: the worktree is locked') `
            "Force plus lock must still write the locked line, got '$($forced[0])'"
    } finally {
        Remove-Item -LiteralPath 'Env:\AHKFLOW_WORKTREE_FORCE_REMOVE' -ErrorAction SilentlyContinue
    }
} finally {
    Remove-TempTree $repo
}

# --- Test: a lock added while the watcher is already waiting is honored ---------
# This is the case a read-then-act lock check cannot cover. The watcher waits up to its whole
# timeout, and a human can lock during that wait. Letting git do the move closes the window,
# because the check happens inside each attempt.
$repo = New-TempGitRepo
try {
    $racedPath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-locked-mid-wait'
    $raceLog = Join-Path (Split-Path -Parent $repo) 'watcher-race.log'

    # A process with the worktree as its current directory holds the folder, so the first move
    # attempts fail and the watcher keeps waiting -- which is what makes the race reachable.
    $holder = Start-Process -FilePath ((Get-Process -Id $PID).Path) -WindowStyle Hidden -PassThru `
        -WorkingDirectory $racedPath `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60')
    try {
        Start-Sleep -Seconds 2
        $staged = New-WatcherInvocation -RepoDir $repo -WorktreePath $racedPath `
            -BranchName 'feat-locked-mid-wait' -LogPath $raceLog -TimeoutSeconds 60
        $watcher = Start-Process -FilePath ((Get-Process -Id $PID).Path) -WindowStyle Hidden -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $staged.WatcherScript,
                '-Mode', 'Watcher', '-ParamFile', $staged.ParamFile)

        # Let the watcher reach its wait loop, then lock underneath it.
        Start-Sleep -Seconds 5
        Invoke-TestGit $repo @('worktree', 'lock', '--reason', 'a human stepped in', $racedPath) | Out-Null

        $watcher | Wait-Process -Timeout 120
        Remove-Item -LiteralPath $staged.RunDir -Recurse -Force -ErrorAction SilentlyContinue

        Assert-True (Test-Path -LiteralPath $racedPath) 'A worktree locked mid-wait must survive'
        $outcome = @(Get-Content -LiteralPath $raceLog)
        Assert-True ($outcome[-1] -match 'Kept: the worktree is locked \(a human stepped in\)\.$') `
            "Expected the locked line after a mid-wait lock, got '$($outcome[-1])'"
    } finally {
        Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
} finally {
    Remove-TempTree $repo
}

# --- Test: an unlocked worktree is still removed, by git rather than by a rename ---
# Without this case, a lock check that refused everything would pass every assertion above.
$repo = New-TempGitRepo
try {
    $freePath = Add-MergedWorktree -RepoDir $repo -BranchName 'feat-watcher-free'
    $freeLog = Join-Path (Split-Path -Parent $repo) 'watcher-free.log'
    Invoke-Watcher -RepoDir $repo -WorktreePath $freePath -BranchName 'feat-watcher-free' -LogPath $freeLog

    Assert-True (-not (Test-Path -LiteralPath $freePath)) 'An unlocked worktree must still be removed'
    $outcome = @(Get-Content -LiteralPath $freeLog)
    Assert-Equal 1 $outcome.Count "A successful removal writes one outcome line, got $($outcome.Count)"
    Assert-True ($outcome[0] -match 'Removed\.$') "Expected the Removed line, got '$($outcome[0])'"

    # git worktree move updates the registry as it goes, so nothing is left listed afterwards.
    $listed = (Invoke-TestGit $repo @('worktree', 'list')) -join "`n"
    Assert-True (-not ($listed -match 'feat-watcher-free')) "git must not still list the removed worktree: $listed"
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree lock honored tests passed.'
