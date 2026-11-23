# 218 - WorktreeSweepRemoteBase reads the diagnostics log with Get-Content -Raw

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (`tests/WorktreeSweepRemoteBase.Tests.ps1`)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

`tests/WorktreeSweepRemoteBase.Tests.ps1` reads the watcher's diagnostics log with
`Get-Content -Raw`. Backlog 216 showed that this call can return an array while another process
appends to the file. This suite then joins the pieces with a space, so a text check can fail, or
pass wrongly, when its text spans the point where the pieces split. No failure has been seen yet.

## User story

As a developer, I want this suite's log checks to read the whole log as written, so that a red or
green run means what it says.

## Root cause

The mechanism is proven. Whether this suite's reads race with a watcher is not checked yet.

1. Backlog 216 reproduced it on 2026-11-22. One process appended to a file in a tight loop. A
   second process ran `Get-Content -Raw` on it 2000 times. The result was not a `[string]` in 1076
   reads on pwsh 7.6.10, and in 1565 reads on Windows PowerShell 5.1. Pull request #495 merged
   backlog 216 on 2026-11-23.
2. This suite reads the diagnostics log that way in one helper
   (`tests/WorktreeSweepRemoteBase.Tests.ps1:282`, "return (Get-Content -Raw -LiteralPath $logPath)").
3. Its callers pass the value to `Assert-Contains` and `Assert-NotContains`, which take a
   `[string]` parameter
   (`tests/WorktreeSweepRemoteBase.Tests.ps1:29`, "param([string] $Haystack, [string] $Needle, [string] $Message)").
4. A `[string]` parameter joins an array into one string, with one space between the pieces. A
   probe on 2026-11-22 showed this on pwsh 7.6.10 and on Windows PowerShell 5.1.26100.9818. So
   this suite does not fail on the type, unlike backlog 216 and backlog 217.
5. The joined text differs from the file wherever the pieces split. An `Assert-Contains` whose
   text spans that point fails. An `Assert-NotContains` whose text spans it passes wrongly.
6. The outcome log helper just above uses the same call
   (`tests/WorktreeSweepRemoteBase.Tests.ps1:274`, "return (Get-Content -Raw -LiteralPath $logPath)").
7. Pickup checked on 2026-11-23 which reads can run while a watcher still writes. One read can.
   That case runs the hook on a merged branch
   (`tests/WorktreeSweepRemoteBase.Tests.ps1:513`, "$resolved = Invoke-RemoveHook -WorktreePath $fixture.Worktree").
   So the hook starts a watcher
   (`scripts/remove-worktree-local-dev.ps1:1107`, "Watcher spawned via WMI.").
   The case then reads the diagnostics log before it waits for the worktree to go
   (`tests/WorktreeSweepRemoteBase.Tests.ps1:515`, "The hook must resolve and report its own base when none is passed.").
   The watcher appends to that log meanwhile. It also writes the outcome line at its end
   (`scripts/remove-worktree-local-dev.ps1:1438`, "Write-Outcome 'Removed.'").
8. The other log reads run after every writer has exited. Each one follows a sweep or a hook
   that keeps the worktree, and the hook keeps a worktree before it starts a watcher
   (`scripts/remove-worktree-local-dev.ps1:953`, "-Reason 'the base branch could not be refreshed'")
   (`scripts/remove-worktree-local-dev.ps1:960`, "-Reason 'the branch is not merged'").
   These are the reads at lines 433, 444, 445, 509 and 510 of the suite. No case reads the
   outcome log while a watcher runs.
9. Not checked yet: where the pieces split.

## Acceptance criteria

- [ ] `Get-RemovalDiagnostics` in `tests/WorktreeSweepRemoteBase.Tests.ps1` returns one string while another process appends to the log.
- [ ] Each changed `Assert-Contains` still fails when the text it expects is missing.
- [ ] Each changed `Assert-NotContains` still fails when the text it forbids is present.

## Out of scope

- The watcher and the sweep. They log correctly.
- `tests/WorktreeMergedCleanupSweep.Tests.ps1`. Backlog 217 covers it.

## Notes / dependencies

- Reuse `Read-LogText`. Backlog 217 moved it into `tests/LogText.Common.ps1`, and pull request
  #496 merged that on 2026-11-23. Do not write another copy.
- The suite runs on Windows only, in the `suites` job, and it runs Windows PowerShell 5.1 (`tests/powershell-suites.json:71`, "WorktreeSweepRemoteBase.Tests.ps1").
- Spec: none — moderate item, the root cause above is the design input.
- Plan: `docs/superpowers/plans/2026-11-23-sweep-remote-base-diagnostics-read-plan-218.md`
