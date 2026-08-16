# Friction measurement: the labelled sample

`scripts/measure-process-friction.ps1` counts five things. Two of them match on wording, and a
word list gives a repeatable number rather than a right one. This file records what those two
metrics caught, what they missed, and how each label was decided.

The evidence is committed beside it:

| File | What it holds |
|---|---|
| `friction-samples/handoffs-sample.csv` | 15 flagged messages and 60 sampled unflagged ones, each with full text, key, session and label |
| `friction-samples/next-step-asks-sample.csv` | 41 flagged and 60 sampled unflagged, same columns |
| `friction-samples/ledgers/*.csv` | One row per counted item for all four transcript metrics, and one row per counted CI run |

Redraw either sample with:

```powershell
pwsh ./scripts/sample-friction-recall.ps1 -Metric handoffs -OutputPath docs/development/friction-samples/handoffs-sample.csv -SampleSize 60
```

| Setting | Value |
|---|---|
| Seed | 20260816 |
| Sample size per metric | 60 unflagged messages |
| Window | 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z |
| Transcript files | 691 after deduplication, subdirectories included |
| Records read | 155,392; 79,691 in window and not sidechain; 19,586 in-window sidechain records excluded |
| Logical messages | 60,596, of which 9,656 were assembled from more than one record |
| Measured and labelled | 2026-08-16 |

## How a label was decided

**Every sampled row was read.** 60 unflagged rows per metric, plus all 15 and all 41 flagged
ones — 176 messages in total. The sample is 60 rather than 200 because 200 could not be read
honestly, and a row labelled from a word list is not a labelled row. That choice widens the
interval, and the wider interval is the true state of the evidence.

The manifests carry each message's **full text**, so any label can be checked. They also carry a
`Screen` column — a wide word list, far wider than the metric's own — which is now a reading aid
rather than a labeller.

**Definitions.** A *handoff* is the agent saying it cannot do something and passing the action to
the person; working around a refusal is not one. A *next-step ask* is the person asking what to do
next; an instruction to carry on is not, and neither is pasted text that contains the words.

## Metric 1 — blocked-agent handoffs

**Flagged: 15. Real: 8. Precision: 53 percent.**

| Label | Items | Why |
|---|---|---|
| Real | F2, F3, F5, F6, F9, F10, F14, F15 | A corrupted `gh` token the agent cannot repair; a file the guard will not let it commit; "run it yourself" with the commands; "Run it yourself:" for a prototype; "I cannot reach" a private-repo finding, twice; "so a handover again"; "Run this from the main checkout" |
| Not real | F1, F4, F7, F8, F11, F12 | Completion summaries and analyses that mention a block without passing anything over |
| Not real | F13 | "The guard refuses variable write targets. Using the Write tool instead" — worked around, nothing handed over |

**Unflagged sample: 60 of 5,678. Missed: 2** — U39 ("those live in the private plans repo, so
from the main checkout") and U18 ("branched off stale `main` — rebase before the PR").

2 in 60 is a 3.3 percent miss rate, 95 percent interval 0.9 to 11.4 percent. Across 5,678
unflagged messages that is **52 to 647 missed handoffs**.

**True count: roughly 60 to 655.** The interval is wide because 60 labels cannot make it narrow.
What it does establish: the flagged 15 is far below the real number, so it is not an upper bound.

## Metric 4 — next-step asks

**Flagged: 41. Real: 19. Precision: 46 percent.**

| Label | Items |
|---|---|
| Real | F3, F4, F5, F6, F7, F13, F15, F17, F18, F21, F25, F27, F28, F30, F31, F35, F38, F39, F41 |
| Not real — an instruction, not a question | F14, F19, F22, F24 |
| Not real — pasted plan, review, memory or handoff text containing the words | F1, F2, F8, F9, F10, F11, F12, F16, F20, F23, F26, F29, F32, F33, F34, F36, F37, F40 |

**Unflagged sample: 60 of 1,052. Missed: 3** — U8 ("are the two things for me still relevant?"),
U45 ("is it ready to pick up?"), U55 ("what are the options?").

3 in 60 is a 5 percent miss rate, 95 percent interval 1.7 to 13.7 percent. Across 1,052 unflagged
messages that is **18 to 144 missed asks**.

**True count: roughly 37 to 163.**

## The other three metrics

- **Metric 2, directory-bound commands (214 lines).** A syntax rule: a line inside a `powershell`
  or `bash` fence that names a directory, deduplicated on message and line text. Precision is
  unmeasured — an example command counts like a handed-over one.
- **Metric 3, cleanup events (75 messages).** Only lines the cleanup scripts actually print. The
  earlier 233 included 180 rows matching the bare script name `remove-worktree`, which is people
  discussing the script. That term is gone.
- **Metric 5, CI minutes (291 across 53 runs).** No word matching, so no recall question. It has a
  coverage problem instead, stated below.

## What limits these numbers

**Two of five figures are wide ranges.** Sixty labels bound a miss rate loosely. A tighter figure
needs either a much larger labelled sample or — better — a classifier that reads structure rather
than wording: a refused tool call, a session that ends on a question.

**Metric 5 classifies 114 of 192 in-window CI runs.** 78 runs have a `head_sha` that is not in
this clone: a closed pull request, or a branch whose head was never fetched. They are reported as
unresolved rather than guessed at. The 291 minutes is therefore a floor for the classified runs,
not a total for the window.

**The transcripts are live.** Runs minutes apart read 691 and 694 files. The manifests and ledgers
are the frozen record; every published figure names the run that produced it.
