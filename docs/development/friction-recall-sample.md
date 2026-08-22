# Friction measurement: the labelled sample

`scripts/measure-process-friction.ps1` counts five things. Two of them match on wording, and a
word list gives a repeatable number rather than a right one. This file records what those two
metrics caught, what they missed, and how each label was decided.

The evidence is committed beside it:

| File | What it holds |
|---|---|
| `friction-samples/handoffs-sample.csv` | 15 flagged messages and 200 sampled unflagged ones, each with full text, key, session and label |
| `friction-samples/next-step-asks-sample.csv` | 29 flagged and 200 sampled unflagged, same columns |
| `friction-samples/*-sample.selection.json` | The selection record for each draw: the transcript root, population size, ordered-key digest, drawn positions, drawn keys |
| `friction-samples/*-sample-2026-08-16.csv` and `.selection.json` | The earlier draw, kept whole. It is the only record of nine flagged asks the transcripts no longer hold |
| `friction-samples/ledgers/*.csv` | One row per counted item for the four transcript metrics, and one row per in-window CI run |

Redraw either sample with:

```powershell
pwsh ./scripts/sample-friction-recall.ps1 `
  -Metric handoffs `
  -ProjectRoot "$HOME/AHKFlowApp-friction-snapshot-2026-08-21" `
  -OutputPath docs/development/friction-samples/handoffs-sample.csv `
  -SampleSize 200 `
  -ExistingManifest docs/development/friction-samples/handoffs-sample.csv
