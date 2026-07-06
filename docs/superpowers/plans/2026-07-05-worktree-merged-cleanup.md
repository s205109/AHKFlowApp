# Worktree Merged-Cleanup on Create Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On worktree creation, detect other worktrees whose branch is already merged into `main` and remove the finished (clean) ones — but only on an explicit opt-in.

**Architecture:** A new standalone `scripts/cleanup-merged-worktrees.ps1` owns detection (merged + clean), the single interactive opt-in, and the removal call. `new-worktree.ps1` invokes it (in-process, before it creates the new worktree) passing a `-Cleanup` switch and an `$isHook` boolean. Removal reuses the existing lock-safe `remove-worktree-local-dev.ps1`. All cleanup output goes to stderr so the `WorktreeCreate` hook's stdout stays exactly the new worktree path.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7 (`#Requires -Version 5.1`), git worktrees, the repo's existing assert-style `*.Tests.ps1` scripts (no Pester).

## Global Constraints

- **PowerShell for script files** — all new/edited scripts use `#Requires -Version 5.1`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` (match `new-worktree.ps1`). Bash only for command blocks inside `.md` docs.
- **Hook stdout contract** — the `WorktreeCreate` hook path (`new-worktree.ps1`) must write **only** the absolute worktree path to stdout. Every cleanup diagnostic goes to stderr.
- **No `git fetch`, local `main` only** — merge detection uses the local `main` ref via `git branch --format="%(refname:short)" --merged main`. Never plain `git branch --merged` (its `* `/`+ ` markers break a naive compare).
- **Opt-in required** — nothing is ever removed without either the single interactive answer `y` **or** the `-Cleanup` switch. No default-removal path.
- **Never remove a dirty worktree** — a worktree with any uncommitted change (`git status --porcelain` non-empty) is excluded even if merged. The main checkout is always excluded.
- **Reuse the removal path** — remove each worktree by shelling out to `scripts/remove-worktree-local-dev.ps1 -WorktreePath <path>` (its default Hook mode); do not re-implement removal.
- **Shared host resolver** — spawn child PowerShell via `Resolve-PowerShellExecutable` (`worktree-powershell.common.ps1`), never bare `powershell`/`$PSHOME`.
- **Exact prompt text** — the one interactive question is exactly `Clean up merged worktrees? (y/n)`.
- **CLI switch** — `new-worktree.ps1` gains `-Cleanup` with alias `-c`.

## File Structure

- **Create** `scripts/cleanup-merged-worktrees.ps1` — one responsibility: sweep merged worktrees. Detection (`Get-EligibleMergedWorktrees`, `ConvertFrom-WorktreePorcelain`), orchestration (`Invoke-MergedWorktreeCleanup`), and the removal shell-out (`Invoke-WorktreeRemoval`). Dot-sourceable (functions only) for tests; runs the sweep when invoked directly.
- **Modify** `scripts/new-worktree.ps1` — add the `-Cleanup`/`-c` switch, compute `$isHook`, and invoke the cleanup script (guarded, output discarded) before creating the worktree.
- **Create** `tests/WorktreeMergedCleanup.Tests.ps1` — assert-style behavior tests (eligibility matrix, `--format` regression guard, hook report-only, stdout-clean end-to-end).
- **Modify** `tests/WorktreePowerShellHost.Tests.ps1` — extend the host-resolver text assertions to cover the new script.
- **Modify** `scripts/README.md` — add the new script to the "Worktree internals — contract" table.
- **Modify** `.agents/worktrees/SKILL.md` only — document `-Cleanup`/`-c` and the interactive question. `.claude/skills/worktrees` and `.github/skills/worktrees` are directory symlinks to `.agents/worktrees` (follow automatically); `plugins/ahkflowapp/skills/worktrees/SKILL.md` is a **hard link** to the same file (not an independent copy) — re-run `scripts/agents/setup-copilot-symlinks.ps1` afterward to guarantee it, then hash-check, instead of hand-editing it a second time.

---

### Task 1: Detection — eligible merged worktrees

**Files:**
- Create: `scripts/cleanup-merged-worktrees.ps1`
- Test: `tests/WorktreeMergedCleanup.Tests.ps1`

**Interfaces:**
- Produces: `Get-EligibleMergedWorktrees -RepoRoot <string> [-MainRef <string='main'>] [-ExcludePath <string>]` → array (possibly empty) of `[pscustomobject]@{ Path=<normalized full path>; Branch=<short name> }`, one per worktree that is merged into `$MainRef` **and** clean, excluding the main checkout, any detached/bare worktree, and `$ExcludePath` when given (the worktree this run is about to create or reuse — see Task 3's race-safety note).
- Produces: `ConvertFrom-WorktreePorcelain -Lines <string[]>` → array of `[pscustomobject]@{ Path; Branch }` (Branch is `$null` for detached/bare).
- Produces: `Write-Stderr -Message <string>` (writes to `[Console]::Error`).

- [ ] **Step 1: Write the failing test file**

Create `tests/WorktreeMergedCleanup.Tests.ps1` with shared helpers plus the eligibility-matrix and `--format` regression tests. (Do **not** name any variable `RepoRoot`, `Cleanup`, `IsHook`, `MainRef`, `Path`, `Name`, or `BranchName` in this file — dot-sourcing `cleanup-merged-worktrees.ps1` binds its `param()` into this scope and PowerShell variables are case-insensitive, so those names would be clobbered.)

```powershell
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

