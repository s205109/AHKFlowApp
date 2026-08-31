# 126 - Run the PowerShell suites in parallel

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Feature
- **Interfaces**: none (test runner scripts)
- **Difficulty**: complex
- **Stage**: 3-plan

## Summary

The 48 Windows PowerShell suites run one after another and take 618 seconds. This item runs
them in parallel from a committed manifest, and divides the slowest suite so that one file no
longer sets the floor for the whole run.

## User story

As a developer running the Gate before a pull request, I want the PowerShell suites to finish
in about 80 seconds instead of 618, so that running them stops being a reason to skip the Gate.

## Acceptance criteria

- [ ] `tests/powershell-suites.json` names all 49 suite files, each with `jobs`, `execution`,
      and `baselineSeconds`.
- [ ] The runner fails before it starts any child process when a suite file is missing from the
      manifest, when a manifest entry names no file, or when a metadata value is unknown.
- [ ] Every `execution: exclusive` entry carries a non-empty `reason`, and a test fails an entry
      that does not.
- [ ] A test fails when the manifest's `invariants` set and the suite list in
      `scripts/ci/check-repo-invariants.ps1` disagree.
- [ ] `scripts/run-powershell-suites.ps1` declares `#Requires -Version 7.0`.
- [ ] The runner takes no `-Profile` parameter. With no selection argument it runs every suite
      whose `jobs` contains `suites`.
- [ ] `-Suite <wildcard[]>` selects a subset. An unmatched wildcard fails, and no successful run
      reports zero suites.
- [ ] `-MaxParallel` defaults to the processor count capped at eight, and an environment
      variable overrides that default.
- [ ] A suite marked `exclusive` never runs at the same time as another suite.
- [ ] Each suite's output prints as one block after that suite ends. The output of two suites
      never interleaves.
- [ ] Every selected suite runs, including after another suite fails or cannot start.
- [ ] The runner writes the timings file once, after every selected suite has ended.
- [ ] `tests/WorktreeMergedCleanup.Tests.ps1` is three files, and none of the three takes more
      than 60 seconds.
- [ ] A parallel run of every suite takes no more than 25% of the wall clock that the same
      selection takes at `-MaxParallel 1`, measured on one machine in one session.
- [ ] A parallel run and a `-MaxParallel 1` run select the same suites and reach the same
      verdict.
- [ ] `scripts/progress.parallel.ps1` declares `#Requires -Version 7.0`, and both
      `scripts/progress.common.ps1` and `scripts/test-fast.ps1` still declare
      `#Requires -Version 5.1`.

## Out of scope

- Suite ownership and an `owner` field. Wave 2 extracts the reusable repositories, and
  ownership belongs to that work.
- Named profiles. One selection is left, so the runner needs no profile name for it.
- Dividing `tests/CitationFreshness.Tests.ps1`.
- Removing the second run of the five invariant suites. Backlog 127 owns that question.
- Making `scripts/ci/check-repo-invariants.ps1` call this runner. Backlog 127 owns it, because
  that job runs on Linux and the runner cannot run there yet.
- Any change to `.github/workflows/ci.yml`. The job calls the runner with no arguments, which
  still means every suite.
- Which PowerShell version the production worktree and hook scripts support.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-31-powershell-suite-performance-design-126.md`
- Plan: none — Stage 3 writes it, and this line then names the file.
- The recorded sequential baseline is 617.9 seconds across 48 suites. The per-suite numbers are
  preserved in the spec's appendix, because worktree result folders are temporary.
- A parallel run ends when the slowest suite ends, not when the work is done.
  `tests/WorktreeMergedCleanup.Tests.ps1` takes 125.6 seconds, so it sets the floor for the
  whole run until it is divided.
- That suite has 2149 lines and builds 58 temporary git repositories. Four repositories are in
  the pure-function group, 13 in the merge-proof group, and 41 in the eligibility group.
  Cutting the eligibility group in half gives three files of about 37, 43, and 45 seconds.
- Simulated against the recorded baseline at eight workers: no split 125.6s, two files 88.8s,
  three files 78.8s, four files 78.8s. The work-limited floor at eight workers is 77.2 seconds,
  so a fourth file gains nothing. After the split the slowest suite is
  `tests/CitationFreshness.Tests.ps1` at 78.8 seconds, which becomes the new floor.
- Saving the timings once, after every suite ends, is what keeps an existing assertion true. It
  reads the real timings file's last-write time and requires the parent runner not to change it
  (`tests/CiPowerShellSuiteRunner.Tests.ps1:167`, "    $timingsPath = Join-Path $repoRoot 'TestResults\progress\run-powershell-suites.json'").
- One comment claims that sequential execution protects a lock on a fixed name in the shared
  `%TEMP%` folder
  (`tests/WorktreeRemoveHook.Tests.ps1:615`, "# scripts/run-powershell-suites.ps1 runs suites one after another, so this lock on a file in the").
  Backlog 118 moved the hook off that shared name, so test the claim before marking the suite
  `exclusive`.
- A scan of all 49 suites found no writes to global git configuration, no process kills by
  name, and no machine-level environment writes. The port strings in
  `tests/AgentWorktreeGuard.Tests.ps1`, `tests/WorktreeJsonEdit.Tests.ps1`, and
  `tests/WorktreeLocalDevSetup.Tests.ps1` are text comparisons, not listening sockets.
- The runner cannot run on Linux today. Two paths use a backslash, which is an ordinary
  character in a Linux file name
  (`scripts/run-powershell-suites.ps1:40`, ". "$PSScriptRoot\progress.common.ps1"") and
  (`scripts/progress.common.ps1:99`, "    return (Join-Path (Join-Path $RepoRoot 'TestResults\progress') "$RunnerKey.json")").
  Backlog 127 owns both.
- The runner takes no `-Profile` parameter because **Profile** is an app term
  (`CONTEXT.md:104`, "**Profile**:"), and `dotnet run --launch-profile` is a second meaning
  already in use.
- `CONTEXT.md` has no entry for **Suite**. Add one: a `tests/*.Tests.ps1` file that runs as its
  own process.
