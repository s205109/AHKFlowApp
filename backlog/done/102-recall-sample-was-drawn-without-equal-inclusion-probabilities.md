# 102 - Recall sample was drawn without equal inclusion probabilities

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 9-ship
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

The two published recall ranges rest on 400 hand-written labels drawn by a sampler that kept
the rows the previous draw had selected and filled the rest at random. That is not a uniform
sample, so the Wilson intervals behind 179–533 and 35–89 are approximate. The sampler is fixed;
the labels still describe the old draw.

## User story

As a reader of the friction figures, I want to know which interval the published ranges can
honestly carry, and why, so that I am not reading a number that claims more than the draw
supports.

**This user story was narrowed on 2026-08-21, and the original is recorded here.** It read: "As
a reader of the friction figures, I want the published interval to describe the draw that
actually happened, so that the range means what a 95 percent interval means." That needs a
redraw and about 386 fresh hand labels. The population those labels would read is being deleted
on a 30-day cycle, so the redraw became its own piece of work with its own deadline. Backlog 113
carries the original user story and the three criteria that serve it. What is left here is the
decision, which is finished.

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

- [x] The paragraph "The committed sample was drawn the old way, and its intervals are
      approximate" is **kept, and says why no redraw happened**, because it still applies.
      `tests/FrictionRecallSample.Tests.ps1` fails if a later edit deletes it while keeping the
      numbers.
      **This criterion was rewritten, not merely annotated.** It originally required removing
      the paragraph. That was written on the assumption a redraw would happen; without one the
      caveat is still true, and deleting it would have withdrawn a warning the figures need.
      Backlog 113 removes the paragraph, after its redraw earns that.
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
      so applying it anyway would have published 164-531 and 34-85: figures resting on an
      assumption the data breaks. A design-based estimator needs the earlier 60-row draw's
      selection record and the population as it stood then, and neither survives.
      `Get-RecallInterval` exists with the correction behind a `-Correct` switch that nothing
      passes, for backlog 113 to use once the draw is uniform. That switch computes the exact
      hypergeometric interval; an earlier draft used a normal approximation that claimed
      certainty at the boundary, and a test case now pins the exact answer.
- [x] The population's retention deadline is measured and written down, and the transcripts are
      copied before more of them age out. See the finding at the end of this file.

### The three criteria that moved to backlog 113

These are **not ticked and not abandoned**. They were removed from this item's list on
2026-08-21 rather than left unticked here, because leaving them here would have parked a
deadline in a closed item. Backlog 113 carries them verbatim, and its own deadline is the
2026-09-11 date on which the last of the window is deleted.

1. Both samples are redrawn with the current sampler, and the selection records are committed
   with the new manifests.
2. Every unlabelled row in the new draw is labelled by hand, against the rule sheet already
   written in `docs/development/friction-recall-sample.md`.
3. The two ranges are recomputed and republished in that file and in
   `backlog/done/072-process-wave-2-parity-drift-guard-templates.md`. Item 072 is untouched by
   this item, and 113 adds its figures there as a dated addition, never a substitution.

## Out of scope

- Changing the sampler. It already draws uniformly.
- The redraw and the relabelling. Both moved to backlog 113 once the population turned out to
  be disappearing; see the finding below.
- The other three metrics. They are not sampled.

## Why this item closes here

Its list above is complete, and no box was ticked that is not true. The three criteria that
would need the redraw were moved out rather than ticked, and backlog 113 now holds them with the
retention deadline attached.

What this item delivered is the decision and the reason behind it. The interval stays plain
Wilson and stays labelled an approximation. The flagged stratum is recorded as a census, not a
sample. `Get-RecallInterval -Correct` exists and computes the exact hypergeometric interval, with
a test that walks every script's syntax tree to prove nothing calls it while the draw is still
the non-uniform one. The retention finding and the snapshot are written into
`docs/development/friction-recall-sample.md`.

The narrower user story above is what closes. The original one is backlog 113's, and it stays
open there until the redraw earns it.

## Notes / dependencies

- The labelling cost, roughly 386 rows read in full across the two metrics, moved to backlog
  113 with the redraw.
- `tests/FrictionRecallSample.Tests.ps1` covers the draw's uniformity and its stability.
- Spec: none — Design has not run.
- Plan: `docs/superpowers/plans/2026-08-21-friction-recall-interval-plan-102.md`

## Finding, 2026-08-21: the population is being deleted

The redraw this item originally asked for cannot reproduce the population the published figures describe.
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
