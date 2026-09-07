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

R1 to R4 land in one commit, because they are one review round over the same records.

## Next stages

Verify, then Document, then Review. This file is deleted in the Ship commit.
