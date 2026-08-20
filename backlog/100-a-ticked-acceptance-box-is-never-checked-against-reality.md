# 100 - A ticked acceptance box is never checked against reality

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (backlog items, process docs)
- **Difficulty**: moderate
- **Stage**: 7-document
- **Depends on**: none

## Summary

Stage 9 Ship wrote a backlog item's acceptance ticks, and Stage 8 Review runs before Stage 9.
So no reviewer ever saw a ticked box. The claims arrived after the only human read of the
branch. This item moves the tick to Stage 7 Document, the last stage before Review.

## User story

As a reviewer, I want a branch's acceptance claims in front of me while I read its diff, so
that I can check a claim against the change instead of taking it on trust after the fact.

## The defect

This item was named in the backlog 072 plan, which called a ticked box that is not true "the
exact defect backlog 100 exists to catch". The item did not exist when that sentence was
written. Filing it closed the forward reference.

**The filed premise was that ticks in `backlog/done/` are false. The measurement disproved
it.** See `## Measurement` below. What the measurement did find is a structural hole that
does not depend on any false-tick rate: Ship wrote the ticks, Review ran earlier, so nothing
read them. That held for every item ever shipped.

Backlog 097 solved the neighbouring problem for `file:line` citations: a citation now carries
its quoted text, and `scripts/check-citation-freshness.ps1` reads the cited line. An
acceptance box carries no such handle, and the same trick does not transfer. A criterion
describes an outcome, and no script can read an outcome. The answer here is a review step,
not a check.

## Measurement

Taken 2026-08-20 against `backlog/done/`. Full table and method in the spec.

- Population: 524 ticked boxes across 94 items. Every item carries at least one.
- Sample: 20 boxes, equal probability, no replacement, `-SetSeed 100`. The unit is the box,
  not the item, so a box in a short item is no likelier to be drawn than one in a long item.

| Verdict | Count |
|---|---|
| true — the outcome is observable in the repository | 17 |
| unverifiable — deciding needs work the record does not carry | 2 |
| superseded — true at merge, made false later on purpose | 1 |
| **false** | **0** |

Three findings came out of it:

1. **Nothing read a tick.** The hole this item now closes.
2. **Two of twenty criteria cannot be checked by anybody**, because they describe a diff
   rather than a state: "keep their current retry behaviour unchanged" (033), and
   "deleted/rewritten ... cover the rebuilt API" (022b). A reviewer is as stuck as a script.
   Fixed by one line in `backlog/000-backlog-item-template.md`.
3. **A retroactive check would be unsound.** Item 055 ticked that a disabled button's reason
   rides on a `MudTooltip` wrapper. `Pages/Profiles.razor` has no `MudTooltip` today, because
   item 056 replaced that pattern on purpose — it was "Found while reviewing the Profiles
   page download button (backlog 055)". The tick was correct and the repository moved under
   it. Any check comparing `backlog/done/` to today's code would report item 055 as a lie.

The sample measures the shipped record. Backlog 071's incident was a tick that was wrong
mid-flight and was corrected before Ship, so it was never in the frame.

## Acceptance criteria

- [x] The failure mode is written down: what a false tick costs, and which of the ticks
      already in `backlog/done/` are wrong. Sample rather than audit all of them.
      Done above. The honest answer is that none of the 20 sampled ticks was false, so the
      cost of a false tick could not be measured from the record. The cost that *was*
      measured is different: every tick in the repository's history was written after the
      only review that could have read it.
- [x] A decision is recorded on whether this is checkable at all. A criterion is prose, so a
      script cannot read it. Name the mechanism, or state plainly that the answer is a
      review step and not a check, and say what that review step is.
      **It is a review step, not a check.** The step: Stage 7 Document ticks the boxes
      against what the branch does, and Stage 8 Review reads them next to the diff. Ship
      keeps only a confirming read, because Review can change what is true.
- [ ] If the answer is a mechanism, it fails a run rather than waiting for a reviewer, in the
      way the four checks from backlog 072 do.
      **Left unticked on purpose. The criterion is conditional and its condition is false** —
      criterion 2 settled on a review step, so there is no mechanism for a run to fail on. A
      check was priced and rejected: roughly 300–400 lines of PowerShell to fail on an
      unexplained empty box, against 4 such boxes in the whole of `backlog/done/`, all of
      them deliberate and explained. It would not have caught backlog 071's incident either,
      because that tick was present and wrong rather than absent. Ticking this box would be
      the exact defect this item is about.

## Out of scope

- Rewriting existing items to a machine-readable criterion format. That is a much larger
  change and this item does not assume it is the answer.
- The `- Plan:` pointer, which `tests/BacklogPlanPointer.Tests.ps1` already checks.
- Any retroactive check or rewrite of `backlog/done/`. Finding 3 above shows it is unsound,
  not merely expensive.

## Notes / dependencies

- Named in `docs/superpowers/plans/2026-08-15-process-wave-2-plan-072.md` (private plans
  repo), Task 10, Step 4.
- Backlog 097 is the closest working example, for citations rather than criteria. Its
  approach does not transfer — a resolve check passes a pointer to wrong content.
- Backlog 072 closed with two boxes deliberately unticked and the reason written into the
  item. That is the behaviour this item makes normal rather than exceptional, and this item
  follows it for criterion 3.
- The change is documentation only: the Stage 7 and Stage 9 **Action** fields and the Stage 7
  not-applicable edge condition in `docs/development/workflow.md`, one bullet split in
  `AGENTS.md`, one line in `backlog/000-backlog-item-template.md`. No **Exit** condition and
  no edge target moved, so `scripts/check-process-parity.ps1` stays quiet and neither HTML
  view, the PDF, nor its hash sidecar needed regenerating.
- Spec: `docs/superpowers/specs/2026-08-20-acceptance-tick-timing-design-100.md`
- Plan: `docs/superpowers/plans/2026-08-20-acceptance-tick-timing-plan-100.md`
