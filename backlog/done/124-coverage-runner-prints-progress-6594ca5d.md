# 124 - Coverage runner prints progress and an estimate

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

`scripts/run-coverage.ps1` prints nothing that says how far along it is. It reuses the progress
module that item 123 adds, so a coverage run reports its position and an estimated time left.

## User story

As a developer, I want a coverage run to say which phase it is in and how much time is left, so
that I can tell a slow run from a stuck one.

## Background

Item 123 builds `scripts/progress.common.ps1` and wires it into
`scripts/run-powershell-suites.ps1` and `scripts/test-fast.ps1`. Those two runners have one
simple unit shape each: a suite file, and a test project.

`scripts/run-coverage.ps1` is different. Its units are not all the same kind. It runs a restore,
then a build, then a loop over the coverage projects, then reportgenerator. A mixed list of
phases and projects is a third unit shape, and it was kept out of item 123 on purpose, so the
shared module could prove itself against two shapes before it took on a third.

## Acceptance criteria

- [x] `scripts/run-coverage.ps1` prints a progress line before each of its units through
      `scripts/progress.common.ps1`.
      (`scripts/run-coverage.ps1:34`, "$PSScriptRoot\progress.common.ps1");
      (`scripts/run-coverage.ps1:68`, "Start-ProgressUnit -Tracker $progress -Name 'restore'");
      (`scripts/run-coverage.ps1:73`, "Start-ProgressUnit -Tracker $progress -Name 'build'");
      (`scripts/run-coverage.ps1:83`, "Start-ProgressUnit -Tracker $progress -Name 'sql container'");
      (`scripts/run-coverage.ps1:97`, "Start-ProgressUnit -Tracker $progress -Name $projectName");
      (`scripts/run-coverage.ps1:136`, "Start-ProgressUnit -Tracker $progress -Name 'report'")
- [x] Its unit list names the restore, the build, each coverage project, and the report step.
      (`scripts/run-coverage.ps1:65`, "$progressUnit = @('restore', 'build', 'sql container') + $expectedProjectName + @('report')").
      The list also names the SQL container start. See the note below.
- [x] Its remembered timings live under their own runner key, so they never mix with the keys
      that `scripts/test-fast.ps1` writes.
      (`scripts/run-coverage.ps1:66`, "New-ProgressTracker -RunnerKey 'run-coverage'");
      (`scripts/run-coverage.ps1:147`, "Save-ProgressTimings -Tracker $progress -KnownUnit $progressUnit");
      (`tests/CoverageRunnerProgress.Tests.ps1:355`, "Invoke-TestCase 'The coverage store never mixes with a test-fast store' {")
- [x] A coverage run started through `scripts/test-fast.ps1 -Mode Coverage` prints one progress
      sequence, not two nested ones.
      (`tests/CoverageRunnerProgress.Tests.ps1:429`, "Invoke-TestCase 'Coverage through test-fast prints one sequence, not two' {")
- [x] `tests/Progress.Tests.ps1`, or a suite beside it, covers a unit list that mixes fixed
      phase names with a project list read at run time.
      `tests/CoverageRunnerProgress.Tests.ps1` is that suite beside it.
      (`tests/CoverageRunnerProgress.Tests.ps1:55`, "$script:LeadingUnit = @('restore', 'build', 'sql container')");
      (`tests/CoverageRunnerProgress.Tests.ps1:312`, "Invoke-TestCase 'The project part of the unit list is read at run time' {")

## Out of scope

- Any change to what `scripts/run-coverage.ps1` measures or reports about coverage itself.
- Any change to the progress module's public functions. If this item needs one, that is a signal
  the module's shape is wrong, and the change belongs in a revision of item 123's design.

## Notes / dependencies

- Item 123 has shipped, so the module this item uses exists. The block is lifted.
- The unit list also carries the SQL container start, which the acceptance criteria do not name.
  The user asked for it on 2026-09-07. `Start-AhkFlowTestSqlContainer` pulls an image on a cold
  machine and then polls until SQL Server answers, with a 120 second timeout
  (`scripts/test-sql-container.common.ps1:86`, "[int]$TimeoutSeconds = 120"). Leaving that outside
  every unit makes the estimate read low by exactly the part a reader mistakes for a hang.
- `scripts/test-fast.ps1` still starts the same container before it creates its tracker, so the
  two runners now disagree about whether that time is measured. Left alone on purpose. No item
  covers it yet.
- The read of the coverage projects moved above the restore, because a tracker needs its whole
  unit list before the first unit runs
  (`scripts/run-coverage.ps1:56`, "$coverageProject = Get-AhkFlowCoverageProject -RepoRoot $repoRoot").
  A solution with nothing to measure now fails in seconds instead of after a restore, a build,
  and a container.
- The coverage run now loads `scripts/progress.common.ps1`, so that file joined the
  `coverage-tooling` list in `.github/code-paths-filter.yml`.
  `tests/CoverageSliceSkip.Tests.ps1` pins that list three ways, and all three moved with it.
- `scripts/test-results.common.ps1` is missing from the same list, and that gap predates this
  item. Filed separately as backlog 141.
- `tests/CoverageRunnerProgress.Tests.ps1` runs on Windows and on Linux. Both runs happened on
  2026-09-07; the Linux one used `mcr.microsoft.com/powershell:latest` with the worktree mounted.
- The suite was proved red before it was trusted. With every `Start-ProgressUnit` and
  `Stop-ProgressUnit` call commented out, eight of its ten cases failed. The two that stayed
  green cover failure paths that read no progress line.
- Spec: none — this item reuses the design written for item 123.
- Plan: docs/superpowers/plans/2026-09-06-coverage-runner-progress-plan-124.md