```

**Always pass `-ExistingManifest`.** It carries the labels and the row ids across a re-run. It
does not change which rows are drawn — see "How the draw picks a row" — but without it every
hand-written label is written out empty, and a hand-written label is the only thing this step
produces.

**`-ProjectRoot` decides which copy of the transcripts the draw reads.** It defaults to
`~/.claude/projects`, which is the live folder that retention deletes from. The published figures
below read the copy named in the next section.

## What changed since 2026-08-16

Three things changed at the same time. A reader comparing the two sets of figures needs all
three, because two of them move the numbers for reasons that have nothing to do with friction.

| What changed | Then | Now |
|---|---|---|
| The population | 5,472 handoff and 1,042 ask messages | 4,633 and 890. Claude Code deleted the window's first week before the transcripts were copied |
| The draw | Kept every row the previous draw had selected, so an older row had about 1.4 times the inclusion probability of a newer one | Uniform. Every row has the same chance, whenever it was written |
| The method | Wilson, a binomial interval, labelled an approximation | The exact hypergeometric interval, which is what a fixed-size draw without replacement supports |

The earlier figures are kept, dated, under "The 2026-08-16 draw, and why it was replaced".

## The run behind the published figures

| Setting | Value |
|---|---|
| Seed | 20260816 |
| Sample size per metric | 200 unflagged messages |
| Window | 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z |
| Transcript root | `~/AHKFlowApp-friction-snapshot-2026-08-21` |
| Transcript files | 674 after deduplication |
| Records read | 166,852 |
| In-window logical messages | 50,989 |
| Flagged, handoffs / asks | 15 / 29 |
| Date | 2026-08-22 |

**The first week of the window is missing from the copy, and that is why the population fell.**
The copy was taken on 2026-08-21. By then Claude Code had already deleted everything older than
30 days, so the earliest surviving in-window message is stamped 2026-07-22 08:06:05. The window
still runs from 2026-07-15, and the three weeks it covers are complete to 2026-08-12 14:14:23.
A smaller count below is partly that missing week, not less friction.

| Metric | Population | Flagged | Unflagged | Ordered-key digest |
|---|---|---|---|---|
| handoffs | 4,633 | 15 | 4,618 | `a58c1426…1bcf2b` |
| next-step-asks | 890 | 29 | 861 | `05e7c7ed…3db705` |

## Why the seed is not the record

A seed reproduces a draw only when the list it indexes into has not moved. This list moves: the
population is the session transcripts, and the live ones both grow and get deleted. Two runs
minutes apart read 691 files, then 672.

So each draw writes a selection record beside its manifest — the transcript root it read, the
population count, a SHA-256 digest of the ordered keys, the drawn positions, and the drawn keys.
The digest says whether the positions still point at the same messages. The keys identify the
rows either way. The root says which copy of the transcripts produced the draw, which a count on
its own cannot.

## How the draw picks a row

The sampler hashes the seed and the message key together and takes the 200 lowest hashes
(`scripts/sample-friction-recall.ps1`). Every unflagged message has the same chance of
selection, and the same rows stay selected as the transcripts grow, so a hand-written label
survives a re-run without the label deciding the sample.

**The draw is uniform, so the interval can be exact.** A Wilson interval is a binomial one: it
assumes each draw is independent, which is what sampling with replacement gives. This draw takes
a fixed number of rows without replacement, so the variance of the sample proportion is smaller.
`Get-RecallInterval -Correct` inverts the hypergeometric tails directly, with no approximation at
any step. That switch has a precondition — every row in the population must have had the same
chance of being drawn — and this draw is the first one in this repository to meet it.

`Get-RecallInterval` in `scripts/sample-friction-recall.ps1` computes the ranges below.
`tests/FrictionRecallSample.Tests.ps1` checks each bound against the definition rather than
against the function itself, and it re-derives every published figure from the committed
manifests, including the totals in
[`072`](../../backlog/done/072-process-wave-2-parity-drift-guard-templates.md).

**The plain Wilson value is stated once beside each range.** Both the population and the method
changed since 2026-08-16, and a reader who only sees one number cannot tell which change moved
it. Wilson is the wider of the two here, which is what a normal approximation to a
finite-population problem usually is.

## Reading a row id

Ids carry across draws. A row the 2026-08-16 draw also selected keeps the id it had then.

- In `handoffs-sample.csv`, an id above **U203** is a row that draw never selected.
- In `next-step-asks-sample.csv`, an id above **U202** is a row that draw never selected.

Eight handoff rows and 46 ask rows carry an id from the earlier draw. Every other unflagged row
in both files was read and labelled for the first time on 2026-08-22.

## How much the two labelling rounds agree

Two checks were run, and neither is strong. Both are reported with what they cannot show.

**Against the 2026-08-16 round: 54 of 54.** The 54 rows both draws selected were labelled again
without reading the committed label, and every label matched. 53 of those 54 are `not-a-case`, so
the check shows the two rounds agree about negatives and says almost nothing about catching
misses.

**Within this round: 20 of 20.** Twenty already-labelled rows were re-derived from the rule sheet
and compared. All twenty matched. This is weaker than it sounds for two reasons. The re-derivation
ran in the same session that wrote the labels, so it is a consistency check and not a blind one.
And all twenty drew negatives, so again nothing about misses was tested.

## How a label was decided

**Every sampled row was read.** 200 unflagged rows per metric, plus all 15 and all 29 flagged
ones — 444 messages in total, of which 346 were labelled for the first time. The manifests carry
each message's **full text**, so any label can be checked. They also carry a `Screen` column — a
wide word list, far wider than the metric's own — which is a reading aid, never a labeller. A row
is labelled from its text, not from its screen hits.

**The flagged stratum is a census, not a sample, and no interval applies to it.** Every message
the match set flags is in the manifest and every one was read, so the precision figures below —
10 real of 15, 15 real of 29 — are counted, not estimated. Nothing about the draw touches them:
the sampling question is about the unflagged remainder, which is the only part that was sampled.
The one thing that does threaten these counts is deletion, not sampling — see "What limits these
numbers".

**Definitions.**

A *handoff* is the agent saying it cannot do something and passing the action to the person.
Three things are not handoffs, and each one was a real labelling mistake in an earlier round:

- Working around a refusal, then carrying on.
- Naming a block without passing anything over. "I cannot reach that finding" followed by the
  agent continuing its own work is a status line, not a handoff.
- Inviting the person to reproduce something the agent already did. "Run it yourself:" after
  "and I ran it" hands over nothing.

A *next-step ask* is the person asking **what work to do next**. Three things are not:

- An instruction to carry on — "continue", "do it", "push it and open the PR".
- Pasted text that contains the words, such as a review body or a transcript.
- A question about a technical mechanism. "How do I resolve this error?" and "is there an
  alternative to gitignore?" ask how a thing works; "is it ready to pick up?" and "what do I do
  with this?" ask what to do next. The line is the subject, not the question mark.

That last rule is written out because it decided seven labels on its own, and without it two
readers get two different counts from the same rows.

## Metric 1 — blocked-agent handoffs

**Flagged: 15. Real: 10. Precision: 67 percent.**

| Label | Items | Why |
|---|---|---|
| Real | F2, F3, F4, F5, F7, F8, F10, F11, F14, F15 | A corrupted `gh` token the agent cannot repair; a file the guard will not let it commit; commands handed over after a refusal, with the reason and the expected output |
| Not real | F1, F6, F9, F12, F13 | F6 invites the person to re-run something the agent already ran; F9 names a block and carries on; the rest are completion summaries that mention a block without passing anything over |

**Unflagged sample: 200 of 4,618. Missed: 9** — U1, U205, U210, U219, U276, U278, U332, U343,
U389. Every one of them is the same shape the match set was built for and did not catch: the
agent is refused, and the person is handed the command, the decision, or the queue. U1 is the
plainest of them — the monthly spend limit is reached, and only the person can raise it.

9 in 200 is a 4.5 percent miss rate, 95 percent hypergeometric interval 2.1 to 8.3 percent.
Across 4,618 unflagged messages that is **98 to 382 missed handoffs**. For comparison, plain
Wilson would give 110 to 385 missed handoffs on the same labels.

**True count: roughly 108 to 392.** The flagged 15 is not an upper bound and is not close to one.

## Metric 4 — next-step asks

**Flagged: 29. Real: 15. Precision: 52 percent.**

Most false positives are pasted review bodies. A reviewer writes "next step" inside a findings
list, the person pastes the whole thing, and the metric reads the paste as the person asking.

**That precision rises because messages were deleted, not because the match set improved.** The
2026-08-16 census was 18 real of 38, which is 47 percent. Nine of those 38 flagged rows are gone
from the transcripts, and only three of the nine were real, so the survivors are a higher share
by chance. The nine live on in
`friction-samples/next-step-asks-sample-2026-08-16.csv` and nowhere else.

**Unflagged sample: 200 of 861. Missed: 7** — U45, U203, U209, U225, U276, U281, U334. U281 is
the plainest: "committed, whats next".

7 in 200 is a 3.5 percent miss rate, 95 percent hypergeometric interval 1.6 to 6.6 percent.
Across 861 unflagged messages that is **14 to 57 missed asks**. For comparison, plain Wilson
would give 15 to 61 missed asks on the same labels.

**True count: roughly 29 to 72.**

## The other three metrics

- **Metric 2, directory-bound commands (179 lines).** A syntax rule: a command line inside a
  `powershell`, `pwsh`, `bash`, `sh` or `shell` fence that names a directory, deduplicated on
  message and line text. Two filters keep prose out — the line must start with a command, and a
  here-string body is skipped. A pull request body passed as `@' … '@` inside a `powershell`
  fence had put two English sentences in the ledger. Precision is still unmeasured: an example
  command counts like a handed-over one.
- **Metric 3, cleanup outcome log lines (18 log lines across 5 sessions, a floor on at least
  204 in-window log lines).** Counts log lines, never cleanup runs: one removal writes several,
  and 91 of the log's 201 in-window lines are `Watcher started.` against 87 `Watcher done (`.
  Not a word list. Every cleanup outcome reaches a transcript as a
  line written by `Write-WorktreeLog`, which stamps it `yyyy-MM-dd HH:mm:ss  <worktree>
  <message>`
  (`scripts/worktree-log.common.ps1:92`, "    return '{0}  {1}  {2}' -f $stamp, $Worktree, $single").
  A line counts when it has that shape **and**
  its message starts with something a cleanup script writes. Matching the wording anywhere in a
  message instead counted the script's own source, injected skill instructions, and reviews
  quoting an outcome — 65 of 75 rows on the first attempt. Six of the eleven phrases then in use
  appeared in no script at all; `cleanup popup` alone produced 24 rows.
  **All 18 rows are labelled, and all 18 are genuine log lines.** 14 arrived as tool results
  reading the removal log; 4 came from one human-typed message, a process brief that pasted a
  log tail as evidence. Nothing counted is source code, an injected instruction, or a
  paraphrase, so the metric over-flags nothing. That is all the labels prove. The record fields
  are the same whether a line was read as it was written or quoted later, so they cannot
  separate an original read from a quotation.
  **The split the count could not make turns out to be the wrong split.** A tool result is
  not a live report either — it is a read of `worktree-removal.log`, and one of the 18 rows
  arrived on 2026-07-30 carrying an event stamped 2026-07-29. Both routes quote the same
  persistent file, and the line's own stamp is the event time in both.
  **So 18 is a floor, not an upper bound.** The removal log itself holds 201 distinct
  in-window outcome log lines. The 18 are not a subset of those 201: 15 of them are, and the
  other 3 predate the log's earliest surviving line, so the true in-window population is 204
  log lines or more.
  That makes the witnessed share **at most about nine percent**, and 186 of the 201 log lines
  reached no session at all. The
  rule sheet and the decision are in
  [`cleanup-event-identity.md`](cleanup-event-identity.md); the labels are in
  `friction-samples/cleanup-events-labelled.csv`, and the log's own rows in
  `friction-samples/ledgers/cleanup-log-events.csv`.
- **Metric 5, CI minutes.** No word matching, so no recall question. It has a coverage problem
  instead, stated below.

These three were measured on 2026-08-16 against the live transcripts and are not redrawn here.
They are not sampled, so the draw does not touch them.

## The 2026-08-16 draw, and why it was replaced

The figures published until 2026-08-22 were **179 to 533 missed handoffs** and **35 to 89 missed
asks**. They are kept in
[`072`](../../backlog/done/072-process-wave-2-parity-drift-guard-templates.md) under
`### Measured 2026-08-16`, and their manifests are committed beside the current ones with a dated
name.

They rest on a draw that was not uniform. The first sampler kept every row the previous draw had
selected and filled the rest at random. The selection records show what that did:
`carriedOverLabels` reads 57 of 200 for handoffs and 58 of 200 for asks. A row that was already
in the population when the earlier 60-row draw ran had two chances of selection, a row written
later had one — roughly 3.7 percent against 2.6 percent, a factor of about 1.4. A Wilson interval
describes a uniform draw, so those two ranges were close to a 95 percent interval rather than
exactly one, and the bias had no measured direction.

Backlog 102 could not repair that. A finite-population correction assumes equal inclusion
probabilities, and applying it anyway would have published 164–531 and 34–85: figures that look
sharper while resting on an assumption the data breaks. A design-based estimator such as
Horvitz–Thompson needs each row's actual inclusion probability, which needs the earlier 60-row
draw's selection record and the population as it stood then. Neither survives. So 102 decided the
ranges stay plain Wilson and stay labelled approximate, and filed the redraw as backlog 113.

Backlog 113 is what this file now publishes. The redraw was only possible because the transcripts
were copied on 2026-08-21, five days after the first draw.

## What limits these numbers

**Both ranges are still ranges.** 200 labels bound a miss rate far better than 60 did, but
neither figure is a point. A point estimate needs a classifier that reads structure rather than
wording: a refused tool call, a session that ends on a question. That is wave-3 work, not a patch
to this script.

**The three-week population is not the four-week one.** The window is unchanged, but its first
week is not in the copy, so every count below is over a smaller base than the 2026-08-16 figures.
Comparing 108–392 against 179–533 measures deletion at least as much as it measures friction.

**Metric 5 classifies 115 of 192 in-window CI runs.** The 77 unresolved runs are **not** missing
from this clone — every in-window `head_sha` was present when this was measured. They have no
landing merge on `origin/main`'s first-parent chain, which is a different fact and the one the
ledger now records per run. The 456.7 minutes is a floor over the classified runs, not a total
for the window. One of the 75 counted runs reported no duration, so it enters the sum as zero;
the ledger's `TimingStatus` column names it.

**A path counts as .NET by its file type.** The first rule also read the folder — anything under
`src/` or `tests/` — which called a PowerShell suite and an nginx config .NET work. 21 runs
changed no .NET file at all and were classified .NET, keeping 163.2 minutes out of a metric that
exists to count them. The published figure was 293.6 minutes across 54 runs before the rule was
corrected and the committed ledger reclassified from its own `ChangedPaths` column.

**The transcripts are live, and the copy is not.** Three runs on one afternoon read 691, then
672, then 670 files. The manifests, the selection records and the ledgers are the frozen record;
every published figure names the run that produced it.

**What deletion took, measured on 2026-08-21.** This is the loss the copy stopped.

| Metric | Population | Unflagged | Flagged |
|---|---|---|---|
| handoffs, drawn 2026-08-16 | 5,472 | 5,457 | 15 |
| handoffs, in the copy | 4,633 | 4,618 | 15 |
| next-step-asks, drawn 2026-08-16 | 1,042 | 1,004 | 38 |
| next-step-asks, in the copy | 890 | 861 | 29 |

The flagged ask count fell from 38 to 29, so nine messages can no longer be re-read. Three of
them were labelled real. The archived 2026-08-16 manifest is the only record of all nine.

**The copy has a deletion date.** `~/AHKFlowApp-friction-snapshot-2026-08-21` holds 755 files and
445 MB. It is machine-local and is in no repository. It is kept until **2026-12-31** and then
deleted. After that the manifests are the only evidence for these figures, which is exactly where
the 2026-08-16 draw already stands.

**A window this long cannot be measured twice.** Claude Code deletes session files older than
`cleanupPeriodDays`, which defaults to 30 days. A four-week window plus the time it takes to
draw, label and publish is already past that. The rule that follows from it is
[ADR 0011](../adr/0011-a-friction-window-fits-inside-transcript-retention.md): a friction window
is at most 21 days, and the draw runs at most 7 days after the window closes.
