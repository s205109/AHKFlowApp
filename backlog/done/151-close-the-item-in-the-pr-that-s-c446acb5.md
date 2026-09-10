# 151 - Close the item in the PR that ships its work

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (script, CI)
- **Difficulty**: complex
- **Stage**: 4-execute

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

Design settled the invariant as two conditions held together. The criteria below name it that
way. The earlier one-condition wording is superseded; see the ADR for why one condition alone
cannot work.

### The rule fires

- [x] The check reports an item still in `backlog/` when the pull request is not a draft and
      every acceptance box in that item is ticked.
- [x] Replaying pull request #400's head against its merge base, with the draft state given as
      not a draft, makes the check report item 132.
- [x] The check reports a `PLAN-PROGRESS.md` that survives into a not-a-draft pull request, as
      its own problem line, separate from the folder and the `Stage` line.

### The rule stays quiet

- [x] A draft pull request whose item has every box ticked does not trigger the check. That is
      the Document-to-Ship window `workflow.md` specifies.
- [x] An item with at least one unticked acceptance box does not trigger the check, whatever its
      stage and whatever the draft state. Most items ship over more than one pull request.
- [x] An item with no `## Acceptance criteria` section, or a section holding no boxes, does not
      trigger the check.
- [x] A branch that only edits an item already in `backlog/done/` does not trigger the check.
- [x] `backlog/000-backlog-item-template.md` is never judged.

### Parsing

- [x] A checkbox outside the `## Acceptance criteria` section is not counted. Item 072's unticked
      box under `## Friction baselines` does not change its verdict.
- [x] A checkbox under a `###` subheading inside the acceptance section is counted. Items 121 and
      122 group their criteria that way.
- [x] A checkbox inside a fenced code block is not counted.
- [x] Only a checkbox starting at column zero is counted.

### Wiring

- [x] The script takes the draft state as a parameter, and the suite exercises both values.
- [x] `ci.yml` runs the check when a pull request is flipped to ready.
- [x] A third arm on `Get-BacklogStaleOpenProblem` reports an item whose records already merged
      with every box ticked and a `Stage` below `9-ship`, with its own message, and without
      depending on the threshold of 12.
- [x] The script header states the invariant, both conditions, and why each single-condition rule
      was rejected, naming item 106.
- [x] Every existing PowerShell suite still passes, and the new suite joins
      `tests/powershell-suites.json` with its `jobs` and `platform` arrays set.

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
  thing and only one is checked. **Design settled this: out of scope here, and it gets its own
  item.** Deriving the plan ticks from the progress file changes what a plan file means, which is
  a bigger decision than this item.
- **The `code` filter is the wrong one to reuse.** `.github/code-paths-filter.yml` excludes
  `!scripts/**/*.ps1` and `!tests/*.ps1`, so a process-tooling pull request counts as "not code",
  including this item's own. It was drawn for the coverage gate, which asks a different question.
  A design that reuses it would be blind to the item class this repository files most often.
- Source: `.superpowers/handoff-close-the-item-in-the-shipping-pr.md`, written 2026-09-10 by the
  housekeeping round on `chore/wt-backlog-housekeeping`. That folder is gitignored.
- ADR: `docs/adr/0016-a-shipping-pull-request-is-ready-and-fully-ticked.md`
- Terms pinned in `CONTEXT.md`: Acceptance box, Records closed, Shipping pull request.
- Spec: `docs/superpowers/specs/2026-09-10-close-the-item-in-the-shipping-pr-design-151.md`
- Plan: `docs/superpowers/plans/2026-09-10-close-the-item-in-the-shipping-pr-plan-151.md`
- **What one `ready_for_review` run costs.** Measured on this branch's five most recent CI runs
  on 2026-09-10: 9m33s, 10m49s, 8m23s, 10m20s, 10m45s. So about ten minutes of wall-clock time,
  once per item at Ship. That is the number the grilling decision assumed was small, and it sits
  right at the ten-minute line the plan named as the point to reconsider. Moving the check into
  its own small workflow would cut it to well under a minute, and it stays worth filing as a
  follow-up. It is not filed yet.
- **A defect this item found and did not fix.** `PLAN-PROGRESS.md` is still tracked on `main`,
  holding backlog 132's progress. Stage 9 requires deleting it, and the housekeeping round that
  closed backlog 132 missed that part. This branch overwrote the content, which moves the defect
  out of sight rather than fixing it on `main`. A housekeeping round should delete it there.
