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

## The answer

**Why the skip exists today.** Decision D4a of the design behind backlog 090 records it:
a finished item has no live gap, because nobody picks it up. The same row records a second
reason: without the skip, backlog 087's own pull request would have turned CI red on 71 items at
once. The check carried a short version of the first reason, and the suite asserted it with the
case `done/ is skipped`.

**The skip is split. Half stays, half goes.**

- `backlog/done/` keeps being skipped for the **presence** of a `- Plan:` bullet.
- `backlog/done/` stops being skipped for the **shape** of one.

**Why.** The damage count decided it. Run on 2026-09-07 against `backlog/done/` with the folder
skip removed: 128 items scanned, 74 problems. 71 of those have no `- Plan:` bullet at all and
shipped before backlog 090 created the rule. Writing a `none — <reason>` line on 71 finished
items means guessing 71 times whether a plan never existed or was merely never found, and no
reader is waiting for any of it. That is the large number the item warned about.

The other 3 are different. Items 104, 124 and 136 each name a real plan file with the backticks
missing, so the pointer is there and cannot be followed. That has a reader.

The stage trigger does not catch them, and this is the part that makes the skip worth changing.
Backlog 136 went from `backlog/` at `3-plan` straight into `backlog/done/`, and only then got its
malformed pointer. It was below the `4-execute` trigger the whole time it sat in `backlog/`, so
the check never read it once. Backlog 124 has a single commit and the same shape. This is a live
route, not old debt, and it was used twice in two months.

**Why not branch scoping.** `scripts/check-shipped-plan-ticked.ps1` already reads the shipped
item's pointer, already knows the pointer can be unreadable, and prints a diagnostic instead of
failing. Turning that into a refusal needs a merge base, a target commit, and git. The split
above needs none of those, keeps `Get-BacklogPointerProblem` a pure folder reader, and fixes the
three broken items now instead of waiting for some branch to touch them.

**Where the reason lives now.** In the comment above the `$shipped` flag in
`scripts/backlog.common.ps1`, in the comment above the `done/` cases in
`tests/BacklogPlanPointer.Tests.ps1`, in `docs/development/workflow.md`, and in `AGENTS.md`.

## Out of scope

- Changing what a valid pointer looks like. The backtick form stays as it is.
- `backlog/blocked/`, which the check already reads.
- Any other backlog check.

## Notes / dependencies

- The skip was asserted here: `tests/BacklogPlanPointer.Tests.ps1` case `done/ is skipped`, at
  `Stage = '9-ship'` with `ShouldPass = $true`. That case is gone. Six `done/` cases stand in its
  place, and `done/ needs no pointer` is the one that keeps the half of the skip that stays.
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
