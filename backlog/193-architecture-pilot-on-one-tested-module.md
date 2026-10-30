# 193 - Architecture pilot on one tested module

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (one module and its tests, chosen from audit data)
- **Difficulty**: complex
- **Stage**: 8-review

## Summary

Some modules are tested many times over: the 2026-10-17 audit found the Lane pool tested in seven
Suites. This item runs one architecture pilot on one module, measures whether a deeper module
makes its tests fewer, faster and still sharp, and ships a written verdict. The code merges only
on a positive verdict and the user's yes.

## User story

As the developer of this repository, I want to know whether reshaping one heavily tested module
cuts test cost without losing defect detection, so that I can decide on wider architecture work
and on Stryker.NET with evidence.

## Acceptance criteria

Each criterion is refined in the spec named below. Tick a box only when its words hold literally.

- [x] The item records which module the pilot took, and the audit data that chose it.
- [x] The pilot ran `/mattpocock-skills:improve-codebase-architecture` as installed in
      `mattpocock-skills` 1.3.1, started by the user. No fork of the skill exists.
- [x] At the skill's start, the session told it to read `CONTEXT.md` as its glossary and to use
      `mp-grilling` and `mp-domain-modeling`. The item records that it did.
- [x] A before-and-after record holds three measures for the module's tests: test time, test
      count, and how many hand-made defects the tests still catch.
- [x] A written verdict states whether the pilot succeeded, from those three measures.
- [x] The pilot's code is merged only if the verdict is positive and the user said yes. Otherwise
      the code is reverted, and only the verdict ships.
      The code is reverted in `70689716`. Two `CONTEXT.md` terms, Lane share and Nested run,
      ship with the verdict. Spec section 6.3 keeps them "either way", because they name concepts
      the code already has.
- [x] The verdict says whether Stryker.NET is worth trying next. Nothing is installed without the
      user's yes at that point.

## Out of scope

- Architecture work on more than one module.
- Installing Stryker.NET or any other tool.
- The stage merge and the review checkpoint (backlog 191), and the memory cleanup (backlog 192).

## Notes / dependencies

- Filed by backlog 188 at its Plan stage. Spec section 4.7.
- The module comes from 188's audit data, recorded in `docs/development/cycle-time-record.md` on
  188's branch. Pick this item up after 188's audit batches, or after 188 merges.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Pilot design spec: `docs/superpowers/specs/2026-10-29-architecture-pilot-on-one-tested-module-design-193.md`
- Plan: `docs/superpowers/plans/2026-10-29-architecture-pilot-on-one-tested-module-plan-193.md`

## Pilot record

- **Module**: the Lane pool, `scripts/test-lanes.common.ps1`, with its test helpers
  `tests/LanePool.Common.ps1` and `tests/DotnetLane.Common.ps1`.
- **Audit data that chose it**: section 3.6 of
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/powershell-suites.md`,
  "The Lane pool is tested in seven suites". The 188 spec names the Lane pool as its example in
  section 4.7.
- **Audit data today**: on 2026-10-29, at `f6db2386`, eight Suites use the module or its test
  helpers: `CiPowerShellSuiteRunner`, `CoverageRunnerProgress`, `CoverageSliceSkip`,
  `GateEvidence`, `LanePool`, `MeasureTestModes`, `TestFastDotnetProgress` and
  `TestFastPowerShellMode`. `CoverageSliceSkip` and `GateEvidence` are new since the audit.
- **Skill start**: on 2026-10-29 the user started `/mattpocock-skills:improve-codebase-architecture`
  from `mattpocock-skills` 1.3.1, with the Lane pool as its direction. At its start, the session told
  it to read `CONTEXT.md` as its glossary in place of `GLOSSARY.md`, and to use `mp-grilling` and
  `mp-domain-modeling` in place of `grilling` and `domain-modeling`.
- **Verdict**: Negative, because the result is Not faster. The median fall in time is 6.71
  percent, against a target of 10 percent. All 12 defects are Caught on both sides, and the
  caller count falls by 25.7 percent. The measures are in
  `docs/development/architecture-pilot-record.md`. The pilot code is reverted, and backlog item
  202 adds the two .NET failure rows again.
