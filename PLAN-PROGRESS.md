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

- [x] Task 3 — the rule, without CI. `scripts/check-shipping-pr-closes-item.ps1` plus
      `tests/ShippingPrClosesItem.Tests.ps1`, registered in the manifest in this task rather than
      in Task 6, following Task 2's lesson.

      **Mutation proof.** Replacing `if ($PullRequestIsDraft) { return @() }` with `if ($false)`
      turned the suite red, naming the draft case: "A draft pull request must not be reported".
      Restored and green. So the draft parameter is really wired.

      **Plan defect: `.Count` on an unrolled return.** The plan wrote
      `$p = Get-FixtureProblem ...`. PowerShell unrolls an array on `return`, so an empty result
      arrives as `$null` and a one-element result arrives as a bare string. Under
      `Set-StrictMode -Version Latest` both refuse `.Count`. Confirmed directly:
      `Set-StrictMode -Version Latest; 'abc'.Count` throws "The property 'Count' cannot be found
      on this object." Fixed by wrapping all eight call sites in `@(...)`.

      **Plan defect: a bare `path:line` citation.** The plan's test text carried
      a comment naming `tests/ShippedPlanTicked.Tests.ps1` with a bare line number after it, and
      no expected text. `CitationFreshness` tier 3
      refuses a bare citation on an added line. Rewritten in the canonical form. Committed
      separately as `docs: 151 canonical citation in the shipping suite`.

      Manifest citations shifted again: inserting `ShippingPrClosesItem.Tests.ps1` moved
      `SkillParity` from `:38` to `:39` and `WatchTask` from `:42` to `:43`. Both repaired.

- [x] Task 4 — replay pull request #400. Pinned to `7ca15577` on purpose. Passed first run, so
      the rule reads the real commits the same way it reads a fixture.

      Every number matches the design prototype exactly:

      ```
      head = fd269d571ab3119e580ab847252561424fcb8cc4
      base = 0a43d9956ea7a82a8a494048997b55a1f9c20bd5
      backlog 132 at that head: 5 ticked, 0 unticked, Stage 4-execute
      ```

- [x] Task 5 — arm 3 on `Get-BacklogStaleOpenProblem`. Added `-AllTicked` to the stale fixtures
      and an acceptance section to `Write-FixtureItem`, then the arm itself.

      Ran red first with exactly the two arm 3 assertions failing, and the other three new
      assertions already green. Then green. The suite's own "the real backlog/ is clean" block
      runs arm 3 against every open item and stayed green, so arm 3 finds no real open item
      claiming to be finished.

- [x] Task 6 — CI wiring. `types: [opened, synchronize, reopened, ready_for_review]` on the
      pull request event, plus the shipping step in the `repo-invariants` job.

      **Plan defect: `RepoInvariantsCiJob.Tests.ps1` pins the invariants job's suite list.** The
      plan never mentions it. Adding two suites to that job turned CI red on the pushed branch
      with "The manifest's invariants job must hold exactly: ...". Both suites added to
      `$expectedSuites`. Found by reading the failing CI run, not locally, because the earlier
      tasks had not yet added the suites to that job.

      **Second mutation proof, against the real branch.** Ticking every box on item 151 in a
      throwaway commit and running the script with this branch's own head and merge base
      reported "Backlog 151 has every acceptance box ticked and is still open in backlog/,
      Boxes: 17 of 17 ticked", plus the separate PLAN-PROGRESS.md line. Probe commit removed and
      the item restored to 17 unticked. So the CI step reads the right two commits.

      **Baselines measured.** `ShippingPrClosesItem` 7.4 s then 8.5 s, recorded as 8.5.
      `AcceptanceBoxes` 0.6 s then 0.9 s, recorded as 0.9. `BacklogStaleOpen` was re-measured
      after arm 3: 24.7 s before, 41.2 s now, so its baseline was updated too.

      **What the extra trigger costs.** The five most recent CI runs on this branch took 9m33s,
      10m49s, 8m23s, 10m20s and 10m45s. So one `ready_for_review` run costs about ten minutes,
      once per item at Ship. That sits right at the line the plan named as the point to
      reconsider. Written into item 151's notes as a follow-up worth filing. Not filed.

- [x] Task 7 — the rule written into `AGENTS.md` and `workflow.md` stage 9.

      **Plan defect: every top-level `AGENTS.md` rule bullet needs a stage anchor.**
      `tests/ProcessAnchors.Tests.ps1` refused the plan's line, which ended with the ADR link:
      "top-level bullet carries no workflow.md stage anchor". The ADR link moved inline and the
      line now ends with the stage 9 anchor.

- [x] Task 8 — the gate.

      **The full PowerShell suite set.** First run: 58 of 59 passed, `CitationFreshness` failed
      with 12 stale citations. All 12 were mine: the `ci.yml` insertions and the `workflow.md`
      stage 9 note shifted lines that six done items, two scripts and one suite cite. Repaired by
      looking up each expected text's new line, never by arithmetic. Second run: all 59 passed.

      **Fast slice.** 2946 tests, 0 failures, across five projects.

      **Citation check, both repositories.** Public repository: "every citation checks out".
      Plans repository with `-ScanRoot docs/superpowers`: "every citation checks out".

      **The five-step Gate.**

      ```
      dotnet build AHKFlowApp.slnx --configuration Release   17 projects, 0 errors, 0 warnings
      dotnet format AHKFlowApp.slnx --verify-no-changes      exit 0
      pwsh ./scripts/test-fast.ps1 -Mode PowerShell          all 59 suite(s) passed
      pwsh ./scripts/test-fast.ps1 -Mode Coverage            all per-assembly thresholds met
                                                             line 94.6%, branch 82.8%
      git diff --check main...HEAD                          exit 0
      ```

      **One box had no test, so a test was written rather than the box left unticked.**
      "`backlog/000-backlog-item-template.md` is never judged" had the guard in the script and
      nothing exercising it. Added `-AsTemplate` to the fixture and a case for it.
      Mutation-proved: replacing the guard with `if ($false)` turned the suite red naming the
      template file. Restored and green.

      All 17 acceptance boxes are now ticked, and item 151 is still open in `backlog/`. That is
      exactly the state its own rule reports. On this draft pull request it stays quiet, which is
      correct. Step 7 flips it to ready and expects CI to refuse it.
