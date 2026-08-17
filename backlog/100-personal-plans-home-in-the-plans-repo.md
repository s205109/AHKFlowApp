# 100 - Personal plans home in the plans repo

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (docs, plans repo layout)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

Give personal plans and specs a home inside the plans repository, under
`docs/superpowers/personal/`. Today `AGENTS.md` sends them out of the repository
altogether, so they end up scattered in personal folders and are never versioned.

## User story

As the repository owner, I want my personal plans stored beside the project plans,
so that one private repository holds all of my planning work.

## Acceptance criteria

- [ ] `docs/superpowers/personal/plans/` and `docs/superpowers/personal/specs/` exist and hold at least one file each, or a `README.md` that explains the folder.
- [ ] `AGENTS.md` no longer tells the reader to keep personal planning work out of the plans repository. It names the two homes instead: project work in `plans/` and `specs/`, personal work in `personal/plans/` and `personal/specs/`.
- [ ] `docs/development/workflow.md` Stage 3 carries the narrative that `AGENTS.md` links to. Today the link points at a section that never mentions this rule.
- [ ] `docs/development/workflow.md` section 6, the linking convention, says the backlog-number naming rule applies to `plans/` and `specs/` only, not to `personal/`.
- [ ] A personal plan needs no backlog number, no backlog item, and no `- Plan:` bullet anywhere.
- [ ] The A/B output-style test plan moves from `C:\Users\btase\.claude\ab-style-test\PLAN.md` into `docs/superpowers/personal/plans/`, as the first resident.
- [ ] A test proves that a backlog item cannot point at a personal plan.

## Out of scope

- Moving any other personal plan. Only the A/B output-style test plan migrates.
- Changing how project plans are named or numbered.
- Changing `scripts/backlog.common.ps1`. Its pointer pattern already rejects a path with a subfolder, and that rejection is what keeps the two homes apart.

## Notes / dependencies

- The exclusion rule lives in exactly one place, `AGENTS.md:156`. It links to
  `docs/development/workflow.md#stage-3-plan`, and that section never states it. So the
  rule has no narrative. Fixing that is part of this item.
- `scripts/backlog.common.ps1:169` requires a `- Plan:` pointer to match
  ``^`docs/superpowers/plans/[^/`]+\.md`\.?$``. A path with a subfolder fails.
  `tests/BacklogPlanPointer.Tests.ps1:80` asserts that failure. So a `personal/` subfolder
  cannot be referenced from a backlog item, which is the separation this item wants.
- The plans repository is `s205109/AHKFlowApp-plans`, and it is already private. Privacy was
  never the reason for the exclusion, so nothing about privacy changes here.
- Spec: none — moderate difficulty goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-08-17-personal-plans-home-plan-100.md`
