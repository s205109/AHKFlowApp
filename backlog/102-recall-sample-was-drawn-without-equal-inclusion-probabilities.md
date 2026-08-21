# 102 - Recall sample was drawn without equal inclusion probabilities

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 3-plan
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

The two published recall ranges rest on 400 hand-written labels drawn by a sampler that kept
the rows the previous draw had selected and filled the rest at random. That is not a uniform
sample, so the Wilson intervals behind 179–533 and 35–89 are approximate. The sampler is fixed;
the labels still describe the old draw.

## User story

As a reader of the friction figures, I want the published interval to describe the draw that
actually happened, so that the range means what a 95 percent interval means.

## The defect

`scripts/sample-friction-recall.ps1` used to preserve every previously selected row and top the
sample up to 200 with random positions. The selection records show the effect:
`carriedOverLabels` reads 57 of 200 for handoffs and 58 of 200 for asks. A message that was
already in the population when the earlier 60-row draw ran had two chances of selection; one
written later had one — about 3.7 percent against 2.6 percent. Unequal inclusion probabilities
are not what a Wilson interval describes.

The sampler now selects the 200 lowest hashes of seed and message key. That draw is uniform and
stable while the transcripts grow, so labels survive a re-run without deciding it. What remains
is the labelling: the fixed sampler selects a different 200 rows per metric, and roughly 7 of
the current 200 overlap.

## Acceptance criteria

- [ ] Both samples are redrawn with the current sampler, and the selection records are
      committed with the new manifests.
- [ ] Every unlabelled row in the new draw is labelled by hand, against the rule sheet already
      written in `docs/development/friction-recall-sample.md`.
- [ ] The two ranges are recomputed and republished in that file and in
      `backlog/done/072-process-wave-2-parity-drift-guard-templates.md`.
- [ ] The paragraph "The committed sample was drawn the old way, and its intervals are
      approximate" is removed rather than softened, because it no longer applies.
- [ ] A decision is recorded on the flagged strata: those are counted whole, so nothing about
      them changes, and the item says so instead of leaving a reader to work it out.
- [ ] The interval is either computed with a finite-population correction, or kept as Wilson
      and labelled an approximation. A uniform draw is not enough on its own: Wilson is a
      binomial interval and the draw takes a fixed number without replacement, which for 200
      of 1,004 asks makes Wilson about 10 percent wider than the truth.

## Out of scope

- Changing the sampler. It already draws uniformly; this item is the redraw and the relabelling.
- The other three metrics. They are not sampled.

## Notes / dependencies

- The labelling cost is the whole item: roughly 386 rows read in full across the two metrics.
- `tests/FrictionRecallSample.Tests.ps1` covers the draw's uniformity and its stability.
- Spec: none — Design has not run.
- Plan: `docs/superpowers/plans/2026-08-21-friction-recall-interval-plan-102.md`

## Finding, 2026-08-21: the population is being deleted

The redraw this item asks for cannot reproduce the population the published figures describe.
Claude Code deletes session transcripts older than `cleanupPeriodDays`, which defaults to 30
days and is not set in this machine's `settings.json`. The window runs 2026-07-15 to
2026-08-12, so its first week is already gone. The oldest surviving transcript file is stamped
2026-07-22, which is exactly 30 days before the measurement below.

A dry run of `scripts/sample-friction-recall.ps1` on 2026-08-21, against the committed
selection records:

| Metric | Population | Unflagged | Flagged |
|---|---|---|---|
| handoffs, published 2026-08-16 | 5,472 | 5,457 | 15 |
| handoffs, 2026-08-21 | 4,633 | 4,618 | 15 |
| next-step-asks, published 2026-08-16 | 1,042 | 1,004 | 38 |
| next-step-asks, 2026-08-21 | 890 | 861 | 29 |

Nine of the 38 flagged asks no longer exist, so the published precision of 47 percent
describes messages that have been deleted. Eight of the 200 drawn handoff rows carry a label
from the old draw; the rest would need labelling again.

Redrawing today would move the handoff range from 179–533 to about 153–452, and the shift
comes from the deletion rather than from the sampling defect this item was filed against. The
whole window is deleted around 2026-09-11.

The transcripts were copied to `~/AHKFlowApp-friction-snapshot-2026-08-21` (755 files, 445 MB)
on 2026-08-21, so what remains of the window stops shrinking.