Write-Host 'Worktree merged-cleanup tests passed.'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — the dot-source of `scripts/cleanup-merged-worktrees.ps1` errors because the file does not exist yet (e.g. "Cannot find path ... cleanup-merged-worktrees.ps1").

- [ ] **Step 3: Create the cleanup script with detection only**

Create `scripts/cleanup-merged-worktrees.ps1`:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Detects worktrees whose branch is already merged into main and, on an explicit
    opt-in, removes the finished (clean) ones via remove-worktree-local-dev.ps1.
.DESCRIPTION
    Invoked by new-worktree.ps1 before it creates a new worktree, and runnable on its
    own. Removal never happens without an explicit opt-in: the single interactive
    question on a real console, or the -Cleanup switch. In a WorktreeCreate hook
    context (-IsHook) detection runs but nothing is prompted or removed, and all
    output stays on stderr so the hook's stdout contract is preserved.
#>

[CmdletBinding()]
param(
    [string] $RepoRoot,
    [switch] $Cleanup,
    [switch] $IsHook,
    [string] $MainRef = 'main',
    [string] $ExcludePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-log.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-powershell.common.ps1')

function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}

# Parses `git worktree list --porcelain` into { Path; Branch } records. Branch is the
# short name for a normal worktree, and $null for a detached-HEAD or bare entry.
function ConvertFrom-WorktreePorcelain {
    param([string[]] $Lines)

    $worktrees = @()
    $current = $null
    foreach ($line in $Lines) {
        if ($line -like 'worktree *') {
            if ($current) { $worktrees += $current }
            $current = [pscustomobject]@{ Path = $line.Substring('worktree '.Length); Branch = $null }
        } elseif ($current -and ($line -like 'branch refs/heads/*')) {
            $current.Branch = $line.Substring('branch refs/heads/'.Length)
        }
    }
    if ($current) { $worktrees += $current }

    return , $worktrees
}

