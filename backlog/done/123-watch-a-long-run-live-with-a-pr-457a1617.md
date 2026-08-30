# 123 - Watch a long run live with a progress estimate

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

A human cannot watch a long background run that an agent started, because the log lives at a
path only the agent knows. One command finds the running task and tails it. The long test
runners also print how far along they are and how much time is left.

## User story

As a developer, I want one short command that shows me the live output of whatever long run is
going now, so that I can tell a working run from a hung one without asking the agent for a path.

## Background

Claude Code writes each background command's output to
`%LOCALAPPDATA%\Temp\claude\<mangled project path>\<session id>\tasks\<task id>.output`.
The session id is a new GUID for every session, and a git worktree gets its own project folder,
so the path changes constantly. Today the agent pastes that path into the chat. It is long, it
is easy to get wrong, and it is worthless once the session ends.

Two things went wrong on 2026-08-29, and both are fixed by this item:

- The path handed over pointed at a real file that held only `EXIT=1`, because the command had
  redirected its own output to a different file. The log the human was told to tail was empty.
- A second path handed over in the same message belonged to a different session, so it did not
  match the run at all.

## Acceptance criteria

- [x] `scripts/watch-task.ps1` exists and takes no required arguments.
      (`scripts/watch-task.ps1:40`, every parameter optional)
- [x] Run with no arguments, it tails the newest still-running task output file for this
      repository, including files that belong to any of the repository's worktrees.
      (`scripts/watch-task.ps1:724`, newest running record; `scripts/watch-task.ps1:94`,
      every checkout comes from `git worktree list`.) The mechanism changed during review —
      see the note under **Notes / dependencies**.
- [x] It decides that a task is still running by the absence of a trailing
      `[exited with code` line, and needs no state of its own to do so.
      (`scripts/watch-task.ps1:213`, `Get-TaskState` reads the file and nothing else)
- [x] It stops on its own when that line appears, and prints the exit code as its last line.
      (`scripts/watch-task.ps1:626`)
- [x] With no running task, it prints the newest finished task's last lines, its exit code, and
      its path, and exits 0. (`scripts/watch-task.ps1:726`)
- [x] With more than one running task, it tails the newest and prints one line naming how many
      others are running. (`scripts/watch-task.ps1:737`)
- [x] `-List` prints the recent tasks with their state, age, and index. `-Index` selects one.
      (`scripts/watch-task.ps1:701` and `scripts/watch-task.ps1:716`)
- [x] `-Root` points the script at another search root, so a test can build a fake tree.
      (`scripts/watch-task.ps1:680`)
- [x] `scripts/progress.common.ps1` exposes functions to create a tracker over a named list of
      units, start a unit, stop a unit, and save the run's timings.
      (`scripts/progress.common.ps1:145`, `:243`, `:256`, `:270`)
- [x] Before each unit, the tracker prints one line carrying the unit's position, the unit's
      name, the elapsed time, and the estimated time left.
      (`scripts/progress.common.ps1:253` prints; `scripts/progress.common.ps1:240` builds the line)
- [x] The estimate comes from the previous run's per-unit seconds, read from
      `TestResults/progress/<runner key>.json`. (`scripts/progress.common.ps1:99`)
- [x] A unit with no remembered time is left out of the estimate and counted in a note on the
      same line. When no unit has a remembered time, the line says the remaining time is
      unknown instead of printing a number. (`scripts/progress.common.ps1:205` counts the
      units with no history; `scripts/progress.common.ps1:216` prints `unknown`)
- [x] A unit records its seconds only when it finishes, so an interrupted run adds nothing.
      (`scripts/progress.common.ps1:263`)
- [x] The timings file is written once, at the end of the run, through a temporary file that is
      then moved into place. (`scripts/progress.common.ps1:296`)
- [x] `scripts/run-powershell-suites.ps1` prints a progress line per suite through that module.
      (`scripts/run-powershell-suites.ps1:97`)
- [x] `scripts/test-fast.ps1` prints a progress line per test project through that module, and
      Fast mode and Integration mode keep separate remembered timings.
      (`scripts/test-fast.ps1:255` prints per project; `scripts/test-fast.ps1:249` puts the
      mode in the runner key)
- [x] `tests/WatchTask.Tests.ps1` covers the project-folder name mangling for a main checkout
      and for a worktree, running against finished detection, newest-running selection, and the
      case where nothing is running. (`tests/WatchTask.Tests.ps1:74` and `:78` for the
      mangling, `:146` for detection, `:173` for newest-running, `:198` for nothing running)
- [x] `tests/Progress.Tests.ps1` covers the estimate with full, partial, and absent history, and
      the atomic save. (`tests/Progress.Tests.ps1:58`, `:75`, `:90`, `:126`)
- [x] `.claude/CLAUDE.md` says that a background command must let its output reach stdout, and
      that the agent hands over `pwsh ./scripts/watch-task.ps1` rather than a temporary path.
      (`.claude/CLAUDE.md:55`, section "Watch a background run")

## Out of scope

- Any wrapper, tee, or redirection around the commands the agent runs. Nothing new goes in the
  output path. The task output file stays the single live log.
- A second copy of the log inside the repository. Task output files already survive the session,
  so the problem is finding them, not keeping them.
- Progress inside `scripts/run-coverage.ps1`. That is item 124.
- Any change to how the agent decides to run a command in the background.

## Notes / dependencies

- How the script finds a worktree's files changed during review. The design looked up folders by
  globbing the mangled checkout name plus `*`. That glob also matched
  `C:\Dev\segocom-github\AHKFlowAppOLD`, which is a different repository. The script now asks git
  for every checkout, and a folder must be the mangled name or start with that name plus `-`. It
  also compares against the directories that sit beside each checkout, and refuses a folder that
  a neighbour claims more closely. The behaviour the item asked for is the same: a worktree's task
  output files are found.
- Follow-up: item 124 adds the same progress lines to `scripts/run-coverage.ps1`.
- `TestResults/` is already ignored by `.gitignore`, so the timings file never reaches a diff.
- `scripts/measure-tests.ps1` already writes timings to `TestResults/measure-tests/summary.json`.
  It is a separate profiling tool and this item does not change it.
- Spec: docs/superpowers/specs/2026-08-29-watch-long-runs-design-123.md
- Plan: none — built directly from the design spec, which carries the full file list, function set, and test list
