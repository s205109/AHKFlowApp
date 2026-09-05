# 128 - Improve .NET test speed and reliability
## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test projects)
- **Difficulty**: complex
- **Stage**: 8-review

## Summary

The .NET test projects have grown to roughly 277 test files and have never been reviewed
as a whole for speed or for reliability. This item asks for that review, and for the
improvements the review finds to be worth making.

## User story

As a developer running the test suites, I want them to finish quickly and to give the same
answer every time, so that a red run always means my change broke something.

## Acceptance criteria

The research is done. The numbers below come from the design, which records how each one was
measured and on what machine.

A run's time is its **median of five warm runs**, each after one solution build and each with
`-NoBuild`. Record every run and the maximum beside the median. One run is not evidence: the
measured Fast spread is 7.12 s.

Starting point, measured 2026-09-03: Fast median 33.88 s over five runs, Integration median
84.64 s over three, E2E median 299.80 s over two, plus a 10 s solution build. A developer's real
inner loop after a one-line edit measured 45 s: a 12 s incremental build, then 33 s of Fast. This
item does not improve the 12 s.

Both targets are provisional. Each is confirmed or replaced at its checkpoint, and a number that
moves takes its reason with it.

- [x] A written measurement exists for each test project: wall clock time, and the slowest
      tests inside it.
- [x] A written list exists of the tests that give a different answer on different runs, or
      a statement, backed by run counts, that none were found.
- [x] The Fast mode's median finishes in under 22 seconds, down from 33.88. Measured 2026-09-05
  after Tasks 1 and 2: median 15.68 s over five runs.
- [x] The Integration mode's median finishes in under 65 seconds, down from 84.64. Measured
  2026-09-05 after Task 4: median 49.59 s over five runs. D3, the shared API host, was declined
  by the human at the Integration checkpoint: the target was already met without it, and its
  predicted 12 seconds did not justify a shared mutable host, an exclusive Collection, and edits
  to 29 test classes. It is filed as backlog 134.
- [x] Each target is measured at its checkpoint before it is written down as met, and every one
      of the five runs is recorded alongside the median and the maximum.
- [x] Every reliability defect the review found is either fixed here, or filed as its own
      backlog item with evidence.
- [x] Three items are filed for the speed findings left out of scope, each with the measurement
      that justifies it: the E2E incremental publish, parallel E2E stacks, and SQL container
      reuse. Filed on 2026-09-05 as backlog 131, 132 and 133, each in its own worktree with a
      draft pull request. A fourth went with them, backlog 134, for the D3 the human declined at
      the Integration checkpoint. Each carries its justifying measurement: D7 of the spec for the
      first three, D3 for the fourth.
- [x] After the collections are reshaped, `API.Tests` and `Infrastructure.Tests` run thirty
      times with no failure. Five full runs fix the medians; they are not enough on their own to
      claim that no flake was introduced, and this item does not make that claim on five.
      Only `Infrastructure.Tests` was reshaped, and it soaked 30 of 30 on 2026-09-05.
      `API.Tests` was never reshaped, because D3 was declined, so it has nothing to soak.
- [x] `pwsh ./scripts/test-fast.ps1 -Mode Fast`, `-Mode Integration`, and `-Mode E2E` pass.
      Verified 2026-09-05 at the Gate: Fast 2941, Integration 644, E2E 57, all green.

The E2E mode carries no target. It is 69 percent of the run, and the design puts it out of
scope with its own backlog item instead.

## Out of scope

- The PowerShell suites in `tests/*.Tests.ps1`. They have their own items.
- Adding coverage for untested code. This item is about the tests that already exist.
- Changing production code, beyond the one test seam the design names. Six CLI tests wait
  through a real two-second retry delay set in production code, and the human accepted an
  optional `TimeSpan` parameter at Design so the tests can pass zero. Runtime behaviour does
  not change.
- The E2E mode. Measured here, but improved under its own item.

## Notes / dependencies

- **Do your own research first.** Do not take the direction below as settled.
  - Measure before you change anything. A slow suite and a flaky suite need different fixes,
    and the evidence tells you which one you have.
  - Decide for yourself which tools and skills help. Check `.claude/skills/` and the
    installed plugins, and read what a skill actually detects before you trust it. A skill
    whose detection assumes a framework this repository does not use will find nothing and
    say nothing, which reads like a clean result.
  - Ask whether the problem is in the tests, in the test harness, or in the code under test.
- Starting size, September 2026: `tests/AHKFlowApp.Application.Tests` 102 test files,
  `tests/AHKFlowApp.UI.Blazor.Tests` 77, `tests/AHKFlowApp.API.Tests` 33,
  `tests/AHKFlowApp.CLI.Tests` 25, `tests/AHKFlowApp.E2E.Tests` 18,
  `tests/AHKFlowApp.Infrastructure.Tests` 10, `tests/AHKFlowApp.Domain.Tests` 9,
  `tests/AHKFlowApp.TestUtilities.Tests` 3.
- Related, but separate: backlog 126 covers running the PowerShell suites in parallel. Its
  measurement found that the whole run equalled its slowest single suite, because the suites
  competed for the disk. Check whether the same effect applies here before assuming more
  parallelism helps.
- Difficulty settled at Design: complex.
- ADR: `docs/adr/0013-sql-backed-tests-isolate-by-database.md`
- Glossary: `CONTEXT.md` now defines Slice, Mode, and Collection.
- Spec: `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`
- Plan: `docs/superpowers/plans/2026-09-04-net-test-speed-and-reliability-plan-128.md`
