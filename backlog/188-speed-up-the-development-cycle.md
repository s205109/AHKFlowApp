# 188 - Speed up the development cycle

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (process docs, test runner scripts, test suites)
- **Difficulty**: complex
- **Stage**: 2-design

## Summary

The full Gate is slow again. On 2026-10-17 the 77 PowerShell Suites took 1,736 suite-seconds, about
twice their committed baselines. The Gate also runs too often, because Verify runs it and every
review round that changes code runs it again. This item makes the whole cycle faster: fewer stages,
a Gate that reuses results whose inputs did not change, one shared review checkpoint, fewer and
cheaper tests, and rules that stop the suites from growing back.

## User story

As the developer of this repository, I want a change to go from pickup to merge with fewer Gate
runs, shorter Gate runs, and fewer interruptions, so that I spend my time on the change and not on
waiting for checks.

## Acceptance criteria

Each criterion is refined in the spec. Tick a box only when its words hold literally.

- [ ] A baseline record holds five measures: Gate time, affected-test time, CI critical path, Gate
      runs per item, and flaky failures.
- [ ] An after record of Gate time and affected-test time, taken on the final revision with the
      baseline's method, sits next to the baseline.
- [ ] A follow-up item carries the before record of the other three measures, and says when their
      after record is due.
- [ ] `docs/development/workflow.md` has no Simplify, Verify or Document stage. Execute ends with
      the Gate on the final revision. The other stages keep their numbers.
- [ ] The Gate reuses a stored green result for a Suite or a step whose inputs did not change, and
      runs it again when an input changed. A Suite with no input list always runs.
- [ ] Each of the ten slowest Suites carries an input list that a script builds, or a written
      reason in the manifest why it reads everything. A check fails when a stored list differs
      from the built one.
- [ ] The Gate warns, and does not fail, when a Suite of 5 s or more runs more than 30 percent over
      its history in that checkout, or over its committed baseline when there is no history.
- [ ] The citation check warns when the cited text moved to exactly one other line, and fails when
      the text is gone or appears on several lines.
- [ ] `workflow.md` describes one review checkpoint: the Claude reviewer and the outside review read
      the same revision, and only a fix to code, tests or config goes back to a reviewer.
- [ ] `CONTEXT.md` defines Gate input, Gate evidence, and Outside review.
- [ ] `AGENTS.md` makes the cheapest check that proves the change the default verification
      artifact, and asks every new test to name the regression it prevents.
- [ ] A saved audit workflow is in `.claude/workflows/`, and a reference file records how to run it.
- [ ] The four retired research tools, the five Suites that retire whole, the two interval helpers,
      and the `Get-AhkFlowTrxRunInterval` case in `tests/TrxIntervals.Tests.ps1` are gone. No live
      doc names them. ADRs, `backlog/done/`, and frozen plans and specs keep their mentions as
      history.
- [ ] A written verdict on the architecture pilot exists.

## Out of scope

- Choosing which tests CI runs. CI keeps running everything.
- Moving the workflow tooling into its own repository (wave 2 of spec 126).
- A refactor of the whole codebase.
- Installing or updating any skill, plugin or tool without the user's yes at that point.
- The remaining flaky-test work in backlog 068, which is picked up as its own item.

## Notes / dependencies

- Design decisions: grilling rounds 1 to 5 on 2026-10-18. The spec carries them.
- The research behind this item was done on 2026-10-17 and 2026-10-18, in a local folder outside
  the repository. The spec quotes every fact it relies on.
- PR #451 already shipped two quick fixes: the lane release race in
  `tests/CiPowerShellSuiteRunner.Tests.ps1` and a faster prefilter in
  `scripts/citation-freshness.common.ps1`.
- Related: backlog 068 (flaky `WorktreeRemoveHook` reads), backlog 187 (UI test events outside
  `InvokeAsync`), spec and plan 126 (the earlier PowerShell suite performance work).
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: none — complex, so Design comes first at pickup.
