# 203 - Audit the non-E2E .NET tests

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (five .NET test projects)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Backlog 194 audits the E2E tests. This item runs the same `test-audit` workflow on the other five
.NET test projects that have time to save: UI.Blazor, CLI, Infrastructure, API and Application.
The 2026-10-17 triage estimated about 12 to 16 seconds of savings in these five projects.

## User story

As the developer of this repository, I want the non-E2E .NET tests to cost less time on every
code change without catching fewer defects, so that a code change reaches a green Gate sooner.

## Acceptance criteria

The rules come from the 194 spec named below. Tick a box only when its words hold literally.

- [ ] The audit covers the triage candidates of the five projects and the 15 slowest tests of each
      of them, ranked by a fresh run at this item's pickup. It does not cover every test method.
- [ ] One auditor takes one Candidate group, and each of the five projects is one Candidate group.
- [ ] The audit uses the saved `test-audit` workflow in `.claude/workflows/`, in its .NET mode, in
      one run of five Candidate groups.
- [ ] One refuter tries to disprove each REMOVE and MERGE claim the auditors return. A claim is
      upheld only when the audited test and another test both fail on the same defect, or when
      the behaviour is gone.
- [ ] The user approves each change on its own row before it is applied.
- [ ] The record holds each applied change's time before and after, and no kept change saves
      less than 0.5 s.
- [ ] A record states the .NET test time of a Gate after a `.cs` change, before and after this
      item, measured with `scripts/measure-test-modes.ps1 -Mode Gate -Change Code`.
- [ ] Every proposal the item does not apply is listed in `docs/development/test-audit-deferred.md`
      with its reason.

## Out of scope

- The E2E tests, which backlog 194 audits.
- Domain and TestUtilities. Their tests take under 0.2 s each, so there is no time to save.
- Running the test projects side by side, which backlog 204 tries.
- Changes that save no time, such as merges that only cut maintenance.
- Installing a mutation testing tool such as Stryker.NET (backlog 193 decides on that).

## Notes / dependencies

- Split from backlog 194 at its Design (decision D13 of the spec). The spec's rules apply here:
  D3, D6 to D9, D11 and D14.
- Pick this item up after 194 merges, because it needs 194's .NET mode of the workflow. If 194 is
  still open, stack this item on `fix/wt-net-test-audit` with `-BaseRef`.
- The structural speed-ups the triage found for these projects belong here: split the four large
  bUnit classes, share one API host across the CLI integration tests, and stop the CLI retry test
  from waiting out a real 2 s delay.
- The triage is `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/dotnet-tests.md`.
- Spec: `docs/superpowers/specs/2026-11-01-net-test-audit-design-194.md`
- Plan: none — Plan comes at pickup.
