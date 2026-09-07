# 131 - Publish the Blazor app incrementally for E2E runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project build)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Outcome: closing on the measurement, no code change

**Decided 2026-09-06. The item was measured, not built. The close itself waits for Review.**

The premise below is wrong. `RemoveDir` deletes `bin/<config>/<tfm>/publish`, and the IL linker
writes into `obj/`. The two folders do not overlap, so the delete does not make the linker run
again. Measured warm, Release, on `main` at `abac2f91`, running the target's own publish command:

| Scenario | Runs (s) | Median (s) |
|---|---|---|
| Publish after the tree changed | 95.39 | 95.39 |
| Publish, folder left in place | 10.29, 10.88, 11.36, 13.17 | 11.12 |
| Delete, then publish | 11.12, 11.54, 13.20, 13.88 | 12.37 |
| Build only, same project | 2.85, 2.89 | 2.87 |

So the delete costs about 1.3 s and the whole publish step costs about 11 s. The ceiling for this
item was about 11 s out of 321.65 s, which is 3.5 percent, not the 85 s the notes below imply.

Three things closed it.

1. The saving is about 11 s, and the observed E2E spread is 12.84 s. Backlog 128's two `-NoBuild`
   E2E runs were 293.38 s and 306.22 s. So the whole saving is smaller than the run-to-run
   variation already measured.
2. CI never benefits. CI builds, then runs one solution-wide `dotnet test --no-build`. A fresh
   runner has no publish folder and no stamp, so the target always runs, and in CI the publish is
   the cold 95 s one.
3. The saving needs the Blazor `bin` folder to be unchanged between two E2E runs. That happens
   when somebody iterates on an E2E test or chases a flake. E2E here is a gate run once per
   branch, so that loop does not apply.

Against that, the change would reverse commit `53ef9f99`, which removed an up-to-date check from
this target because it served a stale app.

The design that was measured and rejected is kept in the plan, so the next reader does not have to
work it out again.

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

None of these became true, because the change was not made. Each one carries its reason.

- [ ] An E2E run on an unchanged tree does not delete and republish the whole Blazor output.
      Not done: the item closed before any change to the publish target.
- [ ] `PublishedFramework_AfterAnyE2ERun_HoldsExactlyOneCopyOfEachBootAsset` passes. That test is
      the guard against the stale-asset problem the current `RemoveDir` avoids by force, so it is
      the thing that says an incremental publish is safe.
      Not applicable: nothing changed, so the guard had nothing new to prove. It still passes as
      it did before.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes, and reports 57 tests.
      Not run: no source file changed, so `AGENTS.md` verification exemption 1 applies.
- [ ] The saving is measured with `pwsh ./scripts/measure-test-modes.ps1 -Mode E2E -Runs 5`, and
      the median of five warm runs is written into this item beside the 321.65 s baseline, with
      all five runs and the maximum.
      Replaced: five warm E2E runs cost about 30 minutes and would have tried to separate an 11 s
      change from a 12.84 s spread. The publish step was timed directly instead, four runs per
      scenario, and those numbers are in the Outcome section. They answer the question the item
      was really asking.

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
- Two follow-ups came out of the measurement. Backlog 139 measures the publish without Brotli
  compression, which is a smaller lever. Backlog 140 chases the 34.38 s to 47.22 s that the
  arithmetic leaves unaccounted once 237 s of test host, about 11 s of publish and about 11 s of
  SQL container start are subtracted from backlog 128's two `-NoBuild` E2E runs of 293.38 s and
  306.22 s.
- A first attempt at closing this item set `Stage: 9-ship` and flipped the pull request to ready
  while no review existed. `workflow.md` puts Review before Ship, so the item came back to
  `4-execute` on 2026-09-06 and the recovery tasks are in `PLAN-PROGRESS.md`. The closing decision
  above did not change; only the stage did.
