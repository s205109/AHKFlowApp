# 082 - Concurrent coverage runs corrupt each other's results

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Bug
- **Interfaces**: none (test scripts)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Two overlapping `run-coverage.ps1` invocations corrupt each other's results. The script
deletes and rewrites `TestResults` and `CoverageReport` at fixed paths, and both runs fight
over the same build outputs. The visible result is a coverage-threshold failure that has
nothing to do with coverage.

Observed on 2026-08-12 during backlog 071.

## Correction to the first version of this item

This item first claimed that a blocked file copy lets the run continue and measure **stale**
assemblies, and that the same conditions could produce a false **green**. Review round 6
showed that is not established, and the evidence does not support it:

- `scripts/run-coverage.ps1:49-53` already builds with `--disable-build-servers` and
  `-p:UseSharedCompilation=false`, and **throws on a nonzero build exit**. A failed build
  does not reach the test phase.
- The preserved run never reported a build failure. It threw
  `Coverage thresholds not met` at `:94`.

The false-green claim is withdrawn. What follows is what the evidence actually shows.

## What the evidence shows

`pwsh .\scripts\test-fast.ps1 -Mode Coverage` failed with:

```
System.AggregateException: One or more errors occurred.
(The process cannot access the file
 '...\tests\AHKFlowApp.UI.Blazor.Tests\bin\Release\net10.0\AHKFlowApp.Application.dll'
 because it is being used by another process.)
::error title=Coverage gate failed::1 assembly(s) failed per-assembly coverage thresholds.
```

- The failure was `FAIL AHKFlowApp.UI.Blazor` and
  `1 assembly(s) failed per-assembly coverage thresholds`, thrown at `run-coverage.ps1:94`.
- The output carried `The process cannot access the file …` for
  `AHKFlowApp.Application.dll` and `ahkflow.dll`.
- 15 `dotnet` processes were alive, the oldest from the previous day.
  `dotnet build-server shutdown` left 1, and the next Coverage run passed with every
  threshold met, line 94.6%, branch 82.6%, nothing changed in the repository.

**The competing run was Fast, not another Coverage run.** `run-coverage.ps1:63-69` requests
no TRX logger at all; `scripts/test-fast.ps1:118` does. So the TRX files found in
`TestResults` after the failure were produced by a **Fast** run, and their Fast-slice counts
say the same thing. An earlier version of this item reasoned from those files as though
Coverage had produced them, and concluded that Coverage had written partial results. That
reasoning was wrong, and the conclusion with it.

What is established: a Fast run and a Coverage run overlapped; both build the same outputs
and both write under `TestResults`; the Coverage run failed a threshold; a later run alone
passed unchanged.

What is **not** established: which process held the DLL locks, and whether any test executed
against an assembly the run did not produce. Round 7 pointed out both are answerable rather
than unknowable — see the open questions below.

This is **not** `backlog/blocked/068`, the known intermittent test failures. No test failed.

## How it is triggered

Two `run-coverage.ps1` invocations overlapping — a backgrounded gate plus a foreground run,
which is what happened here. The script removes `TestResults` and `CoverageReport` at
`:43-45` and rebuilds into the same project outputs, all at fixed paths, so a second run
destroys the first's evidence mid-flight.

## Acceptance criteria

- [ ] **A second concurrent run cannot start, or cannot collide — across scripts, not just
      within one.** The lock must be shared by `run-coverage.ps1` and `test-fast.ps1`, since
      the observed collision was between them. A lock held only by `run-coverage.ps1` would
      not have prevented it.
- [ ] The coverage gate refuses to report when its input is **incomplete**, measured in
      **coverage artifacts** — the per-assembly Cobertura XML it actually consumes at
      `run-coverage.ps1:79-82` — not in TRX files, which Coverage never produces.
- [ ] The threshold error stops claiming coverage when the cause is missing input. The
      current text sends a reader hunting for a coverage regression that does not exist.
- [ ] Timestamps are **not** used to prove freshness. With concurrent runs a file newer than
      this run's start may have been written by the other one. Identity — expected assembly
      set, or a per-run output path — is what the check needs.
- [ ] A test covers the incomplete-result-set path by removing one expected TRX.
- [ ] The failure mode is documented in `docs/development/testing-workflow.md`.

### Open questions, not yet findings

- Which phase held the `AHKFlowApp.Application.dll` and `ahkflow.dll` locks seen in the
  output. `--disable-build-servers` is already set for build and test, so the holder was
  something else — plausibly the other run's test hosts, unverified.
- Whether a test can ever execute against an assembly the run did not produce. If it can,
  that is a separate and more serious item; if it cannot, the incomplete-data path above is
  the whole defect. Answer this before designing the fix.

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
