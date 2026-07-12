# Worktree Cleanup Opt-In Implementation Plan

> **Status: Implemented** on `fix/worktree-cleanup-default-on`. All tasks below are complete; the unchecked boxes are the original execution record, not outstanding work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Return merged-worktree cleanup to opt-in, driven by a persistent per-repo git config (`ahkflow.worktreeCleanup`) with an ask-once console/conversation prompt that remembers the answer.

**Architecture:** All precedence (per-run flag → hook-only env var → git config → ask-once/report-only) collapses into one pure resolver in `cleanup-merged-worktrees.ps1`. `new-worktree.ps1` stops pre-collapsing hook context and passes raw `-IsHook`. IO seams (config read/write, env read) are separate testable functions. The `.agents/worktrees/SKILL.md` canonical doc is restored as the hard-link source for the plugin copy and guarded by a byte-parity test.

**Tech Stack:** PowerShell 5.1+/7 (`pwsh`), git config `--local`, self-running assertion test harness in `tests/*.Tests.ps1` (no Pester), GitHub Actions CI (`worktree-powershell-tests` job).

## Global Constraints

- **`--local` scope on every config read, write, and unset** — `git -C $RepoRoot config --local ...`. A global/system value must never enable cleanup for this repo.
- **`--bool` normalizes** `true/false/1/0/yes/no`; the reader relies on it.
- **Fail closed:** invalid, duplicated, or unreadable config → report-only, never clean, never ask; warn on stderr with repair command `git config --local --unset-all ahkflow.worktreeCleanup`.
- **Env var `AHKFLOW_WORKTREE_CLEANUP` is hook-only** — `1|true|yes|y` enable, `0|false|no|n` disable, other values ignored. It must never change direct-call behavior.
- **`-Cleanup` flag wins in all contexts.**
- **Hook stdout contract:** hook path (`new-worktree.ps1` with no `-Name`) must emit exactly the worktree path on stdout; all cleanup output stays on stderr.
- **Config hint fires only while config is unset** (in hook context, report-only).
- **"Cleans" means *removed*** — removal is async (detached watcher in `remove-worktree-local-dev.ps1`); tests must poll `git worktree list` + folder existence with a bounded timeout, not assert on the request line.
- **Never touch removal mechanics, eligibility rules, or the removal log** (`remove-worktree-local-dev.ps1`, `Get-EligibleMergedWorktrees`, `worktree-removal.log`).
- Observed git exit codes (verified): unset → exit 1 / no output; valid → exit 0 / one line; duplicated → exit 0 / multiple lines; bad boolean → exit 128.

## Confirmed empirical facts (do not re-derive)

```
git config --local --bool --get-all ahkflow.worktreeCleanup   # unset:      exit 1, no output
# after: git config --local ahkflow.worktreeCleanup true
git config --local --bool --get-all ahkflow.worktreeCleanup   # true:       exit 0, "true"
# after: git config --local --add ahkflow.worktreeCleanup false
git config --local --bool --get-all ahkflow.worktreeCleanup   # duplicated: exit 0, "true\nfalse"
# after: value "banana"
git config --local --bool --get-all ahkflow.worktreeCleanup   # garbage:    exit 128, "bad boolean config value"
```

---

### Task 1: Dedupe `Write-Stderr` into the shared common file

Behavior-preserving refactor. `Write-Stderr` is defined identically in both `new-worktree.ps1` and `cleanup-merged-worktrees.ps1`; both already dot-source `worktree-powershell.common.ps1`. Move the single definition there.

**Files:**
- Modify: `scripts/worktree-powershell.common.ps1` (add `Write-Stderr`)
- Modify: `scripts/new-worktree.ps1:26-29` (remove local `Write-Stderr`)
- Modify: `scripts/cleanup-merged-worktrees.ps1:30-33` (remove local `Write-Stderr`)
- Test: `tests/WorktreeMergedCleanup.Tests.ps1` (existing suite exercises the path)

**Interfaces:**
- Produces: `Write-Stderr -Message <string>` — writes one line to stderr. Available to every script that dot-sources `worktree-powershell.common.ps1`.

- [ ] **Step 1: Run the existing suite to establish a green baseline**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: prints `Worktree merged-cleanup tests passed.` (baseline; these assertions change in Task 4).

- [ ] **Step 2: Add `Write-Stderr` to the common file**

Append to `scripts/worktree-powershell.common.ps1` (after `Resolve-PowerShellExecutable`):

```powershell
function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}
```

- [ ] **Step 3: Remove the duplicate from `new-worktree.ps1`**

Delete these lines (currently `scripts/new-worktree.ps1:26-29`):

```powershell
function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}
```

The dot-source of `worktree-powershell.common.ps1` at line 24 already runs before any `Write-Stderr` call, so the shared definition is in scope.

- [ ] **Step 4: Remove the duplicate from `cleanup-merged-worktrees.ps1`**

Delete these lines (currently `scripts/cleanup-merged-worktrees.ps1:30-33`):

```powershell
function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}
```

The dot-source at line 28 already runs first.

- [ ] **Step 5: Run all four worktree suites to confirm no regression**

Run:
```
pwsh -NoProfile -File tests/WorktreePowerShellHost.Tests.ps1
pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1
pwsh -NoProfile -File tests/WorktreeRemoveHook.Tests.ps1
pwsh -NoProfile -File tests/WorktreeLocalDevSetup.Tests.ps1
```
Expected: each prints its `...passed.` line; no exceptions.

- [ ] **Step 6: Commit**

```bash
git add scripts/worktree-powershell.common.ps1 scripts/new-worktree.ps1 scripts/cleanup-merged-worktrees.ps1
git commit -m "refactor: dedupe Write-Stderr into worktree common"
```

---

### Task 2: Config read/write helpers

Add the two IO seams that read and persist `ahkflow.worktreeCleanup`, fail-closed per the confirmed exit codes. Not wired into the decision path yet.

**Files:**
- Modify: `scripts/cleanup-merged-worktrees.ps1` (add `Get-WorktreeCleanupConfig`, `Set-WorktreeCleanupConfig`)
- Test: `tests/WorktreeMergedCleanup.Tests.ps1` (dot-sources the cleanup script, so the functions are importable)

**Interfaces:**
- Produces: `Get-WorktreeCleanupConfig -RepoRoot <string>` → returns one of `'true'`, `'false'`, `'unset'`, `'invalid'`.
- Produces: `Set-WorktreeCleanupConfig -RepoRoot <string> -Enabled <bool>` → writes `true`/`false` at `--local` scope; returns `$true` on success, `$false` if the write failed.

- [ ] **Step 1: Write the failing unit tests**

Insert into `tests/WorktreeMergedCleanup.Tests.ps1` immediately after the `. (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')` import line (currently line 98), before the eligibility-matrix test:

