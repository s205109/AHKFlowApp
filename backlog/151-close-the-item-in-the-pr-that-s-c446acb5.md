# 151 - Close the item in the PR that ships its work

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (script, CI)
- **Difficulty**: complex
- **Stage**: 2-design

## Summary

An item can tick every acceptance box, merge all of its work, and still sit open in `backlog/`
at an earlier stage. Nothing reads that combination, so the item waits for a housekeeping round
or for the twelve-commit staleness rule. This item asks for a check that reads it.

## User story

As a contributor, I want a branch that finishes an item to be refused until it closes that
item's records, so that a merged item never sits in `backlog/` describing work that already
shipped.

## Why now

Item 132 is the case. All of it happened on 2026-09-10.

Pull request #400 merged every part of item 132's work. The branch ticked all five acceptance
boxes and wrote its measurements into the item. It left the `Stage` line at `4-execute`, left
all 37 plan steps unticked, and never moved the file into `backlog/done/`. The merge landed at
`7ca15577`. A housekeeping round found the item by hand about nine hours later and closed it in
`04e27a22`.

Three checks sit near this and each one missed:

- `scripts/check-shipped-plan-ticked.ps1` fires only when the judged commit gives the item
  exactly one Stage line reading `9-ship`. Pull request #400 never wrote `9-ship`, so the gate
  never looked at the item.
- `tests/BacklogStaleOpen.Tests.ps1` arm 1 needs the base branch to move more than twelve
  first-parent commits past the item's own merged records. When the round found item 132,
  `origin/main` was two commits past the merge. Arm 2 fires on `Stage: 9-ship` in `backlog/`,
  which item 132 never wrote.
- `tests/BacklogPlanPointer.Tests.ps1` asks only whether the item names a plan. Item 132 named
  its plan, so this check passed, and it was right to pass.

All three read the `Stage` line. Item 132's failure was that the `Stage` line never moved.

## The signal nobody reads

Item 132 ticked all five acceptance boxes. A branch that has ticked every box has finished the
item by the item's own definition, so it is the shipping branch. That is readable from the diff,
and a partial delivery cannot produce it, because a partial delivery leaves at least one box
unticked. `AGENTS.md` already says to leave a box that is not true unticked with the reason
written into the item, so an honest partial delivery is already outside this signal.

Whether that becomes a new arm on the stale-open check, a new push gate beside the tick gate,
or a CI check on the pull request is the design question. The spec decides it.

## Acceptance criteria

- [ ] A check reports an item that sits in `backlog/` with every acceptance box ticked and a
      `Stage` line below `9-ship`.
- [ ] Replaying pull request #400's head against its merge base makes the check report item 132.
- [ ] An item with at least one unticked acceptance box does not trigger the check, whatever its
      stage. Most items ship over more than one pull request, and every pull request but the last
      leaves boxes unticked.
- [ ] An item with no acceptance boxes at all does not trigger the check.
- [ ] A branch that only edits an item already in `backlog/done/` does not trigger the check.
- [ ] A branch that had all boxes ticked in its own merge base does not trigger the check. It is
      not the branch that finished the item.
- [ ] The check states which invariant it uses and why the rejected candidates were rejected,
      including the candidate item 106 already rejected.
- [ ] A fixture proves both directions: a finished item left open fails, and a finished item
      closed in the same branch passes.
- [ ] Every existing PowerShell suite still passes, and the new check joins
      `scripts/run-powershell-suites.ps1`, which discovers `tests/*.Tests.ps1` by glob.

## Out of scope

- Lowering the staleness threshold of 12. The number was measured and the measurement is
  recorded in `scripts/backlog-staleness.common.ps1`. Lowering it turns a real defect signal
  into noise.
- Automating the stage transition itself. That is item 081.
- Deciding whether `PLAN-PROGRESS.md` should exist beside the plan checkboxes. Recorded as an
  open question below.
- Making the plan tick gate fire earlier than `9-ship`. Item 132 never reached `7-document`, so
  moving the gate to Document would not have caught it. Worth its own item if wanted.

## Notes / dependencies

- **A rejected candidate.** `backlog/done/106-nothing-detects-a-merged-item-whose-records-were-never-closed.md`
  lists "a pull request touching `backlog/NNN-*.md` that does not move it to `backlog/done/`"
  among the candidates it rejected, because most items ship over more than one pull request.
  Any design here must say how it differs from that candidate, or it is re-proposing a rejected
  rule. Read item 106's rejections before proposing anything.
- Item 106 also accepted a known limit: work that never stamps a stage at `4-execute` or later
  leaves no metadata for a metadata check to read. Item 151 does not lift that limit. It reads a
  different field.
- Item 106 blessed the shape of a second cheap arm: "it costs one comparison, so the check keeps
  it as a second arm with its own message." A third arm follows that precedent.
- `scripts/check-shipped-plan-ticked.ps1` is the best model for the merge-base comparison. Its
  header explains why it judges only the items the branch ships, and why judging every touched
  item would get the gate switched off inside a week.
- **Open question, narrowed.** The item 132 branch was not careless. It kept a careful progress
  record in `PLAN-PROGRESS.md`, naming a deliverable commit and a test result for every task. It
  just did not tick the plan checkboxes. The handoff asked whether `PLAN-PROGRESS.md` grew as a
  workaround for awkward ticking. It did not: `docs/development/workflow.md` stage 4 specifies it
  ("two local commits per task boundary, the deliverable then the progress line"), and stage 9
  deletes it. So both records are deliberate. What stays open is that two places record the same
  thing and only one is checked. Settle at Design whether the plan ticks should be derived from
  the progress file rather than written twice.
- **The `code` filter is the wrong one to reuse.** `.github/code-paths-filter.yml` excludes
  `!scripts/**/*.ps1` and `!tests/*.ps1`, so a process-tooling pull request counts as "not code",
  including this item's own. It was drawn for the coverage gate, which asks a different question.
  A design that reuses it would be blind to the item class this repository files most often.
- Source: `.superpowers/handoff-close-the-item-in-the-shipping-pr.md`, written 2026-09-10 by the
  housekeeping round on `chore/wt-backlog-housekeeping`. That folder is gitignored.
- ADR: `docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md`
- Terms pinned in `CONTEXT.md`: Acceptance box, Records closed, Shipping pull request.
- Spec: `docs/superpowers/specs/2026-09-10-close-the-item-in-the-shipping-pr-design-151.md`
- Plan: <path, or "none — reason">
