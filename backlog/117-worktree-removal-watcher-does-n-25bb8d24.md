# 117 - Worktree removal hook is a silent no-op when it cannot read its stdin

## Metadata

- **Epic**: Agent worktree lifecycle
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The `WorktreeRemove` hook exits 0 and writes no outcome line when it cannot parse the JSON
on its stdin. GitHub issue #348 blamed the detached watcher and Windows PowerShell 5.1.
That diagnosis is wrong. The watcher works under 5.1. The real trigger is a UTF-8 byte order
mark on the hook's stdin, which `ConvertFrom-Json` rejects.

## Root cause, with evidence

Three findings, each reproduced on 2026-08-27.

### 1. The watcher is not broken under Windows PowerShell 5.1

`scripts/remove-worktree-local-dev.ps1` in Watcher mode removes the worktree, prunes git,
deletes the branch, and writes `Removed.` under `powershell.exe` 5.1.26100.9168. This was
checked twice: dot-sourced in-process, and spawned as a detached hidden process. Both wrote
the full diagnostics tail and the outcome line:

    [manual-2e3c50] Watcher Watcher done (worktree + branch removed).
    [manual-2e3c50] Watcher OUTCOME Removed.

So `Resolve-PowerShellExecutable` returning the current host is not a defect
(`scripts/worktree-powershell.common.ps1:5`, "    $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().Path").
Issue #348's stated cause does not hold.

### 2. The test harness feeds the hook a byte order mark under 5.1

`tests/WorktreeRemoveHook.Tests.ps1` wrote the hook's stdin with
`Set-Content ... -Encoding utf8` before this item's fix. <!-- citation-check:ignore records the pre-fix tree --> Under Windows PowerShell 5.1 that cmdlet emits a UTF-8 BOM.
Under PowerShell 7 it does not. Measured bytes for the same one-line JSON:

    5.1:  ef bb bf 7b 22 61 22 3a 31 7d 0d 0a
    7.x:        7b 22 61 22 3a 31 7d 0d 0a

### 3. A BOM on stdin turns the hook into a silent no-op

`Read-RawStdin` returned the BOM as a leading character. `ConvertFrom-Json` then failed,
`$WorktreePath` stayed empty, and the empty-path branch of `Invoke-HookMode` returned without
calling `Write-Outcome`. Both sites are in `scripts/remove-worktree-local-dev.ps1` and both are
changed by this item, so the pre-fix line numbers are deliberately left out.
Observed hook stderr:

    Hook stdin was not valid JSON: Invalid JSON primitive: .
    Hook No worktree_path provided; nothing to do.

Exit code 0, worktree still present, `worktree-removal.log` never created. That is exactly
the symptom issue #348 describes.

### Proof that nothing in the production script needs a host bump

A copy of the suite with only two test-side changes — an `$ErrorActionPreference` guard
around `Invoke-TestGit` for the issue #340 stderr defect, and a BOM-less stdin write — passes
in full under `powershell.exe`:

    Worktree remove-hook gate tests passed.

## User story

As an agent or a human running a Claude Code session on `powershell.exe`, I want the removal
hook to say what it did, so that a worktree left behind always has a log line explaining why.

## Acceptance criteria

- [ ] `Read-RawStdin` in `scripts/remove-worktree-local-dev.ps1` decodes stdin as UTF-8 through
      a `StreamReader` over the raw stream, not through `[Console]::In`, so a leading byte order
      mark is consumed and a non-ASCII worktree path survives.
- [ ] The hook writes exactly one outcome line to `worktree-removal.log` when it finds no
      `worktree_path`, so no removal attempt ends with an empty log.
- [ ] `tests/WorktreeRemoveHook.Tests.ps1` declares `#Requires -Version 5.1` and passes under
      both `powershell.exe` and `pwsh`.
- [ ] `tests/WorktreeRemoveHook.Tests.ps1` has a case that feeds BOM-prefixed stdin and
      asserts the worktree is still removed.
- [ ] The header comment of `tests/WorktreeRemoveHook.Tests.ps1` no longer claims the watcher
      fails under Windows PowerShell.

## Out of scope

- Changing `Resolve-PowerShellExecutable`. Finding 1 shows the current host is a safe choice.
- The issue #340 stderr defect itself. This item only guards the one helper that trips on it.

## Notes / dependencies

- Closes GitHub issue #348. That issue's stated root cause is wrong; finding 1 above corrects it.
- Related: issue #340 and PR #347, which raised this suite's floor to `#Requires -Version 7.0`.
- Precedent for a raised floor elsewhere
  (`tests/WorktreeMergedCleanup.Tests.ps1:7`, "#Requires -Version 7.0").
- `[Console]::InputEncoding` is `ibm437` on this machine under both hosts, so the BOM bytes
  decode to `U+2229 U+2557 U+2510` and never to one `U+FEFF`. Trimming a single character does
  not work; the reader has to bypass `[Console]::In`. Recorded in the plan's Task 1.
- Follow-up, not fixed here: `Get-HookInput` in `scripts/new-worktree.ps1` reads its hook stdin
  through `[Console]::In.ReadToEnd()` and carries the same code-page defect.
- Spec: none - root cause is proven above and the change is moderate, so this item goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-08-27-removal-hook-stdin-bom-plan-117.md`