```powershell
# --- Test: Get-WorktreeCleanupConfig fail-closed state machine ------------------
$repo = New-TempGitRepo
try {
    Assert-Equal 'unset' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No config value must read as unset.'

    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A true value must read as true.'

    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'no') | Out-Null
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) '--bool must normalize no to false.'

    # Duplicated key: exit 0 with two lines -> invalid (fail closed).
    Invoke-TestGit $repo @('config', '--local', '--add', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    Assert-Equal 'invalid' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A duplicated value must read as invalid.'

    # Garbage value: git exits 128 (bad boolean) -> invalid.
    Invoke-TestGit $repo @('config', '--local', '--unset-all', 'ahkflow.worktreeCleanup') | Out-Null
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null
    Assert-Equal 'invalid' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'A non-boolean value must read as invalid.'
} finally {
    Remove-TempTree $repo
}

# --- Test: Set-WorktreeCleanupConfig persists and reports success/failure -------
$repo = New-TempGitRepo
try {
    Assert-True (Set-WorktreeCleanupConfig -RepoRoot $repo -Enabled $true) 'Setting true must report success.'
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Set true must be readable as true.'

    Assert-True (Set-WorktreeCleanupConfig -RepoRoot $repo -Enabled $false) 'Setting false must report success.'
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Set false must be readable as false.'

    # Write-failure path: a non-repo directory makes `git config --local` fail.
    $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ('notrepo-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $notARepo -Force | Out-Null
    try {
        Assert-True (-not (Set-WorktreeCleanupConfig -RepoRoot $notARepo -Enabled $true)) 'A failed write must return $false.'
    } finally {
        Remove-Item -LiteralPath $notARepo -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-TempTree $repo
}
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — throws `The term 'Get-WorktreeCleanupConfig' is not recognized` (function not defined yet).

- [ ] **Step 3: Implement the helpers**

Insert into `scripts/cleanup-merged-worktrees.ps1` after `Get-EligibleMergedWorktrees` (before `Invoke-WorktreeRemoval`, currently line 133):

```powershell
# Reads the per-repo cleanup preference at --local scope only, so a global/system value
# can never enable cleanup here. --bool normalizes true/false/1/0/yes/no. Fail closed:
# a duplicated (multi-line) or non-boolean (git exit 128) value reads as 'invalid'.
# Confirmed git behavior: unset -> exit 1/no output; valid -> exit 0/one line;
# duplicated -> exit 0/multiple lines; bad boolean -> exit 128.
function Get-WorktreeCleanupConfig {
    param([Parameter(Mandatory)][string] $RepoRoot)

    $values = & git -C $RepoRoot config --local --bool --get-all ahkflow.worktreeCleanup 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 1) { return 'unset' }
    if ($exit -ne 0) { return 'invalid' }

    $lines = @($values | Where-Object { $null -ne $_ -and ([string] $_).Trim() -ne '' })
    if ($lines.Count -ne 1) { return 'invalid' }

    switch (([string] $lines[0]).Trim()) {
        'true'  { return 'true' }
        'false' { return 'false' }
        default { return 'invalid' }
    }
}

# Persists the preference at --local scope. Returns $true if git accepted the write,
# $false otherwise (e.g. $RepoRoot is not a git repo). Callers honor the current answer
# for the run even when the write fails; they just warn it was not remembered.
function Set-WorktreeCleanupConfig {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][bool] $Enabled
    )

    $value = if ($Enabled) { 'true' } else { 'false' }
    & git -C $RepoRoot config --local ahkflow.worktreeCleanup $value 2>$null
    return ($LASTEXITCODE -eq 0)
}
```

- [ ] **Step 4: Run to verify pass**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: PASS — `Worktree merged-cleanup tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/cleanup-merged-worktrees.ps1 tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "feat: add fail-closed worktreeCleanup config read/write helpers"
```

---

### Task 3: Env-override reader, pure decision resolver, answer mapper

Add the pure precedence resolver and the two small pure/IO helpers around it. Still not wired into `Invoke-MergedWorktreeCleanup` (that is Task 4), so behavior is unchanged and the suite stays green.

**Files:**
- Modify: `scripts/cleanup-merged-worktrees.ps1` (add `Get-EnvCleanupOverride`, `ConvertFrom-CleanupAnswer`, `Resolve-CleanupDecision`, `Set-CleanupAnswer`)
- Test: `tests/WorktreeMergedCleanup.Tests.ps1`

**Interfaces:**
- Produces: `Get-EnvCleanupOverride` → reads `AHKFLOW_WORKTREE_CLEANUP` from the process env; returns `'enable'`, `'disable'`, or `'none'`.
- Produces: `ConvertFrom-CleanupAnswer -Answer <string>` → `[pscustomobject]@{ Clean=<bool>; Enabled=<bool> }`. `y`/`yes` (case-insensitive, whitespace-trimmed) → both `$true`; anything else (including empty) → both `$false`.
- Produces: `Resolve-CleanupDecision -Cleanup <switch> -IsHook <switch> -ConfigState <'true'|'false'|'unset'|'invalid'> -EnvOverride <'enable'|'disable'|'none'> -Interactive <bool>` → `[pscustomobject]@{ Action=<'Clean'|'ReportOnly'|'Skip'|'Prompt'>; ShowHint=<bool> }`.
- Produces: `Set-CleanupAnswer -RepoRoot <string> -Answer <string>` → maps the answer, persists the preference via `Set-WorktreeCleanupConfig`, warns on stderr when the write failed, and returns `[pscustomobject]@{ Clean=<bool>; Persisted=<bool> }`. Extracts the `Prompt`-branch persistence path so it is unit-testable without a live `Read-Host`/TTY.

- [ ] **Step 1: Write the failing unit tests**

Insert into `tests/WorktreeMergedCleanup.Tests.ps1` after the config-helper tests from Task 2:

```powershell
# --- Test: ConvertFrom-CleanupAnswer maps the ask-once answer --------------------
foreach ($yes in @('y', 'Y', 'yes', 'YES', '  y  ')) {
    $m = ConvertFrom-CleanupAnswer $yes
    Assert-True ($m.Clean -and $m.Enabled) "Answer '$yes' must map to clean+enable."
}
foreach ($no in @('', 'n', 'no', 'nope', 'x')) {
    $m = ConvertFrom-CleanupAnswer $no
    Assert-True ((-not $m.Clean) -and (-not $m.Enabled)) "Answer '$no' must map to skip+disable."
}

