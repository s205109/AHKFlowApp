# 214 - run-coverage.ps1 fails in Windows PowerShell 5.1

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (`scripts/run-coverage.ps1`, `scripts/test-sql-container.common.ps1`)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

`scripts/run-coverage.ps1` declares `#Requires -Version 5.1`, but Windows PowerShell 5.1 cannot run
it. This item makes the script run to the end in 5.1, and keeps the `#Requires` line as it is.

GitHub issue #488 reported one cause. A run on 2026-11-18 found a second cause further on.

1. Two `Join-Path` calls pass three path arguments, which only PowerShell 7 accepts. 5.1 stops at
   startup with `A positional parameter cannot be found that accepts argument 'ci'.`
   (`PositionalParameterNotFound`). Commit `4233e9b7` on this branch already fixes both calls.
2. With that fixed, the run stops at the SQL container step. `scripts/test-sql-container.common.ps1:118`
   runs `$output = & docker inspect $ContainerName 2>&1`. When no test SQL container exists yet,
   docker writes `Error: No such object: <name>` to stderr and exits 1. The script runs with
   `$ErrorActionPreference = 'Stop'`. Windows PowerShell 5.1 turns a redirected stderr line into an
   error record, and `Stop` makes that error terminate the script. PowerShell 7 does not do this.
   The log line is
   `docker.exe : Error: No such object: ahkflowapp_chore_wt_backlog_housekeeping_5b27d54c-testsql`.
   The comment above that line says the 5.1 case is harmless. That is not true.

The same module also runs `docker ... 2>&1` at lines 233, 306, 495 and 508. Each of those can stop
a 5.1 run the same way whenever docker writes to stderr.

## User story

As a developer who runs the coverage script from Windows PowerShell 5.1, I want it to run to the
end, so that the `#Requires -Version 5.1` line tells the truth.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] `powershell.exe -NoProfile -File scripts/run-coverage.ps1` runs to the end in Windows
      PowerShell 5.1 on a checkout that has no test SQL container yet. It prints
      `Coverage run complete.` and exits 0.
- [ ] `scripts/run-coverage.ps1` still declares `#Requires -Version 5.1`.
- [ ] In `scripts/test-sql-container.common.ps1`, a `docker` call that writes to stderr does not
      stop a Windows PowerShell 5.1 run while `$ErrorActionPreference` is `Stop`. A PowerShell
      suite shows this by running the module under `powershell.exe` against a docker stub that
      writes to stderr.
- [ ] `pwsh .\scripts\test-fast.ps1 -Mode Coverage` still passes under PowerShell 7.

## Out of scope

- Other scripts that declare `#Requires -Version 5.1`. `scripts/test-fast.ps1` loads the same SQL
  container module, so the module fix helps it too. This item does not promise that every
  `test-fast.ps1` mode runs to the end in 5.1.
- Changing the `#Requires` line to PowerShell 7. Issue #488 offered that as the other fix. The
  files that `run-coverage.ps1` loads say they target 5.1 on purpose, so this item keeps 5.1.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/488
- The first fix started in the housekeeping round as commit `8602ff3c`. The SQL container cause
  made it a two-file change, so it left the round and moved here as `4233e9b7`.
- `tests/CoverageRunnerProgress.Tests.ps1:30` starts `run-coverage.ps1` with the same host that runs
  the suite, and that suite declares `#Requires -Version 7.0`. So no existing test runs the script
  in 5.1.
- Spec: none — `moderate` item. The root cause is known, and there is no design question.
- Plan: `docs/superpowers/plans/2026-11-18-run-coverage-in-windows-powershell-5-1-plan-214.md`
- A third 5.1 cause turned up while the plan was written. `ConvertFrom-Json` in 5.1 returns the
  `docker inspect` array as one object, so `Get-AhkFlowTestSqlContainerState` reads every field as
  empty. The ownership check then refuses the checkout's own container. Plan Task 2 fixes it.
