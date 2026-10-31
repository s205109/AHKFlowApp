# Plan progress: backlog 191

Plan: `docs/superpowers/plans/2026-10-30-one-execute-stage-and-one-shared-review-plan-191.md`

- Task 1 (retired anchors, frozen-plan skip): done at b9eee13b. Tests: `ProcessAnchors.Tests.ps1` 11 cases and `PlanWorkflowParity.Tests.ps1` 15 cases pass; the live parity check prints `SKIP frozen:` for the 071 plan and exits 0. Deferrals: none.
- Task 2 (fold 5-7 into Execute): done at c76dadf1. Tests: 17 Suites pass (Process*, StageTransition*, PlanWorkflowParity*, ShippedPlanTicked*, PlanSplitRecord*, Backlog*, HandoverRules*, GateWording*, ShippingPrClosesItem*, WorkflowPdfGenerator*); parity, anchors, gate wording and citation checks pass; no backlog item at 5, 6 or 7; PDF one page. Deferrals: none. Ruling: added citation-check:ignore to two lines of backlog/done/109, which cited a workflow.md line this task moved, as commits 7e3aabc4 and 58838661 did before.
- Task 3 (one shared review): done at d261f218. Tests: Process*, StageTransition*, HandoverRules*, GateWording*, CitationFreshness* Suites pass; parity, gate wording and anchor checks pass; no Codex line in Stage 8. Deferrals: none.
- Task 4 (cheapest check that proves it): done at ada7d2f7. Tests: ProcessAnchors, SkillParity, CitationFreshness, PersonalDefaultsSyncMarker, HandoverRules Suites pass; anchor check passes; plugin copy byte-identical. Deferrals: none.
- Task 5 (Desktop copy): done, no deliverable commit (-). The user said yes. The four files match their repository sources by hash; ahkflow-design-system.html hash A432F790... unchanged. Deferrals: none.
- Simplify: applied at a38377f6, case 14 of PlanWorkflowParity.Tests.ps1 reuses its fixture. Skipped: deriving the stage count (the constant is the fail-closed check), a shared frozen-file helper (refactor outside this diff), the second parse of workflow.md (milliseconds).
- Verify: the Suites each task ran are green. Fresh-session test, four read-only subagents: idle item 031 (1-pickup, five edges), active item 191 (4-execute, five edges), the round prompt (8-review, Review's four legal edges, the body carries the stage) and the recovery-resume prompt (4-execute, closing steps again from simplify, old lines above the failure heading). All four pass and cite workflow.md. The GitHub anchor check runs at Review entry.
- Document: 15 of 16 boxes ticked. The retired-anchors box stays unticked until the GitHub check at Review entry. The stop-rule box carries the D1 and R2 readings. The docs are the work itself; no other live document names the retired stages.
- Gate green at a7a81684. Build 0 warnings, format clean, 73 of 73 Suites passed, coverage skipped (no compiled path changed), diff check clean.

## Failure edge to 4-execute (2026-10-30)

**Red evidence:**

```
Outside review round 1 at eb3a8fc2, two required findings, both CONFIRMED: (1) testing-workflow.md:47 lightweight tier ignores the coverage-tooling list in .github/code-paths-filter.yml; (2) testing-workflow.md:44 git diff --name-only without --no-renames hides the source side of a rename
```

**Recovery task:** Task 6: Review-tier diff uses --no-renames, and a coverage-tooling path selects the whole Gate (Outside review findings 1 and 2)

- Task 6 (Outside review findings 1 and 2): done at 76d38504. Tests: exemption 1, docs only, no script reads the rule; citation and gate-wording checks pass. Deferrals: none.
- Simplify: nothing to simplify, a nine-line docs change.
- Verify: exemption 1 named; targeted text checks (citation freshness, gate wording) pass and the diff was reviewed.
- Document: the change is the docs; all 16 boxes still hold.
- Gate green at c14d17bf. Build 0 warnings, format clean, 73 of 73 Suites passed, coverage skipped, diff check clean.

## Failure edge to 4-execute (2026-10-30)

**Red evidence:**

```
Claude reviewer round 1 at b3e99f0d, review 5719209156. Finding 1 (required, CONFIRMED): a round never records its Gate revision; Invoke-RoundTransition takes no -Note. Finding 2 (relabeled required, PARTIAL): pre-push prints Plans agree with the source after the parity check skips every plan as frozen.
```

**Recovery task:** Task 7: a round writes Gate green at <sha> into its pull request body, and Review reads it there (finding 1). Task 8: pre-push prints the parity check's skip instead of claiming agreement (finding 2). Task 9: findings 3 to 8, editorial and optional, in the same pass.

- Task 8 (finding 2): done at ed03d17e. Tests: the real pre-push run on this branch. Before: 'Plans agree with the source.' after the frozen skip. After: 'Plans not compared: every plan with an Appendix A is frozen.' No durable test: the step needs the private plans repository, which the PrePushQuickChecks fixture and CI do not have. Deferrals: none.
- Task 7 (finding 1): done at 02de674e. A round writes 'Gate green at <sha>' into its pull request body (workflow.md exit meanings, round section, Execute Gate paragraph); testing-workflow.md step 1 reads it there. Tests: exemption 1, docs only; parity, anchor, gate-wording and citation checks pass. Deferrals: none.
- Task 9 (findings 3 to 8): done at 02de674e. Editorial is a closed list in CONTEXT.md and workflow.md; Review exit reads 'Every review this round triaged' in all four copies, PDF regenerated, one page; resume asks for the Outside review only when the handoff names it; the handoff template carries run, post and no-findings steps; the Gate follows the closing steps; dck-verify states the rule above its table; two Suites drop Document wording. Also: an optional finding may be fixed in the same Execute pass a required one opens. Desktop copy refreshed, hashes match. Tests: 14 Suites pass, including ShippingPrClosesItem and BacklogStaleOpen. Deferrals: none.
- Simplify: nothing to simplify; the pre-push change was already cut to its old line count in 3eb94809.
- Verify: the real pre-push run shows 'Plans not compared' after the frozen skip; 14 Suites green; parity, anchor, gate-wording and citation checks pass.
- Document: all 16 boxes still hold; the docs are the change.

## Failure edge to 4-execute (2026-10-31)

**Red evidence:**

```
Claude reviewer round 2 at cc26b67e, review 5721806058. Finding 1 (required, CONFIRMED): Review step 4 lets an optional fix ride an Execute pass, but steps 6 and 7 send it back to no reviewer, so a changed workflow rule goes unreviewed.
```

**Recovery task:** Task 10: steps 6 and 7 send an optional finding fixed in the Execute pass back to the reviewer that raised it (finding 1). In the same pass: recopy the Desktop workflow.md (finding 2) and add the Gate green line to the round example (finding 4, editorial).

- Task 10 (round 2 findings 1, 2 and 4): done at fd0d5304. Review step 6 sends an optional finding fixed in the same Execute pass back to the reviewer that raised it, and step 7 sends only optional findings closed in triage to no reviewer (workflow.md, workflow.html). The round example names 'Gate green at <sha>' in the pull request body. Desktop copy refreshed after this commit, all four hashes match. Optional finding 3 declined. Tests: exemption 1, docs only; parity, anchor, gate-wording and citation checks pass. Deferrals: none.
- Simplify: nothing to simplify.
- Verify: exemption 1; the four process checks pass; git diff --check clean.
- Document: all 16 boxes still hold; the docs are the change.
