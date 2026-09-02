# 126 - Run the PowerShell suites in parallel

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Feature
- **Interfaces**: none (test runner scripts)
- **Difficulty**: complex
- **Stage**: 9-ship

## Summary

The 48 Windows PowerShell suites run one after another and take 618 seconds. This item runs
them in parallel from a committed manifest, and divides the slowest suite so that one file no
longer sets the floor for the whole run.

## User story

As a developer running the Gate before a pull request, I want the PowerShell suites to finish
in about 80 seconds instead of 618, so that running them stops being a reason to skip the Gate.

## Acceptance criteria

- [x] `tests/powershell-suites.json` holds one entry for every `tests/*.Tests.ps1` file in the
      repository, each with `jobs`, `execution`, and `baselineSeconds`. The criterion is
      one-to-one against what the runner discovers, never a fixed count: this item divides one
      suite into three and adds a tracker suite, so the total moves from 49 to 52.
- [x] Every discovered suite file appears in the manifest exactly once, and no two entries share
      a `name`.
- [x] The runner fails before it starts any child process when a suite file is missing from the
      manifest, when a manifest entry names no file, or when a metadata value is unknown.
- [x] `baselineSeconds` is either `null` or a finite number greater than zero. Zero, a negative
      number, `NaN`, and infinity each fail the manifest.
- [x] Every `execution: exclusive` entry carries a non-empty `reason`, and a test fails an entry
      that does not.
- [x] A test fails when the manifest's `invariants` set and the suite list in
      `scripts/ci/check-repo-invariants.ps1` disagree.
- [x] `scripts/run-powershell-suites.ps1` declares `#Requires -Version 7.0`.
- [x] The runner takes no `-Profile` parameter. With no selection argument it runs every suite
      whose `jobs` contains `suites`.
- [x] `-Suite <wildcard[]>` selects a subset. An unmatched wildcard fails, and no successful run
      reports zero suites.
- [x] `-MaxParallel` defaults to the processor count capped at eight.
      `AHKFLOW_SUITE_MAX_PARALLEL` overrides that default. An explicit `-MaxParallel` wins over
      the variable, and the variable wins over the default.
- [x] An unset or blank `AHKFLOW_SUITE_MAX_PARALLEL` is ignored, and the default applies. A
      value that is not a whole number, or is below one, fails the run with a message that names
      the variable and the value. A misconfigured worker count must not run silently at the
      default.
- [x] A targeted `-Suite` run keeps the timing history of every suite it did not select.
- [x] A suite marked `exclusive` never runs at the same time as another suite.
- [x] Each suite's output prints as one block after that suite ends. The output of two suites
      never interleaves.
- [x] Every selected suite runs, including after another suite fails or cannot start.
- [x] The runner writes the timings file once, after every selected suite has ended.
- [x] `tests/WorktreeMergedCleanup.Tests.ps1` is three files, and none of the three takes more
      than 60 seconds.
- [ ] A parallel run of every suite takes no more than 25% of the wall clock that the same
      selection takes at `-MaxParallel 1`, measured on one machine in one session.
      **Not met: 171.2 of 620.4 seconds is 27.6%.** The suites contend for the disk, so the
      slowest one stretches from 78.8 seconds alone to 169.4 inside the run. See the measurement
      under `## Notes / dependencies`.
- [x] A parallel run and a `-MaxParallel 1` run select the same suites and reach the same
      verdict.
- [x] `scripts/progress.parallel.ps1` declares `#Requires -Version 7.0`, and both
      `scripts/progress.common.ps1` and `scripts/test-fast.ps1` still declare
      `#Requires -Version 5.1`.

## Out of scope

- Suite ownership and an `owner` field. Wave 2 extracts the reusable repositories, and
  ownership belongs to that work.
- Named profiles. One selection is left, so the runner needs no profile name for it.
- Dividing `tests/CitationFreshness.Tests.ps1`.
- Removing the second run of the five invariant suites. Backlog 127 owns that question.
- Making `scripts/ci/check-repo-invariants.ps1` call this runner. Backlog 127 owns it. That job
  runs on Linux, and nobody has run this runner on Linux, so the delegation belongs with the
  item that proves it works there.
