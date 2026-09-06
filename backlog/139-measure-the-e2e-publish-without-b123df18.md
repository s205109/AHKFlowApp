# 139 - Measure the E2E publish without Brotli compression

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project build)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The E2E publish step compresses every framework asset into `.br` and `.gz` siblings, and the E2E
SPA host may not need them. This item measures what `-p:CompressionEnabled=false` saves, and
whether the E2E stack still works without those files.

**Read the ceiling before you pick this up. It is about 2 to 3 s.** Two runs gave 7.52 s and
10.00 s against a 12.37 s median for the normal publish, so the saving is small and the two runs
are not evidence. Pick this up because it is cheap and carries no correctness risk, not because it
is fast money.

## User story

As a developer running the E2E slice, I want the publish to skip work the test host never reads,
so that a run starts testing sooner.

## Acceptance criteria

- [ ] Five warm runs of the publish command with `-p:CompressionEnabled=false`, and five without,
      are recorded in this item with every run, the median and the maximum.
- [ ] The item states whether the E2E SPA host reads the `.br` or `.gz` files. Name the code that
      decides, in `tests/AHKFlowApp.E2E.Tests`, and quote it.
- [ ] If the flag is adopted, `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes and reports the same
      test count as before the change.
- [ ] If the flag is not adopted, this item records the reason and closes.

## Out of scope

- Skipping the publish, or any up-to-date check on the publish target. Backlog 131 measured that
  and closed it.
- Any change to what the E2E tests assert.
- The `.br` and `.gz` files in a real deployment. This is about the E2E publish only, and a
  deployed app does want them.

## Notes / dependencies

- Filed out of backlog 131, which measured the publish step while answering a different question.
- The publish command is in `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`, in the target
  that runs before `VSTest`.
- The measurements behind the ceiling above are in
  `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`.
- Compression is a Blazor publish feature, so prove the property name against the official .NET
  documentation for the version in `Directory.Packages.props` before relying on it.
- Spec: none — the change is one build property and a measurement.
- Plan: none — not yet at Plan.
