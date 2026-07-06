#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'

function Assert-True {
    param([bool] $Condition, [string] $Message)
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
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# Fresh main-checkout repo under a throwaway root. Returns the repo path; its parent
# is the root to delete (worktrees are created as siblings of the repo).
function New-TempGitRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtclean-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    # Force the initial branch to 'main' independent of the host's init.defaultBranch.
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Cleanup Test' *> $null

    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'seed' -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

# Adds a linked worktree on a new branch off main (merged + clean by default).
# -Unmerged adds a commit not in main; -Dirty leaves an uncommitted change.
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

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# Import the cleanup functions (guard keeps the standalone entrypoint from running).
. (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')

# --- Test: eligibility matrix -------------------------------------------------
$repo = New-TempGitRepo
try {
    $cleanPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-clean'
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty' -Dirty | Out-Null
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-unmerged' -Unmerged | Out-Null

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })

    Assert-Equal 1 $eligible.Count 'Only the merged+clean worktree should be eligible.'
    Assert-True ($keys -contains (ConvertTo-Key $cleanPath)) 'The merged+clean worktree must be eligible.'
    Assert-Equal 'feat-clean' $eligible[0].Branch 'Eligible branch short name should be feat-clean.'
    $mainKey = ConvertTo-Key $repo
    Assert-True (-not ($keys -contains $mainKey)) 'The main checkout must never be eligible.'
} finally {
    Remove-TempTree $repo
}

# --- Test: ExcludePath protects the worktree this run is about to create/reuse ---
$repo = New-TempGitRepo
try {
    $targetPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-target'

    # Without exclusion the target itself would be eligible (merged + clean)...
    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-True ((@($eligible | ForEach-Object { ConvertTo-Key $_.Path })) -contains (ConvertTo-Key $targetPath)) 'Sanity check: the target worktree must be eligible before exclusion is applied.'

    # ...but passing -ExcludePath must remove it from the eligible set, so a run that is
    # about to create/reuse this exact path can never race its own async removal.
    $excluded = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -ExcludePath $targetPath
    $excludedKeys = @($excluded | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($excludedKeys -contains (ConvertTo-Key $targetPath))) '-ExcludePath must exclude the target worktree even though it is merged+clean.'
} finally {
    Remove-TempTree $repo
}

# --- Test: --format branch parsing (regression guard for the '+ ' marker) ------
$repo = New-TempGitRepo
try {
    $mergedPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plusprefix'

    # A branch checked out in another worktree is prefixed with '+ ' by plain
    # `git branch --merged`; a naive parse would drop it. Prove the marker is there...
    $plain = (Invoke-TestGit $repo @('branch', '--merged', 'main')) -join "`n"
    Assert-True ($plain -match '(?m)^\+\s+feat-plusprefix$') 'Expected the plain --merged output to prefix the worktree branch with "+ ".'

    # ...then prove detection (which uses --format) still finds it.
    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True ($keys -contains (ConvertTo-Key $mergedPath)) 'A merged branch checked out in a worktree must be detected despite the "+ " marker.'
} finally {
    Remove-TempTree $repo
}

# --- Test: hook context is report-only (detects, never removes/prompts) --------
$repo = New-TempGitRepo
try {
    $hookPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-hook'

    Invoke-MergedWorktreeCleanup -RepoRoot $repo -IsHook -MainRef 'main'

    Assert-True (Test-Path -LiteralPath $hookPath) 'Hook context must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-hook')) -join "`n"
    Assert-True ($branches -match 'feat-hook') 'Hook context must not delete the eligible branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: redirected non-interactive runs skip removal without prompting -------
$repo = New-TempGitRepo
try {
    $skipPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-noninteractive'

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stdin.txt'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'cleanup-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
    $proc = Start-Process -FilePath $psExe `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $repo, '-MainRef', 'main') `
        -WorkingDirectory $suiteRoot `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    Assert-Equal 0 $proc.ExitCode "cleanup-merged-worktrees.ps1 non-interactive path should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = Get-Content -Raw -LiteralPath $stdoutFile
    Assert-True ([string]::IsNullOrWhiteSpace($stdout)) "Non-interactive cleanup must not write to stdout. Got: $stdout"

    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected cleanup detection output on stderr. Stderr: $stderrText"
    Assert-True ($stderrText -match 'cleanup: non-interactive and no -Cleanup; skipping') "Expected non-interactive skip output on stderr. Stderr: $stderrText"

    Assert-True (Test-Path -LiteralPath $skipPath) 'Non-interactive cleanup without -Cleanup must not remove the eligible worktree folder.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-noninteractive')) -join "`n"
    Assert-True ($branches -match 'feat-noninteractive') 'Non-interactive cleanup without -Cleanup must not delete the eligible branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: hook path keeps stdout to exactly the new worktree path -------------
function New-WorktreeToolingRepo {
    param([string] $ScriptsSource)

    $repo = New-TempGitRepo

    $repoScripts = Join-Path $repo 'scripts'
    New-Item -ItemType Directory -Path $repoScripts -Force | Out-Null
    # Top-level *.ps1 only: the worktree contract files, without ci/ or a stray .env.worktree.
    Copy-Item -Path (Join-Path $ScriptsSource '*.ps1') -Destination $repoScripts -Force

    $appSettingsDir = Join-Path $repo 'src\Backend\AHKFlowApp.API'
    New-Item -ItemType Directory -Path $appSettingsDir -Force | Out-Null
    $appSettings = '{ "ConnectionStrings": { "DefaultConnection": "Server=localhost;Database=AHKFlowApp;Trusted_Connection=True;" }, "Cors": { "AllowedOrigins": [] } }'
    Set-Content -LiteralPath (Join-Path $appSettingsDir 'appsettings.json') -Value $appSettings -Encoding utf8

    Set-Content -LiteralPath (Join-Path $repo 'AHKFlowApp.slnx') -Value '<Solution />' -Encoding utf8

    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'worktree tooling') | Out-Null

    return $repo
}

$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    # An eligible (merged + clean) worktree so cleanup has something to report during the run.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-eligible' | Out-Null

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'hook-stdin.json'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'hook-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'hook-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '{"name":"brandnew"}' -Encoding utf8

    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $newWorktreeScript = Join-Path $repo 'scripts\new-worktree.ps1'
    $proc = Start-Process -FilePath $psExe `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $newWorktreeScript) `
        -WorkingDirectory $repo `
        -RedirectStandardInput $stdinFile `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait

    Assert-Equal 0 $proc.ExitCode "new-worktree.ps1 hook path should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = (Get-Content -Raw -LiteralPath $stdoutFile)
    $stdoutLines = @(($stdout -split "`r?`n") | Where-Object { $_.Trim() })
    $expected = ([System.IO.Path]::GetFullPath((Join-Path $repo '.claude\worktrees\brandnew'))).TrimEnd('\', '/')

    Assert-Equal 1 $stdoutLines.Count "Hook stdout must be exactly one line. Got: $stdout"
    Assert-Equal $expected ($stdoutLines[0].Trim().TrimEnd('\', '/')) 'Hook stdout must be exactly the new worktree path.'

    # Proves cleanup actually ran as part of this hook invocation, not just that stdout
    # happened to stay clean (which the pre-existing script would already satisfy).
    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected cleanup detection output on stderr proving cleanup ran. Stderr: $stderrText"
    Assert-True ($stderrText -match 'cleanup: hook context is report-only; nothing removed\.') "Expected the hook-context report-only line on stderr. Stderr: $stderrText"
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree merged-cleanup tests passed.'