# Returns the worktrees that are merged into $MainRef AND clean, excluding the main
# checkout, any detached/bare worktree, and $ExcludePath when given. Each item:
# { Path (normalized); Branch }.
function Get-EligibleMergedWorktrees {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $MainRef = 'main',
        [string] $ExcludePath
    )

    $repoRootFull = ([System.IO.Path]::GetFullPath($RepoRoot)).TrimEnd('\', '/')
    $excludeFull = if ($ExcludePath) { ([System.IO.Path]::GetFullPath($ExcludePath)).TrimEnd('\', '/') } else { $null }

    # Bare, marker-free short names. Plain `git branch --merged` prefixes '* '/'+ ',
    # so --format is required or a naive compare skips every eligible worktree.
    $mergedNames = & git -C $RepoRoot branch --format='%(refname:short)' --merged $MainRef 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr "cleanup: 'git branch --merged $MainRef' failed; skipping merged-cleanup detection."
        return , @()
    }
    $mergedSet = @{}
    foreach ($name in $mergedNames) {
        $trimmed = ([string] $name).Trim()
        if ($trimmed) { $mergedSet[$trimmed] = $true }
    }

    $listLines = & git -C $RepoRoot worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr 'cleanup: git worktree list failed; skipping merged-cleanup detection.'
        return , @()
    }

    $eligible = @()
    foreach ($wt in (ConvertFrom-WorktreePorcelain $listLines)) {
        if (-not $wt.Path) { continue }
        $wtFull = ([System.IO.Path]::GetFullPath($wt.Path)).TrimEnd('\', '/')

        if ([string]::Equals($wtFull, $repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue   # the main checkout is never removed
        }
        # The worktree this run is about to create/reuse: never sweep it out from under
        # itself. remove-worktree-local-dev.ps1's hook mode spawns a detached watcher and
        # returns immediately, so without this exclusion an async removal could still be
        # renaming/deleting this exact path while new-worktree.ps1 reuses/creates it.
        if ($excludeFull -and [string]::Equals($wtFull, $excludeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not $wt.Branch) { continue }                          # detached/bare: not eligible
        if (-not $mergedSet.ContainsKey($wt.Branch)) { continue }  # not merged into main

        # A per-worktree git error must not abort the sweep: log to stderr and skip.
        $status = & git -C $wtFull status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Stderr "cleanup: status check failed for '$wtFull'; skipping it."
            continue
        }
        if ($status) { continue }                                  # dirty: protect in-progress work

        $eligible += [pscustomobject]@{ Path = $wtFull; Branch = $wt.Branch }
    }

    return , $eligible
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: PASS — prints `Worktree merged-cleanup tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/cleanup-merged-worktrees.ps1 tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "feat: detect merged+clean worktrees for cleanup"
```

---

### Task 2: Orchestration, removal shell-out, and standalone entrypoint

**Files:**
- Modify: `scripts/cleanup-merged-worktrees.ps1` (append functions + entrypoint guard)
- Modify: `tests/WorktreeMergedCleanup.Tests.ps1` (append the hook report-only test)
- Modify: `tests/WorktreePowerShellHost.Tests.ps1:45` (append host-resolver assertions for the new script)

**Interfaces:**
- Consumes: `Get-EligibleMergedWorktrees`, `Write-Stderr` (Task 1); `Resolve-PowerShellExecutable` (`worktree-powershell.common.ps1`); `Write-WorktreeLog` (`worktree-log.common.ps1`).
- Produces: `Invoke-MergedWorktreeCleanup -RepoRoot <string> [-Cleanup] [-IsHook] [-MainRef <string='main'>] [-ExcludePath <string>]` → drives the decision matrix; `-ExcludePath` is forwarded to `Get-EligibleMergedWorktrees` so the worktree this run is about to create/reuse is never swept; returns nothing on the success stream; never throws for expected conditions.
- Produces: `Invoke-WorktreeRemoval -RepoRoot <string> -WorktreePath <string>` → spawns `remove-worktree-local-dev.ps1` (Hook mode) with empty stdin; forwards its output to stderr.

- [ ] **Step 1: Write the failing hook report-only test**

Append to `tests/WorktreeMergedCleanup.Tests.ps1`, immediately before the final `Write-Host` line:

```powershell
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — `Invoke-MergedWorktreeCleanup` is not defined ("The term 'Invoke-MergedWorktreeCleanup' is not recognized").

- [ ] **Step 3: Append orchestration, removal, and the entrypoint guard**

Append to `scripts/cleanup-merged-worktrees.ps1` (after `Get-EligibleMergedWorktrees`):

```powershell
# Spawns remove-worktree-local-dev.ps1 (Hook mode) for one worktree. Empty stdin is
# piped in: that script's hook path does an unbounded [Console]::In.ReadToEnd(), which
# would hang if THIS run's own stdin is redirected (agent/CI) and left open.
function Invoke-WorktreeRemoval {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $WorktreePath
    )

    $removeScript = Join-Path $RepoRoot 'scripts\remove-worktree-local-dev.ps1'
    if (-not (Test-Path -LiteralPath $removeScript)) {
        Write-Stderr "cleanup: remove-worktree-local-dev.ps1 not found; cannot remove '$WorktreePath'."
        return
    }

    try {
        $psExe = Resolve-PowerShellExecutable
        $output = '' | & $psExe -NoProfile -ExecutionPolicy Bypass -File $removeScript -WorktreePath $WorktreePath 2>&1
        foreach ($line in $output) {
            if ($line) { Write-Stderr ([string] $line) }
        }
    } catch {
        Write-Stderr "cleanup: removal of '$WorktreePath' failed: $($_.Exception.Message)"
    }
}

# Drives the decision matrix. Detection/removal failures are logged to stderr and
# skipped so worktree creation is never blocked. Emits nothing on the success stream.
function Invoke-MergedWorktreeCleanup {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [switch] $Cleanup,
        [switch] $IsHook,
        [string] $MainRef = 'main',
        [string] $ExcludePath
    )

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $RepoRoot -MainRef $MainRef -ExcludePath $ExcludePath
    if ($eligible.Count -eq 0) {
        Write-Stderr 'cleanup: no merged worktrees eligible for cleanup.'
        return
    }

    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: eligible merged worktree: $($wt.Path) [$($wt.Branch)]"
    }

    if ($IsHook) {
        Write-Stderr 'cleanup: hook context is report-only; nothing removed.'
        return
    }

    $authorized = $false
    if ($Cleanup) {
        $authorized = $true                                    # user already opted in
    } elseif (-not [Console]::IsInputRedirected) {
        $answer = Read-Host 'Clean up merged worktrees? (y/n)'  # single interactive question
        $authorized = ($answer -match '^\s*(y|yes)\s*$')
    } else {
        Write-Stderr 'cleanup: non-interactive and no -Cleanup; skipping (removal needs an explicit opt-in).'
        return
    }

    if (-not $authorized) {
        Write-Stderr 'cleanup: declined; nothing removed.'
        return
    }

    $removalLog = Join-Path $RepoRoot '.claude\worktrees\worktree-removal.log'
    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: removing merged worktree: $($wt.Path) [$($wt.Branch)]"
        try {
            Write-WorktreeLog -LogPath $removalLog -Worktree (Split-Path -Leaf $wt.Path) -Message "Merged-cleanup requested removal (branch $($wt.Branch))."
        } catch { }
        Invoke-WorktreeRemoval -RepoRoot $RepoRoot -WorktreePath $wt.Path
    }
}

