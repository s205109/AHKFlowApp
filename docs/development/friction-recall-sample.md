# Friction measurement: the labelled sample

`scripts/measure-process-friction.ps1` counts five things. Two of them match on wording, and a
word list gives a repeatable number rather than a right one. This file records what those two
metrics caught, what they missed, and how each label was decided.

The evidence is committed beside it:

| File | What it holds |
|---|---|
| `friction-samples/handoffs-sample.csv` | 15 flagged messages and 200 sampled unflagged ones, each with its full text, key, session, and label |
| `friction-samples/next-step-asks-sample.csv` | 41 flagged and 200 sampled unflagged, same columns |

Redraw either with:

```powershell
pwsh ./scripts/sample-friction-recall.ps1 -Metric handoffs -OutputPath docs/development/friction-samples/handoffs-sample.csv
```

| Setting | Value |
|---|---|
| Seed | 20260816 |
| Sample size per metric | 200 unflagged messages |
| Window | 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z |
| Transcript files | 691 after deduplication, subdirectories included |
| Records read | 154,962; 80,080 in window and not sidechain; 21,040 sidechain excluded |
| Logical messages | 60,906, of which 10,872 were assembled from more than one record |
| Measured and labelled | 2026-08-16 |

## How a label was decided

Every message in the manifest carries its **full text**, not an excerpt, because the sentence
that makes a message a handoff is often past the first line.

Labelling ran in two stages, and both are checkable:

1. **A mechanical screen over the whole text.** A word list far wider than the metric's own —
   for handoffs: `yourself`, `manually`, `cannot`, `blocked`, `guard`, `terminal`, `login`, and
   fifteen more. The screen is in `scripts/sample-friction-recall.ps1` and its hits are stored
   in the manifest's `Screen` column. It selected 35 of the 200 sampled handoff messages and 26
   of the 200 sampled asks.
2. **Reading, in full, every screened message and every flagged one.** A row labelled
   `not-a-case` without a screen hit means no word associated with the concept appears anywhere
   in its text, which a reviewer can check against the `Text` column rather than trust.

**Definitions used.** A *handoff* is the agent saying it cannot do something and passing the
action to the person. Working around a refusal is not a handoff. A *next-step ask* is the person
asking what to do next; an instruction to carry on ("continue", "exec the next step") is not,
and neither is pasted review text that contains the words.

## Metric 1 — blocked-agent handoffs

**Flagged: 15. Real: 8. Precision: 53 percent.**

| Label | Items | Why |
|---|---|---|
| Real | F2, F3, F5, F6, F9, F10, F14, F15 | A corrupted `gh` token the agent cannot repair; an uncommitted file the guard blocks; "run it yourself" with the commands; "Run it yourself:" for a prototype; "I cannot reach" a private-repo finding, twice; "so a handover again"; "Run this from the main checkout" |
| Not real | F1, F4, F7, F8, F11, F12 | Completion summaries and analyses that merely mention a block |
| Not real | F13 | "The guard refuses variable write targets. Using the Write tool instead" — the agent worked around it, so nothing was handed over |

**Unflagged sample: 200 of 5,699. Missed: 6.**

| Item | What the word list missed |
|---|---|
| U19 | "commit blocked - guard forbids agent Git mutations… Run in PowerShell:" |
| U30 | "Denied twice - permission mode blocks `git reset --hard` outright… Options:" |
| U62 | "Two loose ends from earlier, both yours to run" |
| U111 | "Plan mode is on now - I can't commit the spec yet" |
| U179 | "7 of the 23 live in `docs/superpowers`, which this session cannot write… hand you exact commands" |
| U189 | "It cannot be saved from here - plans repo again - so same handover" |

6 in 200 is a 3 percent miss rate, 95 percent interval 1.4 to 6.4 percent. Across 5,699
unflagged messages that is **80 to 365 missed handoffs**.

**True count: roughly 88 to 373.** The flagged 15 is not an upper bound and not a lower one.
The word list finds about one handoff in twenty.

## Metric 4 — next-step asks

**Flagged: 41. Real: 19. Precision: 46 percent.**

| Label | Items |
|---|---|
| Real | F3, F4, F5, F6, F7, F13, F15, F17, F18, F21, F25, F27, F28, F30, F31, F35, F38, F39, F41 |
| Not real — an instruction, not a question | F14, F19, F22, F24 |
| Not real — pasted plan, review, memory, or handoff text containing the words | F1, F2, F8, F9, F10, F11, F12, F16, F20, F23, F26, F29, F32, F33, F34, F36, F37, F40 |

**Unflagged sample: 200 of 1,055. Missed: 2.**

| Item | What the word list missed |
|---|---|
| U85 | "should we create a plan to resolve this bug or is it straightforward to fix?" |
| U94 | "can you not use these findings directly? or should I ask the reviewer again" |

2 in 200 is a 1 percent miss rate, 95 percent interval 0.3 to 3.6 percent. Across 1,055
unflagged messages that is **3 to 38 missed asks**.

**True count: roughly 22 to 57.**

## The other three metrics

- **Metric 2, directory-bound commands (214 lines).** A syntax rule, not a word list: a line
  inside a `powershell` or `bash` fence that names a directory. Prose that mentions `cd` does
  not count, and a line repeated inside one message counts once. Recall is not a real question
  for a syntax rule; precision is unmeasured, because a command shown as an example counts the
  same as one handed over.
- **Metric 3, cleanup events (233 messages).** Matches the cleanup scripts' own log strings over
  any record, agent or tool. Not sampled, so no precision figure. The earlier terms `is locked`
  and `is dirty` were replaced by `worktree is locked` and `worktree is dirty`, because the
  short forms match ordinary sentences.
- **Metric 5, CI minutes (551.4 across 302 runs).** No word matching at all, so no recall
  question. Each run is classified from the files its own pull request changed.

## Two things that limit all of this

**The transcripts are live.** Two runs twenty minutes apart read 694 and then 691 files, and the
flagged ask count moved by one. Sessions are written, rotated, and removed while the measurement
runs. The manifests are the frozen record; the published figures name the run that produced them.

**Wording is the wrong signal.** Precision is 53 and 46 percent, and recall for handoffs is about
one in twenty. A future wave that wants tight numbers should classify by structure — a refused
tool call, a session that ends on a question — rather than by the words people happened to use.
