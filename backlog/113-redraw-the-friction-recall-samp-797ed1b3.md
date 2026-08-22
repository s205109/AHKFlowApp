# 113 - Redraw the friction recall samples before retention deletes the window

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: complex
- **Stage**: 2-design
- **Depends on**: 102-recall-sample-was-drawn-without-equal-inclusion-probabilities

## Summary

The two published recall ranges rest on 400 labels from a draw that gave older messages about
1.4 times the inclusion probability of newer ones. Backlog 102 could not fix that, because the
population the labels describe is being deleted on a 30-day cycle. This item does the redraw
against the snapshot, relabels, and decides what a measurement window should be when the
evidence behind it expires.

## User story

As a reader of the friction figures, I want the published interval to describe the draw that
actually happened, so that the range means what a 95 percent interval means.

## Acceptance criteria

- [ ] Both samples are redrawn with the current sampler, reading the snapshot rather than the
      live transcripts, and the selection records are committed with the new manifests.
- [ ] Every unlabelled row in the new draw is labelled by hand, against the rule sheet in
      `docs/development/friction-recall-sample.md`.
- [ ] The two ranges are recomputed with `Get-RecallInterval -Correct` and republished in that
      file. The correction is valid for the new draw, because that draw is uniform.
- [ ] The corrected figures reach `backlog/done/072-process-wave-2-parity-drift-guard-templates.md`
      as a dated addition, never as a substitution. Its `### Measured 2026-08-16` section stays
      readable as what was measured then, and a test pins its two published rows to their exact
      text.
      **This criterion was rewritten on 2026-08-22, at Design.** It originally required the
      addition "under `### The withdrawn figures`". That heading holds a table of figures that
      were withdrawn as wrong, so a current figure placed under it would read as withdrawn too.
      The addition goes in a new `### Measured <date>, redrawn against the 2026-08-21 transcript
      snapshot` section immediately after `### Measured 2026-08-16`, and `### The withdrawn
      figures` is left alone. The requirement the criterion existed for — dated, additive, never
      a substitution — is unchanged and is now also a test.
- [ ] The paragraph "The committed sample was drawn the old way, and its intervals are
      approximate" is removed, because after the redraw it no longer applies.
- [ ] The window question is decided and the decision is written down: a rolling window that
      retention always covers, a longer `cleanupPeriodDays` on the measuring machine, or a
      committed artifact that survives deletion. Whichever is chosen, the reason the other two
      were not is recorded.
- [ ] `tests/FrictionRecallSample.Tests.ps1` asserts the new published ranges, computed with
      `-Correct`, and asserts the companion Wilson value appears exactly once. Its case that
      forbids `-Correct` in `scripts/` is updated or removed with a stated reason.
- [ ] The test also pins what the design leaves otherwise unguarded: both precision figures
      against the manifests, the sentence attributing the ask precision change to deletion, all
      four archived 2026-08-16 records, and `-ProjectRoot` proven end to end by running the
      sampler as a script against a fixture transcript directory.

## Out of scope

- Changing the sampler's selection rule. It already draws uniformly.
- The other three metrics. They are not sampled.
- Deleting the snapshot before the redraw ships.

## Notes / dependencies

- **This item was filed as 112 and renumbered to 113 on 2026-08-21.** PR #337 had already taken
  112 for `backlog/112-stale-citations-in-the-plans-re-75722759.md` on an unmerged branch, so
  `ls` on `backlog/` could not see the clash. CI fails when two files share a number.

- **The clock has stopped, but only because of the snapshot.**
  `~/AHKFlowApp-friction-snapshot-2026-08-21` holds 755 files and 445 MB, copied on 2026-08-21.
  It covers 2026-07-22 onward. The window's first week, 2026-07-15 to 2026-07-22, was already
  deleted when the copy was taken and is not recoverable. Without the snapshot the whole window
  would have gone around 2026-09-11.
- **What the redraw will and will not restore.** The snapshot makes a uniform draw possible and
  makes it reproducible for anyone holding the copy. It does not restore the missing first week,
  so the redrawn population is smaller than the 2026-08-16 one and the recomputed counts will be
  lower for that reason alone. Say so where the figures are published, or the drop reads as a
  fall in friction.
- **A population key list is not a substitute for the snapshot.** A key list reproduces which
  rows were selected, so it makes a draw checkable. It cannot support a fresh label, because
  labelling needs the message text and the text is what retention deletes. Do not offer it as
  the answer to the window question.
- **Nine flagged asks are already gone.** The 2026-08-16 draw flagged 38; on 2026-08-21 the same
  match set flagged 29. The committed manifest is the only surviving record of those nine, so
  the precision figure of 47 percent cannot be re-derived from transcripts.
- **The snapshot needs a deletion date.** Nothing tracks 445 MB sitting in a home directory.
  Propose: delete once this item ships, and in any case review it by 2026-12-31.
- **`cleanupPeriodDays` is a machine setting, not a repository one.** Raising it would slow
  future loss but recovers nothing already deleted, and it changes the human's machine. State
  it as an option; do not change it as part of this item.
- **This item carries backlog 102's original user story.** That item closed on 2026-08-21 on a
  narrower one: which interval the published ranges can honestly carry, and why. Its first three
  acceptance criteria - the redraw, the relabelling, and the republishing - were moved here rather
  than left unticked in a closed file, and they are the first four criteria above. Closing this
  item is what finally satisfies the story 102 was filed for.
- `Get-RecallInterval` already exists in `scripts/sample-friction-recall.ps1` and carries the
  `-Correct` switch this item will be the first to use.
- Base: `origin/main` at e65a5b9c, confirmed at Pickup. The snapshot directory
  `~/AHKFlowApp-friction-snapshot-2026-08-21` was re-checked on 2026-08-22 and still holds
  106 top-level project folders.
- Spec: `docs/superpowers/specs/2026-08-22-friction-recall-redraw-design-113.md`
- Plan: none — the item is at Intake.
