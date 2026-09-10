# Progress — backlog 151, close the item in the shipping pull request

Plan: `docs/superpowers/plans/2026-09-10-close-the-item-in-the-shipping-pr-plan-151.md`

One line per finished task, written after its deliverable commit.

Pacing: stop after Task 2 and report. Agreed with the human at grilling on 2026-09-10.

## Before Task 1

This file replaced a leftover copy holding **backlog 132's** progress. That file was still
tracked on `main`: Stage 9 requires deleting the progress file, and the housekeeping round that
closed backlog 132 on 2026-09-10 missed that one part. Overwriting it here is not the fix for
that defect, it just moves it out of sight on this branch. The finding is recorded in backlog
151's notes so a housekeeping round can deal with `main`.

## Design evidence carried into Execute

A throwaway prototype ran the rule against pull request #400's real head and merge base on
2026-09-10, before any task was written:

```
PR #400 head=fd269d571ab3119e580ab847252561424fcb8cc4 base=0a43d9956ea7a82a8a494048997b55a1f9c20bd5
candidates: 1 -> 132
inventory status: ok, paths: 151
  132 : backlog/132-run-e2e-flow-collections-in-par-59789baa.md boxes 5/5 -> REPORTED
PLAN-PROGRESS.md tracked at that head: yes
```

A scan of all ten open backlog items found none with every acceptance box ticked, so arm 3 will
not fire on the real backlog when Task 5 lands.

## Tasks

- [x] Task 1 — count acceptance boxes. `scripts/backlog-acceptance.common.ps1` plus
      `tests/AcceptanceBoxes.Tests.ps1`. Suite passes.

      **The plan's own assertion was wrong, and the real backlog caught it.** The plan told me to
      assert that backlog 072 reads as fully ticked, because its unticked box sits under
      `## Friction baselines`. It does not. Backlog 072 has a second unticked box at line 99,
      inside its `## Acceptance criteria` section, with the reason written beside it. `AGENTS.md`
      asks for exactly that, so 18 of 19 is the correct reading. The counter was right and the
      plan was wrong.

      Replaced it with a stronger assertion built from measured numbers: backlog 072 holds 30
      checkboxes in the file and 19 Acceptance boxes in the section, 18 of them ticked. A counter
      with no section scope reports 30. That is real data, not a fixture.

      **Mutation proof.** Replacing the section test with `$inSection = $true` turned the suite
      red with 5 problems, including "got 30 in the file and 30 in the section. The section scope
      is not being applied." Restored, and the suite is green again. So the scope rule is really
      wired, not just plausibly present.

      Also added a case the plan did not have: `- [X]` with an upper-case mark counts as ticked.
      And an assertion that every open item reports at least one Acceptance box, which is the
      failure mode a fixture cannot show.
