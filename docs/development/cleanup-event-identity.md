# What the cleanup event count measures

Friction metric 3 counts cleanup outcome log lines. Backlog 103 labelled every row it published
and recorded the rule below. Read this before you quote the figure, change the metric, or add a
row to the ledger.

The measured artifacts are:

- `friction-samples/ledgers/cleanup-events.csv` — the frozen ledger, the 18 rows the metric
  produced.
- `friction-samples/cleanup-events-labelled.csv` — the same 18 rows with their labels.
- `friction-samples/ledgers/cleanup-log-events.csv` — the removal log's own in-window rows.

**All three are dated snapshots, not figures a second machine can regenerate.** They were
measured on 2026-08-21. The two inputs behind them are machine-local and gitignored: the session
transcripts under `~/.claude/projects`, and `.claude/worktrees/worktree-removal.log`
(`.gitignore:451`, ".claude/worktrees/"). Each records only what happened on that machine, and
the removal log does not reach back to the start of the window. Re-running either script on
another machine measures that machine, and prints different numbers. The committed rows are
what makes the published figures auditable; re-running is not.

## 1. What the metric counts

**A distinct cleanup outcome log line that appears in an in-window session transcript.**

It is not a count of cleanup events, it is not a count of cleanup runs, and it is not a count
of messages.

**One removal writes several lines, so the figure is larger than the number of removals behind
it.** In `friction-samples/ledgers/cleanup-log-events.csv`, 91 of the 201 rows are
`Watcher started.` and 87 are `Watcher done (`, across 64 named worktrees. Those two lines
bracket one removal. So a reader who takes 201 as a count of popups, blocked runs, or removals
over-states the real number by more than a factor of two. Every published figure in this file
counts lines.

Each of those three words carries weight:

- **Log line.** Every cleanup outcome reaches a transcript as a line written by
  `Write-WorktreeLog`, which stamps it `yyyy-MM-dd HH:mm:ss  <worktree>  <message>`
  (`scripts/worktree-log.common.ps1:92`, "    return '{0}  {1}  {2}' -f $stamp, $Worktree, $single").
  A line counts when it has that shape and its message starts with something a cleanup script
  writes. The shape rule is
  (`scripts/measure-process-friction.ps1:100`, "$script:CleanupLogLinePattern = ")
  and the message rule is
  (`scripts/measure-process-friction.ps1:104`, "$script:CleanupOutcomePatterns = @(").
- **Distinct.** The same line read twice is one event. One tool result can carry the whole
  tail of the log, and a session often reads that tail more than once.
- **In a transcript.** A cleanup event that no session ever read is invisible to this metric.
  Section 5 gives the size of that gap.
- **In-window.** The window is fixed
  (`scripts/measure-process-friction.ps1:74`, "$script:WindowStart = [datetime]::Parse('2026-07-15T14:14:32Z').ToUniversalTime()")
  and runs four weeks, to 2026-08-12.

## 2. Why "reported" against "quoted" is the wrong split

Backlog 103 was filed to split the 18 rows into events that were reported and events that
were only quoted. The labelling ran, and the split does not exist.

**Both routes into a transcript are a read of the same persistent file.** A tool result is not
a live report. Record `59bd1489-e2bb-410d-b280-63c48f69bb18` arrived on 2026-07-30 and carried
an event stamped 2026-07-29 21:11:10, because the Bash tool read the tail of the log. A person
who pastes the same tail does the same thing by hand.

So the line's own stamp is the event time in both cases. The message timestamp is only the
moment somebody looked. Treating one route as a real event and the other as talk about an
event would draw a line where the data has none.

`Get-CleanupEventLine`
(`scripts/measure-process-friction.ps1:401`, "function Get-CleanupEventLine {")
therefore counts both, and that is deliberate rather than a defect to patch.

## 3. The route label that is worth keeping

The split that does survive is how the line entered the transcript. It is decided from record
fields, never from reading the text. The first rule that matches wins, so a record that answers
to both is a tool result:

| Order | Label | How the record is recognised |
|---|---|---|
| 1 | `tool-result` | the record has a `toolUseResult` field |
| 2 | `human-paste` | `Test-HumanTurn` says so: `type` is `user`, **and** either `origin.kind` is `human` or `promptSource` is `typed`, `suggestion_accepted` or `queued` |
| 3 | `unresolved` | neither rule matched, or no record answers to the row's `Key` |

