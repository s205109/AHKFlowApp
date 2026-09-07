# 131 - Publish the Blazor app incrementally for E2E runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project build)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Outcome: the premise is wrong, and the decision is open

**Measured 2026-09-06. The stated root cause is disproved. Whether to build the change is an open
owner decision, reopened by the review of 2026-09-07.**

Read the two halves separately. The first is settled by measurement. The second is a judgement
call, and an earlier draft of this section wrongly presented it as settled too.

The premise below is wrong. `RemoveDir` deletes `bin/<config>/<tfm>/publish`, and the IL linker
writes into `obj/`. The two folders do not overlap, so the delete does not make the linker run
again. Measured warm, Release, on `main` at `abac2f91`, running the target's own publish command:

| Scenario | Runs (s) | Median (s) |
|---|---|---|
| Publish after the tree changed | 95.39 | 95.39 |
| Publish, folder left in place | 10.29, 10.88, 11.36, 13.17 | 11.12 |
| Delete, then publish | 11.12, 11.54, 13.20, 13.88 | 12.37 |
| Build only, same project | 2.85, 2.89 | 2.87 |

**The saving is about 12.37 s.** The target as it stands deletes and then publishes, so a target
that skips itself skips both. The delete-then-publish median is the number to use, and it is
12.37 s out of a 293.38 s to 306.22 s run, which is about 4 percent. It is not the 85 s the notes
below imply.

The two sample sets overlap: 10.29 s to 13.17 s without the delete, 11.12 s to 13.88 s with it.
Four runs each cannot separate them, so no part of the 12.37 s is attributed to the delete on its
own. An earlier draft claimed 1.3 s for the delete and 11 s for the ceiling. Both were wrong.

### What the measurement settles

The stated root cause is disproved. The delete does not re-run the IL linker, so "a run that
changed nothing does not pay for a full relink" describes a cost that was never there.

**CI never benefits.** CI builds, then runs one solution-wide test call
(`.github/workflows/ci.yml:71`, "dotnet test --configuration Release --no-build"). A fresh runner
has no publish folder and no stamp, so the target
always runs. How long the publish takes on a CI runner is not measured here, and no number is
claimed for it. The only 95.39 s observation was local, after the tree changed.

### What the measurement does not settle

The saving is deterministic, and roughly 12.37 s of it lands on every E2E run that skips. Two
things the earlier draft used against it do not hold.

1. **Run-to-run variance does not cancel a deterministic saving.** The 12.84 s spread comes from
   two runs, and backlog 128 itself treats a two-run median as weak evidence. A wide spread makes
   the saving hard to see in a five-run wall-clock median. It does not make the saving absent.
   This is a measurement problem, not an argument.
2. **How often the loop happens is an owner decision, not a repository fact.** The saving needs
   the Blazor `bin` folder unchanged between two E2E runs, which is what iterating on an E2E test
   or chasing a flake looks like. The repository tells developers to run E2E mode for browser
   flows, Playwright UI behavior, mobile viewport behavior, PWA behavior, and changes to the E2E
   fixture or the published Blazor output
   (`docs/development/testing-workflow.md:142`, "Use it for browser flows"). So the repository
   expects that loop to happen. The owner said on 2026-09-06 that they run E2E once per branch.
   That is a
   priority call about one person's workflow, and the earlier draft wrote it as though it were a
   property of the repository.

Against the saving, the change would reverse commit `53ef9f99`, which removed an up-to-date check
from this target because it served a stale app. The plan holds a design that addresses why the old
check went stale. That design is a proposal and has never been executed or verified.

**So the open question is a trade, and it belongs to the owner:** about 12.37 s per skipping local
E2E run, against reintroducing a mechanism that once served a stale app, with no benefit to CI.

The design is kept in the plan, labelled there as a proposal that has never been executed or
verified, so the next reader does not have to work it out again.

## Summary

