# 131 - Publish the Blazor app incrementally for E2E runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project build)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

`AHKFlowApp.E2E.Tests` deletes its Blazor publish folder and publishes again before every run,
which makes the IL linker run every time. This item asks for an incremental publish, so a run
that changed nothing does not pay for a full relink.

## User story

As a developer running the E2E slice, I want the Blazor publish step to skip work it has already
done, so that a repeat run starts testing sooner.

## Acceptance criteria

- [ ] An E2E run on an unchanged tree does not delete and republish the whole Blazor output.
- [ ] `PublishedFramework_AfterAnyE2ERun_HoldsExactlyOneCopyOfEachBootAsset` passes. That test is
      the guard against the stale-asset problem the current `RemoveDir` avoids by force, so it is
      the thing that says an incremental publish is safe.
- [ ] `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes, and reports 57 tests.
- [ ] The saving is measured with `pwsh ./scripts/measure-test-modes.ps1 -Mode E2E -Runs 5`, and
      the median of five warm runs is written into this item beside the 321.65 s baseline, with
      all five runs and the maximum.

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
  `docs/superpowers/specs/2026-09-03-net-test-speed-and-reliability-design-128.md`, under D7.
- Plan: docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md
- The premise above is wrong, and the plan carries the measurement. `RemoveDir` deletes
  `bin/<config>/<tfm>/publish`, while the IL linker writes into `obj/`, so the delete does not
  make the linker run again. Measured warm on 2026-09-06, Release, on `main` at `abac2f91`:
  delete then publish has a median of 12.37 s over four runs, publish with the folder left in
  place has a median of 11.12 s, and a first publish after the tree changed costs 95.39 s. So the
  delete costs about 1.3 s, and the whole publish step costs about 11 s. The ceiling for this
  item is therefore about 11 s out of 321.65 s, which is 3.5 percent, not the 85 s the notes
  above imply.
