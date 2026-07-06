#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a git worktree and applies AHKFlowApp local-dev isolation.
.DESCRIPTION
    This script can be called directly, or by Claude Code's WorktreeCreate hook.
    For hook use, stdout must contain only the absolute worktree path on success.
#>

[CmdletBinding()]
param(
    [string] $Name,
    [string] $BranchName,
    [string] $Path,

    [Alias('c')]
    [switch] $Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-powershell.common.ps1')

function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}

function Get-HookInput {
    if (-not [Console]::IsInputRedirected) {
        return $null
    }

    # A redirected-but-open stdin (background/piped launch that never sends EOF) makes a
    # blocking ReadToEnd hang forever. Bound the read so a direct invocation can't stall.
    $readTask = [Console]::In.ReadToEndAsync()
    if (-not $readTask.Wait(2000)) {
        Write-Stderr 'No hook stdin within timeout; continuing without hook input.'
        return $null
    }
    $stdin = $readTask.Result
    if ([string]::IsNullOrWhiteSpace($stdin)) {
        return $null
    }

    try {
        return $stdin | ConvertFrom-Json
    } catch {
        Write-Stderr "Ignoring non-JSON hook stdin: $($_.Exception.Message)"
        return $null
    }
}

function ConvertTo-SafeName {
    param([string] $Value)

    $safe = ($Value.Trim() -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if (-not $safe) {
        throw 'Worktree name cannot be empty.'
    }

    return $safe
}

function Invoke-Git {
    param(
        [string] $RepoRoot,
        [string[]] $Arguments
    )

    $output = & git -C $RepoRoot @Arguments
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($line) {
            Write-Stderr ([string] $line)
        }
    }

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Test-BranchExists {
    param(
        [string] $RepoRoot,
        [string] $Branch
    )

    & git -C $RepoRoot show-ref --verify --quiet "refs/heads/$Branch"
    return $LASTEXITCODE -eq 0
}

function Assert-MainCheckout {
    param([string] $RepoRoot)

    if (Test-LinkedWorktree $RepoRoot) {
        throw 'Run new-worktree.ps1 from the main checkout. Nested worktree creation from a linked worktree is refused.'
    }
}

function Copy-WorktreeIncludeEntries {
    param(
        [string] $RepoRoot,
        [string] $WorktreePath
    )

    $includePath = Join-Path $RepoRoot '.worktreeinclude'
    if (-not (Test-Path -LiteralPath $includePath)) {
        return
    }

    foreach ($line in Get-Content -LiteralPath $includePath) {
        $relativePath = $line.Trim()
        if (-not $relativePath -or $relativePath.StartsWith('#')) {
            continue
        }

        $sourcePath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }

        $destinationPath = Join-Path $WorktreePath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null

        $source = Get-Item -LiteralPath $sourcePath -Force
        if ($source.PSIsContainer) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
        } else {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }

        Write-Stderr "Copied $relativePath into worktree."
    }
}

# Sweep orphaned per-worktree Docker compose projects (worktrees removed by plain git,
# Codex, or Copilot never fire the WorktreeRemove hook). Best-effort and non-fatal: a
# missing docker CLI or a prune error must never block worktree creation. Output is
# forwarded to stderr so stdout stays the single worktree path the hook contract requires.
function Invoke-OrphanDockerPrune {
    param([string] $RepoRoot)

    $pruneScript = Join-Path $RepoRoot 'scripts\prune-worktree-docker.ps1'
    if (-not (Test-Path -LiteralPath $pruneScript)) {
        return
    }

    try {
        $psExe = Resolve-PowerShellExecutable
        $pruneOutput = & $psExe -NoProfile -ExecutionPolicy Bypass -File $pruneScript -Quiet 2>&1
        foreach ($line in $pruneOutput) {
            if ($line) {
                Write-Stderr ([string] $line)
            }
        }
    } catch {
        Write-Stderr "Orphan Docker prune skipped: $($_.Exception.Message)"
    }
}

function Assert-WorktreeLocation {
    param(
        [string] $RepoRoot,
        [string] $WorktreePath
    )

    # Worktrees must be direct children of one of these gitignored folders.
    foreach ($relative in @('.claude\worktrees', '.worktrees')) {
        $allowed = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relative))
        $parent = [System.IO.Path]::GetFullPath((Split-Path -Parent $WorktreePath))
        if ($parent.TrimEnd('\') -ieq $allowed.TrimEnd('\')) {
            return
        }
    }

    throw "Refusing to create a worktree outside an allowed direct-child location. Worktrees must be direct children of '.claude\worktrees\' (preferred) or '.worktrees\'; got '$WorktreePath'. Omit -Path to use the default, or pass a direct child path under one of those folders."
}

