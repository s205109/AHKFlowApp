# 159 - extract shared stage transition spine

## Metadata

- **Epic**: Development process
- **Type**: Refactor
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

`scripts/check-plan-split-record.ps1`'s `Get-BranchExecutingItem` and
`scripts/check-shipped-plan-ticked.ps1`'s `Get-BranchShippedItem` both walk the same shape: read
the backlog inventory at a base commit and a target commit, find items whose Stage line entered
some range on this branch, and return one record per matching item. About 60 percent of
`Get-BranchExecutingItem`'s body repeats that walk. Extract the shared spine into
`scripts/backlog-snapshot.common.ps1`, so both checks call one function instead of each carrying
its own copy.

## User story

As a person reading either pre-push check, I want the stage-transition walk to live in one place,
so that a bug fix or a new check does not have to be written twice.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] `scripts/backlog-snapshot.common.ps1` carries one function for the shared stage-transition
      walk, and both `scripts/check-plan-split-record.ps1` and
      `scripts/check-shipped-plan-ticked.ps1` call it instead of each defining its own copy.
- [ ] `tests/PlanSplitRecord.Tests.ps1` and `tests/ShippedPlanTicked.Tests.ps1` pass unmodified,
      proving the extraction is behavior-preserving.
- [ ] The combined line count of `scripts/backlog-snapshot.common.ps1`,
      `scripts/check-plan-split-record.ps1`, and `scripts/check-shipped-plan-ticked.ps1` is lower
      than before the extraction.

## Out of scope

- Any change to what either check enforces. This is a pure refactor; no check's pass/fail verdict
  on any existing input changes.
- The split-trigger threshold recalibration flagged in the same review round. That is a separate
  follow-up, not filed yet.

## Notes / dependencies

- **Where this came from.** Stage 8 review of backlog 157 (PR #417), round 1, 2026-09-18. The
  reviewer's own words: "the largest maintainability exposure, but acceptable for now," with the
  concrete recommendation to extract into `backlog-snapshot.common.ps1` as a follow-up rather than
  inside that PR, since the extraction touches the shipped-plan check too and a PR should stay one
  concern. The finding and its accepted verdict are recorded in the review-response comment on
  PR #417, and in that branch's `PLAN-PROGRESS.md` before it was removed at Ship.
- Estimated by the reviewer at roughly 95 lines net saved across the three files. Not verified
  independently; read as a rough size signal, not a target.
- Spec: none — the shape of the extraction (what the shared function's signature looks like, and
  whether `Get-BranchExecutingItem`'s extra stage-index filtering stays a thin wrapper around it)
  needs a look at both call sites before writing one.
- Plan: none — not planned yet.
