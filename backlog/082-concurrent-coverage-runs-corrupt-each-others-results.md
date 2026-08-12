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

- Every preserved TRX reported **zero** failing tests.
- Only **5 of 8** test assemblies produced a TRX at all. `API.Tests`,
  `Infrastructure.Tests` and `E2E.Tests` produced none, so their coverage was missing from
  the report.
- The 5 that did appear carry the **Fast-slice** counts — `Application.Tests` 1747,
  `CLI.Tests` 182 — not the Coverage counts of 2101 and 207 seen on a clean run. The results
  in the directory did not come from the run that was being measured.
- The failure was `FAIL AHKFlowApp.UI.Blazor` and
  `1 assembly(s) failed per-assembly coverage thresholds`, thrown at `:94`.
- The next Coverage run passed with every threshold met, line 94.6%, branch 82.6%, with
  nothing changed in the repository.

The consistent reading: a second run wiped and repopulated the shared results directory
while the first was using it, so the coverage report was assembled from partial and foreign
data. Incomplete data pushed one assembly under its threshold.

What is **not** established: which phase held the DLL locks that also appeared in the
output, and whether any test ever executed against an assembly it did not match. Both remain
open questions rather than findings.

This is **not** `backlog/blocked/068`, the known intermittent test failures. No test failed.

## How it is triggered

Two `run-coverage.ps1` invocations overlapping — a backgrounded gate plus a foreground run,
which is what happened here. The script removes `TestResults` and `CoverageReport` at
`:43-45` and rebuilds into the same project outputs, all at fixed paths, so a second run
destroys the first's evidence mid-flight.

## Acceptance criteria

- [ ] **A second concurrent run cannot start, or cannot collide.** Either serialise on a
      lock file and fail fast with a clear message, or give each run its own results and
      report directories. Serialising is the smaller change and matches how the script is
      actually used.
- [ ] The coverage gate refuses to report when the result set is **incomplete**: it knows
      which test assemblies it expected and fails naming any that produced no TRX, rather
      than computing a threshold from partial data.
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
