# 217 - WorktreeMergedCleanupSweep reads the diagnostics log with Get-Content -Raw

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (`tests/WorktreeMergedCleanupSweep.Tests.ps1`)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

`tests/WorktreeMergedCleanupSweep.Tests.ps1` reads the watcher's diagnostics log with
`Get-Content -Raw`. Backlog 216 showed that this call can return an array while another process
appends to the file. In this suite an array reaches an `Assert-True` with a `[bool]` parameter,
which fails with no line number. No failure has been seen yet.

## User story

As a developer, I want this suite to pass every time the sweep works, so that a red CI run means
a real problem.

## Root cause

The mechanism is proven. Pickup checked point 5 on 2026-11-23: both reads can race with a
watcher that is still writing.

1. Backlog 216 reproduced it on 2026-11-22. One process appended to a file in a tight loop. A
   second process ran `Get-Content -Raw` on it 2000 times. The result was not a `[string]` in 1076
   reads on pwsh 7.6.10, and in 1565 reads on Windows PowerShell 5.1. Backlog 216 merged on
   2026-11-23 in pull request #495.
2. This suite reads the diagnostics log twice that way:
   (`tests/WorktreeMergedCleanupSweep.Tests.ps1:428`, "Assert-True ((Get-Content -Raw -LiteralPath $diagnosticsLog) -match") <!-- citation-check:ignore: backlog 217 replaced this read with Read-LogText. The line records the code when the item was filed. -->
   and (`tests/WorktreeMergedCleanupSweep.Tests.ps1:576`, "$diagnostics = Get-Content -Raw -LiteralPath (Join-Path $repo"). <!-- citation-check:ignore: backlog 217 replaced this read with Read-LogText. The line records the code when the item was filed. -->
3. `-match` on an array returns the matching elements, not a boolean.
4. The suite's `Assert-True` takes a `[bool]` parameter
   (`tests/WorktreeMergedCleanup.Common.ps1:26`, "param([bool] $Condition, [string] $Message)").
   An array fails during parameter binding, and a binding failure names no line. Backlog 068 saw
   that kind of error in another suite on 2026-08-08.
5. Checked at Pickup: yes, a watcher can still write when either line reads. `Write-Outcome`
   writes the outcome line first
   (`scripts/remove-worktree-local-dev.ps1:338`, "Write-WorktreeLog -LogPath $script:LogPath -Worktree $script:WorktreeLogName -Message $Message").
   Only then does it append the same line to the diagnostics log
   (`scripts/remove-worktree-local-dev.ps1:339`, "OUTCOME $Message").
   After that the watcher can still log a failed temp-folder delete
   (`scripts/remove-worktree-local-dev.ps1:1441`, "Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript").
   Both tests wait for the outcome log, never for the diagnostics log. Line 428 waits for the
   outcome lines of two removed worktrees. Line 576 waits for the outcome lines of all three of
   its worktrees, at lines 538, 546 and 570. So at both reads, the watcher whose outcome line
   the test just saw can still be appending to the diagnostics log. The race is in the test's
   own order, not only in other worktrees' watchers.

## Acceptance criteria

- [x] No `-match` in `tests/WorktreeMergedCleanupSweep.Tests.ps1` runs on a diagnostics log value that can be an array.
- [x] The suite reads the diagnostics log with a read that returns one string while another process appends to the file.
- [x] Each changed assertion still fails when the diagnostics line it expects is missing.

## Out of scope

- The watcher and the sweep. They log correctly.
- `tests/WorktreeSweepRemoteBase.Tests.ps1`. Backlog 218 covers it.

## Notes / dependencies

- Pick this up after pull request #495 merges. Backlog 216 adds the helper `Read-LogText` to
  `tests/WorktreeRemoveHook.Tests.ps1`. This item can move it into a shared test file, so the
  suites do not keep two copies.
- The suite runs on Windows only, in the `suites` job (`tests/powershell-suites.json:64`, "WorktreeMergedCleanupSweep.Tests.ps1").
- Spec: none — moderate item, the root cause above is the design input.
- Plan: `docs/superpowers/plans/2026-11-23-sweep-suite-diagnostics-read-plan-217.md`
