# 216 - Suite flake: WorktreeRemoveHook locked-helper case misses 'Watcher spawned'

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (`tests/WorktreeRemoveHook.Tests.ps1`)
- **Difficulty**: moderate
- **Stage**: 1-pickup
- **Issue**: #491

## Summary

The PowerShell suite `tests/WorktreeRemoveHook.Tests.ps1` failed once on CI and passed when the
job ran again. The suite reads the watcher's diagnostics log while the watcher is still writing
to it. `Get-Content -Raw` then returns an array instead of one string, and `Assert-True` rejects
the result of `-match`. This is the recurrence that blocked backlog 068 has waited for.

## User story

As a developer, I want this suite to pass every time the hook works, so that a red CI run means
a real problem.

## Detail

- It failed in CI run 43973543752, attempt 1, job 133671949721 (`powershell-suites`), on the
  `windows-latest` runner. Attempt 2 passed.
- The branch was PR #486. It changed no file that this suite uses.
- The case starts at (`tests/WorktreeRemoveHook.Tests.ps1:640`, "# --- Test: a locked helper in the shared temp folder no longer breaks the copy ----").

Issue #491 says the log did not hold "Watcher spawned". That is wrong. The job log shows the
real error, and the value it prints holds "Watcher spawned via WMI. PID=2176":

```text
Exception: D:\a\AHKFlowApp\AHKFlowApp\tests\WorktreeRemoveHook.Tests.ps1:34
     | Assert-True needs a boolean. Got [System.Object[]] with 1 value(s) from line 680: 2026-11-16 22:53:18
     | wt-feat-locked-helper  [hook-20261116225317-ede3bd]
     ...
     | --porcelain: exit=0 2026-11-16 22:53:20  wt-feat-locked-helper  [hook-20261116225317-ede3bd] Watcher spawned via
     | WMI. PID=2176
     ...
     | [hook-20261116225317-ede3bd] Watcher started. PID=2176
     | Worktree=C:\Users\runneradmin\AppData\Local\Temp\wtremove-6dfa0ef6\wt-feat-locked-helper
     | Branch=feat-locked-helper Timeout=300s . Original message: Expected the hook to reach the spawn. Log: 2026-11-16
```

## Root cause

The test reads the diagnostics log while the watcher still appends to it. `Get-Content -Raw`
then returns more than one string, so `-match` returns an array instead of a boolean.

1. The test waits until the worktree folder is gone (`tests/WorktreeRemoveHook.Tests.ps1:673`, "$removed = Wait-ForCondition { -not (Test-Path -LiteralPath $wtPath) }").
2. The folder disappears when the watcher renames it with `git worktree move` (`scripts/remove-worktree-local-dev.ps1:1255`, "'worktree', 'move', $worktreeFull, $tempName").
3. The watcher keeps logging after that rename. The next line is (`scripts/remove-worktree-local-dev.ps1:1258`, "git worktree move succeeded"). The delete, the branch cleanup and "Watcher done" follow.
4. So the test reads the log while it grows (`tests/WorktreeRemoveHook.Tests.ps1:676`, "$diagnostics = Get-Content -Raw -LiteralPath (Get-RemovalDiagnosticsPath $repo)").
5. While another process appends to a file, `Get-Content -Raw` on it can return more than one string. The repro below shows this. So `$diagnostics` becomes an array. The repro proves the behaviour only. Nobody has read the `Get-Content` source to name the exact step.
6. `-match` on an array returns the matching elements, not `$true` (`tests/WorktreeRemoveHook.Tests.ps1:680`, "Assert-True ($diagnostics -match 'Watcher spawned')").
7. `Assert-True` refuses any value that is not a boolean (`tests/WorktreeRemoveHook.Tests.ps1:31`, "if ($Condition -isnot [bool]) {").

The CI value fits this. The one matching element ends right after "Watcher started", the line
before the rename. The rest of the log was in a second element, which did not match.

**Reproduced on 2026-11-22.** One process appended a line to a file in a tight loop. A second
process ran `Get-Content -Raw` on the same file 2000 times and counted results that were not a
`[string]`:

```text
Host 7.6.10: 1076 of 2000 reads returned a non-string (largest count 3).
Host 5.1.26100.9818: 1565 of 2000 reads returned a non-string (largest count 3).
```

The core of the probe:

```powershell
# In a second process: while ($true) { [System.IO.File]::AppendAllText($file, "line`r`n") }
$value = Get-Content -Raw -LiteralPath $file
$value -isnot [string]   # True on 54% to 78% of reads while the file grows
```

Thirteen other lines in this suite read a log with `Get-Content -Raw`, at lines 225, 226, 297,
414, 471, 517, 536, 556, 575, 585, 630, 705 and 797. Some of them may read while the watcher
still writes. The plan decides which ones need the same fix.

## Acceptance criteria

- [ ] No `-match` in `tests/WorktreeRemoveHook.Tests.ps1` runs on a log value that can be an array.
- [ ] The locked-helper case still fails when the diagnostics log has no "Watcher spawned" line.
- [ ] A test reads a file that another process appends to, and the suite's log read returns one string every time.
- [ ] Backlog 068 is in `backlog/done/`, and its two open boxes are ticked or carry a reason.

## Out of scope

- The watcher itself. It logs correctly; only the test reads too early.
- Other suites that read a growing file. File each one as its own item.

## Notes / dependencies

- Backlog 068 (`backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md`)
  waits for exactly this failure. Its flake A ruled the array out because `Get-Content -Raw`
  "returns one string for one file". The repro above shows that this is false while the file
  grows. This item does the work 068 asks for, and closes 068 in the same pull request.
- GitHub issue #491 holds the first report. Its cause line is wrong, as the Detail section says.
- The suite runs on Windows only, in the `suites` job (`tests/powershell-suites.json:69`, "WorktreeRemoveHook.Tests.ps1").
- Backlog 118 and GitHub issue #339 added the locked-helper case.
- Spec: none — moderate item, the root cause above is the design input.
- Plan: <path, or "none — reason">
