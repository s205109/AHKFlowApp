# 123 - Watch a long run live with a progress estimate

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 0-intake

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

- [ ] `scripts/watch-task.ps1` exists and takes no required arguments.
- [ ] Run with no arguments, it tails the newest still-running task output file for this
      repository, including files that belong to any of the repository's worktrees.
- [ ] It decides that a task is still running by the absence of a trailing
      `[exited with code` line, and needs no state of its own to do so.
- [ ] It stops on its own when that line appears, and prints the exit code as its last line.
- [ ] With no running task, it prints the newest finished task's last lines, its exit code, and
      its path, and exits 0.
- [ ] With more than one running task, it tails the newest and prints one line naming how many
      others are running.
- [ ] `-List` prints the recent tasks with their state, age, and index. `-Index` selects one.
- [ ] `-Root` points the script at another search root, so a test can build a fake tree.
- [ ] `scripts/progress.common.ps1` exposes functions to create a tracker over a named list of
      units, start a unit, stop a unit, and save the run's timings.
- [ ] Before each unit, the tracker prints one line carrying the unit's position, the unit's
      name, the elapsed time, and the estimated time left.
- [ ] The estimate comes from the previous run's per-unit seconds, read from
      `TestResults/progress/<runner key>.json`.
- [ ] A unit with no remembered time is left out of the estimate and counted in a note on the
      same line. When no unit has a remembered time, the line says the remaining time is
      unknown instead of printing a number.
- [ ] A unit records its seconds only when it finishes, so an interrupted run adds nothing.
- [ ] The timings file is written once, at the end of the run, through a temporary file that is
      then moved into place.
- [ ] `scripts/run-powershell-suites.ps1` prints a progress line per suite through that module.
- [ ] `scripts/test-fast.ps1` prints a progress line per test project through that module, and
      Fast mode and Integration mode keep separate remembered timings.
- [ ] `tests/WatchTask.Tests.ps1` covers the project-folder name mangling for a main checkout
      and for a worktree, running against finished detection, newest-running selection, and the
      case where nothing is running.
- [ ] `tests/Progress.Tests.ps1` covers the estimate with full, partial, and absent history, and
      the atomic save.
- [ ] `.claude/CLAUDE.md` says that a background command must let its output reach stdout, and
      that the agent hands over `pwsh ./scripts/watch-task.ps1` rather than a temporary path.

## Out of scope

- Any wrapper, tee, or redirection around the commands the agent runs. Nothing new goes in the
  output path. The task output file stays the single live log.
- A second copy of the log inside the repository. Task output files already survive the session,
  so the problem is finding them, not keeping them.
- Progress inside `scripts/run-coverage.ps1`. That is item 124.
- Any change to how the agent decides to run a command in the background.

## Notes / dependencies

- Follow-up: item 124 adds the same progress lines to `scripts/run-coverage.ps1`.
- `TestResults/` is already ignored by `.gitignore`, so the timings file never reaches a diff.
- `scripts/measure-tests.ps1` already writes timings to `TestResults/measure-tests/summary.json`.
  It is a separate profiling tool and this item does not change it.
- Spec: docs/superpowers/specs/2026-08-29-watch-long-runs-design-123.md
- Plan: <path, or "none — reason">
