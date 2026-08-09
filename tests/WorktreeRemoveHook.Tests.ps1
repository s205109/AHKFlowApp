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
    $out = & git -C $RepoDir @GitArgs 2>&1
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
function Add-TestWorktree {
    param(
        [string] $RepoDir,
        [string] $BranchName,
        [switch] $Unmerged,
        [switch] $Dirty
    )

    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null

    if ($Unmerged) {
        Set-Content -LiteralPath (Join-Path $wtPath 'extra.txt') -Value 'unmerged' -Encoding utf8
        Invoke-TestGit $wtPath @('add', '-A') | Out-Null
        Invoke-TestGit $wtPath @('commit', '-m', "work on $BranchName") | Out-Null
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

function Get-RemovalLogPath {
    param([string] $RepoDir)
    return Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
}

# Invokes the hook by piping {"worktree_path":"<path>"} JSON to remove-worktree-local-dev.ps1,
# exactly as Claude's WorktreeRemove hook does. Returns the process exit code; log content is
# read separately by the caller once the process has exited.
function Invoke-RemoveHook {
    param(
        [string] $WorktreePath,
        [hashtable] $EnvOverrides
    )

    $stdinFile = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $payload = (@{ worktree_path = $WorktreePath } | ConvertTo-Json -Compress)
        Set-Content -LiteralPath $stdinFile -Value $payload -Encoding utf8

        $previousValues = @{}
        if ($EnvOverrides) {
            foreach ($key in $EnvOverrides.Keys) {
                $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
                [Environment]::SetEnvironmentVariable($key, [string] $EnvOverrides[$key], 'Process')
            }
        }

        try {
            $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
            $proc = Start-Process -FilePath $psExe `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $removeScript, '-Mode', 'Hook') `
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

# --- Test: unmerged -> folder preserved, reason + guidance logged --------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unmerged' -Unmerged

    $result = Invoke-RemoveHook -WorktreePath $wtPath
    Assert-Equal 0 $result.ExitCode "Hook should exit 0. Stderr: $($result.Stderr)"

    Assert-True (Test-Path -LiteralPath $wtPath) 'Unmerged worktree must be preserved (no watcher removal).'

    $log = Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo)
    Assert-True ($log -match '(?i)not merged') "Expected the log to name the unmerged reason. Log: $log"
    Assert-True ($log -match 'AHKFLOW_WORKTREE_FORCE_REMOVE') "Expected the log to mention the force override opt-out. Log: $log"
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

    $log = Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo)
    Assert-True ($log -match '(?i)uncommitted') "Expected the log to name the dirty-tree reason. Log: $log"
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

    $log = Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo)
    Assert-True ($log -match '(?i)detached') "Expected the log to name the detached-HEAD reason. Log: $log"
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
    $log = Get-Content -Raw -LiteralPath (Get-RemovalLogPath $repo)
    Assert-True ($log -match '(?i)force override.*bypassing merge/clean gate') "Expected a force-override log line proving the gate was consulted and bypassed. Log: $log"
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree remove-hook gate tests passed.'