# Run the sweep only when executed directly. When dot-sourced (e.g. by tests) to import
# the functions, $MyInvocation.InvocationName is '.', so the entrypoint is skipped.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RepoRoot) {
        $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    }
    Invoke-MergedWorktreeCleanup -RepoRoot $RepoRoot -Cleanup:$Cleanup -IsHook:$IsHook -MainRef $MainRef -ExcludePath $ExcludePath | Out-Null
}
```

- [ ] **Step 4: Run the behavior test to verify it passes**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: PASS — prints `Worktree merged-cleanup tests passed.`

- [ ] **Step 5: Append host-resolver assertions for the new script**

Add to `tests/WorktreePowerShellHost.Tests.ps1` after line 45 (after the `remove-worktree-local-dev.ps1` assertions, before the `.claude\settings.json` block):

```powershell
$cleanupPath = Join-Path $repoRoot 'scripts\cleanup-merged-worktrees.ps1'
Assert-True (Test-Path -LiteralPath $cleanupPath) 'Expected cleanup-merged-worktrees.ps1 to exist.'
$cleanupContent = Get-Content -LiteralPath $cleanupPath -Raw
Assert-DoesNotMatch $cleanupContent '(?m)&\s+powershell(\.exe)?\s+-NoProfile' 'cleanup-merged-worktrees.ps1 must not launch remove-worktree-local-dev.ps1 through bare powershell.'
Assert-True ($cleanupContent -match [regex]::Escape('worktree-powershell.common.ps1')) 'cleanup-merged-worktrees.ps1 should use the shared PowerShell host resolver.'
Assert-True ($cleanupContent -match 'Resolve-PowerShellExecutable') 'cleanup-merged-worktrees.ps1 should resolve the PowerShell host via the shared resolver.'
```

- [ ] **Step 6: Run the host-resolver test to verify it passes**

Run: `pwsh -NoProfile -File tests/WorktreePowerShellHost.Tests.ps1`
Expected: PASS — prints `Worktree PowerShell host tests passed.`

- [ ] **Step 7: Commit**

```bash
git add scripts/cleanup-merged-worktrees.ps1 tests/WorktreeMergedCleanup.Tests.ps1 tests/WorktreePowerShellHost.Tests.ps1
git commit -m "feat: merged-worktree cleanup decision + removal shell-out"
```

---

### Task 3: Wire cleanup into `new-worktree.ps1`

**Files:**
- Modify: `scripts/new-worktree.ps1:10-15` (add the switch), `scripts/new-worktree.ps1:202-203` (compute `$isHook`), and `scripts/new-worktree.ps1:222-226` (invoke cleanup once the target path is known, with `-ExcludePath`)
- Test: `tests/WorktreeMergedCleanup.Tests.ps1` (append the stdout-clean end-to-end test)

**Interfaces:**
- Consumes: `Invoke-MergedWorktreeCleanup` via `& scripts/cleanup-merged-worktrees.ps1` (Task 2).
- Produces: `new-worktree.ps1` accepts `-Cleanup` (alias `-c`); on the hook path, stdout stays exactly the new worktree path.

**Race safety:** cleanup must not run before `$worktreePath` is resolved. `remove-worktree-local-dev.ps1`'s hook mode spawns a detached watcher and returns with the folder still present — if a same-named create/reuse targets the exact worktree cleanup just told to remove, an async delete and this run's reuse of that path could execute concurrently. Resolving `$worktreePath` first and passing it as `-ExcludePath` keeps that specific path out of the eligible set no matter how the timing falls.

- [ ] **Step 1: Write the failing stdout-clean end-to-end test**

Append to `tests/WorktreeMergedCleanup.Tests.ps1`, immediately before the final `Write-Host` line. This builds a throwaway repo that copies the real top-level scripts plus a minimal committed `appsettings.json` (enough for `setup-worktree-local-dev.ps1` to derive a DB name without touching SQL), pre-creates an eligible worktree, then drives the real hook path.

```powershell
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
    $appSettings = '{ "ConnectionStrings": { "DefaultConnection": "Server=localhost;Database=AHKFlowApp;Trusted_Connection=True;" } }'
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — before Step 3, the copied `new-worktree.ps1` still creates the worktree but does not invoke cleanup, so the stderr-proof assertion fails because no `cleanup: eligible merged worktree` line is emitted. Confirm the failure is in this new test block.