# --- Test: Resolve-CleanupDecision precedence matrix -----------------------------
# Each row: Cleanup, IsHook, ConfigState, EnvOverride, Interactive => Action, ShowHint
$cases = @(
    # -Cleanup wins everywhere.
    @{ C=$true;  H=$false; Cfg='false';  Env='none';    I=$false; A='Clean';      Hint=$false }
    @{ C=$true;  H=$true;  Cfg='false';  Env='disable'; I=$false; A='Clean';      Hint=$false }
    # Hook + env override (hook-only), overrides config.
    @{ C=$false; H=$true;  Cfg='false';  Env='enable';  I=$false; A='Clean';      Hint=$false }
    @{ C=$false; H=$true;  Cfg='true';   Env='disable'; I=$false; A='ReportOnly'; Hint=$false }
    # Hook + config (no env).
    @{ C=$false; H=$true;  Cfg='true';   Env='none';    I=$false; A='Clean';      Hint=$false }
    @{ C=$false; H=$true;  Cfg='false';  Env='none';    I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$true;  Cfg='invalid';Env='none';    I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$true;  Cfg='unset';  Env='none';    I=$false; A='ReportOnly'; Hint=$true  }
    # Hook + env disable + config unset: hint still fires (env is transient, config is the nudge).
    @{ C=$false; H=$true;  Cfg='unset';  Env='disable'; I=$false; A='ReportOnly'; Hint=$true  }
    # Direct calls ignore env entirely (EnvOverride is only read when hook; resolver still must
    # not act on it when IsHook is false, so pass 'enable' here to prove it is inert).
    @{ C=$false; H=$false; Cfg='unset';  Env='enable';  I=$false; A='ReportOnly'; Hint=$false }
    @{ C=$false; H=$false; Cfg='unset';  Env='enable';  I=$true;  A='Prompt';     Hint=$false }
    # Direct + config.
    @{ C=$false; H=$false; Cfg='true';   Env='none';    I=$true;  A='Clean';      Hint=$false }
    @{ C=$false; H=$false; Cfg='false';  Env='none';    I=$true;  A='Skip';       Hint=$false }
    @{ C=$false; H=$false; Cfg='invalid';Env='none';    I=$true;  A='ReportOnly'; Hint=$false }
    # Direct + unset, non-interactive -> report-only (no console to prompt).
    @{ C=$false; H=$false; Cfg='unset';  Env='none';    I=$false; A='ReportOnly'; Hint=$false }
)
foreach ($c in $cases) {
    $d = Resolve-CleanupDecision -Cleanup:$c.C -IsHook:$c.H -ConfigState $c.Cfg -EnvOverride $c.Env -Interactive $c.I
    $label = "C=$($c.C) H=$($c.H) Cfg=$($c.Cfg) Env=$($c.Env) I=$($c.I)"
    Assert-Equal $c.A $d.Action "Action mismatch for [$label]."
    Assert-Equal $c.Hint $d.ShowHint "ShowHint mismatch for [$label]."
}

# --- Test: Get-EnvCleanupOverride classifies the env var ------------------------
$oldEnv = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
try {
    foreach ($v in @('1', 'true', 'YES', ' y ')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'enable' (Get-EnvCleanupOverride) "Env '$v' must classify as enable."
    }
    foreach ($v in @('0', 'false', 'NO', ' n ')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'disable' (Get-EnvCleanupOverride) "Env '$v' must classify as disable."
    }
    foreach ($v in @('', 'maybe', '2')) {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $v, 'Process')
        Assert-Equal 'none' (Get-EnvCleanupOverride) "Env '$v' must classify as none."
    }
} finally {
    [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $oldEnv, 'Process')
}

