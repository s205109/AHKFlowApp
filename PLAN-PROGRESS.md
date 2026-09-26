# Progress — backlog 160, one home for emitted runtime helpers

Plan: `docs/superpowers/plans/2026-09-26-one-home-for-emitted-runtime-helpers-plan-160.md`

Base revision: `362d7ce`.

One line per finished task, written after its deliverable commit.

## Baseline

Recorded in the plan on 2026-09-26, in this worktree at `3392cb2`:

```
git diff --quiet 362d7ce -- src tests && echo "src+tests unchanged since 362d7ce"
src+tests unchanged since 362d7ce
```

```
dotnet test tests/AHKFlowApp.Application.Tests/AHKFlowApp.Application.Tests.csproj --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests|FullyQualifiedName~GetHotstringPreviewQueryHandlerTests|FullyQualifiedName~GetHotkeyPreviewQueryTests|FullyQualifiedName~AhkHotstringRoundTripTests"
Passed!  - Failed:     0, Passed:   116, Skipped:     0, Total:   116, Duration: 275 ms - AHKFlowApp.Application.Tests.dll (net10.0)
```

Transient byte test, expected SHA-256
`D9ADCC9FF2EF1DC840EFE66D9745F8A9CBF45D649E4436D2E2BFED87FEF0DB98`.

## Tasks

- [x] Task 1 — `-`. Byte baseline in place. On unchanged code (`src+tests unchanged since
      362d7ce` printed again) the byte-baseline assertion passed:
      `Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 123 ms`.
      The session started a Docker daemon (`dockerd`) in the container, so Task 3 runs the Docker
      checks itself.
- [x] Task 2 — `de52b82`. `RuntimeHelpers.cs` and `DefinitionWrapping.cs` (both CRLF) own the
      helper, the helper decision, the Description lines, and the `#HotIf` wrapping. The
      Application build had 0 warnings, and the solution build had 0 warnings. Tests:
      `Passed!  - Failed:     0, Passed:   117, Skipped:     0, Total:   117, Duration: 248 ms`
      (116 baseline plus the byte test, whose byte-baseline assertion passed). The three
      acceptance searches printed nothing.

      **Not in the plan: stale citations.** The move broke six filing-time evidence citations in
      the backlog item, which `check-citation-freshness.ps1` failed. Each now carries
      `citation-check:ignore` with the reason, and the repository check passes again. The plan
      itself cites the base tree in 31 places, and those now fail the pre-push plan check. See
      the end of this file.

      **Not in the plan: the stage field.** The item still read `3-plan`. `867e5b3` stamps
      `4-execute` by hand, because `take-stage-transition.ps1` needs `gh`.
- [x] Task 3 — `315a615`. The 11-row parity theory and the one comment line in
      `ListHotstringsQuery.cs`. The byte test passed one last time
      (`Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 104 ms`),
      then it was deleted. The committed `tests/` diff holds the theory and the one comment at
      `GetHotkeyPreviewQueryTests.cs:101`, and the row count printed `11`. The Fast slice passed:
      Application 1749, CLI 185, UI.Blazor 960, Domain 44, TestUtilities 14, 0 failed.

      Docker checks, run by this session against the committed file. The session started
      `dockerd` in the container, so no checkpoint push was needed.

      - `main`'s copy of the class: `Passed!  - Failed:     0, Passed:    27, Skipped:     0, Total:    27`
      - Before the mutation: `Passed!  - Failed:     0, Passed:    38, Skipped:     0, Total:    38, Duration: 2 s`
      - Mutation (`>=` to `>`), theory alone: `Failed!  - Failed:     3, Passed:     8, Skipped:     0, Total:    11`.
        The three failing cases, as predicted:
        `kind: Text, delivery: Auto, asciiChars: 200, supplementaryChars: 0, trailingSpaces: 0`,
        `kind: Text, delivery: Auto, asciiChars: 199, supplementaryChars: 0, trailingSpaces: 1`,
        `kind: Text, delivery: Auto, asciiChars: 0, supplementaryChars: 100, trailingSpaces: 0`.
      - After `git checkout --` restored the file (`git status --short` printed nothing):
        `Passed!  - Failed:     0, Passed:    38, Skipped:     0, Total:    38, Duration: 2 s`

## Open: the plan's own citations

The plan cites the base tree `362d7ce` on purpose ("Line numbers in the tasks are those of the
base commit"). After Task 2, 31 of those citations fail tiers 1 and 2 of
`check-citation-freshness.ps1`, which the pre-push hook runs on this branch's plan. The plan is
not frozen yet: Stage 9 freezes it. This needs a human decision before the next push through
the hook.