The precedence is
(`scripts/label-cleanup-events.ps1:218`, "function Get-RecordRoute {"),
and the second rule is the metric's own human-turn rule, called rather than copied
(`scripts/measure-process-friction.ps1:181`, "function Test-HumanTurn {"),
so the two agree by construction. Because the rule is mechanical,
`scripts/label-cleanup-events.ps1` computes the label instead of a person judging it.

`unresolved` is a real output of the script. It must never reach the committed file, because an
unresolved row is a row nobody labelled, and `tests/CleanupEventLabels.Tests.ps1` fails one.

A row's `Key` is the identity the metric wrote for its record: `msg:<message.id>` when the
record carries a message id, `uuid:<uuid>` otherwise
(`scripts/measure-process-friction.ps1:265`, "function Get-MessageKey {").
The labeller looks up both. Its third form, `text:<text>`, names no record and cannot be
resolved; the same test fails a ledger row that carries one.

The label answers a real question — how cleanup outcomes reach a conversation — without
claiming one route is more real than the other.

## 4. The one judgment column

`IsGenuineLogLine` is the only column a person fills in. It asks whether the line is real
`Write-WorktreeLog` output, rather than one of the three things the earlier version of this
metric counted by mistake: the cleanup script's own source code, an injected skill
instruction, or a paraphrase of an outcome.

It is checked against `.claude/worktrees/worktree-removal.log` where the log still reaches
back, and by reading the record where it does not.

All 18 published rows read `yes`.

**What `yes` proves, and what it does not.** It proves the text is real `Write-WorktreeLog`
output rather than invented text or a paraphrase. It does not say when the line was read. The
same genuine line can arrive the moment it is written, or in a log tail read weeks later, or in
a quotation inside a later review, and the record fields are identical in all three. So the
labels rule out fabrication. They do not separate an original read from a later quotation, and
section 2 explains why that separation would draw a line the data does not have.

## 5. The decision: the count is a floor

**18 is a floor, not an upper bound.**

The removal log is the closest thing to the size of the real population. It holds 201 distinct
outcome lines inside the window.

**The 18 witnessed rows are not a subset of those 201, so do not divide one by the other.** 15
of the 18 are in the log. The other 3 are stamped 2026-07-25, which is before the log's earliest
surviving line, so they are inside the window but outside the log. That puts the true in-window
population at 204 or more: the log's 201, plus at least those 3.

So the witnessed share is **at most about nine percent**, and probably less. 18 out of 204 is
8.8 percent, and 204 is itself a floor — every event the log has since lost pushes the
denominator up and the share down. The share is a ceiling for the same reason the count is a
floor.

The count can be wrong in two directions, and only one of them is small:

1. **Events that no transcript ever carried are invisible.** This is the large one. 186 of the
   201 log lines reached no session that the metric read, and the true number of unwitnessed
   events is higher still, because the log does not reach the start of the window.
2. **Two genuine events that produced identical lines fold into one.** The line has
   one-second resolution and carries no event id, so two events in the same second, in the
   same worktree, with the same message cannot be told apart. This has never happened: all
   295 outcome lines in the log are distinct.

Nothing in the count runs the other way. All 18 rows are genuine log lines, so the metric
over-flags nothing.

The 201 is itself a floor for the window. The log survives back to 2026-07-26 only, and the
window opens on 2026-07-15. The true count for those first eleven days cannot be recovered,
and this file does not estimate it.

## 6. The log shape changed on 2026-08-21

Backlog 073 split the removal log in two. From that date `worktree-removal.log` carries one line
per removal attempt and nothing else, and everything that used to sit beside the outcome moved to
`worktree-removal-diagnostics.log`.

So the file holds two shapes, and **a count that spans the change is not a like-for-like figure**.
Before the change one removal wrote about twenty lines, of which several matched an outcome
pattern. After it, one removal writes one. A drop in this count across that date measures the
change in the log, not a change in cleanup friction.

The frozen ledgers were measured on 2026-08-21, before the split, and are untouched. Both sets of
patterns live in `scripts/measure-process-friction.ps1`, so a re-run still reads the historical
part of the file correctly.
