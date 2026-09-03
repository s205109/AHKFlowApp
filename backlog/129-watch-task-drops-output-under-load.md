# 129 - Watch-task drops output under load

## Meta
- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: none (developer tooling)
- **Difficulty**: complex
- **Stage**: 3-plan

## Summary

`tests/WatchTask.Tests.ps1` fails on one assertion when the machine is busy. The failing
assertion is always the same one, and the same text is always the part that goes missing. The
defect is in `scripts/watch-task.ps1`, not in the test. Backlog 126 found it while running the
PowerShell suites in parallel, and left it out of scope.

## User story

As a developer running the Gate before a pull request, I want `tests/WatchTask.Tests.ps1` to pass
every time, so that a red gate always means my own change broke something.

## Acceptance criteria

- [ ] The race happens on purpose, driven by a test that makes the writer finish between the two
      reads. A test that only runs the suite under load does not count. It proves nothing when it
      passes.
- [ ] The root cause is stated with a `file:line` in `scripts/watch-task.ps1`. The reproduction
      test fails before the fix and passes after it.
- [ ] `tests/WatchTask.Tests.ps1` passes 20 times in a row while a full parallel suite run works
      beside it.
- [ ] The suite stays `parallel` in `tests/powershell-suites.json`. Marking it `exclusive` was
      tried during backlog 126 and did not help.

## Out of scope

- Making `scripts/watch-task.ps1` faster.
- Any change to the parallel suite runner from backlog 126.
- Deciding which tools or skills to use. The agent who picks this up does that research.

## Notes / dependencies

- **What fails.** The assertion "Checkpoint replacement: changed output before the old offset must
  not be lost". The text `REPLACEMENT-BEFORE-OLD-OFFSET` is always the part missing from the
  captured output.
- **When it fails.** Only on a busy machine. Counted during backlog 126:
  - Idle machine, suite started on its own: 0 failures in 16 runs.
  - Busy machine: 4 failures in 18 runs.
  - Two later runs beside a full parallel run: one failed, one passed. So the rate is not high.
- **The defect is older than backlog 126.** That branch changed neither
  `tests/WatchTask.Tests.ps1` nor `scripts/watch-task.ps1`. Running the suites at the same time is
  what makes the defect show, not what causes it.
- **Where the code points, unproven.** The watcher reads the checkpoint bytes that decide whether
  the file was replaced (`scripts/watch-task.ps1:596`, "            $currentCheckpoint = Read-FileCheckpoint `"),
  and reads the file length afterwards (`scripts/watch-task.ps1:573`, "            $available = $length - $Reader.Offset").
  A writer that finishes between those two reads is missed. The checkpoint still looks unchanged,
  so the reader never goes back to the start. The length is already full, so it reads the new tail
  and stops at the terminal marker. That matches every captured failure. Nobody has made the race
  happen on purpose, so treat it as a lead and not a conclusion.
- **20 runs under load, 2026-09-03.** `failed 0 of 20`, with 7 rounds of the full parallel suite
  run beside them. One load round, the first, reported `1 of 51 suite(s) failed`, and the suite was
  `CiPowerShellSuiteRunner.Tests.ps1`, not `WatchTask.Tests.ps1`. The one case that failed there is
  "A suite folder whose path contains an apostrophe still runs", and it reported an empty child
  output. That suite passed in the other 6 rounds and passes on its own, and this branch changes
  neither it nor the runner it tests. `WatchTask.Tests.ps1` passed in every load round as well.
- Found by backlog 126, `backlog/126-run-the-powershell-suites-in-parallel.md`.
- Plan: `docs/superpowers/plans/2026-09-02-watch-task-checkpoint-race-plan-129.md`
- **Design outcome, 2026-09-02.** The lead above was right, and a second, worse race sits beside
  it: the writer can also finish after the check and before the data read, which no reordering
  closes. Both races are now driven on purpose by tests, with no load and no sleep. The reader
  also has to stop re-reading its checkpoint from the file. Details in the spec and the plan.
