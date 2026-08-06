---
name: mp-grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when they want to stress-test thinking, or use any 'grill' trigger phrase.
---

<!--
AHKFlow adaptation of mattpocock/skills (MIT), pinned at commit 6acc160e4e0cd062dbbbd7a1b26ae92855edf07e.
Update policy: manual-selective-merge — do not bulk-sync with upstream.
-->

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled — the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Each question should be formatted like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree — settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it — don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report — ask the rest of the frontier now. The _decisions_ are the user's — put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

## Two terms, explained once

**Design tree** — all the decisions this work needs, drawn as a tree. One decision sits above
another when the answer to the first changes what the second even asks.

**Frontier** — the decisions you can ask about right now. A decision is on the frontier when every
decision above it is already answered. Nothing above it is still open.

So a round is one sweep of the frontier. You ask every question that is ready. You wait. The answers
make more questions ready. You ask those next.
