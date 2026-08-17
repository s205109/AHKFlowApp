# Friction measurement: the labelled sample

`scripts/measure-process-friction.ps1` counts five things. Two of them match on wording, and a
word list gives a repeatable number rather than a right one. This file records what those two
metrics caught, what they missed, and how each label was decided.

The evidence is committed beside it:

| File | What it holds |
|---|---|
| `friction-samples/handoffs-sample.csv` | 15 flagged messages and 200 sampled unflagged ones, each with full text, key, session and label |
| `friction-samples/next-step-asks-sample.csv` | 38 flagged and 200 sampled unflagged, same columns |
| `friction-samples/*-sample.selection.json` | The selection record for each draw: population size, ordered-key digest, drawn positions, drawn keys |
| `friction-samples/ledgers/*.csv` | One row per counted item for the four transcript metrics, and one row per in-window CI run |

Redraw either sample with:

```powershell
pwsh ./scripts/sample-friction-recall.ps1 `
  -Metric handoffs `
  -OutputPath docs/development/friction-samples/handoffs-sample.csv `
  -SampleSize 200 `
  -ExistingManifest docs/development/friction-samples/handoffs-sample.csv
```

**Always pass `-ExistingManifest`.** It carries the labels and the row ids across a re-run. It
does not change which rows are drawn — see "How the draw picks a row" — but without it every
hand-written label is written out empty, and a hand-written label is the only thing this step
produces.

Two runs are named below, and they are not the same run. The sample was drawn first, then the
figures were measured. The transcripts grew between them, so the populations differ slightly.
Neither number is adjusted to match the other.

| Setting | The draw | The measurement |
|---|---|---|
| Seed | 20260816 | — |
| Sample size per metric | 200 unflagged messages | — |
| Window | 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z | same |
| Transcript files | 672 after deduplication | 670 after deduplication |
| Records read | 152,664; 77,001 in window and not sidechain | 152,847; 76,683 in window and not sidechain |
| Sidechain records excluded | 19,532 | 19,532 |
| Logical messages | 58,616, of which 9,273 span more than one record | 58,393, of which 9,230 span more than one record |
| Flagged, handoffs / asks | 15 / 38 | 15 / 38 |
| Date | 2026-08-16 | 2026-08-16 |

The flagged counts agree, which is what matters: the precision figures below are counted over the
same 15 and 38 messages the ledgers hold.

## Why the seed is not the record

A seed reproduces a draw only when the list it indexes into has not moved. This list moves: the
population is the live session transcripts, and they grow while the script runs. Two runs minutes
apart read 691 files, then 672.

So each draw writes a selection record beside its manifest — the population count, a SHA-256
digest of the ordered keys, the drawn positions, and the drawn keys. The digest says whether the
positions still point at the same messages. The keys identify the rows either way.

## How the draw picks a row

The sampler hashes the seed and the message key together and takes the 200 lowest hashes
(`scripts/sample-friction-recall.ps1`). Every unflagged message has the same chance of
selection, and the same rows stay selected as the transcripts grow, so a hand-written label
survives a re-run without the label deciding the sample.

**The committed sample was drawn the old way, and its intervals are approximate.** The first
sampler kept every row the previous draw had selected and filled the rest at random. The
selection records show what that did: `carriedOverLabels` reads 57 of 200 for handoffs and 58 of
200 for asks. A row that was already in the population when the earlier 60-row draw ran had two
chances of selection, a row written later had one — roughly 3.7 percent against 2.6 percent, a
factor of about 1.4. That is a probability sample with unequal inclusion probabilities, and a
Wilson interval describes a uniform one. So read both ranges below as close to a 95 percent
interval rather than exactly one. The bias has no measured direction: it over-represents older
messages, and nothing says the miss rate differs between older and newer ones.

Redrawing with the fixed sampler produces a different 200 rows per metric and would need those
rows labelled by hand again. That work is filed as backlog 102, not done here: throwing away 400
labels to redraw is a decision with a cost, and the labels themselves are still evidence for the
rows they describe.

| Metric | Population | Flagged | Unflagged | Ordered-key digest |
|---|---|---|---|---|
| handoffs | 5,472 | 15 | 5,457 | `649fdf9f…2da7c57` |
| next-step-asks | 1,042 | 38 | 1,004 | `05f383ef…67f6a31` |

