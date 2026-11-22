# 216 - Suite flake: WorktreeRemoveHook locked-helper case misses 'Watcher spawned'

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (`tests/WorktreeRemoveHook.Tests.ps1`, `scripts/remove-worktree-local-dev.ps1`)
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup
- **Issue**: #491

## Summary

The PowerShell suite `tests/WorktreeRemoveHook.Tests.ps1` failed once on CI and passed when the
job ran again. The case "a locked helper in the shared temp folder no longer breaks the copy"
failed its check that the diagnostics log holds the line "Watcher spawned". The watcher did
remove the worktree, so the check before it passed. The root cause is not known yet.

## User story

As a developer, I want this suite to pass every time the hook works, so that a red CI run means
a real problem.

## Detail

- It failed in CI run 43973543752, attempt 1, on the `windows-latest` runner. Attempt 2 passed.
- The branch was PR #486. It changed no file that this suite uses.
- The case starts at (`tests/WorktreeRemoveHook.Tests.ps1:640`, "# --- Test: a locked helper in the shared temp folder no longer breaks the copy ----").
- The failing check is at (`tests/WorktreeRemoveHook.Tests.ps1:680`, "Assert-True ($diagnostics -match 'Watcher spawned')").

The failure message, as quoted in issue #491:

```text
Expected the hook to reach the spawn. Log: ...
[hook-20261116225317-ede3bd] Watcher started. PID=2176
Worktree=C:\Users\runneradmin\AppData\Local\Temp\wtremove-6dfa0ef6\wt-feat-locked-helper
Branch=feat-locked-helper Timeout=300s
```

The hook writes "Watcher spawned" after it starts the watcher, at
(`scripts/remove-worktree-local-dev.ps1:1107`, "Watcher spawned via WMI. PID=").
The watcher writes "Watcher started" as its first line, at
(`scripts/remove-worktree-local-dev.ps1:1196`, "Watcher started. PID=$PID Worktree=").
So the watcher's line reached the log, and the hook's line did not, or not yet.

## Acceptance criteria

- [ ] The item states the root cause, with `file:line` evidence or a log line.
- [ ] The locked-helper case in `tests/WorktreeRemoveHook.Tests.ps1` passes in 20 repeated local runs in a row.
- [ ] The locked-helper case still fails when the hook never reaches the spawn.

## Out of scope

- Other cases in `tests/WorktreeRemoveHook.Tests.ps1`, unless the same root cause affects them.
- Other flaky suites. File each one as its own item.

## Notes / dependencies

- GitHub issue #491 holds the first report.
- The suite runs on Windows only, in the `suites` job (`tests/powershell-suites.json:69`, "WorktreeRemoveHook.Tests.ps1").
- Backlog 118 and GitHub issue #339 added this case.
- Spec: <path, or "none — reason">
- Plan: <path, or "none — reason">
