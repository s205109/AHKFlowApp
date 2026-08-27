# 117 - Give each worktree removal its own temp directory

## Metadata

- **Epic**: Worktree tooling
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 1-pickup

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

`Get-RemovalTempDir` returns the bare `%TEMP%` (`scripts/remove-worktree-local-dev.ps1:273`, "function Get-RemovalTempDir {").

The watcher script and the param file carry the run id in their names (`scripts/remove-worktree-local-dev.ps1:909`, "$watcherScript = Join-Path $tempDir").

The two helper copies do not:

- `worktree-log.common.ps1` (`scripts/remove-worktree-local-dev.ps1:927`, "Copy-Item -LiteralPath $logSource -Destination (Join-Path $tempDir 'worktree-log.common.ps1') -Force")
- `worktree-holder.common.ps1` (`scripts/remove-worktree-local-dev.ps1:939`, "Copy-Item -LiteralPath $holderSource -Destination (Join-Path $tempDir 'worktree-holder.common.ps1') -Force")

One merged-cleanup sweep starts several watchers at once. Each copies both helpers to the same
fixed path with `Copy-Item -Force`, while another watcher may hold the file open for dot-sourcing.
The copy then fails, the script catches and logs it, and that watcher degrades to its inline
fallback. The log fallback loses the retrying writer. The holder fallback loses the process name in
a timed-out outcome line.

## The fix the reviewer suggested

Give each attempt its own directory, `%TEMP%/ahkflowapp-wt-remove-<RunId>/`. It holds the watcher
script, the param file, and both helper copies. Delete the directory as one unit. That removes the
fixed-name coupling entirely.

This touches three places: the spawn path, the cleanup path, and `Test-GeneratedTempArtifactPath` (`scripts/remove-worktree-local-dev.ps1:1314`, "function Test-GeneratedTempArtifactPath {").

## Acceptance criteria

- [ ] The hook writes the watcher script, the param file, and both helper copies into a directory
      named after the run id under the system temp folder.
- [ ] The watcher deletes that whole directory when it finishes, on every exit path that cleans up
      today.
- [ ] The deletion guard refuses a path whose parent is not the system temp folder, and refuses a
      leaf name that does not match the generated pattern.
- [ ] The watcher's current directory is never the directory it must delete.
- [ ] A PowerShell test proves that two removal attempts get different helper copies.
- [ ] `pwsh ./scripts/run-powershell-suites.ps1` passes.

## Out of scope

- The shared outcome log at `%TEMP%\worktree-removal.log`. It stays at the temp root, because every
  attempt writes to that one file on purpose.
- Any change to what the watcher logs, or to the outcome wording.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/339
- Spec: none — the root cause and the fix are both stated in the issue, so this goes straight to Plan.
- Plan: <path, or "none — reason">
