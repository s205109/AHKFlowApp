# 106 - Nothing detects a merged item whose records were never closed

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (script, CI)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

Nothing detects an item whose pull request merged while its records stayed open.
`workflow.md` Stage 9 requires the closure commit, and no check confirms it happened.

## User story

As a contributor, I want a merged pull request that left its backlog item open to fail a
check, so that the item does not sit in `backlog/` describing work that already shipped.

## Acceptance criteria

- [ ] A check detects an item whose work merged while the item stayed in `backlog/`.
- [ ] The check decides on the **pull request diff**, never on the pull request title.
      Titles go stale: PR #312 is titled "backlog 096" but did item 097's work and closed
      097 correctly. The item was renumbered by commit `db1a7884` and the title never
      caught up. A title-based detector reports that as a defect; a diff-based one does not.
- [ ] The check states plainly which invariant it uses, and why the rejected ones were
      rejected. Candidates: an item in `backlog/` whose Stage is `9-ship`; a pull request
      touching `backlog/NNN-*.md` that does not move it to `backlog/done/`; a post-merge
      sweep of `main`. The first two are cheap and miss the 071 shape. The third catches it
      and needs a schedule.
- [ ] A fixture proves both directions: a merged pull request that left its item open
      fails, and one that closed its item passes.
- [ ] Partial work on an item across several pull requests does not trigger the check.
      Most items ship over more than one pull request, so a naive rule is unusable.
- [ ] The check joins `scripts/run-powershell-suites.ps1`, which discovers
      `tests/*.Tests.ps1` by glob and needs no wiring.

## Out of scope

- Closing backlog 071 itself. A housekeeping round does that.
- Changing what Stage 9 requires. The rule is correct; only the enforcement is missing.

## Notes / dependencies

- Measured on 2026-08-15: this happened **once** in 274 merged pull requests, backlog 071
  (merged in PR #288 on 2026-08-12, item left at `Stage: 8-review` with 10 unticked boxes).
  Low frequency, high cost — the item that went stale was the one defining the process.
- The wording that made the fix route ambiguous was corrected in backlog 072:
  `workflow.md` section 5 now says closing a merged item is not a pickup.
- Spec: none — moderate.
- Plan: `docs/superpowers/plans/2026-08-19-detect-unclosed-merged-item-plan-106.md`
- The `9-ship` candidate is rejected as **the** invariant, not as a signal. It misses the 071
  shape, so it cannot be the rule; it costs one comparison, so the check keeps it as a second
  arm with its own message. Decided at grilling on 2026-08-19.
