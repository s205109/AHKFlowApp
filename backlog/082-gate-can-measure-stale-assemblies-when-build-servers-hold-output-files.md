# 082 - Gate can measure stale assemblies when build servers hold output files

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (test scripts)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

A leftover `dotnet` build server or test host keeps a lock on
`tests/*/bin/Release/net10.0/*.dll`. The rebuild then fails to **copy** the new assembly,
the run continues against the old one, and the gate reports on stale output.

Observed on 2026-08-12 during backlog 071. The dangerous part is not the red run — it is
that the same conditions can produce a **green** run over stale assemblies, and nothing says
so.

## Root cause, with evidence

`pwsh .\scripts\test-fast.ps1 -Mode Coverage` failed with:

```
System.AggregateException: One or more errors occurred.
(The process cannot access the file
 '...\tests\AHKFlowApp.UI.Blazor.Tests\bin\Release\net10.0\AHKFlowApp.Application.dll'
 because it is being used by another process.)
::error title=Coverage gate failed::1 assembly(s) failed per-assembly coverage thresholds.
```

- The TRX named **zero** failing tests. No test failed; an assembly was never replaced.
- 15 `dotnet` processes were alive, the oldest from 17:56 the previous day, plus 13
  `msedgewebview2` processes left over from earlier E2E runs.
- `dotnet build-server shutdown` reduced that to 1 process.
- The next Coverage run passed with every per-assembly threshold met, line 94.6%,
  branch 82.6%. Nothing in the repository changed between the two runs.

This is **not** `backlog/blocked/068`, the known intermittent test failures. That item is
about tests that fail; here no test ran against the code it was supposed to.

## How it is triggered

Two test runs overlapping in one session is enough — a backgrounded gate plus a foreground
run, which is exactly what happened. MSBuild node reuse and the VB/C# compiler server both
outlive the command that started them, so the locks persist between runs.

## Acceptance criteria

- [ ] A copy failure during the gate's build fails the run loudly, naming the file and the
      holding process. It must never continue to the test phase against stale output.
- [ ] `scripts/test-fast.ps1` releases stale locks before building, or detects them and
      stops. `dotnet build-server shutdown` is the cheap version; `-nodeReuse:false` on the
      build is the narrower one.
- [ ] A green run proves the assemblies under test were produced by that run. Compare the
      build output timestamps against the run start, or equivalent.
- [ ] The failure mode is documented in `docs/development/testing-workflow.md`, because a
      contributor seeing a coverage-threshold error will otherwise hunt for a coverage
      regression that does not exist.
- [ ] A test covers the detection path, using a deliberately locked file.

## Out of scope

- The intermittent test failures in `backlog/blocked/068`. Different cause, different item.
- Killing the leftover `msedgewebview2` processes from E2E runs. Related symptom of the same
  session, but a separate cleanup concern.

## Notes / dependencies

- Found while verifying the backlog-071 gate, after review round 5 asked for the earlier
  unexplained coverage failure to be nailed down rather than assumed to be a flake.
- Evidence preserved at the time of the failure: console log and TRX files.
- The misleading part is the error text. `1 assembly(s) failed per-assembly coverage
  thresholds` points at coverage, while the real cause is a file lock several hundred lines
  earlier in the output.
