# Worktree Cleanup Ask On Create Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow merged-worktree cleanup when Claude Code creates a worktree natively, including `claude --worktree <name>`, without breaking the `WorktreeCreate` stdout contract.

**Architecture:** `WorktreeCreate` hooks cannot prompt because command-hook stdout must be only the absolute worktree path, and hook subprocesses do not have a normal terminal for interactive input. The CLI bootstrap path will therefore use an explicit environment-variable opt-in (`AHKFLOW_WORKTREE_CLEANUP=1`) that makes `scripts/new-worktree.ps1` perform cleanup automatically. The in-conversation `EnterWorktree` path will keep report-only hook behavior, then the `worktrees` skill will tell Claude to run a visible detection pass and ask the user with `AskUserQuestion`.

**Tech Stack:** PowerShell 5.1 scripts, git worktrees, Claude Code `WorktreeCreate` hooks, Markdown skill docs, repository PowerShell test scripts.

---

## Decisions

- `claude --worktree <name>` support is required. The previous docs-only plan excluded this path and is not acceptable.
- No prompt is attempted inside `WorktreeCreate`. The hook must return exactly one stdout value: the created worktree path.
- CLI cleanup is opt-in and non-interactive:

  ```powershell
  $env:AHKFLOW_WORKTREE_CLEANUP = '1'
  claude --worktree my-feature
  Remove-Item Env:AHKFLOW_WORKTREE_CLEANUP
  ```

- Accepted true values for the env var: `1`, `true`, `yes`, `y` (case-insensitive). Any missing, empty, or other value means "not requested."
- The existing `-Cleanup` / `-c` switch for direct `scripts/new-worktree.ps1` calls stays authoritative.
- In hook mode, `-Cleanup` and `AHKFLOW_WORKTREE_CLEANUP=1` must override report-only mode. Today `cleanup-merged-worktrees.ps1` exits early whenever `-IsHook` is true, so `new-worktree.ps1` must pass `-IsHook:$false` when cleanup was explicitly requested.
- The in-conversation ask-after-create path belongs in `.agents/worktrees/SKILL.md`, not in hook stdout. Its `-RepoRoot` calculation must be robust for both `.claude\worktrees\<name>` and `.worktrees\<name>`; do not use the old "two parents" shortcut because it resolves `.claude` instead of the repo root for the default layout.
- Do not implement a `SessionStart` pending-prompt mechanism in this plan. The CLI path is handled by explicit env opt-in; the conversational path is handled by skill behavior after `EnterWorktree`.

## File Structure

- Modify `scripts/new-worktree.ps1` - add environment opt-in parsing and split "cleanup requested" from "hook report-only".
- Modify `Tests/WorktreeMergedCleanup.Tests.ps1` - add a regression that drives the real `new-worktree.ps1` hook path with `AHKFLOW_WORKTREE_CLEANUP=1` and proves cleanup is attempted while stdout remains exactly one worktree path.
- Modify `.agents/worktrees/SKILL.md` - document CLI env opt-in and the in-conversation ask-after-create workflow with corrected repo-root detection.
- Modify `plugins/ahkflowapp/skills/worktrees/SKILL.md` - not by hand; resync it through `scripts/agents/setup-copilot-symlinks.ps1`.
- Modify `scripts/README.md` - document the env opt-in as part of the worktree cleanup contract.

---

### Task 1: Add CLI Hook Opt-In Regression

**Files:**
- Modify: `Tests/WorktreeMergedCleanup.Tests.ps1`

- [ ] **Step 1: Add failing regression test**

Append this block immediately after the existing test headed `# --- Test: hook path keeps stdout to exactly the new worktree path -------------` and before the final `Write-Host 'Worktree merged-cleanup tests passed.'` line.

