# 191 - One Execute stage and one shared review

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (process docs, stage-transition script, process checks)
- **Difficulty**: complex
- **Stage**: 4-execute

## Summary

The Gate runs again at Verify and again at Review, and every review round that needs code walks
Simplify, Verify and Document again. This item folds Simplify, Verify and Document into Execute,
sets up one review that the Claude reviewer and the Outside review read together, and replaces
the "durable test by default" rule with "the cheapest check that proves it".

## User story

As the developer of this repository, I want each change to pass the Gate once per real change
and to be reviewed once by both reviewers together, so that review rounds stop repeating whole
stages and adding tests nobody needs.

## Acceptance criteria

Each criterion is refined in the spec named below. Tick a box only when its words hold literally.

- [ ] `docs/development/workflow.md` has no Stage 5, 6 or 7. The simplify pass, the verification
      artifact, the docs update and the acceptance-box ticks happen inside Execute, before a Gate
      on the final revision that ends Execute.
- [ ] The other stages keep their numbers: `0-intake`, `1-pickup`, `2-design`, `3-plan`,
      `4-execute`, `8-review`, `9-ship` and `10-cleanup`.
- [ ] The anchors `stage-5-simplify`, `stage-6-verify` and `stage-7-document` lead to the Execute
      section, so every existing link still works.
- [ ] `scripts/take-stage-transition.ps1` takes the new legal targets from `workflow.md`, and its
      Suite and every other process check that reads the stage graph pass.
- [ ] No item sits at Stage 5, 6 or 7.
- [ ] An ADR records the stage merge and the reasons for it.
- [ ] Review starts with one reviewer handoff file. The Claude reviewer and the Outside review
      read the same revision at the same time.
- [ ] `workflow.md` no longer names Codex or `/codex:review` as part of Review.
- [ ] One `custom-review-findings` pass triages both reviews once both are in.
- [ ] An editorial fix closes in triage with a fresh citation. A change to behaviour, to a
      requirement, or to an executable workflow rule goes back to the reviewer that raised it.
      When both raised it, only the Outside review reads it.
- [ ] Review stops at the first round with no CONFIRMED or PARTIAL finding.
- [ ] Review's exit checks that the Gate evidence for the final revision is still valid, and runs
      only what is not.
- [ ] The reviewer instructions limit required findings to correctness, the stated requirements,
      security, data loss, concurrency and real performance regressions. Everything else is
      optional.
- [ ] `AGENTS.md` states the new default verification artifact: the cheapest check that proves
      the change, where an existing test that covers it counts. A new test names the regression it
      prevents and why the existing tests miss it. A plan task starts with a failing test only
      when it changes behaviour. A routine change usually adds 0 to 3 tests, and a pull request
      that adds more says why in one sentence. The three exemptions stay.
- [ ] The rule for tests in routine work says: reuse existing coverage; explain each new and each
      removed test in the pull request; audit nearby tests only when duplication or slow setup is
      plain to see; a removal needs surviving coverage, or a behaviour that is gone.
- [ ] After the user's yes at that point, `workflow.md`, `workflow.html`,
      `ahkflow-workflow-cheatsheet.html` and `ahk-workflow.pdf` in
      `C:\Users\btase\Desktop\AHKFLOW WORKFLOW PROCESS\` are rebuilt from the repository's
      `docs/development/workflow.md`. `ahkflow-design-system.html` is unchanged.

## Out of scope

- Gate reuse, the time budget and citation drift. Backlog 188 carries them.
- The memory and instruction cleanup, and the architecture pilot. Each is an item of its own.
- Any change to which tests CI runs.

## Notes / dependencies

- Filed by backlog 188 at its Plan stage. Spec sections: 4.5 "Stage merge" and "Review
  checkpoint", 4.6 (the verification rule and the rule for tests in routine work), 4.8, and
  section 5 (the stage-merge ADR).
- Uses the term Outside review, which backlog 188 adds to `CONTEXT.md`. Pick this item up after
  188 merges, or stack it on 188 with `-BaseRef`.
- Its merge starts the window for "Gate-required stage exits per item" in 188's follow-up item
  (spec 4.3). After it merges, the stages that need a green Gate are `4-execute` and `8-review`.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: `docs/superpowers/plans/2026-10-30-one-execute-stage-and-one-shared-review-plan-191.md`