# --- Test: Set-CleanupAnswer persists the answer and warns on write failure -----
# Covers the exact seam the Prompt branch calls, so removing the persistence call or the
# warning is caught here (the child-process integration tests can't reach the Prompt branch
# because they redirect stdin).
$repo = New-TempGitRepo
try {
    $yes = Set-CleanupAnswer -RepoRoot $repo -Answer 'y'
    Assert-True ($yes.Clean -and $yes.Persisted) 'Yes must clean and report persisted.'
    Assert-Equal 'true' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'Yes must persist true.'

    $no = Set-CleanupAnswer -RepoRoot $repo -Answer 'n'
    Assert-True ((-not $no.Clean) -and $no.Persisted) 'No must skip but still report persisted.'
    Assert-Equal 'false' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No must persist false.'

    # Failed write (non-repo dir): must honor the answer for the run, report not-persisted,
    # and warn on stderr. Capture stderr in-process to assert the warning is emitted.
    $notARepo = Join-Path ([System.IO.Path]::GetTempPath()) ('notrepo-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $notARepo -Force | Out-Null
    $sw = New-Object System.IO.StringWriter
    $origErr = [Console]::Error
    [Console]::SetError($sw)
    try {
        $failed = Set-CleanupAnswer -RepoRoot $notARepo -Answer 'y'
    } finally {
        [Console]::SetError($origErr)
        Remove-Item -LiteralPath $notARepo -Recurse -Force -ErrorAction SilentlyContinue
    }
    Assert-True ($failed.Clean -and (-not $failed.Persisted)) 'Failed write must honor the answer but report not persisted.'
    Assert-True ($sw.ToString() -match 'could not persist') 'Failed write must warn on stderr.'
} finally {
    Remove-TempTree $repo
}
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — `The term 'ConvertFrom-CleanupAnswer' is not recognized`.

- [ ] **Step 3: Implement the four functions**

Insert into `scripts/cleanup-merged-worktrees.ps1` after `Set-WorktreeCleanupConfig` (from Task 2):

```powershell
# Reads the hook-only env override. 'enable'/'disable'/'none'. Callers must only consult
# this in hook context; a leftover value in a shell must never affect a direct call.
function Get-EnvCleanupOverride {
    $value = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) { return 'none' }

    $v = $value.Trim()
    if ($v -match '^(1|true|yes|y)$') { return 'enable' }
    if ($v -match '^(0|false|no|n)$') { return 'disable' }
    return 'none'
}

# Maps the ask-once console answer to an action. 'y'/'yes' -> clean now and enable;
# anything else (including the empty default) -> skip and disable. Pure; testable
# without Read-Host.
function ConvertFrom-CleanupAnswer {
    param([string] $Answer)

    $yes = ($Answer -match '^\s*(y|yes)\s*$')
    return [pscustomobject]@{ Clean = $yes; Enabled = $yes }
}

# The single source of precedence. Pure: no git, env, or console access -- callers gather
# those and pass them in. Precedence: -Cleanup > hook-only env > config > ask-once/report.
# ShowHint is true only in hook context while config is unset (the hint nudges toward
# setting the config; env is a transient per-run override, so it does not suppress it).
function Resolve-CleanupDecision {
    param(
        [switch] $Cleanup,
        [switch] $IsHook,
        [Parameter(Mandatory)][ValidateSet('true', 'false', 'unset', 'invalid')][string] $ConfigState,
        [ValidateSet('enable', 'disable', 'none')][string] $EnvOverride = 'none',
        [bool] $Interactive
    )

    if ($Cleanup) { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }

    if ($IsHook -and $EnvOverride -eq 'enable') { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }
    $envDisable = ($IsHook -and $EnvOverride -eq 'disable')

    if (-not $envDisable -and $ConfigState -eq 'true') { return [pscustomobject]@{ Action = 'Clean'; ShowHint = $false } }
    if ($ConfigState -eq 'false') {
        $action = if ($IsHook) { 'ReportOnly' } else { 'Skip' }
        return [pscustomobject]@{ Action = $action; ShowHint = $false }
    }
    if ($ConfigState -eq 'invalid') { return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = $false } }

    # config unset (or env-disabled over a would-be-true/unset config)
    if ($IsHook) { return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = ($ConfigState -eq 'unset') } }
    if ($Interactive) { return [pscustomobject]@{ Action = 'Prompt'; ShowHint = $false } }
    return [pscustomobject]@{ Action = 'ReportOnly'; ShowHint = $false }
}

# Applies the ask-once answer: persists the preference and reports whether removal should
# proceed. Warns on stderr when the write failed but still honors the answer for this run.
# Extracted from the Prompt branch so the persist+warn path is unit-testable without a live
# Read-Host/TTY. Returns [pscustomobject]@{ Clean=<bool>; Persisted=<bool> }.
function Set-CleanupAnswer {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $Answer
    )

    $mapped = ConvertFrom-CleanupAnswer $Answer
    $persisted = Set-WorktreeCleanupConfig -RepoRoot $RepoRoot -Enabled $mapped.Enabled
    if (-not $persisted) {
        Write-Stderr 'cleanup: could not persist your choice to git config; honoring it for this run only.'
    }
    return [pscustomobject]@{ Clean = $mapped.Clean; Persisted = $persisted }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: PASS — `Worktree merged-cleanup tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/cleanup-merged-worktrees.ps1 tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "feat: add env override, answer mapper, pure cleanup decision resolver"
```

---

### Task 4: Wire the resolver in, flip the default to opt-in, make `-IsHook` honest

The atomic behavior change. `Invoke-MergedWorktreeCleanup` now drives the resolver, asks once (interactive direct + unset) and persists, warns on invalid config, and prints the config hint. `new-worktree.ps1` stops collapsing hook context into a report-only flag and passes raw `-IsHook`; its env handling is deleted (the resolver owns it). Integration tests and the two affected script synopses + the `scripts/README.md` line update in the same commit.

**Files:**
- Modify: `scripts/cleanup-merged-worktrees.ps1` (rewrite `Invoke-MergedWorktreeCleanup`; update `.SYNOPSIS`/`.DESCRIPTION`)
- Modify: `scripts/new-worktree.ps1` (remove `Test-EnvironmentFlagDisabled` and the `$cleanupRequested`/`$cleanupIsReportOnly` collapse; pass raw `-IsHook:$isHook`)
- Modify: `scripts/README.md:56` (worktree-contract table row for `cleanup-merged-worktrees.ps1`)
- Test: `tests/WorktreeMergedCleanup.Tests.ps1` (flip default-on assertions; add matrix cases)

**Interfaces:**
- Consumes: `Get-EligibleMergedWorktrees`, `Get-WorktreeCleanupConfig`, `Get-EnvCleanupOverride`, `Resolve-CleanupDecision`, `Set-CleanupAnswer`, `Invoke-WorktreeRemoval`, `Write-WorktreeLog`, `Write-Stderr` (all defined earlier / in commons). The `Prompt` branch persists via `Set-CleanupAnswer` (which wraps `ConvertFrom-CleanupAnswer` + `Set-WorktreeCleanupConfig`).
- Produces: `Invoke-MergedWorktreeCleanup -RepoRoot <string> [-Cleanup] [-IsHook] [-MainRef <string>] [-ExcludePath <string>]` — same signature; `-IsHook` now means literal hook context (not "report-only").

- [ ] **Step 1: Update the hook-default integration test to expect report-only**

In `tests/WorktreeMergedCleanup.Tests.ps1`, find the block headed `# --- Test: hook path keeps stdout to exactly the new worktree path ---` (currently starting at line 262). Replace its three post-exit cleanup assertions (currently lines 291-295, the `# Proves cleanup runs by default...` comment and the three `Assert-*` on `removing`/`report-only`) with:

```powershell
    # Default hook context (no env, no config) is now opt-in: report-only with the config hint,
    # nothing removed. Stdout stays exactly the new worktree path (asserted above).
    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected detection output on stderr. Stderr: $stderrText"
    Assert-True (-not ($stderrText -match 'cleanup: removing merged worktree')) "Default hook cleanup must not remove anything (opt-in). Stderr: $stderrText"
    Assert-True ($stderrText -match 'git config --local ahkflow\.worktreeCleanup true') "Default hook report-only must print the config hint. Stderr: $stderrText"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo '.claude\worktrees')) 'Worktree tooling dir should still exist.'
```

- [ ] **Step 2: Update the env-opt-out integration test comment and keep its report-only assertions**

In the block headed `# --- Test: CLI env opt-out (0) keeps WorktreeCreate hook report-only ---` (currently line 300), the assertions already expect report-only and no removal, which remain correct (hook + env disable + config unset → report-only). Update only the leading comment to reflect the new model:

```powershell
# --- Test: CLI env opt-out (0) keeps WorktreeCreate hook report-only -----------
# With opt-in as the default, env '0' is a redundant-but-honored disable in hook context.
```

No assertion changes in this block.

- [ ] **Step 3: Add a polling helper and the new matrix integration tests**

Add this helper in `tests/WorktreeMergedCleanup.Tests.ps1` near the other helpers, after `Remove-TempTree` (currently ends line 95):

```powershell
# Removal is delegated to a detached watcher (remove-worktree-local-dev.ps1), so "cleaned"
# is only observable after the fact. Per the spec, "cleans means removed": success requires
# the worktree to actually be GONE -- dropped from `git worktree list` (deregistered) AND its
# folder deleted. A watcher log line is NOT proof of success: the watcher writes
# "Watcher done (worktree preserved)." when it KEPT the worktree (e.g. a locked folder), which
# must fail this poll, not pass it. The log is therefore consulted only to fail fast when the
# watcher explicitly preserved this worktree -- there is no point waiting out the timeout for a
# removal that will never happen. (Confirmed by reading remove-worktree-local-dev.ps1: Hook
# mode with -WorktreePath resolves the main checkout from the worktree's git-common-dir, passes
# the merged+clean gate for these test worktrees, skips DB/Docker when no .env.worktree
# manifest exists, prunes git and deletes the folder on success, and creates the log dir if
# missing. Each log line is "<stamp>  <leaf>  <message>", so the leaf tags the "preserved" line.)
function Wait-ForWorktreeCleaned {
    param([string] $RepoDir, [string] $WorktreePath, [int] $TimeoutMs = 30000)

    $key = ConvertTo-Key $WorktreePath
    $leaf = Split-Path -Leaf $WorktreePath
    $logPath = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $listed = @(& git -C $RepoDir worktree list --porcelain 2>$null) |
            Where-Object { $_ -like 'worktree *' } |
            ForEach-Object { ConvertTo-Key ($_.Substring('worktree '.Length)) }
        # Actually gone: deregistered AND folder deleted. This is the ONLY success signal.
        if (($listed -notcontains $key) -and -not (Test-Path -LiteralPath $WorktreePath)) { return $true }

        # Fail fast: the watcher explicitly preserved this worktree, so it will never be
        # removed. A "preserved" outcome must NOT count as cleaned.
        if (Test-Path -LiteralPath $logPath) {
            foreach ($line in (Get-Content -LiteralPath $logPath)) {
                if ($line -match [regex]::Escape($leaf) -and $line -match 'Watcher done \(worktree preserved\)') { return $false }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

# Runs the REAL cleanup script as a child process against $RepoDir, with optional extra args,
# a process-scoped env override (restored after), and redirected stdin/stdout/stderr.
function Invoke-CleanupChild {
    param(
        [string] $RepoDir,
        [string[]] $ExtraArgs = @(),
        [hashtable] $EnvVars = @{},
        [string] $Stdin = ''
    )

    $parent = Split-Path -Parent $RepoDir
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stdinFile = Join-Path $parent "cin-$suffix.txt"
    $stdoutFile = Join-Path $parent "cout-$suffix.txt"
    $stderrFile = Join-Path $parent "cerr-$suffix.txt"
    Set-Content -LiteralPath $stdinFile -Value $Stdin -Encoding utf8

    $cleanupScript = Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1'
    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-RepoRoot', $RepoDir, '-MainRef', 'main') + $ExtraArgs

    $restore = @{}
    foreach ($k in $EnvVars.Keys) {
        $restore[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $EnvVars[$k], 'Process')
    }
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList `
            -WorkingDirectory $suiteRoot `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
    } finally {
        foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $restore[$k], 'Process') }
    }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stdout   = (Get-Content -Raw -LiteralPath $stdoutFile)
        Stderr   = (Get-Content -Raw -LiteralPath $stderrFile)
    }
}
```

Then add these test blocks before the final `Write-Host 'Worktree merged-cleanup tests passed.'` line. Report-only/skip cases use the lightweight `New-TempGitRepo`; cleaning cases use `New-WorktreeToolingRepo` so `remove-worktree-local-dev.ps1` is present for the async removal:

```powershell
# --- Test: config false -> hook report-only (no hint), direct skip -------------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-cfgfalse'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null

    $hook = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook')
    Assert-Equal 0 $hook.ExitCode "Hook + config false should exit 0. Stderr: $($hook.Stderr)"
    Assert-True ($hook.Stderr -match 'cleanup: eligible merged worktree') 'Config-false hook must still detect.'
    Assert-True (-not ($hook.Stderr -match 'ahkflow\.worktreeCleanup true')) 'Config-false hook must NOT print the enable hint.'
    Assert-True (-not ($hook.Stderr -match 'cleanup: removing')) 'Config-false hook must not remove.'
    Assert-True (Test-Path -LiteralPath $kept) 'Config-false must leave the worktree folder.'

    $direct = Invoke-CleanupChild -RepoDir $repo
    Assert-True (-not ($direct.Stderr -match 'cleanup: removing')) 'Config-false direct call must skip.'
    Assert-True (Test-Path -LiteralPath $kept) 'Config-false direct call must leave the worktree folder.'
} finally {
    Remove-TempTree $repo
}

# --- Test: invalid config fails closed to report-only with a warning -----------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-invalidcfg'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'banana') | Out-Null

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook')
    Assert-Equal 0 $res.ExitCode "Invalid config should not crash. Stderr: $($res.Stderr)"
    Assert-True ($res.Stderr -match 'invalid or duplicated') 'Invalid config must warn.'
    Assert-True ($res.Stderr -match 'git config --local --unset-all ahkflow\.worktreeCleanup') 'Warning must include the repair command.'
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) 'Invalid config must not remove (fail closed).'
    Assert-True (Test-Path -LiteralPath $kept) 'Invalid config must leave the worktree folder.'
} finally {
    Remove-TempTree $repo
}

# --- Test: direct call ignores the env var entirely ----------------------------
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-envdirect'
    # Env '1' set, no config, non-interactive direct (no -IsHook) -> must NOT clean.
    $res = Invoke-CleanupChild -RepoDir $repo -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '1' }
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) 'Direct call must ignore AHKFLOW_WORKTREE_CLEANUP.'
    Assert-True (Test-Path -LiteralPath $kept) 'Env var must not trigger removal on a direct call.'
} finally {
    Remove-TempTree $repo
}

# --- Test: no eligible worktrees -> no prompt, nothing persisted ---------------
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-dirty-only' -Dirty | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo
    Assert-True ($res.Stderr -match 'no merged worktrees eligible') 'With no eligible worktrees, cleanup must report none.'
    Assert-Equal 'unset' (Get-WorktreeCleanupConfig -RepoRoot $repo) 'No eligible worktrees must not persist any preference.'
} finally {
    Remove-TempTree $repo
}

# --- Test: config true cleans (hook and non-interactive direct) ----------------
foreach ($mode in @(@{ Args = @('-IsHook'); Label = 'hook' }, @{ Args = @(); Label = 'direct' })) {
    $repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
    try {
        $target = Add-TestWorktree -RepoDir $repo -BranchName "feat-cfgtrue-$($mode.Label)"
        Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null

        $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs $mode.Args
        Assert-Equal 0 $res.ExitCode "config true ($($mode.Label)) should exit 0. Stderr: $($res.Stderr)"
        Assert-True ($res.Stderr -match 'cleanup: removing merged worktree') "config true ($($mode.Label)) must request removal. Stderr: $($res.Stderr)"
        Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "config true ($($mode.Label)) worktree must actually be removed (deregistered + folder gone). Stderr: $($res.Stderr)"
    } finally {
        Remove-TempTree $repo
    }
}

# --- Test: env overrides config in hook context (hook-only) --------------------
# env '1' + config false -> cleans.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-env1-cfgfalse'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook') -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '1' }
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "env '1' must override config false in hook context. Stderr: $($res.Stderr)"
} finally {
    Remove-TempTree $repo
}

# env '0' + config true -> report-only (nothing removed).
$repo = New-TempGitRepo
try {
    $kept = Add-TestWorktree -RepoDir $repo -BranchName 'feat-env0-cfgtrue'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'true') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-IsHook') -EnvVars @{ 'AHKFLOW_WORKTREE_CLEANUP' = '0' }
    Assert-True (-not ($res.Stderr -match 'cleanup: removing')) "env '0' must override config true in hook context. Stderr: $($res.Stderr)"
    Assert-True (Test-Path -LiteralPath $kept) "env '0' must leave the worktree folder even with config true."
} finally {
    Remove-TempTree $repo
}

# --- Test: -Cleanup overrides config false (cleans, no prompt) ------------------
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-flag-over-false'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "-Cleanup must override config false. Stderr: $($res.Stderr)"
} finally {
    Remove-TempTree $repo
}
```

- [ ] **Step 4: Run to verify the new/updated tests fail against current behavior**

Run: `pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1`
Expected: FAIL — the default-hook test now expects report-only but the current code removes by default; new config/prompt cases hit unimplemented resolver wiring.

- [ ] **Step 5: Rewrite `Invoke-MergedWorktreeCleanup` to use the resolver**

Replace the whole `Invoke-MergedWorktreeCleanup` function body (currently `scripts/cleanup-merged-worktrees.ps1:162-210`) with:

```powershell
# Drives the decision matrix through Resolve-CleanupDecision. Detection/removal failures
# are logged to stderr and skipped so worktree creation is never blocked. Emits nothing on
# the success stream.
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

    $configState = Get-WorktreeCleanupConfig -RepoRoot $RepoRoot
    if ($configState -eq 'invalid') {
        Write-Stderr 'cleanup: ahkflow.worktreeCleanup has an invalid or duplicated value; treating as report-only. Repair with: git config --local --unset-all ahkflow.worktreeCleanup'
    }

    $envOverride = if ($IsHook) { Get-EnvCleanupOverride } else { 'none' }
    $interactive = -not [Console]::IsInputRedirected

    $decision = Resolve-CleanupDecision -Cleanup:$Cleanup -IsHook:$IsHook -ConfigState $configState -EnvOverride $envOverride -Interactive $interactive

    switch ($decision.Action) {
        'Prompt' {
            $answer = Read-Host "Found $($eligible.Count) merged, clean worktree(s). Remove them now and enable automatic cleanup for this repository? [y/N]"
            $applied = Set-CleanupAnswer -RepoRoot $RepoRoot -Answer $answer
            if (-not $applied.Clean) {
                Write-Stderr 'cleanup: declined; nothing removed.'
                return
            }
        }
        'Clean' { }
        'Skip' {
            Write-Stderr 'cleanup: ahkflow.worktreeCleanup=false; skipping.'
            return
        }
        default {
            # ReportOnly
            if ($decision.ShowHint) {
                Write-Stderr 'cleanup: report-only. Enable automatic cleanup for this repository with: git config --local ahkflow.worktreeCleanup true'
            } else {
                Write-Stderr 'cleanup: report-only; nothing removed.'
            }
            return
        }
    }

    # Reached only for Clean or an accepted Prompt.
    $removalLog = Join-Path $RepoRoot '.claude\worktrees\worktree-removal.log'
    foreach ($wt in $eligible) {
        Write-Stderr "cleanup: removing merged worktree: $($wt.Path) [$($wt.Branch)]"
        try {
            Write-WorktreeLog -LogPath $removalLog -Worktree (Split-Path -Leaf $wt.Path) -Message "Merged-cleanup requested removal (branch $($wt.Branch))."
        } catch { }
        Invoke-WorktreeRemoval -RepoRoot $RepoRoot -WorktreePath $wt.Path
    }
}
```

- [ ] **Step 6: Update the cleanup script `.SYNOPSIS`/`.DESCRIPTION`**

Replace the header comment block (currently `scripts/cleanup-merged-worktrees.ps1:2-12`) with:

```powershell
<#
.SYNOPSIS
    Detects worktrees whose branch is already merged into main and removes the finished
    (clean) ones when the per-repo preference or an explicit opt-in says so.
.DESCRIPTION
    Invoked by new-worktree.ps1 before it creates a new worktree, and runnable on its own.
    Precedence: -Cleanup flag > AHKFLOW_WORKTREE_CLEANUP env var (hook context only) >
    git config --local ahkflow.worktreeCleanup (true/false) > ask-once on an interactive
    console (unset) > report-only. Invalid/duplicated config fails closed to report-only.
    In hook context (-IsHook) all output stays on stderr so the hook's stdout contract is
    preserved; when config is unset it prints the one-liner to enable cleanup.
#>
```

- [ ] **Step 7: Make `-IsHook` honest in `new-worktree.ps1`**

First delete `Test-EnvironmentFlagDisabled` (currently `scripts/new-worktree.ps1:31-40`):

```powershell
function Test-EnvironmentFlagDisabled {
    param([string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return $value.Trim() -match '^(0|false|no|n)$'
}
```

Then replace the cleanup-invocation block (currently `scripts/new-worktree.ps1:244-263`, from the `# Sweep other worktrees...` comment through the closing `}` of the `try/catch`) with:

```powershell
# Sweep other worktrees whose branch is already merged into main before creating/reusing
# this one. -ExcludePath protects $worktreePath itself: without it a same-named create/reuse
# could race the async removal. -IsHook passes the RAW hook context; the cleanup script's
# resolver owns the full decision (hook-only env var, git config, ask-once). Best-effort:
# never block creation, and pipe to Out-Null so cleanup output can never reach hook stdout.
try {
    & (Join-Path $PSScriptRoot 'cleanup-merged-worktrees.ps1') -RepoRoot $repoRoot -Cleanup:$Cleanup -IsHook:$isHook -ExcludePath $worktreePath | Out-Null
} catch {
    Write-Stderr "Merged-worktree cleanup skipped: $($_.Exception.Message)"
}
```

- [ ] **Step 8: Update the `scripts/README.md` contract row**

Replace the `cleanup-merged-worktrees.ps1` row (currently `scripts/README.md:56`) with:

```markdown
| `cleanup-merged-worktrees.ps1` | Detects worktrees merged into `main` and removes the clean ones. Opt-in via `git config --local ahkflow.worktreeCleanup true` (the recommended set-once switch); unset asks once on an interactive create; `AHKFLOW_WORKTREE_CLEANUP` (hook context only) and `-Cleanup` are per-run overrides. Invoked by `new-worktree.ps1` before it creates a worktree. |
```

- [ ] **Step 9: Run the full worktree suite to verify pass**

Run:
```
pwsh -NoProfile -File tests/WorktreeMergedCleanup.Tests.ps1
pwsh -NoProfile -File tests/WorktreePowerShellHost.Tests.ps1
pwsh -NoProfile -File tests/WorktreeRemoveHook.Tests.ps1
pwsh -NoProfile -File tests/WorktreeLocalDevSetup.Tests.ps1
```
Expected: each prints its `...passed.` line; no exceptions.

- [ ] **Step 10: Commit**

```bash
git add scripts/cleanup-merged-worktrees.ps1 scripts/new-worktree.ps1 scripts/README.md tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "fix: worktree cleanup opt-in via ahkflow.worktreeCleanup config, honest -IsHook"
```

---

### Task 5: Restore skill hard link, rewrite canonical SKILL.md, add parity guard

The plugin copy `plugins/ahkflowapp/skills/worktrees/SKILL.md` is a divergent copy (byte-identical today, but not a hard link). Rewrite the canonical `.agents/worktrees/SKILL.md` for the tri-state config, re-run the setup script to restore the hard link so the committed plugin copy matches, and add a byte-parity guard test wired into CI.

**Files:**
- Modify: `.agents/worktrees/SKILL.md` (rewrite the cleanup sections)
- Regenerate: `plugins/ahkflowapp/skills/worktrees/SKILL.md` (via `setup-cross-agent-skills.ps1`)
- Create: `tests/SkillParity.Tests.ps1`
- Modify: `.github/workflows/ci.yml:108-112` (add the new test to the `worktree-powershell-tests` job)

**Interfaces:**
- Consumes: nothing from earlier tasks (docs + independent guard test).
- Produces: a CI-run assertion that every `plugins/ahkflowapp/skills/*/SKILL.md` matches its `.agents/<skill>/SKILL.md` source byte-for-byte.

- [ ] **Step 1: Write the failing parity guard test**

Create `tests/SkillParity.Tests.ps1`:

```powershell
#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pluginSkills = Join-Path $suiteRoot 'plugins\ahkflowapp\skills'
$agentsRoot = Join-Path $suiteRoot '.agents'

$failures = @()
foreach ($skillFile in (Get-ChildItem -LiteralPath $pluginSkills -Recurse -Filter 'SKILL.md' -File)) {
    $skillName = Split-Path -Leaf (Split-Path -Parent $skillFile.FullName)
    $canonical = Join-Path $agentsRoot (Join-Path $skillName 'SKILL.md')

    if (-not (Test-Path -LiteralPath $canonical)) {
        $failures += "No canonical .agents/$skillName/SKILL.md for plugin copy $($skillFile.FullName)."
        continue
    }

    $pluginBytes = [System.IO.File]::ReadAllBytes($skillFile.FullName)
    $canonicalBytes = [System.IO.File]::ReadAllBytes($canonical)
    $identical = ($pluginBytes.Length -eq $canonicalBytes.Length)
    if ($identical) {
        for ($i = 0; $i -lt $pluginBytes.Length; $i++) {
            if ($pluginBytes[$i] -ne $canonicalBytes[$i]) { $identical = $false; break }
        }
    }

    if (-not $identical) {
        $failures += "Plugin skill '$skillName' SKILL.md differs from .agents/$skillName/SKILL.md. Re-run scripts/agents/setup-cross-agent-skills.ps1 and edit only the .agents copy."
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Skill parity tests passed.'
```

- [ ] **Step 2: Run to verify it passes today (byte-identical copies) — sanity check the test itself**

Run: `pwsh -NoProfile -File tests/SkillParity.Tests.ps1`
Expected: PASS — `Skill parity tests passed.` (the copies match now; the test's job is to *keep* them matching). To prove the test can fail, temporarily append a space to the plugin copy, re-run (expect a thrown parity error), then discard the edit with `git checkout -- plugins/ahkflowapp/skills/worktrees/SKILL.md`.

- [ ] **Step 3: Rewrite the canonical SKILL.md cleanup sections**

In `.agents/worktrees/SKILL.md`, replace the section `### Cleanup of merged worktrees on create` through the end of the `#### Claude Code in-conversation native creation` subsection (currently lines 26-114, ending just before `## Removing`) with:

````markdown
### Cleanup of merged worktrees on create

Creating a worktree first checks the other worktrees whose branch is already merged
into `main`. What happens next is governed by one persistent per-repo setting plus
per-run overrides.

**The recommended switch — set it once:**

```bash
git config --local ahkflow.worktreeCleanup true    # always remove merged, clean worktrees
git config --local ahkflow.worktreeCleanup false   # never remove, never ask
git config --local --unset ahkflow.worktreeCleanup # back to ask-once
```

It lives in `.git/config` (never committed), is read at `--local` scope only (a global
value can't enable it here), and governs every context. An invalid or duplicated value
fails closed to report-only with a repair hint.

Precedence, highest first:

1. **`-Cleanup` / `-c` flag** (direct calls) — removes every merged, clean worktree, no prompt.
2. **`AHKFLOW_WORKTREE_CLEANUP`** — hook context only: `1|true|yes|y` enables, `0|false|no|n`
   disables, other values ignored. Per-run; never affects a direct call.
3. **`ahkflow.worktreeCleanup`** config — `true` removes, `false` skips. All contexts.
4. **Unset + interactive console** — asks once: *"Found N merged, clean worktrees. Remove
   them now and enable automatic cleanup for this repository? [y/N]"*. `y` removes now and
   persists `true`; anything else persists `false`. The answer is remembered, so it never
   asks again.
5. **Unset + hook / non-interactive** — report-only; the hook prints the one-liner to enable.

```bash
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name>            # ask-once if unset
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name> -Cleanup   # force removal this run
```

A worktree with uncommitted changes is never removed, even if its branch is merged. The
worktree currently being created or reused is always excluded from the sweep. Removal
reuses `remove-worktree-local-dev.ps1` (`git branch -d`, DB drop, Docker teardown,
lock-safe folder delete) and is logged to `.claude\worktrees\worktree-removal.log`.

#### Claude Code in-conversation native creation: ask once, then remember

Applies when *you* create a brand-new worktree in direct response to a conversation
request via `EnterWorktree` with `name`. Entering an existing worktree with `path` never
triggers this.

`EnterWorktree` fires the `WorktreeCreate` hook, which runs the resolver above: with a
recognized `AHKFLOW_WORKTREE_CLEANUP` env value or the config set (`true`/`false`) it acts
silently and there is nothing to do. Only when neither governs — no env override **and** the
config is **unset** — mirror the console ask-once in the conversation.

First work out the two absolute paths, then substitute them literally into the commands
below — do not paste PowerShell `$variables` into a Bash-tool command line, because the
Bash tool (Git Bash) expands `$newPath`/`$mainRoot` to empty strings before `pwsh` ever
runs, silently breaking the call.

- `<new-worktree-absolute-path>`: the exact path `EnterWorktree` returned.
- `<main-root>`: that path with the trailing worktree segment removed — drop
  `\.claude\worktrees\<name>` (default layout) or `\.worktrees\<name>` (fallback layout).
  Do not use a fixed parent count; the two layouts have different depths. Before running,
  confirm `<main-root>\scripts\cleanup-merged-worktrees.ps1` exists — if it does not, you
  removed the wrong number of segments.

1. Honor a session-wide env override first. If `AHKFLOW_WORKTREE_CLEANUP` holds a recognized
   value, the environment already governs this session (the `WorktreeCreate` hook applied it),
   so do nothing here — do not detect, do not ask, do not write config. Stop.

   ```bash
   printf '%s' "${AHKFLOW_WORKTREE_CLEANUP:-}"
   ```

   `1`/`true`/`yes`/`y` (enable) or `0`/`false`/`no`/`n` (disable), case-insensitive and
   trimmed → env owns the session; stop. Empty or any other value → continue. (This is why
   `AHKFLOW_WORKTREE_CLEANUP=0` set before launching Claude Code suppresses the whole flow.)

2. Check the config with the SAME four-state read the script uses — `--get-all` (not `--get`,
   which silently returns only the last value when the key is duplicated):

   ```bash
   git -C '<main-root>' config --local --bool --get-all ahkflow.worktreeCleanup
   ```

   - Exit 1, no output → **unset** → continue to step 3.
   - Exit 0 with exactly one `true`/`false` line → **set** → act silently, stop.
   - Anything else — exit 128 (bad boolean) or exit 0 with more than one line (duplicated) →
     **invalid** → report-only. Tell the user the value is invalid/duplicated and to repair it
     with `git config --local --unset-all ahkflow.worktreeCleanup`; do NOT ask and do NOT
     overwrite it. Stop.

3. Detect eligible merged worktrees. This is report-only here: step 1 ruled out any env
   override and step 2 guaranteed the config is unset, so `-IsHook` only lists — it removes
   nothing.

   ```bash
   pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -IsHook -ExcludePath '<new-worktree-absolute-path>'"
   ```

   If that command errors (non-zero exit or an exception), report the error to the user and
   stop; do not ask on the basis of a failed detection run.

   - No `cleanup: eligible merged worktree: ...` line → stay silent, do not ask, do not write config.
   - One or more `cleanup: eligible merged worktree: <path> [<branch>]` lines → ask once via
     `AskUserQuestion`: "Found N merged worktree(s) ready to clean up: `<path>` [`<branch>`], … .
     Clean them up automatically from now on? I'll remember either way." with options
     `Yes, remove them` / `No, leave them`.

4. Persist the answer (mirrors the console ask-once exactly):

   - **Yes** → enable and remove now:

     ```bash
     git -C '<main-root>' config --local ahkflow.worktreeCleanup true
     pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -Cleanup -ExcludePath '<new-worktree-absolute-path>'"
     ```

   - **No** → remember the choice, remove nothing:

     ```bash
     git -C '<main-root>' config --local ahkflow.worktreeCleanup false
     ```

To suppress this whole flow for a session regardless of config, set
`AHKFLOW_WORKTREE_CLEANUP=0` in the shell *before launching Claude Code*; step 1 stops before
any detection or ask.
````

- [ ] **Step 4: Restore the hard link and regenerate the plugin copy**

Run: `pwsh -NoProfile -File scripts/agents/setup-cross-agent-skills.ps1`
Expected: prints `[DONE] ...` and (for the worktrees skill) a `[FIX] Refreshed hard link plugins/ahkflowapp/skills/worktrees/SKILL.md.` or `Replaced symlink...` line. This rewrites the plugin `SKILL.md` as a hard link to the canonical file, so the committed content now matches the rewrite.

- [ ] **Step 5: Verify byte parity**

Run: `pwsh -NoProfile -File tests/SkillParity.Tests.ps1`
Expected: PASS — `Skill parity tests passed.`

Also confirm git sees both files updated:
Run: `git status --porcelain .agents/worktrees/SKILL.md plugins/ahkflowapp/skills/worktrees/SKILL.md`
Expected: both listed as modified.

- [ ] **Step 6: Wire the parity test into CI**

In `.github/workflows/ci.yml`, add the new test to the `worktree-powershell-tests` job's run block (currently lines 108-112), after the existing four lines:

```yaml
          ./tests/WorktreePowerShellHost.Tests.ps1
          ./tests/WorktreeMergedCleanup.Tests.ps1
          ./tests/WorktreeRemoveHook.Tests.ps1
          ./tests/WorktreeLocalDevSetup.Tests.ps1
          ./tests/SkillParity.Tests.ps1
```

- [ ] **Step 7: Commit**

```bash
git add .agents/worktrees/SKILL.md plugins/ahkflowapp/skills/worktrees/SKILL.md tests/SkillParity.Tests.ps1 .github/workflows/ci.yml
git commit -m "docs: rewrite worktree cleanup skill for tri-state config; add parity guard"
```

---

## Self-Review

**Spec coverage:**
- Mechanism (tri-state `--local` config, `--bool`, fail-closed) → Task 2 (`Get-WorktreeCleanupConfig`) + Global Constraints.
- Decision precedence (5 rules) + behavior matrix (all cells) → Task 3 (`Resolve-CleanupDecision`, unit-tested per cell) + Task 4 wiring.
- Ask-once prompt + persist + write-failure warning → Task 3 (`Set-CleanupAnswer` seam wrapping `ConvertFrom-CleanupAnswer` + `Set-WorktreeCleanupConfig`, unit-tested for yes/no/failed-write incl. the stderr warning via `[Console]::SetError`), Task 4 (`Prompt` branch calls `Set-CleanupAnswer`). The child-process integration tests redirect stdin so they can't reach `Prompt`; the seam test is what guards the persistence call + warning.
- Refactor 1 (honest `-IsHook`) → Task 4 Step 7. Refactor 2 (centralize matrix) → Tasks 3–4. Refactor 3 (dedupe `Write-Stderr`) → Task 1.
- Encouragement (console prompt, in-conversation ask-once, docs) → Task 5 SKILL.md rewrite + Task 4 README row. The in-conversation flow mirrors the script exactly: env override checked first (so `AHKFLOW_WORKTREE_CLEANUP` genuinely suppresses/governs the session), then the four-state `--get-all` config read (unset→ask, set→silent, invalid/duplicated→report-only+repair-hint), then report-only detection, then persist.
- Skill-file sync (restore hard link + byte-parity guard in harness style) → Task 5.
- Tests ("cleans means removed" polling, full matrix, invalid config, no-eligible, ask-once persistence, parity guard) → Tasks 2–5.
- Docs (SKILL.md, README, script synopses) → Task 4 (synopses + README) + Task 5 (SKILL.md).

**Placeholder scan:** none — every code/test step carries full content.

**Type consistency:** `Get-WorktreeCleanupConfig` → `'true'|'false'|'unset'|'invalid'` used verbatim by `Resolve-CleanupDecision -ConfigState` and its unit table. `Resolve-CleanupDecision` returns `{ Action; ShowHint }` consumed by the Task 4 `switch`. `ConvertFrom-CleanupAnswer` returns `{ Clean; Enabled }` consumed by the `Prompt` branch. `Get-EnvCleanupOverride` → `'enable'|'disable'|'none'` matches `-EnvOverride`. Consistent throughout.

## Unresolved questions

*(none — spec is approved and the git exit-code assumption was verified empirically)*