- Any change to `.github/workflows/ci.yml`. The job calls the runner with no arguments, which
  still means every suite.
- Which PowerShell version the production worktree and hook scripts support.

## Notes / dependencies

- **Acceptance measurement, one machine, one session, 2026-09-01.** 16 processors, 8 workers,
  52 suite files, 51 of them in the `suites` job.
  - Sequential, `-MaxParallel 1`: **620.4 seconds**, all 51 passed.
  - Parallel, default workers: **171.2 seconds**, all 51 passed.
  - `pwsh .\scripts\test-fast.ps1 -Mode PowerShell`: **170.7 seconds**, all 51 passed.
  - Parallel is **27.6%** of sequential. The limit is 25%, so that one criterion is **not met**.
    The limit was not raised, and the box below stays unticked.
- **Why 27.6% and not the predicted 12.8%.** The prediction assumed each suite keeps its solo
  duration. It does not. Under eight workers the suites slow each other down, because they are
  bound by disk and by `git` child processes rather than by the processor.
  `tests/CitationFreshness.Tests.ps1` measures 78.8 seconds on its own and **169.4 seconds**
  inside the parallel run. The whole run took 171.2 seconds, so that one suite is the run.
  `tests/AgentWorktreeGuard.Tests.ps1` shows the same effect, 65.3 seconds alone against 147.9
  in the run.
- **The floor is `tests/CitationFreshness.Tests.ps1`.** Anyone who wants this faster has to make
  that suite faster, or reduce how much the suites contend for the disk. A different worker count
  cannot help: the run already equals its slowest suite. Dividing that suite is out of scope here.
- **The three divided files, measured on their own:** `WorktreeMergedCleanup.Tests.ps1` 19.0
  seconds, `WorktreeMergedCleanupEligibility.Tests.ps1` 53.5 seconds,
  `WorktreeMergedCleanupSweep.Tests.ps1` 49.9 seconds. All three are under the 60-second limit.
  The eligibility file first measured 66.1 seconds, so four whole sections moved into the sweep
  file. No section was split, and the 70 section headers are the same set before and after.
- **`tests/WatchTask.Tests.ps1` fails intermittently, and this item did not cause it.** The Gate's
  PowerShell step failed once on it. The failing assertion is always the same one, "Checkpoint
  replacement: changed output before the old offset must not be lost", and the text
  `REPLACEMENT-BEFORE-OLD-OFFSET` is always the part that goes missing.
  - This branch changes neither the suite nor the script it drives. `git log main..HEAD` over
    `tests/WatchTask.Tests.ps1` and `scripts/watch-task.ps1` is empty.
  - **A busy machine is what brings it out.** Counting every run made while investigating:
    - Idle machine, suite started on its own: **0 failures in 16 runs** — ten in this worktree
      and six from the main checkout.
    - Busy machine: **4 failures in 18 runs** — one in eight parallel runs, one in five runs
      beside ten synthetic load processes, and one in each of the two Gate runs.
  - So the defect is older than this item, but this item makes it show. Running the suites one
    after another left the machine quiet enough that it almost never appeared. Running them
    together does not.
  - Marking the suite `exclusive` does not fix it. That was tried for one measurement round and
    it still failed, so the marking was reverted rather than kept for a benefit it does not give.
  - Where the code points: `scripts/watch-task.ps1` reads the checkpoint bytes that decide
    whether the file was replaced (`scripts/watch-task.ps1:539`, "            $currentCheckpoint = Read-FileCheckpoint `"),
    and reads the file length afterwards (`scripts/watch-task.ps1:567`, "        $available = $stream.Length - $Reader.Offset").
    A writer that finishes between those two reads is missed: the checkpoint still looks
    unchanged, so the reader never goes back to the start, but the length is already full, so it
    reads the new tail and stops at the terminal marker. That matches every captured failure,
    but nobody has proved it by making the race happen on purpose.
  - Backlog 129 owns the defect, `backlog/129-watch-task-drops-output-under-load.md`. It is out
    of scope here.
