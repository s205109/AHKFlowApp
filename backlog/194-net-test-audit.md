# 194 - .NET test audit

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (the eight .NET test projects)
- **Difficulty**: complex
- **Stage**: 0-intake

## Summary

Backlog 188's baseline shows that the .NET tests cost 180.8 s of a 513.6 s Gate after a `.cs`
change, which is 35.2 percent. This item runs 188's saved test-audit workflow on the eight .NET test
projects. It removes, merges and speeds up tests where a refuter cannot show a lost defect.

## User story

As the developer of this repository, I want the .NET tests to cost less time on every code change
without catching fewer defects, so that a code change reaches a green Gate sooner.

## Acceptance criteria

Each criterion is refined in the spec named below. Tick a box only when its words hold literally.

- [ ] The audit covers the candidates from the 2026-10-17 triage (about 15 removals, 30 merges and
      15 speed-ups) and the 15 slowest tests of each .NET test project. It does not cover every
      test method.
- [ ] One auditor takes one group of candidates inside one project.
- [ ] The audit uses 188's saved workflow in `.claude/workflows/`, at the same size limit: runs of
      at most five groups, about 10 agents per run.
- [ ] One refuter tries to disprove each REMOVE and MERGE claim with the `test-value-evidence`
      method: put the bug back, or switch the feature off, and check whether another test still
      catches it.
- [ ] The user approves each batch, change by change, before it is applied.
- [ ] Each applied change is measured on its own, and the record holds its time before and after.
- [ ] The audit leaves the files that backlog 187 touches alone until 187 merges.
- [ ] A record states the .NET test time of a Gate after a `.cs` change, before and after the
      audit, measured with `scripts/measure-test-modes.ps1 -Mode Gate -Change Code`.

## Out of scope

- The PowerShell Suites, which backlog 188 audits.
- Changing which tests CI runs.
- Installing a mutation testing tool such as Stryker.NET (backlog 193 decides on that).

## Notes / dependencies

- Filed by backlog 188 at its Task 3, after the user confirmed the .NET verdict "worth an audit
  item" on 2026-10-19. Spec section 4.4.
- The baseline numbers are in `docs/development/cycle-time-record.md` on 188's branch.
- Pick this item up after 188 merges: it needs 188's saved workflow.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: none — the spec is the design; Plan comes at pickup.
