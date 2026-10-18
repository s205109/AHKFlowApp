# 193 - Architecture pilot on one tested module

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (one module and its tests, chosen from audit data)
- **Difficulty**: complex
- **Stage**: 0-intake

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

- [ ] The item records which module the pilot took, and the audit data that chose it.
- [ ] The pilot ran `/mattpocock-skills:improve-codebase-architecture` as installed in
      `mattpocock-skills` 1.3.1, started by the user. No fork of the skill exists.
- [ ] At the skill's start, the session told it to read `CONTEXT.md` as its glossary and to use
      `mp-grilling` and `mp-domain-modeling`. The item records that it did.
- [ ] A before-and-after record holds three measures for the module's tests: test time, test
      count, and how many hand-made defects the tests still catch.
- [ ] A written verdict states whether the pilot succeeded, from those three measures.
- [ ] The pilot's code is merged only if the verdict is positive and the user said yes. Otherwise
      the code is reverted, and only the verdict ships.
- [ ] The verdict says whether Stryker.NET is worth trying next. Nothing is installed without the
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
- Plan: none — the spec is the design; Plan comes at pickup.
