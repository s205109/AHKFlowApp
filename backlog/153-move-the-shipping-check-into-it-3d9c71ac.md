# 153 - Move the shipping check into its own workflow

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (CI)
- **Difficulty**: moderate
- **Stage**: 4-execute

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

- [x] A workflow other than `ci.yml` runs `scripts/check-shipping-pr-closes-item.ps1` when a pull
      request is flipped to ready.
- [x] That workflow checks out with `fetch-depth: 0`, because the check reads the merge base.
- [x] That workflow passes the pull request head from the event, and the base from
      `git merge-base`, never from the event's `base.sha`.
- [x] `ci.yml` no longer lists `ready_for_review` in the `types` of its pull request event.
- [x] A ready pull request that leaves a fully ticked item open fails the new workflow.
- [x] A draft pull request reports success rather than skipping, so the check can stay a required
      check without blocking every draft.
- [x] `tests/ShippingPrClosesItem.Tests.ps1` still passes, and still replays pull request #400.
- [x] The new workflow's wall-clock time on one real ready flip is recorded in this item.

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
- **Grilling on 2026-09-11 widened the branch protection edit.** The same edit also makes
  `repo-invariants` a required check. It is not required today, and every other `ci.yml` job needs
  it. GitHub says a job skipped because a job it needs failed "may not block merging". So a red
  `repo-invariants` can let a merge through today. No box tracks this, because no diff shows it.
  The plan holds the command and the proof step.
- **A person reading a red mark must then look in two places.** That is the cost the grilling
  decision was protecting against, and it does not go away. The measurement is what makes it
  worth paying.
- Backlog 151 filed this, and its notes carry the same numbers.
  `backlog/done/151-close-the-item-in-the-pr-that-s-c446acb5.md`
- ADR: `docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md`
- Terms pinned in `CONTEXT.md`: Shipping pull request, Records closed, Acceptance box.
- Spec: none — the rule is already designed and this item only changes where it runs.
- Plan: `docs/superpowers/plans/2026-09-11-shipping-check-own-workflow-plan-153.md`

## Verification runs

All on 2026-09-12, on pull request #409, head commit `b9eab7e3`.

**Linux.** The new suite ran in Docker on `mcr.microsoft.com/powershell:latest` and printed
`ShippingPrClosesItemWorkflow tests passed.` So its manifest `platform` keeps both values.

**The draft push.** Run `34681215374`, `success`. Its log holds
`Pull request 409 draft state at run time: true` and
`This pull request closes the records of every item it finishes.` The first line proves the job
read the draft state from the REST API, not from the event payload.

**Ready flip 1, boxes still open, must pass.** The flip fired at 07:38:05Z. Run `34681242126`
started at 07:38:07Z and finished `success` at 07:38:18Z, so the ready flip cost **11 seconds**.
Its log holds `Pull request 409 draft state at run time: false`. The draft-time run on the same
head said `true`, so the two lines together show the run-time read following the pull request.

`ci.yml` started no run after the flip. Its newest run on this branch was created at 07:37:26Z,
which is the push, not the flip.

Before this change the same flip cost 9 min 59 s. The measured saving is about 9 minutes 48
seconds per ready flip.

## Branch protection

Edited on 2026-09-12, with the human's yes in chat. `main` now requires six checks, all from
app 15368: `build-test`, `powershell-suites`, `bicep-lint`, `codex-skills-hash-parity`,
`repo-invariants`, and `shipping-pr-closes-item`. The last two are new. No diff shows this edit,
which is why it is written here.

`repo-invariants` is the wider edit decision D6b describes. Every other `ci.yml` job needs it, and
GitHub says a job skipped because a job it needs failed "may not block merging".

**Ready flip 1b, the baseline.** Run at 08:04:47Z on head `b9eab7e3`, with the acceptance boxes
still open on the remote. Shipping run `34682347964` finished `success` at 08:05:02Z. All six
required checks read `SUCCESS`, and `mergeStateStatus` read `CLEAN` while the pull request was
ready. So under these protection settings nothing else blocks the merge. The ruleset's
`require_extra_approval_for_unattributed_changes` did not fire on commits authored by Claude.

This baseline is what makes flip 2's result readable. `mergeStateStatus` says the merge is
blocked; it never says which rule blocked it.
