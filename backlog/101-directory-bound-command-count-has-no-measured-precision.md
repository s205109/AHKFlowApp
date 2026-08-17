# 101 - Directory-bound command count has no measured precision

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs)
- **Difficulty**: moderate
- **Stage**: 0-intake
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

Backlog 072 published 179 directory-bound command lines handed to the human. Three of its
five friction counts carry a measured precision or a rule that separates a real event from
discussion of one. This one carries neither, and neither does the cleanup count, which
backlog 103 carries. The figure is a count of matched command lines and nothing more.

## User story

As a contributor planning wave 4, I want the directory-bound command count to mean the same
thing the other four counts mean, so that the five figures can sit in one table without a
footnote that undoes one of them.

## The defect

Backlog 072 left one measurement requirement unticked, and said why in
`backlog/done/072-process-wave-2-parity-drift-guard-templates.md`. Two metrics fail it: this
one, and cleanup events, which backlog 103 carries. Two separate problems sit behind this one.

**It over-counts.** A command line inside a fenced block counts whether it was handed over or
merely used as an example. Handoffs and next-step asks measured this by hand-labelling every
flagged row — precision came out at 67 and 47 percent. Nothing equivalent ran here.

**It under-counts, so 179 is not an upper bound either.** The rule needs a path in the
command line. A command that is directory-bound only because of the shell's working
directory carries no path, and the match set never sees it. This is the second unresolved
question at the end of the backlog 072 plan.

## Acceptance criteria

- [ ] Every flagged row is labelled by hand, using the same rule sheet the other two metrics
      used, so precision is measured rather than assumed. 179 rows, ledger already committed
      at `docs/development/friction-samples/ledgers/directory-bound-commands.csv`.
- [ ] A sample of unflagged messages is labelled for misses, at the sample size backlog 072
      used for its other two metrics, so the result is a range rather than a point.
- [ ] The rule sheet is written down before labelling starts and committed with the labels.
      Backlog 072 found that one unwritten rule — a next-step ask is about what work to do
      next, not about how a mechanism works — decided seven rows on its own.
- [ ] The published figure in `backlog/done/072-...md` is replaced with the measured range,
      and the row that reads "Precision unmeasured" is removed rather than softened.
- [ ] The unticked measurement requirement in backlog 072 is ticked, or the reason it still
      cannot be is written down.
- [ ] A decision is recorded on the working-directory case: widen the rule to catch it, or
      state that it is out of the metric's definition. Do not leave it open — two compliant
      readers would count differently.

## Out of scope

- Re-measuring the other four friction counts. They are published with their evidence and
  nothing here disputes them.
- Changing what the metric is for. It stays a count of command lines, not messages.

## Notes / dependencies

- The measurement script is `scripts/measure-process-friction.ps1` and the labelled evidence
  format is `docs/development/friction-recall-sample.md`.
- Wave 4 (backlog 074) does not depend on this. The direction — fewer directory-bound
  commands — holds whatever the precision turns out to be.
- Spec: none — Design has not run.
- Plan: none — the item is at Intake.
