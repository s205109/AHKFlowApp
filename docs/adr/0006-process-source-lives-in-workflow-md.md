# Process source lives in workflow.md

`docs/development/workflow.md` is the only normative description of the development process.
`docs/development/workflow.html`, `docs/development/ahkflow-workflow-cheatsheet.html`,
`docs/development/ahk-workflow.pdf`, `AGENTS.md`, and `.claude/CLAUDE.md` are all derived from
it. When one of them disagrees with `workflow.md` about a Stage name, an exit condition, or an
Edge target, `workflow.md` wins and the other document is fixed. Wave 1 wrote the process into
those places at the same time, and three review rounds in a row then found the copies drifting
apart. Each drift was caught by a reader, which is not a control.

## Considered options

Making `AGENTS.md` canonical was rejected. Every agent reads it first, so it looks like the
natural home. But it must stay a short index that a session can hold in context, and the
process narrative is long enough to swamp it.

Treating the documents as equal peers was also rejected. Nothing then decides a disagreement,
so each drift becomes a discussion instead of a defect with a known fix.

## What the document is called

The noun is **Source**, pinned in `CONTEXT.md`. The adjective is "canonical", spelled out:
"`workflow.md` is the canonical source".

The clipped noun "canon" was used first and is now retired. It is not a common English word,
so it fails the **Plain English** rule in `AGENTS.md`, and it is not in the ASD-STE100 approved
dictionary either. It also sounds like "cannon". "Canonical" survives because it is the plain
adjective for exactly this idea, and because dropping it would leave no short way to say a
document wins.

One more use was cleaned up at the same time. "The canonical gate" became "the Gate", which
`CONTEXT.md` already defines as the five steps. The anchor id `canonical-pre-pr-gate` did not
change: an anchor is an address, and seven documents link to it.

## Consequences

A change to a Stage name, an exit condition, or an Edge target must change every derived
document in the same commit. The PDF is generated from the cheatsheet, so that change also
means regenerating the PDF. One script does that and writes both hash sidecars in the same run,
so the PDF and the cheatsheet it came from cannot be updated apart. It needs a browser, so it
runs locally; only the checks run in CI.

The generator also writes the cheatsheet's digest into the PDF itself, through the title of a
rendered copy, and reads it back before it publishes anything. That digest is what ties the
PDF to one cheatsheet. Two hash sidecars alone would only say the three files were written
together, and a person can refresh a sidecar by hand: edit the cheatsheet, rewrite its
sidecar, leave the old PDF, and both pairs still agree.

None of this proves the PDF's rendered content matches the cheatsheet — that would mean
extracting text from a compressed PDF, which this repository deliberately does not do. The
check proves which cheatsheet the PDF was rendered from, not what the pages show.

Two Checks enforce this instead of a reader. `scripts/check-process-parity.ps1` compares the
three process documents and fails on any disagreement, naming the losing file and line. A
second Check requires every process rule in `AGENTS.md` and `.claude/CLAUDE.md` to link to a
Stage anchor that exists in `workflow.md`, so a rule cannot quietly grow a second copy of the
narrative.

A Check is not the Guard. `CONTEXT.md` keeps the two apart: the Guard refuses an agent action
reaching outside its own worktree, and there is one of it. A Check compares two records that
must agree. Both fail a run, so a reader who cannot tell them apart cannot tell what broke.
