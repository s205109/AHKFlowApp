# 118 - Give each worktree removal its own temp directory

## Metadata

- **Epic**: Worktree tooling
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

The removal hook copies two helper files to fixed names in the bare `%TEMP%`. Several watchers run
at once during a merged-cleanup sweep, so one copy can fail while another watcher holds the same
file open. Each removal attempt should own a private temp directory instead.

## User story

As a developer running a merged-cleanup sweep, I want every watcher to read its own helper copies,
so that a concurrent sweep never degrades a watcher to its inline fallback.

## Where this came from

GitHub issue #339, deferred from the review of pull requests #336 and #338 (backlog item 073).

## Detail

Before this change, `Get-RemovalTempDir` returned the bare `%TEMP%` and the hook staged everything
there. The watcher script and the param file carried the run id in their names. The two helper
copies, `worktree-log.common.ps1` and `worktree-holder.common.ps1`, did not: each landed on one
fixed path.

One merged-cleanup sweep starts several watchers at once. Each copied both helpers to that same
fixed path with `Copy-Item -Force`, while another watcher held the file open for dot-sourcing. The
copy failed and that watcher ran on its inline fallbacks. The log fallback loses the retrying
writer. The holder fallback loses the process name in a timed-out outcome line.

## The fix

Each attempt gets its own directory, `%TEMP%\ahkflowapp-wt-remove-<RunId>\`, built by
`Get-RemovalRunTempDir` (`scripts/remove-worktree-local-dev.ps1:292`, "function Get-RemovalRunTempDir {").
It holds the watcher script, the param file, and both helper copies
(`scripts/remove-worktree-local-dev.ps1:973`, "Copy-Item -LiteralPath $logSource -Destination (Join-Path $runDir 'worktree-log.common.ps1') -Force -ErrorAction Stop").

`Remove-WatcherArtifacts` deletes the directory as one unit
(`scripts/remove-worktree-local-dev.ps1:1368`, "Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction Stop"),
after `Test-RemovalRunTempDirPath` confirms the path is a run directory in the temp root
(`scripts/remove-worktree-local-dev.ps1:1377`, "function Test-RemovalRunTempDirPath {").

`Get-RemovalTempDir` still means the temp root
(`scripts/remove-worktree-local-dev.ps1:282`, "function Get-RemovalTempDir {"). The shared outcome
log and the watcher's working directory both stay there.

## Two further findings

**The `catch` blocks around all three copies were dead.** The script runs with
`$ErrorActionPreference = 'Continue'`, and a failed `Copy-Item` raises a non-terminating error, so
none of them ever ran. The failure this item describes was silent, not logged, and a failed snapshot
of the watcher script let the hook spawn a script that was not there. All three copies now pass
`-ErrorAction Stop`.

**A `Win32_Process.Create` child does not inherit the caller's `TEMP`.** Measured on 2026-08-27. The
old deletion guard compared against the watcher's own `%TEMP%`, so a mismatch made it refuse every
cleanup. The param file now records the root the hook used, and the watcher reads it back.

## Acceptance criteria

- [x] The hook writes the watcher script, the param file, and both helper copies into a directory
      named after the run id under the system temp folder.
- [x] The watcher deletes that whole directory when it finishes, on every exit path that cleans up
      today. All eleven call sites still pass the same two paths; `Remove-WatcherArtifacts` derives
      the directory from them.
- [x] The deletion guard refuses a path whose parent is not the temp root it was given, and refuses
      a leaf name that does not match the generated pattern.
- [x] The watcher's current directory is never the directory it must delete.
- [x] A PowerShell test proves that a locked copy of a helper in the bare temp folder no longer
      makes the hook log a failed helper copy. Proved with a mutation: reverting the one line makes
      the test fail.
- [x] `pwsh ./scripts/run-powershell-suites.ps1` passes.

## Out of scope

- The shared outcome log at `%TEMP%\worktree-removal.log`. It stays at the temp root, because every
  attempt writes to that one file on purpose.
- Any change to what the watcher logs, or to the outcome wording.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/339
- This item was filed as 117 and renumbered to 118. A local unpushed branch,
  `fix/wt-removal-watcher-powershell-5`, already owns 117.
- That branch also changes `scripts/remove-worktree-local-dev.ps1`, for GitHub issue #348. It has
  not touched the script yet, so there is no conflict today. Whichever branch merges second rebases.
- Spec: none — the root cause and the fix are both stated in the issue, so this goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-08-27-worktree-removal-run-temp-dir-plan-118.md`
