# 188 - Speed up the development cycle

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (process docs, test runner scripts, test suites)
- **Difficulty**: complex
- **Stage**: 5-simplify

## Summary

The full Gate is slow again. On 2026-10-17 the 77 PowerShell Suites took 1,736 suite-seconds, about
twice their committed baselines. This item measures the Gate, cuts and speeds up the slowest
PowerShell Suites, lets the Gate reuse a Suite result whose inputs did not change, warns when a
Suite slows down, and makes a citation whose text moved to exactly one other line warn instead of
fail. Missing or ambiguous citation text still fails. Three sibling items, filed at this
item's Plan, carry the process change, the memory cleanup and the architecture pilot.

## User story

As the developer of this repository, I want a change to go from pickup to merge with shorter Gate
runs and fewer red CI runs, so that I spend my time on the change and not on waiting for checks.

## Acceptance criteria

Each criterion is refined in the spec. Tick a box only when its words hold literally.

- [ ] A baseline record holds five measures: Gate time, affected-test time, CI critical path,
      Gate-required stage exits per item, and flaky failures. It also states whether the .NET
      steps are worth an audit item of their own.
- [ ] Each of the five measures has a target that the user approved after the baseline and before
      any improvement work.
- [ ] An after record of Gate time and affected-test time, taken on the final revision with the
      baseline's method and preparation, sits next to the baseline. It reports both targets as met
      or missed, and a missed target carries the user's decision to accept it or continue.
- [ ] A follow-up item carries the before record and the targets of the other three measures, and
      says when each after window starts and when it is ready.
- [ ] Every audit batch the user approved is applied, and the after record lists what each batch
      removed, merged or sped up.
- [ ] The four retired research tools, the five Suites that retire whole, the two interval helpers,
      and the `Get-AhkFlowTrxRunInterval` case in `tests/TrxIntervals.Tests.ps1` are gone. No live
      doc names them. ADRs, `backlog/done/`, and frozen plans and specs keep their mentions as
      history.
- [ ] A saved audit workflow is in `.claude/workflows/`, and a reference file records how to run it.
- [ ] The Gate reuses a stored green result for a PowerShell Suite whose inputs did not change,
      inside one worktree, and runs it again when an input changed. A Suite with no input list
      always runs. Build, format and coverage are not reused.
- [ ] Every Suite in the audit's candidate set that still exists is marked in the manifest as
      eligible for reuse, or as not eligible with a one-line reason. The reuse key builds an
      eligible Suite's input list each time, and an unresolved dependency switches reuse off.
- [ ] Evidence is written only after a Suite passed and only when no input changed during the run.
      Unreadable or malformed evidence counts as a miss.
- [ ] The Gate warns, and does not fail, when a Suite of 5 s or more runs more than 30 percent over
      its committed `baselineSeconds`. A reused result never warns.
- [ ] The citation check warns when the cited text moved to exactly one other line, and fails when
      the text is gone or appears on several lines.
- [ ] `CONTEXT.md` defines Gate input, Gate evidence, and Outside review.
- [ ] The process item, the memory and instruction cleanup item, and the architecture pilot item
      are filed, each pointing at the spec and carrying the criteria of its part.

## Out of scope

- Changing which tests CI runs.
- Reuse across worktrees, and reuse of build, format or coverage. They come later, if the after
  record shows they are worth it.
- The stage merge, the review checkpoint, the new verification rule, the stage-merge ADR and the
  Desktop copy. The process item carries them.
- The memory and instruction cleanup, and the architecture pilot. Each is an item of its own.
- The .NET test audit, unless the baseline says it is worth an item of its own.
- Moving the workflow tooling into its own repository (wave 2 of spec 126).
- Installing or updating any skill, plugin or tool without the user's yes at that point.
- The remaining flaky-test work in backlog 068, which is picked up as its own item.

## Notes / dependencies

- Design decisions: grilling rounds 1 to 5, the builder check, and the design review of
  2026-10-18. The spec carries them, and its section 5 maps each part to its item.
- The research behind this item was done on 2026-10-17 and 2026-10-18. The three reports the work
  reads are in the plans repository, in
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/`.
- PR #451 already shipped two quick fixes: the lane release race in
  `tests/CiPowerShellSuiteRunner.Tests.ps1` and a faster prefilter in
  `scripts/citation-freshness.common.ps1`.
- Related: backlog 068 (flaky `WorktreeRemoveHook` reads), backlog 187 (UI test events outside
  `InvokeAsync`), spec and plan 126 (the earlier PowerShell suite performance work).
- Siblings: 191 (process), 192 (memory and instructions), 193 (architecture pilot).
- Follow-ups: 196 measures the CI critical path, the stage exits per item and the flaky failures
  once their windows are ready. 195 applies or rejects the deferred test-audit speed-ups. 194
  carries the .NET test audit.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: `docs/superpowers/plans/2026-10-18-speed-up-the-development-cycle-plan-188.md`
