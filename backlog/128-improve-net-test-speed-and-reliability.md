# 128 - Improve .NET test speed and reliability
## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test projects)
- **Difficulty**: to-be-determined
- **Stage**: 2-design

## Summary

The .NET test projects have grown to roughly 277 test files and have never been reviewed
as a whole for speed or for reliability. This item asks for that review, and for the
improvements the review finds to be worth making.

## User story

As a developer running the test suites, I want them to finish quickly and to give the same
answer every time, so that a red run always means my change broke something.

## Acceptance criteria

Do the research before you write these numbers. Replace the placeholders below with real
targets and record where each number came from.

- [ ] A written measurement exists for each test project: wall clock time, and the slowest
      tests inside it.
- [ ] A written list exists of the tests that give a different answer on different runs, or
      a statement, backed by run counts, that none were found.
- [ ] The full run is faster than the measured starting point by an agreed amount.
- [ ] Every reliability defect the review found is either fixed here, or filed as its own
      backlog item with evidence.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode Fast`, `-Mode Integration`, and `-Mode E2E` pass.

## Out of scope

- The PowerShell suites in `tests/*.Tests.ps1`. They have their own items.
- Adding coverage for untested code. This item is about the tests that already exist.
- Changing production code, unless a test proves a defect in it.

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
- Spec: none — write one at Stage 2, because the difficulty is not yet known.
- Plan: none — write one at Stage 3.
