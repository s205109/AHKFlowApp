# 145 - Lower the suite runner default worker count

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Feature
- **Interfaces**: none (test runner scripts)
- **Difficulty**: moderate
- **Stage**: 6-verify

## Summary

The suite runner starts eight suites at once on a machine with eight physical cores. A
measurement on 2026-09-07 shows that six at once finishes the same run in the same time. The
seventh and eighth workers add load to the machine and return nothing. This item lowers the
default to about 75% of the physical cores.

## User story

As a developer running the PowerShell suites on my laptop, I want the run to start only the
workers it can benefit from, so that the machine stays usable while the suites run.

## Acceptance criteria

Two decisions in this list changed during the grilling round on 2026-09-08. The default now
stops at eight workers, which the list below never asked for. And a run inside GitHub Actions
skips the 75% rule and uses every processor it has, which is how the seventh criterion is met.
Both are argued in full in the plan.

- [x] The default worker count is about 75% of the machine's physical cores, with a floor of
      one, and a new ceiling of eight. Before this item it was the logical processor count capped at eight, written as
      `$workerCount = [Math]::Min([Environment]::ProcessorCount, 8)` on line 123 of
      `scripts/run-powershell-suites.ps1`. That line no longer exists, so this record quotes it
      rather than citing it. <!-- citation-check:ignore -->
      Text quoted from commit e6821d86, the branch point for this work.
- [x] The count comes from physical cores, not from `[Environment]::ProcessorCount`. That
      property returns logical processors. On the measured machine it returns 16 for 8 physical
      cores, and 75% of 16 is 12, which is more than the old default. `Get-PhysicalCoreCount`
      reads the real number and the local run reports 8 physical of 16 logical.
- [ ] The runner reads the physical core count on Windows and on Linux, and a test covers both.
      The test is one case in `tests/SuiteRunnerLinux.Tests.ps1`, which the `suites` job runs on
      Windows and the `invariants` job runs on Linux. It passes on Windows locally. Ticked when
      the Linux job reports its count too.
- [x] A machine whose physical core count cannot be read still runs. The fallback is the logical
      processor count capped at eight, which is the rule this item replaced, and the reason is
      written into `Get-DefaultSuiteWorkerCount`. Three assertions cover the path.
- [x] `-MaxParallel` still wins over `AHKFLOW_SUITE_MAX_PARALLEL`, and the variable still wins
      over the default. The precedence does not change, and the variable is now proved to win on
      both sides of the GitHub Actions branch.
- [x] The `Workers:` line the run prints reports the count the run really used, and a test
      proves the printed number is the number the pool used. The test sizes a barrier at the
      printed number and compares it against the real peak overlap. The line now also names the
      reason for the number.
- [ ] The CI `powershell-suites` job is no slower than it is today, measured on one commit
      before and after. A run inside GitHub Actions takes every processor it has, which is what
      the job did before this item, so the count should not move. Ticked when the branch's own
      CI run reports `Workers: 4`, the same number as run 34206922028 on 2026-09-08.

## Out of scope

- Making any single suite faster. Backlog 126 named `tests/CitationFreshness.Tests.ps1` as the
  slowest, and that is still a separate question.
- Changing the longest-first order the schedule uses.
- Stopping two runs from overlapping. Backlog 146 owns that.
- Setting the priority class of the suite child processes.

## Notes / dependencies

- **Measurement, one machine, 2026-09-07.** Intel Core i9-11900H, 8 physical cores, 16 logical
  processors, 32 GB, NVMe SSD. 56 suites in the `suites` job on Windows, holding 716.7 seconds
  of solo work in total. Every run passed all 56 suites.

  | Workers | Priority | Defender exclusions | Wall clock |
  |---|---|---|---|
  | 8 | Normal | no | 197 s |
  | 4 | Normal | no | 265 s |
  | 8 | BelowNormal | no | 209 s |
  | 8 | Normal | yes | 180 s |
  | 8 | BelowNormal | yes | 163.1 s |
  | 6 | BelowNormal | yes | 160.7 s |

- **Six is not slower than eight.** The 2.4-second difference is inside run-to-run noise. What
  the pair shows is that the last two workers buy nothing.
- **Contention sets the limit, not the processor.** At six lanes the ideal is 119.5 seconds and
  the run takes 160.7, a factor of 1.35. At eight lanes the ideal is 89.6 seconds and the run
  takes 163.1, a factor of 1.8. The extra lanes wait on the disk and on process starts.
- **Backlog 126's floor no longer holds.** That item measured the run as equal to its slowest
  suite, 169.4 seconds of 171.2. In the eight-worker run above the slowest suite finished at
  36.5 seconds. The suite set has grown and rebalanced since, so any further tuning needs a
  fresh measurement rather than that number.
- **"75%" means physical cores. That is decided, not open.** 75% of the 8 physical cores is 6,
  and the measurement supports it. 75% of the 16 logical processors is 12, which is above
  today's default and which nothing here supports. The reading was confirmed on 2026-09-07. The
  second reading stays written down only so that nobody reopens the question.
- **The machine stayed usable.** A full run at six workers, at BelowNormal priority, with the
  Defender exclusions in place, gave one short pause over the whole run. Before this the laptop
  became hard to use while the suites ran. No stopwatch can measure that difference, so it is
  recorded here as the reason the item exists.
- Two runs at once, at 4 workers each, took 296.2 and 296.1 seconds and both passed. That is 8
  lanes in total, the same load as one run at today's default. It is the evidence behind
  backlog 146.
- Spec: none — the change is one default and the tests around it.
- Plan: `docs/superpowers/plans/2026-09-08-suite-runner-worker-default-plan-145.md`