`AHKFlowApp.E2E.Tests` deletes its Blazor publish folder and publishes again before every run,
which makes the IL linker run every time. This item asks for an incremental publish, so a run
that changed nothing does not pay for a full relink.

**The sentence above is the original claim, and the Outcome section shows it is wrong.** It is
left unchanged so the record shows what was believed when the item was filed.

## User story

As a developer running the E2E slice, I want the Blazor publish step to skip work it has already
done, so that a repeat run starts testing sooner.

## Acceptance criteria

None of these are true yet, because no change has been made. Each one carries its state. They stay
here rather than being deleted, because the decision is open and they still describe the work if
the owner says to build it.

- [ ] An E2E run on an unchanged tree does not delete and republish the whole Blazor output.
      Not started: the publish target is untouched, pending the owner's decision.
- [ ] `PublishedFramework_AfterAnyE2ERun_HoldsExactlyOneCopyOfEachBootAsset` passes. That test is
      the guard against the stale-asset problem the current `RemoveDir` avoids by force, so it is
      the thing that says an incremental publish is safe.
      Not exercised: nothing changed, so the guard has had nothing new to prove. It passes as it
      did before.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes, and reports 57 tests.
      Not run: no source file changed, so `AGENTS.md` verification exemption 1 applies to the
      measurement work done so far.
- [ ] The saving is measured with `pwsh ./scripts/measure-test-modes.ps1 -Mode E2E -Runs 5`, and
      the median of five warm runs is written into this item beside the 321.65 s baseline, with
      all five runs and the maximum.
      Not run, and it is the wrong instrument for this size of change. A 12.37 s deterministic
      saving would sit inside a wall-clock spread that two runs already put at 12.84 s. Timing the
      publish target directly is what measures the saving, and those numbers are in the Outcome
      section. If the owner decides to build the change, replace this criterion with a paired
      before-and-after timing of the target itself, skipped and not skipped.

## Out of scope

- Running E2E flow collections in parallel stacks. That is backlog 132.
- Any change to what the E2E tests assert.
- The .NET Fast and Integration Modes. Backlog 128 covered those.

## Notes / dependencies

- Filed out of backlog 128, which measured the cost. E2E wall clock is 321.65 s and the test host
  holds 237 s, so roughly 85 s sits in build, publish and container start.
- The republish is in `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`, in the target that
  calls `RemoveDir` before publishing.
- The freshness guard already exists, in `tests/AHKFlowApp.E2E.Tests/PublishFreshnessTests.cs`.
- Backlog 128's design calls this the contained half of the E2E work, and separates it from the
  parallel-stacks item on purpose: bundled, the contained change would wait behind the risky one.
- Spec: none — the design is in
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`, under D7. That
  spec is shipped and frozen, so its D7 text keeps the 85 s framing. This item is the correction.
- Plan: `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`
- Three follow-ups came out of the measurement and the reviews. Backlog 139 measures the publish
  without Brotli compression, which is a smaller lever. Backlog 140 estimates the remainder of an
  E2E run that no named step accounts for. Backlog 142 covers a gap in
  `tests/BacklogPlanPointer.Tests.ps1`, which never reads items in `backlog/done/`.
- Two review rounds shaped this item. The first, on 2026-09-06, found that a first attempt set
  `Stage: 9-ship` and flipped the pull request to ready while no review existed. `workflow.md`
  puts Review before Ship, so the item came back to `4-execute`.
- The second round, on 2026-09-07, found that the closing argument was overstated. The ceiling was
  written as 11 s when the target's own cost is 12.37 s, the delete was given 1.3 s that the
  overlapping samples cannot support, run-to-run variance was used to dismiss a deterministic
  saving, one person's workflow was written as a repository fact, and a CI publish duration was
  claimed without measuring it. All five are corrected above, and the decision is open again.
- The recovery tasks for both rounds are in `PLAN-PROGRESS.md`.
