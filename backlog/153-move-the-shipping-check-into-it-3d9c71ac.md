# 153 - Move the shipping check into its own workflow

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (CI)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The shipping check runs in under a second, but the trigger that starts it re-runs the whole CI
workflow for about ten minutes. Give the check its own workflow, so the ready flip costs a run
that does only the work it needs.

## User story

As a contributor at Ship, I want the ready flip to start only the check that the ready flip
exists for, so that closing a backlog item does not cost a second full CI run.

## Why now

Backlog 151 added `scripts/check-shipping-pr-closes-item.ps1` and the trigger that makes it run.
`ready_for_review` is not one of the default pull request types, and Stage 9 pushes the closure
commit before it flips the pull request to ready. Without the trigger, the last CI run on a
shipping pull request is always the draft-time run, and that stale green carries into the merge.

The trigger is correct. Its cost is the problem. `.github/workflows/ci.yml` holds five jobs and
no per-job conditions, so the ready flip starts all five again.

Measured on GitHub Actions run `34569724686`, the last run on pull request #407 before it merged:

| What | Time |
|---|---|
| The whole workflow | 9 min 59 s |
| `powershell-suites` | 8 min 34 s |
| `build-test` | 6 min 51 s |
| `repo-invariants` | 1 min 21 s |
| The shipping check step itself | under 1 s |

Backlog 151's plan named ten minutes as the point to reconsider. The measurement landed on it.

## The decision this reverses

Grilling on 2026-09-10 chose to keep the check inside `ci.yml`, because `ci.yml` being the one
pull request gate is worth more than those minutes, and because splitting it out later is a small
change. That reasoning still holds for the first half. This item is the "later".

The measurement is what changed. The decision was taken before any number existed.

## Acceptance criteria

- [ ] A workflow other than `ci.yml` runs `scripts/check-shipping-pr-closes-item.ps1` when a pull
      request is flipped to ready.
- [ ] That workflow checks out with `fetch-depth: 0`, because the check reads the merge base.
- [ ] That workflow passes the pull request head from the event, and the base from
      `git merge-base`, never from the event's `base.sha`.
- [ ] `ci.yml` no longer lists `ready_for_review` in the `types` of its pull request event.
- [ ] A ready pull request that leaves a fully ticked item open fails the new workflow.
- [ ] A draft pull request reports success rather than skipping, so the check can stay a required
      check without blocking every draft.
- [ ] `tests/ShippingPrClosesItem.Tests.ps1` still passes, and still replays pull request #400.
- [ ] The new workflow's wall-clock time on one real ready flip is recorded in this item.

## Out of scope

- Changing the rule itself. `docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md`
  owns it, and this item only moves where it runs.
- Adding per-job conditions to `ci.yml`. That is a bigger change to the one pull request gate and
  needs its own item.
- Arm 3 in `scripts/backlog-staleness.common.ps1`. It runs in `repo-invariants` on every pull
  request and is not affected by the trigger.

## Notes / dependencies

- **Branch protection must move with it.** `ci.yml` is the one pull request gate today. After the
  split, two workflows can fail a pull request. The required-checks list must name the new
  workflow, or the check can fail and a merge can still be permitted. This is the real risk in
  the item, and it is not visible in the diff.
- **A person reading a red mark must then look in two places.** That is the cost the grilling
  decision was protecting against, and it does not go away. The measurement is what makes it
  worth paying.
- Backlog 151 filed this, and its notes carry the same numbers.
  `backlog/done/151-close-the-item-in-the-pr-that-s-c446acb5.md`
- ADR: `docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md`
- Terms pinned in `CONTEXT.md`: Shipping pull request, Records closed, Acceptance box.
- Spec: none — the rule is already designed and this item only changes where it runs.
- Plan: none — filed at Intake. Pickup classifies it and writes one.
