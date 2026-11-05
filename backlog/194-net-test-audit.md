# 194 - .NET test audit

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (`tests/AHKFlowApp.E2E.Tests`)
- **Difficulty**: complex
- **Stage**: 8-review

## Summary

Backlog 188's baseline shows that the .NET tests cost 180.8 s of a 513.6 s Gate after a `.cs`
change, which is 35.2 percent. E2E is the largest part of that time. This item extends 188's saved
test-audit workflow for .NET and runs it on the E2E tests. It removes, merges and speeds up tests
where a refuter cannot show a lost defect. Backlog 203 audits the other .NET test projects, and
backlog 204 tries running the projects side by side.

## User story

As the developer of this repository, I want the .NET tests to cost less time on every code change
without catching fewer defects, so that a code change reaches a green Gate sooner.

## Acceptance criteria

Each criterion is refined in the spec named below. Tick a box only when its words hold literally.

- [x] The audit covers the E2E candidates from the 2026-10-17 triage and the 15 slowest E2E tests
      of a fresh run on this branch. It does not cover every E2E test.
- [x] One auditor takes one Candidate group.
- [x] The audit uses 188's saved workflow in `.claude/workflows/`, in a .NET mode, at the same size
      limit: one run of at most five Candidate groups, about 10 agents.
- [x] One refuter tries to disprove each REMOVE and MERGE claim the auditors return, with the
      `test-value-evidence` method. A claim is upheld only when the audited test and another test
      both fail on the same defect, or when the behaviour is gone.
- [x] The user approves each change on its own row before it is applied.
- [x] The record holds each applied change's time before and after, and no kept change saves less
      than 0.5 s.
- [x] A record states the .NET test time of a Gate after a `.cs` change, before and after the
      audit, measured with `scripts/measure-test-modes.ps1 -Mode Gate -Change Code`.
- [x] Every proposal the audit does not apply is listed in `docs/development/test-audit-deferred.md`
      with its reason.
- [x] `docs/development/test-audit-workflow.md` says how to run the workflow on a .NET test
      project.

## Evidence for the ticks

- Coverage: the ranking in `docs/development/cycle-time-record.md` under `### Ranking` names the
  triage candidates and the 15 slowest tests of the before session.
- Workflow: this session had no workflow runtime. A gitignored driver ran
  `.claude/workflows/test-audit.js` with stub functions. It wrote the script's own prompts and
  applied its own claim filter. Five auditors and five refuters ran, so 10 agents, over five
  Candidate groups. `### Run 1` in the cycle-time record says so.
- Approval: the user approved rows 1 to 23 and, with a merge proof each, rows 26 to 29, on
  2026-11-05. Every change had its own row in the approval table.
- Times: `### Changes` holds each kept row's before and after. The smallest saving is 0.72 s.
- Gate: `### Gate before` and `### Gate after` hold the .NET test time, 180.19 s and 159.51 s.
- Deferred: rows 24, 25 and 30 to 37 are in `docs/development/test-audit-deferred.md`.

## Out of scope

- The PowerShell Suites, which backlogs 188, 195 and 201 audited.
- The UI.Blazor, CLI, Infrastructure, API and Application tests, which backlog 203 audits.
- Domain and TestUtilities, whose tests take under 0.2 s each.
- Running the test projects side by side, which backlog 204 tries.
- Changing which tests CI runs.
- Installing a mutation testing tool such as Stryker.NET (backlog 193 decides on that).

## Notes / dependencies

- Filed by backlog 188 at its Task 3, after the user confirmed the .NET verdict "worth an audit
  item" on 2026-10-19. Spec section 4.4.
- The baseline numbers are in `docs/development/cycle-time-record.md`.
- Design on 2026-11-01 narrowed this item to E2E and filed backlogs 203 and 204. The old criterion
  about backlog 187's files was dropped, because 187 has merged.
- Parent spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Spec: `docs/superpowers/specs/2026-11-01-net-test-audit-design-194.md`
- Plan: `docs/superpowers/plans/2026-11-01-net-test-audit-plan-194.md`
