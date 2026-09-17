# 157 - A plan declares its pull requests and the criteria each closes

## Metadata

- **Epic**: Development process
- **Type**: Process / CI
- **Interfaces**: none (workflow documents, a new Check)
- **Difficulty**: complex
- **Stage**: 0-intake

## Summary

A plan lists its tasks, and a backlog item lists its acceptance criteria. No document joins
the two lists. So a plan can carry a batch of work that merges one time, at the end, and
nobody sees the batch until the branch is days old. This item adds the record that joins
them, and a Check that proves the record is complete.

## User story

As a person who reads a plan before Execute starts, I want the plan to say which pull request
closes which acceptance criterion, so that I see a batch before the work starts and not four
days later.

## Acceptance criteria

- [ ] One document records, for each pull request the work will open, the tasks it ships and
      the acceptance criteria it closes. Design decides whether that document is the plan or
      the backlog item, and records the reason.
- [ ] `docs/development/workflow.md` requires that record, names the stage that writes it, and
      names the Difficulty values it applies to. `workflow.md` is the Source, so the rule lives
      there first.
- [ ] `AGENTS.md` and `.claude/CLAUDE.md` each carry one rule line that links to the new
      `workflow.md` section, in the same form the rule lines around it use.
- [ ] A PowerShell suite reports a problem when the record is missing, for an item that needs
      one and stands at Stage `4-execute` or later.
- [ ] The same suite reports a problem when the record omits a task the plan defines.
- [ ] The same suite reports a problem when the record omits an acceptance criterion the item
      defines.
- [ ] The same suite reports no problem for an item whose Difficulty does not need the record,
      and for an item that has not reached the stage that writes it.
- [ ] The suite is listed in `tests/powershell-suites.json`, with a measured baseline and a
      platform array backed by a recorded run.

## Out of scope

- A limit on how many tasks one acceptance criterion may need. The record makes that number
  visible. Nobody sets a threshold yet. Read the real numbers from two or three items first.
- The decision to split. The Check proves the record exists and is complete. A person reads it
  and decides whether the item is two items.
- Rewriting plans that are already committed. This item changes the rule from now on.
- A second plan under one backlog item. One item keeps one `- Plan:` bullet, and that does not
  change.
- Backlog item 146 itself. Its work shipped. This item does not reopen it.

## Notes / dependencies

- **Where this came from.** Backlog item 146 carried 7 acceptance criteria. Its plan carried 8
  tasks. Nothing joined the two lists, so nothing showed that one acceptance criterion needed
  seven of the eight tasks. The branch ran from 2026-09-13 to 2026-09-17. It merged one time,
  at the end, and took `main` in twice. Five commits on 2026-09-16 only repaired drift that the
  branch age caused.
- **Measured cost of that batch.** The implementing session took 11 turns and 3 hours 15 minutes
  of agent time, spread over 50 hours of wall clock. It started 19 subagents, stopped 6 times on
  an account usage limit, and compacted twice. Task 5 of 8 closed the user story. Tasks 6 and 7
  extended one acceptance criterion to a second surface and cost two further sessions.
- **The rule this strengthens already exists.** "Keep a PR focused on a single concern; split a
  large change into stacked PRs", in the Git Workflow section of `AGENTS.md`. Item 146 did not
  apply it, because no record made the batch visible at Plan.
- **Shape to copy.** `tests/BacklogPlanPointer.Tests.ps1` proves a `- Plan:` bullet exists and
  never judges the plan behind it. The new suite proves the record exists and is complete, and
  never judges the split.
- **The open design question, and why this item is `complex`.** A plan lives in
  `docs/superpowers/`, a separate private repository that a worktree links in. A hosted CI run
  clones the public repository only, so a Check that runs in CI may not be able to read a plan at
  all. That splits the design two ways: put the record in the plan and check it locally, or put
  the record in the backlog item, which is public, and check it in CI. Design answers this first,
  because the answer changes every other part of the item.
- **A limit this item accepts.** The Check cannot fail backlog item 146 on its own. Criterion 1
  of that item reads "Two local test runs started from different checkouts of this repository
  share one limit", and a .NET run is a local test run, so every task maps to it and no cell is
  empty. What the record gives a reader is the fan-out number: one criterion, seven tasks. The
  number is the signal, and a person reads it.
- Spec: none yet - Design writes it.
- Plan: none - filed at Intake. The Plan stage writes the path here.
