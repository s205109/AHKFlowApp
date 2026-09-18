# 157 - Make the size of a batch visible before Execute starts

## Metadata

- **Epic**: Development process
- **Type**: Process / CI
- **Interfaces**: none (workflow documents, a new Check)
- **Difficulty**: complex
- **Stage**: 8-review

## Summary

A plan lists its tasks, and a backlog item lists its acceptance criteria. No document joins
the two lists, and no document says how long the work will take. So a plan can carry a batch
that merges one time, at the end, and nobody sees the size of the batch until the branch is
days old.

Two answers are on the table. One makes the batch visible. The other stops the batch from
growing that large. The person who picks this item chooses one, and writes down why. Read
"The choice to make at pickup" before you write the spec.

## User story

As a person who reads a plan before Execute starts, I want the plan to tell me how large the
work really is, so that I see the size before the work starts and not four days later.

## The choice to make at pickup

Read both. Pick one. Write the choice and the reason into this item and into the spec.

### Approach A - the pull request map

**Design deleted this branch.** Approach A is deferred, not rejected. Its description and the
reason it lost are kept in
[`docs/adr/0019-a-plan-declares-its-split-and-its-extension.md`](../docs/adr/0019-a-plan-declares-its-split-and-its-extension.md),
under "Considered options". Nothing here needs it, and a future item can pick it up.

### Approach B - a size budget at Plan

The Plan stage states an estimate in work sessions. When the estimate is more than two
sessions, the item is split into stacked items before Execute starts. A cheap Check counts
`## Task` headings in the plan and reports a problem for a `complex` item at Stage
`4-execute` with more than three tasks.

- **What it gives you.** A limit, not a report. The batch does not get to exist. This is the
  pain you named: a plan that does not fit one or two 5-hour sessions costs cold starts, and
  a cold start with a large plan in context is expensive.
- **What it costs.** An estimate is a guess, and a wrong guess is either a false alarm or a
  free pass. A task-count threshold is a rough measure of size. A plan can carry three heavy
  tasks or eight light ones.
- **Why the threshold is worth setting anyway.** The repository already treats four or more
  independent tasks as the point where a `complex` item goes to subagent-driven execution
  (`docs/development/workflow.md:475`, "plus four or more independent tasks"). That rule adds
  agents. It does not reduce work.
- **The weakness.** Nobody has read real task counts across several items yet. Setting the
  threshold at three is a guess until somebody does.

### A third option

Take Approach B now and leave Approach A for later. The two do not conflict. If you do both
at once, this item becomes the shape it is trying to prevent.

## The choice made at pickup

**Chosen: Approach B, a size budget at Plan. Approach A is deferred, not rejected.** This is
the third option the section above describes: take B now, leave A for later.

**Why.** A limit beats a report. Both reviews of the first version of this item said so, and
the 146 evidence agrees. A map of that item would have read "one criterion, seven tasks", and
the work would still have run for four days.

**What pickup measured.** The section above says the threshold of three is a guess "until
somebody does" read real task counts. Pickup read them, across all 209 committed plans in
`docs/superpowers/plans/`:

- Plans write `### Task N:`, not `## Task`. The Check that Approach B describes counts the
  wrong heading level. It would read zero tasks for most plans and pass them all.
- 168 of the 209 plans carry numbered tasks. The median is 6 tasks, p75 is 8, and p85 is 10.
- A threshold of three would report a problem for 145 of those 168 plans, and for 18 of the
  30 newest. A Check that fails the middle of the population is noise, not a limit.
- Task count is a weak measure of size. Across the last 15 shipped items, task count matches
  the number of commits that touched the item's own file at r = 0.40. Plan length does a little
  better at r = 0.50. That proxy is rough and the sample is small.
- The two extremes prove the point the section above makes. Item 146 carries 8 tasks in 699
  lines. Item 156 carries 3 tasks in 1254 lines. A three-task threshold would stop 146 and
  wave 156 through, even though 156 is the larger plan by volume.

**What Design must settle.** The direction is right. The mechanism in the section above is
not. Design carries these three questions into the spec:

1. The session estimate names the pain directly, because the pain is the cost of a cold
   start. Design decides whether the estimate, not the task count, is what the Check requires.
2. If the task count stays, it is a second and cheap trigger only, and its threshold comes
   from the measured distribution above rather than from a guess.
3. The Check counts `### Task N:` with a pattern that ignores heading level, so it reads the
   plans this repository actually writes.

Design settled all three. The estimate is the required record. The task count is gone
entirely, because no threshold separates 146 from healthy work. A count of the plan lines that
name a test-run command replaced it. The spec gives the numbers.

## Acceptance criteria

Criterion 1 picks the branch. Design then deletes the branch it did not choose from this
list, and writes into this item which branch it deleted.

- [x] The person who picks this item reads "The choice to make at pickup", chooses one
      approach, and records the choice and the reason in this item and in the spec.
- [x] `docs/development/workflow.md` carries the new rule. It names the stage that applies the
      rule, names the Difficulty values the rule covers, and says what the writer must record.
      `workflow.md` is the Source, so the rule lives there first.
