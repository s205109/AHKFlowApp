# Simplify, Verify and Document fold into Execute

Backlog 191 retires stages 5, 6 and 7. Their work stays. The simplify pass, the verification
artifact, the docs update and the acceptance-box ticks all happen inside Execute. Execute then
ends with the Gate on the final revision. The other stages keep their numbers, so the spine goes
from `4-execute` straight to `8-review`.

## Why

The Gate ran twice for one revision. Verify ran the whole Gate. Then Review's exit asked for
"gate re-green" on the same code.

Every review finding that needed code walked the three stages again. Review's failure edge went
to Execute, "then Simplify, Verify, Document again as needed". So each such review round ran the
Gate again, and took three more transition commits and pushes. The backlog 164 plan names at
least five review rounds.

The three stages made no decision of their own. Each one always followed Execute, in a fixed
order, and a Sonnet session did each one, as it does Execute. A stage boundary earns its record
when the work changes hands: to the human, to a stronger model, or to a reviewer. These three
boundaries did not change hands.

The design is in section 4.5 of the backlog 188 spec,
`docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`.

## The alternatives that were rejected

**Renumber the stages 0 to 7.** The numbers would read more neatly. But every item, plan, pull
request body, ADR and transcript written before this change names a stage by its number. After a
renumber, `8-review` in an old record would point at a different stage. A gap in the numbers
costs nothing. A number that changes its meaning costs every reader of an old record.

**Keep the three stages, with no commit of their own.** A housekeeping round already records them
only in its pull request body. That still leaves a separate Gate at Verify, and a review round
still walks all three stages again.

## What follows from this

- The anchors `stage-5-simplify`, `stage-6-verify` and `stage-7-document` sit on the Execute
  section. Every older link still lands on the work it named.
- `scripts/take-stage-transition.ps1` reads the legal targets from `workflow.md` at run time. So
  the stage graph changes in one document, and the script follows it.
- The stages that need a green Gate are `4-execute` and `8-review`. Review's exit checks that the
  Gate evidence for the final revision is still valid, and runs only what is not.
- A review fix that needs code goes back to `4-execute`. Execute's exit runs the Gate once for it.
- An item at stage 5, 6 or 7 when this change lands moves to `4-execute`. None sat there.

## Related

- [`0006-process-source-lives-in-workflow-md.md`](0006-process-source-lives-in-workflow-md.md) —
  why `workflow.md` is the one place a stage is defined.
- [`0020-a-transition-runs-outside-the-entered-worktree.md`](0020-a-transition-runs-outside-the-entered-worktree.md) —
  why the transition script reads `workflow.md` instead of keeping its own copy of the stages.