## How a label was decided

**Every sampled row was read.** 200 unflagged rows per metric, plus all 15 and all 38 flagged
ones — 453 messages in total. The manifests carry each message's **full text**, so any label can
be checked. They also carry a `Screen` column — a wide word list, far wider than the metric's own
— which is a reading aid, never a labeller. A row is labelled from its text, not from its screen
hits.

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

**Unflagged sample: 200 of 5,457. Missed: 11** — U14, U18, U94, U141, U162, U167, U169, U179,
U188, U195, U202. Every one of them is the same shape the match set was built for and did not
catch: the agent is refused, and the person is handed the command, the decision, or the queue.

11 in 200 is a 5.5 percent miss rate, 95 percent Wilson interval 3.1 to 9.6 percent. Across
5,457 unflagged messages that is **169 to 523 missed handoffs**.

**True count: roughly 179 to 533.** The flagged 15 is not an upper bound and is not close to one.

## Metric 4 — next-step asks

**Flagged: 38. Real: 18. Precision: 47 percent.**

Most false positives are pasted review bodies. A reviewer writes "next step" inside a findings
list, the person pastes the whole thing, and the metric reads the paste as the person asking.

A paste is only a false positive while the person adds nothing. F36 pastes an agent's report and
then asks, in its last two lines, whether to implement, update or merge first, and for the best
next step. That is the person asking what work to do next, so it is real. It was labelled
not-a-case in the first round because the paste decided the label instead of the person's own
words; the rule below the definitions says the subject decides.

**Unflagged sample: 200 of 1,004. Missed: 7** — U1, U8, U45, U55, U105, U118, U150.

7 in 200 is a 3.5 percent miss rate, 95 percent Wilson interval 1.7 to 7.0 percent. Across 1,004
unflagged messages that is **17 to 71 missed asks**.

**True count: roughly 35 to 89.**

## The other three metrics

- **Metric 2, directory-bound commands (179 lines).** A syntax rule: a command line inside a
  `powershell`, `pwsh`, `bash`, `sh` or `shell` fence that names a directory, deduplicated on
  message and line text. Two filters keep prose out — the line must start with a command, and a
  here-string body is skipped. A pull request body passed as `@' … '@` inside a `powershell`
  fence had put two English sentences in the ledger. Precision is still unmeasured: an example
  command counts like a handed-over one.
- **Metric 3, cleanup events (18 log lines across 5 sessions).** Not a word list. Every cleanup outcome reaches a transcript as a
  line written by `Write-WorktreeLog`, which stamps it `yyyy-MM-dd HH:mm:ss  <worktree>
  <message>`
  (`scripts/worktree-log.common.ps1:22`, "    $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $Message").
  A line counts when it has that shape **and**
  its message starts with something a cleanup script writes. Matching the wording anywhere in a
  message instead counted the script's own source, injected skill instructions, and reviews
  quoting an outcome — 65 of 75 rows on the first attempt. Six of the eleven phrases then in use
  appeared in no script at all; `cleanup popup` alone produced 24 rows.
  **It does not separate a reported event from a quoted one.** A message that quotes a whole
  stamped line carries the stamp, and the metric counts it — deliberately, because that is how a
  tool result holding the tail of the worktree log arrives. So 18 counts stamped lines, not
  reported events, and the 18 rows are not yet labelled. Backlog 103 carries that work.
- **Metric 5, CI minutes.** No word matching, so no recall question. It has a coverage problem
  instead, stated below.

## What limits these numbers

**Both ranges are still ranges, and both are approximate.** 200 labels bound a miss rate far
better than 60 did — the handoff interval went from 60–655 to 179–533, and the ask interval from
37–163 to 35–89 — but neither figure is a point. A point estimate needs a classifier that reads
structure rather than wording: a refused tool call, a session that ends on a question. That is
wave-3 work, not a patch to this script. The draw that produced these 400 labels was not
uniform either, for the reason given under "How the draw picks a row"; backlog 102 carries the
redraw.

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

**The transcripts are live.** Three runs on one afternoon read 691, then 672, then 670 files. The
manifests, the selection records and the ledgers are the frozen record; every published figure
names the run that produced it.
