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