```powershell
# --- Test: CLI env opt-in lets WorktreeCreate hook remove merged worktrees ----
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    # An eligible merged + clean worktree so the env opt-in has something to remove.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-env-cleanup' | Out-Null

    $stdinFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stdin.json'
    $stdoutFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stdout.txt'
    $stderrFile = Join-Path (Split-Path -Parent $repo) 'hook-env-stderr.txt'
    Set-Content -LiteralPath $stdinFile -Value '{"name":"brandnew-env"}' -Encoding utf8

    $oldCleanupEnv = [Environment]::GetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', 'Process')
    [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', '1', 'Process')
    try {
        $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
        $newWorktreeScript = Join-Path $repo 'scripts\new-worktree.ps1'
        $proc = Start-Process -FilePath $psExe `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $newWorktreeScript) `
            -WorkingDirectory $repo `
            -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru -Wait
    } finally {
        [Environment]::SetEnvironmentVariable('AHKFLOW_WORKTREE_CLEANUP', $oldCleanupEnv, 'Process')
    }

    Assert-Equal 0 $proc.ExitCode "new-worktree.ps1 hook path with env cleanup should exit 0. Stderr: $(Get-Content -Raw -LiteralPath $stderrFile)"

    $stdout = Get-Content -Raw -LiteralPath $stdoutFile
    $stdoutLines = @(($stdout -split "`r?`n") | Where-Object { $_.Trim() })
    $expected = ([System.IO.Path]::GetFullPath((Join-Path $repo '.claude\worktrees\brandnew-env'))).TrimEnd('\', '/')

    Assert-Equal 1 $stdoutLines.Count "Hook stdout must remain exactly one line when env cleanup is enabled. Got: $stdout"
    Assert-Equal $expected ($stdoutLines[0].Trim().TrimEnd('\', '/')) 'Hook stdout must remain exactly the new worktree path when env cleanup is enabled.'

    $stderrText = Get-Content -Raw -LiteralPath $stderrFile
    Assert-True ($stderrText -match 'cleanup: eligible merged worktree') "Expected cleanup detection output on stderr. Stderr: $stderrText"
    Assert-True ($stderrText -match 'cleanup: removing merged worktree') "Expected env opt-in to request removal instead of report-only mode. Stderr: $stderrText"
    Assert-True (-not ($stderrText -match 'cleanup: hook context is report-only')) "Env opt-in must not leave cleanup in hook report-only mode. Stderr: $stderrText"
} finally {
    Remove-TempTree $repo
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
pwsh -NoProfile -File Tests\WorktreeMergedCleanup.Tests.ps1
```

Expected: FAIL in the new block because current `new-worktree.ps1` still passes `-IsHook:$true` during hook creation, so stderr contains `cleanup: hook context is report-only; nothing removed.` and does not contain `cleanup: removing merged worktree`.

- [ ] **Step 3: Commit failing test if using TDD checkpoints**

If the implementation session uses checkpoint commits, commit only the test:

```bash
git add Tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "test: cover worktree cleanup env opt-in"
```

---

### Task 2: Implement CLI Env Opt-In In `new-worktree.ps1`

**Files:**
- Modify: `scripts/new-worktree.ps1`

- [ ] **Step 1: Add env flag helper**

Insert this function immediately after `Write-Stderr` in `scripts/new-worktree.ps1`.

```powershell
function Test-EnvironmentFlagEnabled {
    param([string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return $value.Trim() -match '^(1|true|yes|y)$'
}
```

- [ ] **Step 2: Split cleanup requested from hook report-only**

Replace the current cleanup invocation block:

```powershell
try {
    & (Join-Path $PSScriptRoot 'cleanup-merged-worktrees.ps1') -RepoRoot $repoRoot -Cleanup:$Cleanup -IsHook:$isHook -ExcludePath $worktreePath | Out-Null
} catch {
    Write-Stderr "Merged-worktree cleanup skipped: $($_.Exception.Message)"
}
```

with:

```powershell
$cleanupRequested = [bool] $Cleanup
if (-not $cleanupRequested -and (Test-EnvironmentFlagEnabled -Name 'AHKFLOW_WORKTREE_CLEANUP')) {
    $cleanupRequested = $true
}

$cleanupIsReportOnly = $isHook -and -not $cleanupRequested

try {
    & (Join-Path $PSScriptRoot 'cleanup-merged-worktrees.ps1') -RepoRoot $repoRoot -Cleanup:$cleanupRequested -IsHook:$cleanupIsReportOnly -ExcludePath $worktreePath | Out-Null
} catch {
    Write-Stderr "Merged-worktree cleanup skipped: $($_.Exception.Message)"
}
```

This preserves the existing behavior for:

- Direct interactive `scripts/new-worktree.ps1 -Name <name>`: still prompts when eligible worktrees exist.
- Direct `scripts/new-worktree.ps1 -Name <name> -Cleanup`: still removes.
- Hook `claude --worktree <name>` without env var: still report-only.
- Hook `AHKFLOW_WORKTREE_CLEANUP=1 claude --worktree <name>`: removes eligible merged clean worktrees while keeping stdout clean.

- [ ] **Step 3: Run focused test**

Run:

```powershell
pwsh -NoProfile -File Tests\WorktreeMergedCleanup.Tests.ps1
```

Expected: PASS with final line:

```text
Worktree merged-cleanup tests passed.
```

- [ ] **Step 4: Run PowerShell host contract test**

Run:

```powershell
pwsh -NoProfile -File Tests\WorktreePowerShellHost.Tests.ps1
```

Expected: PASS with final line:

```text
Worktree PowerShell host tests passed.
```

- [ ] **Step 5: Commit implementation**

```bash
git add scripts/new-worktree.ps1 Tests/WorktreeMergedCleanup.Tests.ps1
git commit -m "feat: allow cli worktree cleanup opt-in"
```

---

### Task 3: Update Worktree Skill And Script Docs

**Files:**
- Modify: `.agents/worktrees/SKILL.md`
- Modify: `scripts/README.md`
- Resync: `plugins/ahkflowapp/skills/worktrees/SKILL.md`

- [ ] **Step 1: Replace the cleanup section in `.agents/worktrees/SKILL.md`**

Replace the current `### Cleanup of merged worktrees on create` section with:

````markdown
### Cleanup of merged worktrees on create

Creating a worktree first checks the other worktrees whose branch is already merged
into `main`. Nothing is removed without an explicit opt-in:

- **Interactive direct create (a real console, no flag):** it lists the merged, clean
  worktrees and asks once - `Clean up merged worktrees? (y/n)`. `y` removes them all;
  `n` skips.
- **Direct `-Cleanup` / `-c`:** removes every merged, clean worktree with no prompt:

  ```bash
  pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name> -Cleanup
  ```

- **Claude Code CLI bootstrap (`claude --worktree <name>`):** set
  `AHKFLOW_WORKTREE_CLEANUP=1` before launching Claude to request cleanup during
  native worktree creation:

  ```powershell
  $env:AHKFLOW_WORKTREE_CLEANUP = '1'
  claude --worktree <name>
  Remove-Item Env:AHKFLOW_WORKTREE_CLEANUP
  ```

- **WorktreeCreate hook without the env var, or non-interactive direct create without
  `-Cleanup`:** detection is logged to stderr only; nothing is removed.

A worktree with uncommitted changes is never removed, even if its branch is merged.
The worktree currently being created or reused is always excluded from the sweep, so a
same-named recreate can never race its own removal. Removal reuses
`remove-worktree-local-dev.ps1` (`git branch -d`, DB drop, Docker teardown, lock-safe
folder delete).

#### Claude Code in-conversation native creation: ask afterward

Applies only when *you* create a brand-new worktree in direct response to a
conversation request via `EnterWorktree` with `name`. Entering an existing worktree
with `path` never triggers this.

`EnterWorktree` fires the `WorktreeCreate` hook above. The hook stdout must stay
exactly the new worktree path, it cannot prompt, and hook stderr is not usable as a
conversation signal. Right after `EnterWorktree` returns the new worktree absolute
path, run detection yourself as a normal Bash call so the output is visible:

```bash
pwsh -NoProfile -Command "$newPath = '<new-worktree-absolute-path>'; $mainRoot = Split-Path -Parent $newPath; while ($mainRoot -and -not (Test-Path -LiteralPath (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1'))) { $mainRoot = Split-Path -Parent $mainRoot }; if (-not $mainRoot) { throw 'Could not resolve main checkout from worktree path.' }; & (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1') -RepoRoot $mainRoot -IsHook -ExcludePath $newPath"
```

Do not compute the repo root with a fixed parent count. Default worktrees live under
`.claude\worktrees\<name>`, while fallback worktrees may live under `.worktrees\<name>`.
Walking upward from the new worktree's parent until `scripts\cleanup-merged-worktrees.ps1`
is found handles both layouts and avoids targeting the new worktree or `.claude`.

- No `cleanup: eligible merged worktree: ...` line: stay silent, do not ask.
- One or more `cleanup: eligible merged worktree: <path> [<branch>]` lines: ask via
  `AskUserQuestion`, listing what was found, for example:
  "Found N merged worktree(s) ready to clean up: `<path>` [`<branch>`], ... . Remove them now?"
  with options `Yes, remove them` / `No, leave them`.
- If the user answers yes, re-run with `-Cleanup` instead of `-IsHook`:

  ```bash
  pwsh -NoProfile -Command "$newPath = '<new-worktree-absolute-path>'; $mainRoot = Split-Path -Parent $newPath; while ($mainRoot -and -not (Test-Path -LiteralPath (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1'))) { $mainRoot = Split-Path -Parent $mainRoot }; if (-not $mainRoot) { throw 'Could not resolve main checkout from worktree path.' }; & (Join-Path $mainRoot 'scripts\cleanup-merged-worktrees.ps1') -RepoRoot $mainRoot -Cleanup -ExcludePath $newPath"
  ```

- If the user answers no, leave them; do not run the removal command.
````

- [ ] **Step 2: Update `scripts/README.md` cleanup row**

Replace the `cleanup-merged-worktrees.ps1` row with:

```markdown
| `cleanup-merged-worktrees.ps1` | Detects worktrees merged into `main` and removes the clean ones on opt-in (`-Cleanup`, `AHKFLOW_WORKTREE_CLEANUP=1` for Claude CLI native worktree creation, or the interactive prompt); invoked by `new-worktree.ps1` before it creates a worktree. |
```

- [ ] **Step 3: Resync skill links and hard links**

Run:

```powershell
pwsh -NoProfile -File scripts/agents/setup-copilot-symlinks.ps1
```

Expected: exit 0 and output ending:

```text
[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills hard-link to the same SKILL.md files
```

- [ ] **Step 4: Hash-verify plugin hard link content**

Run:

```powershell
pwsh -NoProfile -Command "if ((Get-FileHash .agents/worktrees/SKILL.md).Hash -ne (Get-FileHash plugins/ahkflowapp/skills/worktrees/SKILL.md).Hash) { throw 'SKILL.md copies differ' } else { 'SKILL.md copies match' }"
```

Expected:

```text
SKILL.md copies match
```

- [ ] **Step 5: Verify symlink directories**

Run:

```powershell
pwsh -NoProfile -File scripts/agents/check-symlinks.ps1 -Path .claude/skills/worktrees -NoRecurse
pwsh -NoProfile -File scripts/agents/check-symlinks.ps1 -Path .github/skills/worktrees -NoRecurse
```

Expected: both checks report `LinkType = SymbolicLink` with target `.agents\worktrees`.

- [ ] **Step 6: Commit docs**

```bash
git add .agents/worktrees/SKILL.md plugins/ahkflowapp/skills/worktrees/SKILL.md scripts/README.md
git commit -m "docs: document native worktree cleanup opt-in"
```

---

### Task 4: Final Verification

**Files:**
- Verify: `scripts/new-worktree.ps1`
- Verify: `scripts/cleanup-merged-worktrees.ps1`
- Verify: `Tests/WorktreeMergedCleanup.Tests.ps1`
- Verify: `.agents/worktrees/SKILL.md`

- [ ] **Step 1: Run focused PowerShell worktree tests**

```powershell
pwsh -NoProfile -File Tests\WorktreeMergedCleanup.Tests.ps1
pwsh -NoProfile -File Tests\WorktreePowerShellHost.Tests.ps1
```

Expected:

```text
Worktree merged-cleanup tests passed.
Worktree PowerShell host tests passed.
```

- [ ] **Step 2: Parse-check changed scripts**

Run:

```powershell
pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts\new-worktree.ps1)) | Out-Null; [scriptblock]::Create((Get-Content -Raw scripts\cleanup-merged-worktrees.ps1)) | Out-Null; 'PowerShell parse OK'"
```

Expected:

```text
PowerShell parse OK
```

- [ ] **Step 3: Check markdown and whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [ ] **Step 4: Run solution build if implementation touched only scripts/docs**

Run:

```powershell
dotnet build AHKFlowApp.slnx --configuration Release
```

Expected: build succeeds.

- [ ] **Step 5: Manual CLI smoke test**

Only run this if the implementation session can safely create and remove scratch worktrees.

```powershell
$env:AHKFLOW_WORKTREE_CLEANUP = '1'
claude --worktree wt-cli-cleanup-smoke
Remove-Item Env:AHKFLOW_WORKTREE_CLEANUP
```

Expected:

- Claude Code creates the requested worktree.
- The `WorktreeCreate` hook still receives exactly one stdout path from `new-worktree.ps1`.
- Eligible merged clean worktrees are removed before the new worktree setup continues.
- The newly created worktree is not removed because `new-worktree.ps1` passes it as `-ExcludePath`.

- [ ] **Step 6: Final commit or amend**

If Task 1 through Task 3 used separate commits, leave them separate. If the implementation session kept the work in one working tree, commit everything together:

```bash
git add scripts/new-worktree.ps1 Tests/WorktreeMergedCleanup.Tests.ps1 .agents/worktrees/SKILL.md plugins/ahkflowapp/skills/worktrees/SKILL.md scripts/README.md
git commit -m "feat: enable cleanup for native worktree creation"
```

---

## Self-Review Notes

- CLI path coverage: Task 1 and Task 2 implement `AHKFLOW_WORKTREE_CLEANUP=1` for `claude --worktree <name>`.
- Conversational path coverage: Task 3 updates the worktrees skill to run detection after `EnterWorktree` and ask through `AskUserQuestion`.
- Hook stdout safety: Task 1 asserts stdout is exactly one line, and Task 2 keeps the cleanup invocation piped to `Out-Null`.
- Main-checkout safety: the skill detection command walks upward from the new worktree parent and passes `-RepoRoot` explicitly; `cleanup-merged-worktrees.ps1` already excludes the passed repo root and `-ExcludePath`.
- Race safety: `new-worktree.ps1` continues to resolve `$worktreePath` before cleanup and passes `-ExcludePath $worktreePath`.
- No prompt-in-hook behavior remains: hooks either report-only or env-opt-in cleanup; asking happens only in normal conversation after `EnterWorktree`.
