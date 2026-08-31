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
      (`scripts/watch-task.ps1:40`, "param(")
- [x] Run with no arguments, it tails the newest still-running task output file for this
      repository, including files that belong to any of the repository's worktrees.
      (`scripts/watch-task.ps1:1073`, "$running = @(");
      (`scripts/watch-task.ps1:99`, "function Get-RepositoryCheckoutPath").
      The mechanism changed during review —
      see the note under **Notes / dependencies**.
- [x] It decides that a task is still running when the file ends with neither
      `[exited with code N]` nor `[killed]`, and needs no state of its own to do so.
      (`scripts/watch-task.ps1:282`, "$lastNonEmpty -match $script:ExitMarker");
      (`scripts/watch-task.ps1:285`, "$lastNonEmpty -match $script:KilledMarker")
- [x] It stops on its own when a terminal marker is the file's last line. It prints the exit code
      or killed state as its last line. (`scripts/watch-task.ps1:938`, "if ($reader.AtEnd)");
      (`scripts/watch-task.ps1:952`, "-not $state.Running");
      (`scripts/watch-task.ps1:990`, "State: killed");
      (`scripts/watch-task.ps1:993`, "Exit code:")
- [x] With no running task, it prints the newest stopped task's last lines, path, and terminal
      state, and exits 0. (`scripts/watch-task.ps1:1075`, "if ($running.Count -eq 0)");
      (`scripts/watch-task.ps1:1080`, "Show-Tail -Path $newest.Path");
      (`scripts/watch-task.ps1:1087`, "Path:")
- [x] With more than one running task, it tails the newest and prints one line naming how many
      others are running. (`scripts/watch-task.ps1:1097`, "if ($running.Count -gt 1)")
- [x] `-List` prints the recent tasks with their state, age, and index. `-Index` selects one.
      (`scripts/watch-task.ps1:1042`, "if ($List)");
      (`scripts/watch-task.ps1:1065`, "if ($Index -gt 0)")
- [x] `-Root` points the script at another search root, so a test can build a fake tree.
      (`scripts/watch-task.ps1:1021`, "$searchRoot = if")
- [x] `scripts/progress.common.ps1` exposes functions to create a tracker over a named list of
      units, start a unit, stop a unit, and save the run's timings.
      (`scripts/progress.common.ps1:149`, "function New-ProgressTracker");
      (`scripts/progress.common.ps1:247`, "function Start-ProgressUnit");
      (`scripts/progress.common.ps1:260`, "function Stop-ProgressUnit");
      (`scripts/progress.common.ps1:274`, "function Save-ProgressTimings")
- [x] Before each unit, the tracker prints one line carrying the unit's position, the unit's
      name, the elapsed time, and the estimated time left.
      (`scripts/progress.common.ps1:257`, "Write-Host (Get-ProgressLine");
      (`scripts/progress.common.ps1:244`, "elapsed $elapsed")
- [x] The estimate comes from the previous run's per-unit seconds, read from
      `TestResults/progress/<runner key>.json`.
      (`scripts/progress.common.ps1:99`, "TestResults\progress")
- [x] A unit with no remembered time is left out of the estimate and counted in a note on the
      same line. When no unit has a remembered time, the line says the remaining time is
      unknown instead of printing a number.
      (`scripts/progress.common.ps1:209`, "$Tracker.History.Contains");
      (`scripts/progress.common.ps1:221`, "unknown$noHistoryNote")
- [x] A unit records its seconds only when it finishes, so an interrupted run adds nothing.
      (`scripts/progress.common.ps1:269`, "$Tracker.Completed")
- [x] The timings file is written once, at the end of the run, through a temporary file that is
      then moved into place. (`scripts/progress.common.ps1:302`, "Move-Item -LiteralPath $temp")
- [x] `scripts/run-powershell-suites.ps1` prints a progress line per suite through that module.
      (`scripts/run-powershell-suites.ps1:97`, "Start-ProgressUnit -Tracker $progress")
- [x] `scripts/test-fast.ps1` prints a progress line per test project through that module, and
      Fast mode and Integration mode keep separate remembered timings.
      (`scripts/test-fast.ps1:255`, "Start-ProgressUnit -Tracker $progress");
      (`scripts/test-fast.ps1:249`, "test-fast.$Mode")
- [x] `tests/WatchTask.Tests.ps1` covers the project-folder name mangling for a main checkout
      and for a worktree, running against finished detection, newest-running selection, and the
      case where nothing is running.
      (`tests/WatchTask.Tests.ps1:84`, "project folder name mangling");
      (`tests/WatchTask.Tests.ps1:254`, "Running versus finished detection");
      (`tests/WatchTask.Tests.ps1:322`, "Newest-running selection");
      (`tests/WatchTask.Tests.ps1:350`, "nothing-is-running path")
- [x] `tests/Progress.Tests.ps1` covers the estimate with full, partial, and absent history, and
      the atomic save. (`tests/Progress.Tests.ps1:58`, "estimate with full history");
      (`tests/Progress.Tests.ps1:75`, "estimate with partial history");
      (`tests/Progress.Tests.ps1:90`, "estimate with no history");
      (`tests/Progress.Tests.ps1:126`, "save writes through a temporary file")
- [x] `.claude/CLAUDE.md` says that a background command must let its output reach stdout, and
      that the agent hands over `pwsh ./scripts/watch-task.ps1` rather than a temporary path.
      (`.claude/CLAUDE.md:55`, "Watch a background run");
      (`.claude/CLAUDE.md:57`, "background command must let its output reach stdout");
      (`.claude/CLAUDE.md:59`, "pwsh ./scripts/watch-task.ps1")

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
- The final review found that `scripts/run-coverage.ps1` deleted all of `TestResults/`, including
  the new history store. Coverage cleanup now removes only its own inputs and report.
  (`scripts/run-coverage.ps1:47`, "Remove-AhkFlowCoverageArtifacts")
- The final review also added bounded log reads, terminal `[killed]` handling, a bounded failure
  path when a selected output file disappears, and object-only history parsing.
- A second independent review capped newline-free output at 1 MiB, made read retries consecutive,
  limited ReportGenerator to the cleaned coverage folder, and checked replacements at the last
  consumed offset. (`scripts/watch-task.ps1:63`, "$script:MaxTailTextBytes");
  (`scripts/run-coverage.ps1:116`, "$coverageResultsRoot/**/coverage.cobertura.xml")
- A third review found four more watcher defects, all now fixed. Two directories that mangle to
  one folder name no longer let either one claim it. The byte bound now caps a single line, not
  the whole initial tail. Output written while the terminal state is read is now printed. The
  unfinished last line now counts toward `-Tail` instead of arriving on top of it.
  (`scripts/watch-task.ps1:213`, "-ge $best");
  (`scripts/watch-task.ps1:690`, "$lineCapReached = $position");
  (`scripts/watch-task.ps1:814`, "$wantedLines = if");
  (`scripts/watch-task.ps1:965`, "while (-not $reader.AtEnd)")
- `TestResults/` is already ignored by `.gitignore`, so the timings file never reaches a diff.
- `scripts/measure-tests.ps1` already writes timings to `TestResults/measure-tests/summary.json`.
  It is a separate profiling tool and this item does not change it.
- Spec: docs/superpowers/specs/2026-08-29-watch-long-runs-design-123.md
- Plan: none — built directly from the design spec, which carries the full file list, function set, and test list
