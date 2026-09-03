# 128 - Improve .NET test speed and reliability
## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test projects)
- **Difficulty**: complex
- **Stage**: 2-design

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

Starting point, measured 2026-09-03 on one solution build followed by `-NoBuild`: Fast 34 s,
Integration 91 s (mean of three), E2E 300 s (mean of two), plus a 10 s solution build.

- [ ] A written measurement exists for each test project: wall clock time, and the slowest
      tests inside it.
- [ ] A written list exists of the tests that give a different answer on different runs, or
      a statement, backed by run counts, that none were found.
- [ ] The Fast mode finishes in under 22 seconds, down from 34.
- [ ] The Integration mode finishes in under 65 seconds, down from 91.
- [ ] Every reliability defect the review found is either fixed here, or filed as its own
      backlog item with evidence.
- [ ] Every speed finding the review left out of scope is filed as its own backlog item, with
      the measurement that justifies it.
- [ ] Fast and Integration each run five times after the change with no failure, because
      making tests run at the same time is what can introduce a flake.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode Fast`, `-Mode Integration`, and `-Mode E2E` pass.

The E2E mode carries no target. It is 69 percent of the run, and the design puts it out of
scope with its own backlog item instead.

## Out of scope

- The PowerShell suites in `tests/*.Tests.ps1`. They have their own items.
- Adding coverage for untested code. This item is about the tests that already exist.
- Changing production code, beyond the one test seam the design names. Six CLI tests wait
  through a real two-second retry delay set in production code, and the human accepted an
  optional `TimeProvider` parameter at Design so the tests can skip that wait. Runtime
  behaviour does not change.
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
- Spec: `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`
- Plan: none — Design just finished; Stage 3 writes it.