> Note: this test copies the **current** `scripts/*.ps1`. Before Step 3, `new-worktree.ps1` does not call cleanup, so the assertion that drives the integrated behavior fails. After Step 3 the copied script includes the wiring.

- [ ] **Step 3a: Add the `-Cleanup`/`-c` switch to the param block**

In `scripts/new-worktree.ps1`, replace the param block (lines 10-15):

```powershell
[CmdletBinding()]
param(
    [string] $Name,
    [string] $BranchName,
    [string] $Path
)
```

with:

```powershell
[CmdletBinding()]
param(
    [string] $Name,
    [string] $BranchName,
    [string] $Path,

    [Alias('c')]
    [switch] $Cleanup
)
```

- [ ] **Step 3b: Compute `$isHook`**

In `scripts/new-worktree.ps1`, replace these lines (202-203):

```powershell
# A direct call supplies -Name and never needs hook stdin; only read it for hook invocations.
$hookInput = if ($Name) { $null } else { Get-HookInput }
```

with:

```powershell
# A direct call supplies -Name and never needs hook stdin; only read it for hook invocations.
$hookInput = if ($Name) { $null } else { Get-HookInput }

# Hook-driven iff -Name absent AND hook JSON was read. Do NOT derive hook-ness from
# [Console]::IsInputRedirected: that is also true for a redirected direct/agent call.
$isHook = (-not $Name) -and ($null -ne $hookInput)
```

