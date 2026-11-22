# 217 - WorktreeMergedCleanupSweep reads the diagnostics log with Get-Content -Raw

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (`tests/WorktreeMergedCleanupSweep.Tests.ps1`)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

`tests/WorktreeMergedCleanupSweep.Tests.ps1` reads the watcher's diagnostics log with
`Get-Content -Raw`. Backlog 216 showed that this call can return an array while another process
appends to the file. In this suite an array reaches an `Assert-True` with a `[bool]` parameter,
which fails with no line number. No failure has been seen yet.

## User story

As a developer, I want this suite to pass every time the sweep works, so that a red CI run means
a real problem.

## Root cause

The mechanism is proven. Whether this suite's reads race with a watcher is not checked yet.

1. Backlog 216 reproduced it on 2026-11-22. One process appended to a file in a tight loop. A
   second process ran `Get-Content -Raw` on it 2000 times. The result was not a `[string]` in 1076
   reads on pwsh 7.6.10, and in 1565 reads on Windows PowerShell 5.1. Backlog 216 is on pull
   request #495 and is not on `main` yet.
2. This suite reads the diagnostics log twice that way:
   (`tests/WorktreeMergedCleanupSweep.Tests.ps1:428`, "Assert-True ((Get-Content -Raw -LiteralPath $diagnosticsLog) -match")
   and (`tests/WorktreeMergedCleanupSweep.Tests.ps1:576`, "$diagnostics = Get-Content -Raw -LiteralPath (Join-Path $repo").
3. `-match` on an array returns the matching elements, not a boolean.
4. The suite's `Assert-True` takes a `[bool]` parameter
   (`tests/WorktreeMergedCleanup.Common.ps1:26`, "param([bool] $Condition, [string] $Message)").
   An array fails during parameter binding, and a binding failure names no line. Backlog 068 saw
   that kind of error in another suite on 2026-08-08.
5. Not checked yet: whether either read can run while a watcher still writes. The watcher writes
   its outcome line after its last normal diagnostics line
   (`scripts/remove-worktree-local-dev.ps1:1438`, "Write-Outcome 'Removed.'"). Line 428 reads
   after every outcome line has arrived. Line 576 reads after the outcome line of one worktree.
   The test has other worktrees, so Pickup must check whether a watcher for one of them can still
   write at that moment.

## Acceptance criteria

- [ ] No `-match` in `tests/WorktreeMergedCleanupSweep.Tests.ps1` runs on a diagnostics log value that can be an array.
- [ ] The suite reads the diagnostics log with a read that returns one string while another process appends to the file.
- [ ] Each changed assertion still fails when the diagnostics line it expects is missing.

## Out of scope

- The watcher and the sweep. They log correctly.
- `tests/WorktreeSweepRemoteBase.Tests.ps1`. Backlog 218 covers it.

## Notes / dependencies

- Pick this up after pull request #495 merges. Backlog 216 adds the helper `Read-LogText` to
  `tests/WorktreeRemoveHook.Tests.ps1`. This item can move it into a shared test file, so the
  suites do not keep two copies.
- The suite runs on Windows only, in the `suites` job (`tests/powershell-suites.json:64`, "WorktreeMergedCleanupSweep.Tests.ps1").
- Spec: <path, or "none — reason">
- Plan: <path, or "none — reason">
