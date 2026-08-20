# What the cleanup event count measures

Friction metric 3 counts cleanup events. Backlog 103 labelled every row it published and
recorded the rule below. Read this before you quote the figure, change the metric, or add a
row to the ledger.

The measured artifacts are:

- `friction-samples/ledgers/cleanup-events.csv` — the frozen ledger, the 18 rows the metric
  produced.
- `friction-samples/cleanup-events-labelled.csv` — the same 18 rows with their labels.
- `friction-samples/ledgers/cleanup-log-events.csv` — the removal log's own in-window rows.

## 1. What the metric counts

**A distinct cleanup outcome log line that appears in an in-window session transcript.**

It is not a count of cleanup events, and it is not a count of messages.

Each of those three words carries weight:

- **Log line.** Every cleanup outcome reaches a transcript as a line written by
  `Write-WorktreeLog`, which stamps it `yyyy-MM-dd HH:mm:ss  <worktree>  <message>`
  (`scripts/worktree-log.common.ps1:22`, "    $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $Message").
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
(`scripts/measure-process-friction.ps1:394`, "function Get-CleanupEventLine {")
therefore counts both, and that is deliberate rather than a defect to patch.

## 3. The route label that is worth keeping

The split that does survive is how the line entered the transcript. It is decided from record
fields, never from reading the text:

| Label | How the record is recognised |
|---|---|
| `human-paste` | `promptSource` is `typed`, or `origin.kind` is `human` |
| `tool-result` | the record has a `toolUseResult` field and a `tool_result` content block |

Those are the same fields the metric's own human-turn rule reads
(`scripts/measure-process-friction.ps1:174`, "function Test-HumanTurn {"),
so the two agree by construction. Because the rule is mechanical,
`scripts/label-cleanup-events.ps1` computes the label instead of a person judging it.

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

## 5. The decision: the count is a floor

**18 is a floor, not an upper bound.**

The removal log is the size of the real population. It holds 201 distinct outcome lines inside
the window. The transcripts witnessed 18 of them, which is about nine percent.

The count can be wrong in two directions, and only one of them is small:

1. **Events that no transcript ever carried are invisible.** This is the large one. At least
   183 in-window outcomes never reached a session that the metric read.
2. **Two genuine events that produced identical lines fold into one.** The line has
   one-second resolution and carries no event id, so two events in the same second, in the
   same worktree, with the same message cannot be told apart. This has never happened: all
   295 outcome lines in the log are distinct.

Nothing in the count runs the other way. All 18 rows are genuine log lines, so the metric
over-flags nothing.

The 201 is itself a floor for the window. The log survives back to 2026-07-26 only, and the
window opens on 2026-07-15. The true count for those first eleven days cannot be recovered,
and this file does not estimate it.