- [x] `AGENTS.md` and `.claude/CLAUDE.md` each carry one rule line that links to the new
      `workflow.md` section, in the same form the rule lines around it use.
- [x] A PowerShell suite reports a problem when the record the chosen approach requires is
      missing, for an item that needs one and stands at Stage `4-execute` or later.
- [x] The same suite reports a problem when a plan carries no session estimate, and when it
      carries no line naming the task at which the user story closes.
- [x] The same suite reports a problem when a plan meets the split trigger and carries no split
      verdict. The trigger is an estimate over two sessions, or fifteen or more plan lines that
      name a test-run command.
- [x] The same suite reports no problem for an item whose plan pointer reads `- Plan: none`,
      and for an item that has not reached the stage that writes the record.
- [x] The suite is listed in `tests/powershell-suites.json`, with a measured baseline and a
      platform array backed by a recorded run.
- [x] The plan for this item states its own estimate in work sessions, and that estimate is two
      sessions or fewer. If the first draft is larger, the item is split into stacked items
      before Execute starts. This item must not repeat the shape it describes.

## Out of scope

- A limit on how many tasks one acceptance criterion may need, under Approach A. The record
  makes that number visible. Nobody sets a threshold yet. Read the real numbers from two or
  three items first.
- The decision to split, under Approach A. The Check proves the record exists and is complete.
  A person reads it and decides whether the item is two items.
- Rewriting plans that are already committed. This item changes the rule from now on.
- A second plan under one backlog item. One item keeps one `- Plan:` bullet, and that does not
  change.
- Backlog item 146 itself. Its work shipped. This item does not reopen it.

## Notes / dependencies

- **Where this came from.** Backlog item 146 carried 7 acceptance criteria. Its plan carried 8
  tasks and 696 lines. Nothing joined the two lists, so nothing showed that one acceptance
  criterion needed seven of the eight tasks. The branch ran from 2026-09-13 to 2026-09-17. It
  merged one time, at the end, and took `main` in twice. Five commits on 2026-09-16 only
  repaired drift that the branch age caused.
- **Measured cost of that batch.** The implementing session took 11 turns and 3 hours 15 minutes
  of agent time, spread over 50 hours of wall clock. It started 19 subagents, stopped 6 times on
  an account usage limit, and compacted twice. Task 5 of 8 closed the user story. Tasks 6 and 7
  extended one acceptance criterion to a second surface and cost two further sessions.
- **The review verdict this item now carries.** Two independent reviews of the first version of
  this item reached the same answer: the diagnosis is right, and the pull request map is a weak
  lever for the pain. Both said the same thing in different words. "A map makes a large batch
  visible. You need the batch not to exist." Both also warned that a Check reading a private
  plan is itself a `complex` item, because CI cannot read `docs/superpowers/`. That warning is
  why Approach A now says the record belongs in the public backlog item.
- **The session evidence behind the verdict.** The reviewed Codex session is the 146 Execute
  start. Its working directory was the 146 worktree, and it began at the `PLAN-PROGRESS` commit
  `108072ba`. The session log carries 11 turn-context events, 16 user-role payloads, and about
  48 usage-limit or compaction hits, alongside a second reviewer thread. Every cold start
  reloaded the whole 696-line plan.
- **The rule this strengthens already exists.** "Keep a PR focused on a single concern; split a
  large change into stacked PRs", in the Git Workflow section of `AGENTS.md`. Item 146 did not
  apply it, because nothing made the size visible at Plan.
- **Shape to copy.** `tests/BacklogPlanPointer.Tests.ps1` proves a `- Plan:` bullet exists and
  never judges the plan behind it. The new suite proves the record exists and is complete, and
  never judges the split. Design found a closer model: `scripts/check-shipped-plan-ticked.ps1`
  opens the plan at pre-push, and `tests/ShippedPlanTicked.Tests.ps1` proves its rule on
  fixtures. The new check must open the plan too, so it copies that pair. See the spec.
- **A limit Approach A accepts.** The Check cannot fail backlog item 146 on its own. Criterion 1
  of that item reads "Two local test runs started from different checkouts of this repository
  share one limit", and a .NET run is a local test run, so every task maps to it and no cell is
  empty. What the record gives a reader is the fan-out number: one criterion, seven tasks. The
  number is the signal, and a person reads it.
- Spec: `docs/superpowers/specs/2026-09-17-plan-split-record-design-157.md`
- Design deleted the Approach A branch. The choice, the measurements behind it, and the three
  new glossary terms are in the spec. The rejected alternatives are in ADR 0019.
- **Suite evidence.** On 2026-09-18, `tests/PlanSplitRecord.Tests.ps1` passed on Windows 11 under
  `scripts/run-powershell-suites.ps1`, in 4.4 seconds, which is the manifest baseline. It also
  passed on Linux in Docker, image `mcr.microsoft.com/powershell:latest`, with the repository
  mounted read-only and git installed in the container. So the manifest carries
  `["windows","linux"]`.
- Plan: `docs/superpowers/plans/2026-09-18-plan-split-record-plan-157.md`