function Assert-SetupScriptCommitted {
    param(
        [string] $RepoRoot,
        [string] $Ref
    )

    # git worktree add checks out only committed files. If the worktree setup scripts live in
    # the working tree but are not committed on the source ref, the new worktree won't contain
    # them and setup can't run. Fail early -- before creating the worktree, so no half-made
    # worktree is left behind -- with an actionable message instead of the later "not found".
    # ls-tree prints the path when committed and nothing (exit 0, no stderr) when absent, so it
    # avoids the NativeCommandError that 'cat-file -e' raises under ErrorActionPreference=Stop.
    $trackedPath = 'scripts/setup-worktree-local-dev.ps1'
    $committed = & git -C $RepoRoot ls-tree -r --name-only $Ref -- $trackedPath
    if (-not $committed) {
        throw "The worktree setup scripts are not committed on '$Ref'. 'git worktree add' only checks out committed files, so a new worktree would be missing '$trackedPath'. Commit the worktree tooling (scripts\, .worktreeinclude, .claude\settings.json) on '$Ref', then rerun."
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Assert-MainCheckout $repoRoot
# A direct call supplies -Name and never needs hook stdin; only read it for hook invocations.
$hookInput = if ($Name) { $null } else { Get-HookInput }

# Hook-driven iff -Name absent AND hook JSON was read. Do NOT derive hook-ness from
# [Console]::IsInputRedirected: that is also true for a redirected direct/agent call.
$isHook = (-not $Name) -and ($null -ne $hookInput)

if (-not $Name -and $hookInput -and $hookInput.PSObject.Properties.Name -contains 'name') {
    $Name = [string] $hookInput.name
}

if (-not $Name) {
    throw 'Provide -Name, or call this script from a Claude WorktreeCreate hook.'
}

$safeName = ConvertTo-SafeName $Name
if (-not $BranchName) {
    $BranchName = $safeName
}

if (-not $Path) {
    $Path = Join-Path $repoRoot ".claude\worktrees\$safeName"
}

$worktreePath = [System.IO.Path]::GetFullPath($Path)
Assert-WorktreeLocation -RepoRoot $repoRoot -WorktreePath $worktreePath
$worktreeExists = Test-Path -LiteralPath (Join-Path $worktreePath '.git')

# Sweep other worktrees whose branch is already merged into main before creating/reusing
# this one. -ExcludePath protects $worktreePath itself now that it is known: without it,
# a same-named create/reuse could race the async removal. Best-effort: never block
# creation, and pipe to Out-Null so cleanup output can never reach hook stdout.
try {
    & (Join-Path $PSScriptRoot 'cleanup-merged-worktrees.ps1') -RepoRoot $repoRoot -Cleanup:$Cleanup -IsHook:$isHook -ExcludePath $worktreePath | Out-Null
} catch {
    Write-Stderr "Merged-worktree cleanup skipped: $($_.Exception.Message)"
}

Invoke-OrphanDockerPrune $repoRoot

if (-not $worktreeExists) {
    $branchExists = Test-BranchExists $repoRoot $BranchName
    $sourceRef = if ($branchExists) { $BranchName } else { 'HEAD' }
    Assert-SetupScriptCommitted -RepoRoot $repoRoot -Ref $sourceRef

    New-Item -ItemType Directory -Path (Split-Path -Parent $worktreePath) -Force | Out-Null

    if ($branchExists) {
        Invoke-Git $repoRoot @('worktree', 'add', $worktreePath, $BranchName)
    } else {
        Invoke-Git $repoRoot @('worktree', 'add', $worktreePath, '-b', $BranchName)
    }
}

Copy-WorktreeIncludeEntries $repoRoot $worktreePath

$setupScript = Join-Path $worktreePath 'scripts\setup-worktree-local-dev.ps1'
if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "Setup script was not found in the new worktree: $setupScript"
}

$psExe = Resolve-PowerShellExecutable
$setupOutput = & $psExe -NoProfile -ExecutionPolicy Bypass -File $setupScript -RepoRoot $worktreePath -Quiet
$setupExitCode = $LASTEXITCODE
foreach ($line in $setupOutput) {
    if ($line) {
        Write-Stderr ([string] $line)
    }
}

if ($setupExitCode -ne 0) {
    throw "Worktree setup failed with exit code $setupExitCode."
}

[Console]::Out.WriteLine($worktreePath)
