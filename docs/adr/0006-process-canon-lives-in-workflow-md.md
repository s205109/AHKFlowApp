# Process canon lives in workflow.md

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

## Consequences

A change to a Stage name, an exit condition, or an Edge target must change every derived
document in the same commit. The PDF is generated from the cheatsheet, so that change also
means regenerating the PDF and refreshing its hash sidecar by hand; no script generates it.

Two guards enforce this instead of a reader. `scripts/check-process-parity.ps1` compares the
three process documents and fails on any disagreement, naming the losing file and line. A
second guard requires every process rule in `AGENTS.md` and `.claude/CLAUDE.md` to link to a
Stage anchor that exists in `workflow.md`, so a rule cannot quietly grow a second copy of the
narrative.
