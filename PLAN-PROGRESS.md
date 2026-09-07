# PLAN-PROGRESS — backlog 131

Plan: `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`

The item measures a proposed change and closes without making it. The deliverable is the number
and the decision, so the tasks below are records, not code.

## Original tasks

| # | Task | Commit | Tests | Deferred |
|---|---|---|---|---|
| 1 | Measure the delete and the publish step, warm and cold | 15409222 | none — measurement | — |
| 2 | Put the corrected trade to the human, record the decision | 748ed3fc | none — records | — |
| 3 | File the follow-ups 139 and 140 | bc6ee927 | none — records | — |
| 4 | Correct backlog 132's out-of-scope line | 748ed3fc | none — records | — |

## Recovery tasks from the review of 2026-09-06

The first attempt reached Ship without a Review. `workflow.md` Stage 8 takes the failure edge back
to Execute and asks for the findings as named tasks here, because an Execute resume reads this
file and never the review.

| # | Task | Commit | Tests | Deferred |
|---|---|---|---|---|
| R1 | Return the item to `backlog/` at `Stage: 4-execute`, unfreeze the plan, put the pull request back to draft | - | none — records | — |
| R2 | Correct the E2E spread everywhere: 12.84 s from runs of 293.38 s and 306.22 s, not 6.4 s | - | none — records | — |
| R3 | Reframe backlog 140 as unexplained E2E harness overhead of 34.38 s to 47.22 s, and split the build measurement out | - | none — records | — |
| R4 | Mark backlog 139's saving range preliminary at 2.37 s to 4.85 s, and drop the unverified "no correctness risk" claim | - | none — records | — |

R1 to R4 landed in `ab11e046`, one commit, because they are one review round over the same records.

## Recovery tasks from the review of 2026-09-07

The second round found the closing argument overstated. The item stays at `4-execute` and the
decision on the trade is open again.

| # | Task | Commit | Tests | Deferred |
|---|---|---|---|---|
| R5 | Correct the ceiling to 12.37 s, the whole target's cost, and withdraw the 1.3 s attributed to the delete | - | none — records | — |
| R6 | Stop using run-to-run variance to dismiss a deterministic saving; say it is a measurement problem | - | none — records | — |
| R7 | Reframe the once-per-branch loop as an owner priority call, citing (`docs/development/testing-workflow.md:142`, "Use it for browser flows") | - | none — records | — |
| R8 | Drop the unmeasured "CI publish is the cold 95 s one" claim, keeping only what `ci.yml` proves | - | none — records | — |
| R9 | State backlog 140's range as an estimated remainder, and use 12.37 s in its arithmetic | - | none — records | — |
| R10 | Label the plan a rejected, unverified proposal rather than a sound design | - | none — records | — |
| R11 | File backlog 142 for the plan-pointer check's `backlog/done/` blind spot | - | none — records | — |

R5 to R11 land in one commit, for the same reason R1 to R4 did.

## Next stages

The owner decides the trade. Then either the item closes, or the plan's design is executed and this
file grows real implementation tasks. This file is deleted in the Ship commit.
