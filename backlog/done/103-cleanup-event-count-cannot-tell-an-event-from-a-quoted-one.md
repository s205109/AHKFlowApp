# 103 - Cleanup event count cannot tell an event from a quoted one

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 9-ship
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

- [x] Every one of the 18 rows in
      `docs/development/friction-samples/ledgers/cleanup-events.csv` is labelled, and the
      labels are committed.
      **This box asked for a different label, and the wording is corrected rather than
      stretched.** It asked for each row to be marked a reported event or a quoted one. The
      labelling found that split does not exist: a tool result is a read of the same
      persistent log that a human paste reads, and the line's own stamp is the event time in
      both. So each row carries a mechanical `Route` of `tool-result` or `human-paste`, taken
      from record fields, plus one hand-checked column `IsGenuineLogLine`. The labels are in
      `docs/development/friction-samples/cleanup-events-labelled.csv`.
- [x] The published figure is replaced with the labelled result, in
      `backlog/done/072-process-wave-2-parity-drift-guard-templates.md` and in
      `docs/development/friction-recall-sample.md`. Both now name the unit: the figure counts
      cleanup outcome **log lines**, never cleanup runs. One removal writes several lines.
- [x] A decision is recorded on event identity, in
      `docs/development/cleanup-event-identity.md`.
      **The decision is neither of the two this box offered.** It offered a rule that tells a
      report from a quote, or a statement that the count is an upper bound. No such rule
      exists, and the count is a floor rather than an upper bound. The removal log holds 201
      distinct in-window outcome log lines, 15 of which a transcript witnessed. The other 3
      witnessed lines predate the log, so the witnessed share is a ceiling of about nine
      percent rather than a measurement of it. The matching box in backlog 072 therefore
      stays unticked, because neither branch it offered came true.
- [x] The deduplication comment in `scripts/measure-process-friction.ps1` is corrected, and the
      collapse case is stated rather than fixed. The line carries no event id to fix it with,
      and all 295 outcome lines in the log are distinct, so the collapse has never happened.

## Out of scope

- The other four metrics. Backlog 101 covers directory-bound commands; 102 covers the recall
  samples.
- Changing what `Write-WorktreeLog` writes. A richer line would help, but rewriting the log
  format to make a measurement easier is a separate decision.

## What the labelling found

Measured on 2026-08-21. The committed CSVs are the record. They are dated snapshots of one
machine: both inputs — the session transcripts under `~/.claude/projects` and
`.claude/worktrees/worktree-removal.log` — are machine-local and gitignored, so re-running the
two scripts elsewhere measures that machine and prints different numbers. Audit the figures
against the committed rows, not against a re-run.

- **All 18 rows are genuine log lines.** None is source code, an injected instruction, or a
  paraphrase. The metric over-flags nothing. The labels prove authenticity and nothing more:
  the record fields are identical whether a line was read as it was written or quoted weeks
  later, so they cannot separate an original read from a quotation.
- **14 arrived as tool results and 4 in one human-typed message.** The four came from a single
  process brief that pasted a tail of the removal log as evidence.
- **The reported-against-quoted split does not exist.** A tool result is not a live report. One
  row arrived on 2026-07-30 carrying an event stamped 2026-07-29, because the tool read the log
  tail. Both routes read the same persistent file.
- **Every figure here counts log lines, not cleanup runs.** One removal writes several lines:
  of the log's 201 in-window rows, 91 are `Watcher started.` and 87 are `Watcher done (`,
  across 64 named worktrees. Reading 201 as a count of popups, blocked runs or removals
  over-states the real number by more than a factor of two.
- **18 is a floor, not an upper bound.** The removal log holds 201 distinct in-window outcome
  log lines, and 15 of the 18 witnessed rows are among them. The other 3 are stamped
  2026-07-25, before the log's earliest surviving line, so they sit inside the window and
  outside the log. The true in-window population is therefore 204 log lines or more, 186 of the
  201 log lines reached no session, and the witnessed share is a ceiling of about nine percent.
  The 201 is itself a floor, because the log survives back to 2026-07-26 only and the window
  opens on 2026-07-15.
- **The deduplication comment was wrong about its reason.** Only `Watcher started.` lines carry
  a process id — 134 of 134, against 0 of 130 `Watcher done (` lines. The collapse it feared is
  real but has never happened: all 295 outcome lines in the log are distinct.

Artifacts: `docs/development/cleanup-event-identity.md`,
`docs/development/friction-samples/cleanup-events-labelled.csv`,
`docs/development/friction-samples/ledgers/cleanup-log-events.csv`,
`scripts/label-cleanup-events.ps1`, `scripts/measure-cleanup-log-events.ps1`,
`tests/CleanupEventLabels.Tests.ps1`.

## Notes / dependencies

- The measurement requirement in
  `backlog/done/072-process-wave-2-parity-drift-guard-templates.md` still does not hold for this
  metric, and its box records why. Neither branch it offered came true: no rule separates an
  original read from a quotation, and the figure is a floor rather than an upper bound. The box
  also stays unticked for directory-bound commands, because backlog 101 closed on 2026-08-20
  without implementation.
- Spec: none — Design has not run.
- Plan: `docs/superpowers/plans/2026-08-20-cleanup-event-identity-plan-103.md`
