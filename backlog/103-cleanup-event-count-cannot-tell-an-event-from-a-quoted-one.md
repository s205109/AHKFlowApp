# 103 - Cleanup event count cannot tell an event from a quoted one

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 1-pickup
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

Backlog 072 says the cleanup metric separates a real event from discussion of one, because
discussion never carries the log stamp. It is not true. The metric reads every message type and
counts any line with the stamp shape whose message starts with a cleanup script's wording, so a
message that quotes a log line counts as an event.

## User story

As a contributor reading the five friction counts, I want each one to say whether it separates
an event from talk about an event, so that the table does not carry a claim that only holds for
some rows.

## The defect

`Get-CleanupEventLine` in `scripts/measure-process-friction.ps1` identifies an event by line
shape and wording alone. The metric also reads every message type on purpose, because the agent
reports cleanup outcomes as often as a tool does. Together those two facts mean a quoted line is
indistinguishable from a reported one: `tests/ProcessFriction.Tests.ps1` asserts exactly that a
stamped line inside a longer message counts, which is right for a tool result carrying the log
tail and wrong for a review quoting one.

The published 18 lines may therefore hold quoted lines. Nobody has checked which.

Deduplication has a second, smaller problem. Two identical lines are treated as one event, and
the code says the stamp, the worktree and the process id make that safe. Most outcome lines
carry no process id — only `Watcher started.` does — and the stamp has one-second resolution. So
two genuinely separate events in the same second, in the same worktree, with the same message
collapse into one.

## Acceptance criteria

- [ ] Every one of the 18 rows in
      `docs/development/friction-samples/ledgers/cleanup-events.csv` is labelled by hand as a
      reported event or a quoted one, and the labels are committed.
- [ ] The published figure is replaced with the labelled result, in
      `backlog/done/072-process-wave-2-parity-drift-guard-templates.md` and in
      `docs/development/friction-recall-sample.md`.
- [ ] A decision is recorded on event identity: either a rule that tells a report from a quote,
      or a plain statement that the count is an upper bound and why.
- [ ] The deduplication comment in `scripts/measure-process-friction.ps1` is corrected, and the
      collapse case is either fixed or stated.

## Out of scope

- The other four metrics. Backlog 101 covers directory-bound commands; 102 covers the recall
  samples.
- Changing what `Write-WorktreeLog` writes. A richer line would help, but rewriting the log
  format to make a measurement easier is a separate decision.

## Notes / dependencies

- The unticked measurement requirement lives in
  `backlog/done/072-process-wave-2-parity-drift-guard-templates.md` and now names this metric
  as well as directory-bound commands.
- Spec: none — Design has not run.
- Plan: none — the item is at Intake.
