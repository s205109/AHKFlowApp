# 102 - Recall sample was drawn without equal inclusion probabilities

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 8-review
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
      **Not done, and not doable from this item.** The population is deleted on a 30-day cycle
      and had already lost the window's first week. Handed to backlog 112, which redraws
      against the snapshot.
- [ ] Every unlabelled row in the new draw is labelled by hand, against the rule sheet already
      written in `docs/development/friction-recall-sample.md`.
      **Not done.** It follows the redraw. Handed to backlog 112.
- [ ] The two ranges are recomputed and republished in that file and in
      `backlog/done/072-process-wave-2-parity-drift-guard-templates.md`.
      **Not done, and deliberately so.** No defensible corrected range exists for this draw —
      see the last box. Item 072 is untouched. Handed to backlog 112, which adds its figures
      to 072 as a dated addition rather than a substitution.
- [x] The paragraph "The committed sample was drawn the old way, and its intervals are
      approximate" is **kept, and says why no redraw happened**, because it still applies.
      `tests/FrictionRecallSample.Tests.ps1` fails if a later edit deletes it while keeping the
      numbers.
      **This criterion was rewritten, not merely annotated.** It originally required removing
      the paragraph. That was written on the assumption a redraw would happen; without one the
      caveat is still true, and deleting it would have withdrawn a warning the figures need.
      Backlog 112 removes the paragraph, after its redraw earns that.
- [x] A decision is recorded on the flagged strata: those are counted whole, so nothing about
      them changes, and the item says so instead of leaving a reader to work it out.
      Recorded in `docs/development/friction-recall-sample.md` under "How a label was decided":
      the flagged stratum is a census, not a sample, so no interval applies to it.
- [x] The interval is either computed with a finite-population correction, or kept as Wilson
      and labelled an approximation. A uniform draw is not enough on its own: Wilson is a
      binomial interval and the draw takes a fixed number without replacement, which for 200
      of 1,004 asks makes Wilson about 10 percent wider than the truth.
      **Second branch taken, and the reason the first is unavailable is written down.** A
      finite-population correction assumes equal inclusion probabilities. This draw had none,
      so applying it anyway would have published 164–531 and 34–85: figures resting on an
      assumption the data breaks. A design-based estimator needs the earlier 60-row draw's
      selection record and the population as it stood then, and neither survives.
      `Get-RecallInterval` exists with the correction behind a `-Correct` switch that nothing
      passes, for backlog 112 to use once the draw is uniform. That switch computes the exact
      hypergeometric interval; an earlier draft used a normal approximation that claimed
      certainty at the boundary, and a test case now pins the exact answer.

## Out of scope

- Changing the sampler. It already draws uniformly.
- The redraw and the relabelling. Both moved to backlog 112 once the population turned out to
  be disappearing; see the finding below.
- The other three metrics. They are not sampled.

## Why this item stays open

Three of its six boxes are unticked, and its user story is not satisfied: the published interval
still does not describe the draw that happened. Ship closes an item when its boxes are ticked,
so moving this file to `backlog/done/` would record a result that is not true.

What this item did deliver is the decision and the reason behind it. The interval stays plain
Wilson and stays labelled an approximation, the flagged stratum is recorded as a census, and the
retention finding is written into `docs/development/friction-recall-sample.md`. The work that
would satisfy the user story is backlog 112.

**The Stage is `8-review`, and that is deliberate.** It was `3-plan`, which
`tests/BacklogStaleOpen.Tests.ps1` excludes from its candidates by design — a plan may sit
unstarted for as long as it likes. This item is not unstarted: its plan executed and merged. Had
the Stage stayed at `3-plan`, an item whose work had shipped would have sat open in `backlog/`
with nothing ever noticing. At `8-review` the twelve-commit stale check does apply, so if
backlog 112 has not closed this out by then, the suite raises it rather than leaving it to
memory.

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

What a redraw would publish is unknown: it selects different rows and only 8 of the 200 drawn
handoff rows carry a label. What can be measured is the base the rate multiplies. Holding the
observed 11 in 200 fixed and applying it to the 4,618 surviving unflagged rows gives 153–452
instead of 179–533 — an illustration of the deletion's effect on the base, not a prediction of
the redraw, whose labels are unread. The whole window is deleted around 2026-09-11.

The transcripts were copied to `~/AHKFlowApp-friction-snapshot-2026-08-21` (755 files, 445 MB)
on 2026-08-21, so what remains of the window stops shrinking.
