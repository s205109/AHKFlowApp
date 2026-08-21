# 073 - Process wave 3 - cleanup UX

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts)
- **Difficulty**: complex
- **Stage**: 3-plan
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

Wave 3 of the development process. Cleanup is the stage that interrupts the human most
often: a terminal window opens, the log is hard to read, and a removal fails without
saying which process holds the folder. This wave fixes the cleanup experience.

## User story

As a contributor, I want worktree cleanup to run quietly and explain its own failures so
that a merged branch never leaves me a popup to dismiss.

## Acceptance criteria

- [ ] Worktree removal opens no terminal window when WMI startup information is available,
      which is every removal on a healthy Windows install. The two degraded paths that can
      still flash a window each log that they took it. See "Criterion 1, and how far it
      goes" below.
- [ ] The removal log is readable: one line per attempt, the outcome named in plain words.
      Every path that decides about a worktree writes that line, including a sweep that
      refuses one without ever starting the removal script.
- [ ] When a removal fails because a process holds the folder, the log names that process.
      Both kinds of holder count: a process with the folder as its current directory, and a
      process with a file open below the folder.
- [ ] A guard refuses to remove a worktree whose plan was never implemented, and says so.
      A worktree created before this change records no item number, so the guard cannot
      judge it and allows the removal. That exception is named here on purpose.
- [ ] The merged-cleanup sweep honors `git worktree lock` and skips a locked worktree. The
      detached watcher honors it too, including a lock added while it is already waiting.

## Out of scope

- Parity check and drift guard — wave 2 (backlog 072).
- CI routing — wave 4 (backlog 074).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §13
  (private plans repo).
- Design: `docs/superpowers/specs/2026-08-21-cleanup-ux-design-073.md` (private plans repo).
- Plan: `docs/superpowers/plans/2026-08-21-cleanup-ux-plan-073.md`
- The sweep deletes the worktree folder directly today
  (`scripts/remove-worktree-local-dev.ps1`), so a git-level lock alone protects nothing.
  Proved on 2026-08-21 in a scratch repository: `git worktree remove` exits 128 on a locked
  worktree, and `[System.IO.Directory]::Move` on the same folder succeeds.
- The fix is not to read the lock file. Two worktrees whose folders share a basename get
  administrative names `shared` and `shared1`, so a path built from the folder name reads
  the wrong worktree's lock — measured in the same probe. And a read-then-act check races a
  human who locks during the watcher's 300-second wait. Instead the rename becomes
  `git worktree move`, which git refuses on a locked worktree at the moment of the
  operation: `fatal: cannot move a locked working tree`. Verified: it moves a dirty
  worktree, updates git's registry, and `prune -v` cleans up after the delete.
- Target: cleanup popups and blocked runs drop to zero. That is a direction, not a
  percentage: backlog 072 has no established baseline yet.

### Criterion 1, and how far it goes

Backlog 088 shipped it. `New-HiddenProcessStartup` passes `ShowWindow = 0` to
`Win32_Process.Create`, and `tests/WorktreeWatcherWindow.Tests.ps1` covers it. This item
adds no code for that criterion; it runs that test and ticks the narrowed box above.

The criterion was narrowed because the original wording claimed more than the code delivers.
Two paths can still show a window, and both already say so in the log:

- `New-HiddenProcessStartup` returns `$null` when the CIM class is unavailable, and the
  caller then logs "the watcher window may flash".
- When the WMI spawn fails, the script falls back to `Start-Process -WindowStyle Hidden`,
  which hides the window only after the host starts.

The existing test covers the successful WMI path only. Ticking the original wording would
have been a false tick.

### Scope this design widens, deliberately

- The acceptance criterion names only the merged-cleanup sweep for `git worktree lock`. The
  detached watcher deletes folders the same way, so it honors the lock too. Fixing one of
  two identical holes would leave the hole open.
- The diagnostics file the log split creates is capped at 5 MB, keeping one old generation.
  No criterion asks for that. Replacing one file that grows forever with another one is not
  an improvement.
- `AHKFLOW_WORKTREE_FORCE_REMOVE=1` clears the new plan guard and does **not** clear a lock.
  A lock is aimed at one worktree by a human on purpose, and git itself demands
  `remove -f -f` for one.
- `scripts/.env.worktree` gains one key, `AHKFLOW_BACKLOG_ITEM`. Without a recorded item
  number the plan guard has to guess from the folder name, and that guess already misses:
  `wt-recall-sample-was-drawn-without-9d48aac4` has no item with that slug. The manifest
  guard ignores keys it does not know, so adding one changes nothing else.
- The removal log's append becomes reliable rather than best-effort: it retries on a sharing
  violation, rotation takes a cross-process mutex, and a write that still fails falls back
  to stderr and `%TEMP%`. Today a failed append is swallowed. That was survivable across
  twenty lines and is not survivable when one line is the whole record.
- The holder probe reads open-file holders through the Restart Manager API as well as
  current-directory holders. The criterion says "the log names that process", and an editor
  holding a file below the worktree is that process just as often.
