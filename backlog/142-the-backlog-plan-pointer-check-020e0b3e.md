# 142 - The backlog plan pointer check never reads done items

## Metadata

- **Epic**: Repository tooling
- **Type**: Tooling
- **Interfaces**: none (repository check)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

`tests/BacklogPlanPointer.Tests.ps1` skips every item in `backlog/done/`, so a malformed `- Plan:`
pointer on a shipped item is never reported. This item decides whether that skip should stay.

The skip is deliberate and has its own test case, so this is a design question, not a defect
report. The question is whether the reason for the skip still outweighs what it lets through.

## The evidence that raised it

Backlog 131 carried a bare `- Plan: docs/superpowers/plans/...md` pointer. The check requires the
path in backticks. While the item sat in `backlog/done/` the error was invisible, and the branch
passed every CI job with it. The error only appeared when the item moved back to `backlog/` for a
different reason.

So the failure mode is real: an item can ship with a pointer nobody can follow, and nothing says
so. A reader who later wants that plan has to guess.

## User story

As a developer looking for the plan behind a finished item, I want its `- Plan:` pointer to be
readable, so that I can find the plan without guessing.

## Acceptance criteria

- [ ] This item records why `done/` is skipped today. The skip is asserted by a named test case, so
      the reason is a decision somebody made and it must be found before it is changed.
- [ ] This item states whether the skip stays, and why. Both answers are acceptable; silence is
      not.
- [ ] If the skip goes, every existing item in `backlog/done/` passes the check, or the ones that
      do not are fixed in the same change.
- [ ] If the skip stays, the reason is written where a reader of the check will find it.

## Out of scope

- Changing what a valid pointer looks like. The backtick form stays as it is.
- `backlog/blocked/`, which the check already reads.
- Any other backlog check.

## Notes / dependencies

- The skip is asserted here: `tests/BacklogPlanPointer.Tests.ps1` case `done/ is skipped`, at
  `Stage = '9-ship'` with `ShouldPass = $true`.
- Start by finding out why. A plausible reason is that a shipped item is finished, so a late
  failure would block an unrelated branch for old debt. That is the same argument
  `scripts/check-shipped-plan-ticked.ps1` makes for judging only the items a branch ships, and it
  is a good argument. If it is the real one, the fix may be to check `done/` only for items the
  current branch touches, rather than to drop the skip.
- Counting the damage first is cheap. Run the check's own reader across `backlog/done/` by hand and
  see how many existing items would fail. A large number changes the answer.
- Filed out of backlog 131, where the gap was found.
- Spec: none — the change is one check and its tests.
- Plan: `docs/superpowers/plans/2026-09-07-plan-pointer-reads-done-plan-142.md`
