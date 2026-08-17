# 100 - A ticked acceptance box is never checked against reality

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (backlog items, scripts)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake
- **Depends on**: none

## Summary

A backlog item ships with its acceptance boxes ticked, and nothing compares a ticked box
against what the branch actually does. The tick is the only record that the criterion is
met, and it is written by the same session that would benefit from writing it.

## User story

As a reviewer, I want a ticked acceptance box to carry evidence, so that reading
`backlog/done/` tells me what shipped rather than what somebody claimed.

## The defect

This item is named in the backlog 072 plan, which called a ticked box that is not true
"the exact defect backlog 100 exists to catch". The item did not exist when that sentence
was written. Filing it now closes the forward reference.

The defect has been seen. Backlog 071 published five friction figures against ticked boxes,
and every one of the five was withdrawn in review. The boxes stayed ticked through three
attempts.

Backlog 097 solved the neighbouring problem for `file:line` citations: a citation now carries
its quoted text, and `scripts/check-citation-freshness.ps1` reads the cited line. An
acceptance box carries no such handle. The sentence describes an outcome, and no script can
read an outcome.

## Acceptance criteria

- [ ] The failure mode is written down: what a false tick costs, and which of the ticks
      already in `backlog/done/` are wrong. Sample rather than audit all of them.
- [ ] A decision is recorded on whether this is checkable at all. A criterion is prose, so a
      script cannot read it. Name the mechanism, or state plainly that the answer is a
      review step and not a check, and say what that review step is.
- [ ] If the answer is a mechanism, it fails a run rather than waiting for a reviewer, in the
      way the four checks from backlog 072 do.

## Out of scope

- Rewriting existing items to a machine-readable criterion format. That is a much larger
  change and this item does not assume it is the answer.
- The `- Plan:` pointer, which `tests/BacklogPlanPointer.Tests.ps1` already checks.

## Notes / dependencies

- Named in `docs/superpowers/plans/2026-08-15-process-wave-2-plan-072.md` (private plans
  repo), Task 10, Step 4.
- Backlog 097 is the closest working example, for citations rather than criteria.
- Backlog 072 closed with two boxes deliberately unticked and the reason written into the
  item. That is the behaviour this item wants to make normal rather than exceptional.
- Spec: none — Design has not run.
- Plan: none — the item is at Intake.
