# 207 - The shortcut warning rule checks only negative claims

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

`ShortcutWording.BannedTerms` refuses only negative claims, such as `will not open the panel`.
A positive claim, such as `will open the panel`, passes, but the refusal message says the rule
covers both.

## User story

As an owner, I want the shortcut warning rule to refuse what its message says it refuses, so
that I understand why my text was or was not accepted.

## Acceptance criteria

- [ ] `ShortcutWording.BannedTerms` refuses a positive absolute claim such as `will open the
      panel`, or the refusal message stops promising to cover what will happen.
- [ ] A test proves the banned-term list is complete against a set of examples written
      independently of the list itself.

## Out of scope

- The wording of other messages. Item 169 owns it.

## Notes / dependencies

- Split from backlog 169 at its Pickup on 2026-11-05. Item 169 asked for one pull request per
  outcome, and this is its outcome 4.
- Found by the acceptance sweep on 2026-10-13, finding F24. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F24, the absolute-claim rule.** `Constants/ShortcutWording.cs` bans only negative
  constructions: `never`, `will not`, `cannot`, `won't`, `can't`. So `will not open the panel` is
  refused with "Say what the keys do, not what will or will not happen.", while `will open the
  panel` and `always opens the panel` are both accepted. The message promises both halves and the
  list enforces one.
- Why no test catches F24. `CreateCustomKnownShortcutCommandValidatorTests` drives its cases from
  `BannedTerms` itself and asserts every entry makes an absolute claim. That proves the list is
  internally consistent, never that it is complete.
- **This one needs a decision first.** Either the list grows to refuse positive claims, or the
  message shrinks to promise only what the list enforces. `CONTEXT.md` says a Shortcut warning
  "never promises what will happen when the keys are pressed", which covers both halves. Plan
  makes the decision and records why.
- Spec: none — the decision is which side moves, and it fits in the plan.
- Plan: `docs/superpowers/plans/2026-11-06-shortcut-warning-rule-refuses-positive-claims-plan-207.md`
