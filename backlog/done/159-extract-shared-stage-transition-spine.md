# 159 - extract shared stage transition spine

## Metadata

- **Epic**: Development process
- **Type**: Refactor
- **Interfaces**: none (internal script code, no UI/API/CLI change)
- **Difficulty**: moderate
- **Stage**: 9-ship

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

- [x] `scripts/backlog-snapshot.common.ps1` carries one function for the shared stage-transition
      walk, and both `scripts/check-plan-split-record.ps1` and
      `scripts/check-shipped-plan-ticked.ps1` call it instead of each defining its own copy.
      The function is `Get-BranchBacklogTransition`. Neither caller keeps a copy of the walk.
- [x] `tests/PlanSplitRecord.Tests.ps1` and `tests/ShippedPlanTicked.Tests.ps1` pass unmodified,
      proving the extraction is behavior-preserving. `git diff origin/main...HEAD -- tests/`
      returns nothing, and both suites pass. Mutating the new function's return value fails 8
      split tests and 15 shipped tests, so both suites really do run through it.
- [x] The combined line count of `scripts/backlog-snapshot.common.ps1`,
      `scripts/check-plan-split-record.ps1`, and `scripts/check-shipped-plan-ticked.ps1` is lower
      than before the extraction. 895 before, 892 after. The margin is three lines, not the 95 the
      reviewer estimated, so this criterion turned out to be a weak one. See the size note below.

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
  needs a look at both call sites before writing one. The plan below carries that look in its
  Design notes, so no separate spec was written.
- Plan: `docs/superpowers/plans/2026-09-18-extract-shared-stage-transition-spine-plan-159.md`
- **Base branch.** `main`. At Pickup, `scripts/check-plan-split-record.ps1` existed only on
  `feature/wt-plan-declares-its-pull-requests`, so the branch was rebased onto that one first.
  PR #417 merged on 2026-09-18, and the branch was rebased onto `main`.
- **Size, measured.** The reviewer's estimate of about 95 lines saved is far too high. The three
  files hold 895 lines before the extraction and 892 after, so the saving is 3 lines. The spine
  costs about as many lines as the two copies it replaces, because the walk itself is irreducible
  and the new function carries its own comment block. Criterion 3 asks only for a lower total, so
  it holds, but a future item should not use line count as the test for an extraction. The value
  here is that a bug in the walk, or a new check that needs the same walk, has one place to go.
- **Third caller left alone.** `Get-ShippingPrProblem` in `scripts/check-shipping-pr-closes-item.ps1`
  reads the same two snapshots, but it reports instead of throwing, carries on when the base is
  unusable, decides on acceptance box counts rather than Stage lines, and skips the item template
  by file name. Folding it in would need three or four switch parameters, and a shared function
  steered by flags reads worse than the copies it replaced.
