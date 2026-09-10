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

- [x] Task 2 — extract the commit-based item finder into
      `scripts/backlog-snapshot.common.ps1`. `Get-SingleBacklogStage`,
      `Get-BacklogNumberFromPath` and `Get-BranchBacklogCandidate` moved unchanged.
      `check-shipped-plan-ticked.ps1` now dot-sources them.

      **Behavior unchanged, proved both ways.** `tests/ShippedPlanTicked.Tests.ps1` passed before
      the move and passes after, with the same final line. The gate also still runs as a script:
      `-MergeBase <base> -TargetCommit HEAD` reported "every shipped plan carries a ticked step.
      Looked at 1 backlog item(s) this branch touches, of which it ships 0".

      **Mutation proof.** Renaming `scripts/backlog-snapshot.common.ps1` to `.bak` turned
      `ShippedPlanTicked` red, naming the missing file. So no duplicate definition was left behind
      in the original. Restored and green.

      **Three defects in the plan, all found by running it.**

      1. The plan registered the new suite in Task 6. The runner refuses to run at all while a
         suite file is missing from `tests/powershell-suites.json`, so registration has to happen
         in the task that creates the suite. `AcceptanceBoxes.Tests.ps1` is registered now.
      2. The plan used `"baselineSeconds": 0` as the placeholder. The runner rejects it: "has an
         unusable baselineSeconds '0'. Use a number above zero, or null." `null` is the correct
         placeholder. Measured 0.6 s on two consecutive runs and set that.
      3. Inserting one line at the top of `tests/powershell-suites.json` shifted every line below
         it and broke two live citations, in `backlog/done/129-*` (`:41` to `:42`) and
         `backlog/done/138-*` (`:37` to `:38`). Both repaired. The manifest is alphabetical and
         `AcceptanceBoxes` sorts first, so the shift was unavoidable, not a choice.

      **And two of my own citations drifted.** Moving code out of
      `check-shipped-plan-ticked.ps1` moved the lines the spec and plan cite in that same file.
      `:112` became `:105` and `:82` became `:78`. Both repaired. This is the trap of citing a
      file in the same change that edits it.

      `pwsh ./scripts/run-powershell-suites.ps1 -Job invariants`: all 7 suites passed.