- One section that this split moved unchanged failed once, with
  `fatal: failed to read .git/worktrees/wt-feat-done-forced/commondir`, and passed on two
  re-runs. It is a race between the cleanup child process and the `git branch --list` call that
  follows it. The section's text is the same as before the split, so this is not new.

- Spec: `docs/superpowers/specs/2026-08-31-powershell-suite-performance-design-126.md`
- Plan: `docs/superpowers/plans/2026-08-31-powershell-suite-performance-plan-126.md`
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
  (`tests/CiPowerShellSuiteRunner.Tests.ps1:308`, "    $timingsPath = Join-Path $repoRoot 'TestResults\progress\run-powershell-suites.json'").
- **Shared-resource audit, six categories, all 49 suites. No suite is exclusive.**
  1. *A fixed file or folder in the shared temp directory.* One hit,
     `tests/CoverageInputCompleteness.Tests.ps1`
     (`tests/CoverageInputCompleteness.Tests.ps1:187`, "    $standInRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'ahkflow-coverage-root-check'").
     The path is only built and compared, and never created on disk, so two suites cannot meet
     there. The suite stays `parallel`.
  2. *A fixed port or a listening socket.* No hit opens a socket. Every hit is a port number
     inside text that a case compares, in `tests/AgentWorktreeGuard.Tests.ps1`,
     `tests/WorktreeJsonEdit.Tests.ps1`, and `tests/WorktreeLocalDevSetup.Tests.ps1`. The
     `Start-Job` hits in `tests/WatchTask.Tests.ps1` and `tests/WorktreeRemovalLog.Tests.ps1`
     start child jobs that write into their own fixture folders.
  3. *Killing a process by name.* No hit.
  4. *Writes into the real repository.* No hit.
  5. *Machine-level environment or global git configuration.* No hit.
  6. *A lock whose safety depends on suite order.* One hit, the comment in
     `tests/WorktreeRemoveHook.Tests.ps1`. The claim was stale, and the audit corrected it. The
     hook now copies both helpers into a per-run directory
     (`scripts/remove-worktree-local-dev.ps1:1040`, "            Copy-Item -LiteralPath $logSource -Destination (Join-Path $runDir 'worktree-log.common.ps1') -Force -ErrorAction Stop"),
     so the lock on the shared name collides with nothing. No other suite writes those two
     names: every other file that mentions them reads the repository's own `scripts/` folder,
     or copies one into its own fixture. The comment now says that
     (`tests/WorktreeRemoveHook.Tests.ps1:616`, "# This lock is on a file in the shared %TEMP%, and it collides with nothing. Backlog 118 moved the").
     The suite stays `parallel`.
- `Save-ProgressTimings` used to rebuild the store from the units one run completed and then
  replace the file whole. A tracker starts with no completed units
  (`scripts/progress.common.ps1:178`, "        Completed    = [ordered]@{}"), so a one-suite
  `-Suite` run would have deleted every other suite's history. It now merges into the store it
  read at start (`scripts/progress.common.ps1:327`, "    $payload = [ordered]@{}"). The merging
  save is the one change this item makes to that 5.1 module, and it stays inside 5.1.
- Nobody has ever run the runner on Linux, so whether it works there is unknown. An earlier
  draft of this item claimed that two backslash paths stop it from starting. That claim was
  wrong. Microsoft documents the opposite: "Paths given to cmdlets are now slash-agnostic (both
  `/` and `\` work as directory separators)". See
  [PowerShell differences on non-Windows platforms](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support?view=powershell-7.6#filesystem-support-for-linux-and-macos).
  Backlog 127 runs it on Linux and fixes whatever actually fails.
- The runner takes no `-Profile` parameter because **Profile** is an app term
  (`CONTEXT.md:104`, "**Profile**:"), and `dotnet run --launch-profile` is a second meaning
  already in use.
- `CONTEXT.md` has no entry for **Suite**. Add one: a `tests/*.Tests.ps1` file that runs as its
  own process.
