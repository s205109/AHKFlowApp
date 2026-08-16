# Friction measurement: the labelled sample

`scripts/measure-process-friction.ps1` counts five things by matching words. A word list gives
a repeatable number, but repeatable is not the same as right. This file records what the two
word-matching metrics actually caught, and what they missed, so both figures can be checked
rather than believed.

Redraw the same sample with:

```powershell
pwsh ./scripts/sample-friction-recall.ps1 -Metric handoffs
pwsh ./scripts/sample-friction-recall.ps1 -Metric next-step-asks
```

| Setting | Value |
|---|---|
| Seed | 20260816 |
| Sample size per metric | 200 unflagged records |
| Window | 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z |
| Transcript files | 392 after deduplication, across 84 project directories |
| Records read | 134,056; 80,655 fall inside the window |
| Labelled on | 2026-08-16 |

The sample is stratified. Every flagged record is labelled, which gives exact precision. The
unflagged remainder is sampled, which bounds the miss rate. A random sample of the whole
population would have contained almost no real cases and would have measured nothing about
recall.

## Metric 1 — blocked-agent handoffs

**Definition used when labelling.** The agent cannot do something itself and asks the person to
run it or to act. A record that merely mentions a command, a guard, or a block is not a handoff.

**Flagged: 13. Real: 2. Precision: 15 percent.**

| Label | Items | Why |
|---|---|---|
| Real | F3, F12 | F3 hands over a commit command the guard refuses. F12 reports both agents dead on authentication and asks for `/login`. |
| Not real | F5, F6, F7, F11, F13 | The literal text `Not logged in — Please run /login`. That is the harness speaking, not the agent handing work over. |
| Not real | F1, F2, F4, F8, F9, F10 | Completion summaries that happen to contain a matched phrase. |

**Unflagged sample: 200 of 2,586. Misses found: 5.**

| Item | What the match set missed |
|---|---|
| U20 | "Two things still need you" — work passed to the person, no matched phrase |
| U126 | plan and spec edits "so from the main checkout" — the agent cannot, the person must |
| U180 | "The plan needs re-committing - plans repo, so a handover again" |
| U186 | "Writing both corrected files to scratchpad, ready to copy into place" |
| U197 | "SQL container exited (255)... Start it and check logs" |

5 misses in 200 is a miss rate of 2.5 percent, with a 95 percent interval of roughly 0.8 to 5.7
percent. Across 2,586 unflagged records that projects to **21 to 147 missed handoffs**, most
likely about 65.

**Verdict: 13 is not an upper bound, and not a lower one either.** The true count is a range of
roughly **23 to 149**. The word list finds `/login` notices reliably and real handoffs barely at
all.

## Metric 4 — next-step asks

**Definition used when labelling.** The person asks what to do next. An instruction to carry on
("continue", "exec the next step") is not an ask. Pasted review text that contains the words is
not an ask either.

**Flagged: 36. Real: 16. Precision: 44 percent.**

| Label | Items |
|---|---|
| Real | F1, F2, F4, F5, F11, F13, F15, F17, F21, F23, F24, F26, F27, F29, F33, F34 |
| Not real — an instruction, not a question | F12, F18, F20 |
| Not real — pasted review or plan text containing the words | F3, F6, F7, F8, F9, F10, F14, F16, F19, F22, F25, F28, F30, F31, F32, F35, F36 |

**Unflagged sample: 200 of 1,070. Misses found: 6.**

| Item | What the match set missed |
|---|---|
| U99 | "what are the next backlog items to pick up?" |
| U101 | "what do you suggest doing with these backlog items? Push + PR or make plan here" |
| U105 | asks which of the listed items to take |
| U148 | "what do you suggest, superpowers brainstorming or grilling first" |
| U153 | "what are the next items to pick up in the backlog in what order" |
| U180 | "why push and PR? can we just review the plan locally and then implement?" |

6 misses in 200 is a miss rate of 3 percent, with a 95 percent interval of roughly 1.1 to 6.4
percent. Across 1,070 unflagged records that projects to **12 to 68 missed asks**, most likely
about 32.

**Verdict: the true count is a range of roughly 28 to 84**, against a flagged figure of 36. The
figure is close by accident: the 20 false positives and the roughly 32 misses nearly cancel.

## What this means for the other three metrics

Metrics 2, 3 and 5 were not sampled, because only metrics 1 and 4 match on wording in a way
that can miss a real case silently.

- **Metric 2, directory-bound commands**, matches command syntax, not prose. A line either
  starts with `cd` or carries `git -C` or it does not. Precision is not measured; a command
  inside an explanatory example counts the same as one handed over.
- **Metric 3, cleanup events**, matches tool output. Two of its terms — `is locked` and
  `is dirty` — are ordinary words that appear in unrelated output, so 221 is very likely high.
  It was not sampled, so that is a suspicion, not a measurement.
- **Metric 5, CI minutes**, does not match words at all. Each run is classified from the files
  its own commit changed, so it has no recall question. Every in-window run resolved locally,
  so nothing was dropped.

## The honest summary

Neither word list is good enough to publish a single number. Both are published as ranges, and
this file is the reason the ranges are what they are. A future wave that wants tighter figures
should classify records by structure — a tool call that was refused, a session that ended on a
question — rather than by wording.