- [ ] **Step 3c: Invoke cleanup only after the target path is resolved**

`$isHook` alone is not enough — cleanup must not run until `$worktreePath` exists, so it can exclude that exact path (see this task's "Race safety" note above: without the exclusion, a same-named create/reuse could race the detached-watcher removal `remove-worktree-local-dev.ps1` kicks off for that same folder).

In `scripts/new-worktree.ps1`, replace these lines (222-226):

```powershell
$worktreePath = [System.IO.Path]::GetFullPath($Path)
Assert-WorktreeLocation -RepoRoot $repoRoot -WorktreePath $worktreePath
$worktreeExists = Test-Path -LiteralPath (Join-Path $worktreePath '.git')

Invoke-OrphanDockerPrune $repoRoot
```

with:

```powershell
$worktreePath = [System.IO.Path]::GetFullPath($Path)
Assert-WorktreeLocation -RepoRoot $repoRoot -WorktreePath $worktreePath
$worktreeExists = Test-Path -LiteralPath (Join-Path $worktreePath '.git')

# Sweep other worktrees whose branch is already merged into main before creating/reusing
# this one. -ExcludePath protects $worktreePath itself now that it is known: without it,
# a same-named create/reuse could race the async removal (see this task's race-safety
# note). Best-effort: never block creation, and pipe to Out-Null so cleanup output can
# never reach the hook's stdout (which must stay the single worktree path).
try {
    & (Join-Path $PSScriptRoot 'cleanup-merged-worktrees.ps1') -RepoRoot $repoRoot -Cleanup:$Cleanup -IsHook:$isHook -ExcludePath $worktreePath | Out-Null
} catch {
    Write-Stderr "Merged-worktree cleanup skipped: $($_.Exception.Message)"
}

Invoke-OrphanDockerPrune $repoRoot
```

- [ ] **Step 4: Run the end-to-end test to verify it passes**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: PASS — prints `Worktree merged-cleanup tests passed.` (all four behavior tests green).

- [ ] **Step 5: Regression-check the host-resolver suite**

Run: `pwsh -NoProfile -File tests/WorktreePowerShellHost.Tests.ps1`
Expected: PASS — prints `Worktree PowerShell host tests passed.` (the `.claude\settings.json` hook assertion still holds; the switch addition does not change the hook command).

- [ ] **Step 6: Commit**

```bash
git add scripts/new-worktree.ps1 tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "feat: run merged-cleanup on worktree create (-Cleanup/-c)"
```

---

### Task 4: Documentation

**Files:**
- Modify: `scripts/README.md:55` (contract table)
- Modify: `.agents/worktrees/SKILL.md` (source of truth; edit once)
- Run: `scripts/agents/setup-copilot-symlinks.ps1` (re-syncs the hard-linked/symlinked copies)

**Interfaces:** none (docs only).

- [ ] **Step 1: Add the script to the README contract table**

In `scripts/README.md`, in the "Worktree internals — contract" table, insert a row immediately after the `remove-worktree-local-dev.ps1` row (line 55):

```markdown
| `cleanup-merged-worktrees.ps1` | Detects worktrees merged into `main` and removes the clean ones on opt-in (`-Cleanup`, or the interactive prompt); invoked by `new-worktree.ps1` before it creates a worktree. |
```

- [ ] **Step 2: Document the flag and prompt in the worktrees skill — edit the source once**

`plugins/ahkflowapp/skills/worktrees/SKILL.md` is a **hard link** to `.agents/worktrees/SKILL.md` (same inode on this checkout — confirmed via `(Get-Item .agents/worktrees/SKILL.md).LinkType` / `(Get-Item plugins/ahkflowapp/skills/worktrees/SKILL.md).LinkType`, both `HardLink`), and `.claude/skills/worktrees` / `.github/skills/worktrees` are directory symlinks to `.agents/worktrees`. Editing `.agents/worktrees/SKILL.md` is therefore the only edit needed. Do **not** also hand-edit the plugin copy: if the hard link happens to survive the edit tool's write, a second identical edit would insert the subsection twice; if the edit tool instead replaces the inode (write-new-file-then-rename), the plugin copy goes silently stale until re-synced anyway. Either way, Step 3's re-sync — not a second hand edit — is what keeps them correct.

In `.agents/worktrees/SKILL.md`, add this subsection under "## Creating", immediately before the "## Removing" heading:

```markdown
### Cleanup of merged worktrees on create

Creating a worktree first checks the other worktrees whose branch is already merged
into `main`. Nothing is removed without an explicit opt-in:

- **Interactive create (a real console, no flag):** it lists the merged, clean
  worktrees and asks once — `Clean up merged worktrees? (y/n)`. `y` removes them all;
  `n` skips.
- **`-Cleanup` / `-c`:** removes every merged, clean worktree with no prompt (use in
  scripts, or when you have already decided):

  ```bash
  pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name> -Cleanup
  ```

- **WorktreeCreate hook, or non-interactive without the flag:** detection is logged to
  stderr only; nothing is removed.

A worktree with uncommitted changes is never removed, even if its branch is merged.
The worktree currently being created or reused is always excluded from the sweep, so a
same-named recreate can never race its own removal. Removal reuses
`remove-worktree-local-dev.ps1` (`git branch -d`, DB drop, Docker teardown, lock-safe
folder delete).
```

- [ ] **Step 3: Re-sync the hard-linked/symlinked copies**

Run: `pwsh -NoProfile -File scripts/agents/setup-copilot-symlinks.ps1`
Expected: exits 0; output ends with `[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills hard-link to the same SKILL.md files`. This recreates `plugins/ahkflowapp/skills/worktrees/SKILL.md` as a fresh hard link to the just-edited `.agents/worktrees/SKILL.md`, regardless of whether the edit tool preserved the original hard link.

- [ ] **Step 4: Verify the two skill files are byte-identical**

Run: `pwsh -NoProfile -Command "if ((Get-FileHash .agents/worktrees/SKILL.md).Hash -ne (Get-FileHash plugins/ahkflowapp/skills/worktrees/SKILL.md).Hash) { throw 'SKILL.md copies differ' } else { 'SKILL.md copies match' }"`
Expected: `SKILL.md copies match`

- [ ] **Step 5: Commit**

```bash
git add scripts/README.md .agents/worktrees/SKILL.md plugins/ahkflowapp/skills/worktrees/SKILL.md
git commit -m "docs: document merged-worktree cleanup on create"
```

---

## Self-Review

**Spec coverage:**
- CLI surface (`-Cleanup`/`-c`) → Task 3 Step 3a.
- Context detection (`$isHook` from `-Name` absent + hook JSON; not `IsInputRedirected`) → Task 3 Step 3b.
- Decision matrix (hook report-only; interactive question; `-Cleanup` no-prompt; non-interactive skip) → Task 2 Step 3 (`Invoke-MergedWorktreeCleanup`).
- Detection eligibility (merged via `--format --merged main`; clean via `status --porcelain`; exclude main checkout + detached) → Task 1 Step 3.
- Removal via `remove-worktree-local-dev.ps1` → Task 2 Step 3 (`Invoke-WorktreeRemoval`).
- Architecture (standalone script, shared helpers reused) → Task 1/2.
- Error handling (non-fatal detection/removal; hook output to stderr) → Task 1 (skip-and-continue), Task 2 (try/catch), Task 3 (`try` + `| Out-Null`).
- Testing: host-resolution → Task 2 Step 5; eligibility matrix + `-ExcludePath` → Task 1; `--format` regression → Task 1; hook report-only → Task 2 Step 1; stdout-clean e2e (with stderr proof cleanup ran) → Task 3 Step 1.
- Test limitation: the authorized removal path (`-Cleanup` or interactive `y`) is intentionally not driven end-to-end because `remove-worktree-local-dev.ps1` spawns a detached watcher and performs real branch/DB/Docker cleanup; the plan covers the decision matrix and shell-out shape but not watcher completion.
- Documentation: README contract table → Task 4 Step 1; SKILL.md flag + question → Task 4 Step 2 (single source edit), Step 3 (re-sync), Step 4 (hash-check).

**Placeholder scan:** No TBD/TODO; every code step shows complete content; no "similar to Task N" cross-refs left unfilled.

**Type consistency:** `Get-EligibleMergedWorktrees` returns `{ Path; Branch }` and every consumer (`Invoke-MergedWorktreeCleanup`, all tests) reads `.Path`/`.Branch`. `Invoke-WorktreeRemoval` and `Invoke-MergedWorktreeCleanup` signatures match the `& cleanup.ps1 -RepoRoot ... -Cleanup:$Cleanup -IsHook:$isHook -ExcludePath $worktreePath` call in `new-worktree.ps1`; `-ExcludePath` threads consistently through the script's top-level `param()`, `Get-EligibleMergedWorktrees`, `Invoke-MergedWorktreeCleanup`, and the standalone entrypoint. Prompt text is `Clean up merged worktrees? (y/n)` in both the script and the assertion narrative.

## Unresolved questions

None. (Spec Open Questions were empty.)

Implementation notes surfaced during planning, already handled above:
- **Race safety:** `Get-EligibleMergedWorktrees` and `Invoke-MergedWorktreeCleanup` take `-ExcludePath`; `new-worktree.ps1` resolves `$worktreePath` before invoking cleanup and passes it as `-ExcludePath` (Task 3, Steps 3b/3c), so a same-named create/reuse can never race the async removal `remove-worktree-local-dev.ps1`'s detached-watcher hook mode kicks off for that same path.
- **Interactive UX:** direct real-console creates intentionally stop once to ask `Clean up merged worktrees? (y/n)` when eligible merged, clean worktrees exist. Hook and redirected/non-interactive paths do not prompt.
- `plugins/ahkflowapp/skills/worktrees/SKILL.md` is a **hard link** to `.agents/worktrees/SKILL.md` (confirmed same inode), not an independent copy — Task 4 edits the source once and re-syncs via `scripts/agents/setup-copilot-symlinks.ps1` rather than hand-editing both, then verifies byte-equality.
- `Invoke-WorktreeRemoval` pipes empty stdin into `remove-worktree-local-dev.ps1` to avoid its unbounded `[Console]::In.ReadToEnd()` hanging when the cleanup run's own stdin is redirected.
- `new-worktree.ps1`'s cleanup call is `| Out-Null`-guarded so cleanup output can never leak into the hook's stdout.
