# Progress — backlog 140, E2E harness overhead

Plan: `docs/superpowers/plans/2026-09-12-e2e-harness-overhead-plan-140.md`

One line per task: the task, the deliverable commit, the tests state, and any deferral. This file
was missing during Execute and was restored after the second review round, from the branch's own
commit log. Every SHA below is on this branch.

## Plan tasks

- [x] Task 1 — every timing record becomes an interval — `45161b28` — Fast slice green, recorder tests 3 of 3 — no deferral
- [x] Task 2 — gate records queue wait apart from gated work — `4326e466` — `HostStartGateTests` 5 of 5 — no deferral
- [x] Task 3 — stack fixture records its three remaining steps — `2233cc6b` — `StackIsolationTests` green; AGENTS.md exemption 2 — no deferral
- [x] Task 4 — interval union with deterministic coverage — `05e14817` — PowerShell slice 64 of 64 — no deferral
- [x] Task 5 — read intervals out of the TRX — `017ad749` — `TrxIntervals.Tests.ps1` green, `measure-tests.ps1` completed — no deferral
- [x] Task 6 — the breakdown report — `6193b918` — `HarnessOverheadReport.Tests.ps1` green — no deferral
- [x] Task 7 — one driver, per-run artifacts, build inside the run — `83dbc404` — `MeasureTestModes.Tests.ps1` all cases green — no deferral
- [x] Task 8 — measure and write the record — `2a23475b`, `34c5b74a`, `4c108709`, `a2b3ec4a` — boxes ticked, AcceptanceBoxes and citation checks green — rebalance iceboxed as backlog 155

## Review recovery tasks

Round one, three findings that needed code changes:

- [x] R1 — a failed timing write left the host gate locked — `e06c53c4` — `RunAsync_WhenRecordingTheWaitFails_StillReleasesTheGate` red then green — no deferral
- [x] R2 — the report could not isolate the four stack starts — `e06c53c4`, then `72a725ce` and `9eb12330` for the caller-aware session — recorder, gate and report caller tests green — no deferral
- [x] R3 — a second measurement session deleted the first — `6f34a528` — `Two measurements in one Mode keep both sessions` red then green — no deferral

Round two, no code change:

- [x] R4 — workflow records not reconciled: Stage stale, plan unticked, this file absent — `-` — plan ticked 49 of 49, this file restored, Stage set to 5-simplify — no deferral
- [x] R5 — parallel-startup explanation stated as fact — `5928a881` — targeted text check — no deferral

## Simplify

- [x] S1 — `/simplify` pass over the branch diff — `3eebb199` — 14 PowerShell suites green, `HostStartGateTests` 7 of 7, `TestTimingRecorderTests` 4 of 4, format clean — skipped findings listed below

Fixed: one shared backlog folder pattern replaces six copies; one fixture-timing reader replaces
two; the report uses the shared TRX lookup and a local command boundary; the gate tests share their
timing setup; the recorder scans assemblies once; `+=` array growth removed from the new readers.

Skipped: timing writes held inside the gate (changes what QueueWait measures); an `AsyncLocal`
parent in place of `caller` (redesign); `test-fast.ps1 -ResultsRoot` (outside the diff); the TRX
parsed twice and three `Measure-Object` passes (too small to matter); the derivable `finishedUtc`
field (changes the record format the report reads).

## Verify recovery

- [x] R6 — Gate step 3 red after S1: `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` failed 1 of 67, `CitationFreshness.Tests.ps1`: "backlog/done/130-fail-the-push-when-a-shipped-it-0c4f5d37.md:32 tier 2: (`scripts/worktree-git.common.ps1:1535`, ...) does not match". S1 added six lines above that function, which now sits at 1541. Citation moved to 1541 — commit below — PowerShell step re-run — no deferral <!-- citation-check:ignore quotes the stale citation from the failure output -->

## Stage state

- 4-execute: complete. Every planned task and every recovery task above is committed.
- 5-simplify: complete, see S1.
- 6-verify: owed. Earlier evidence predates Simplify. Stage is set here.
- 7-document: evidence exists but predates Simplify. Every acceptance box is ticked with its measurement.
- 8-review: two rounds received. Round one took the failure edge to Execute; round two needed no code change.

Simplify can change code, so Verify, Document and Review are owed again after it, as
`docs/development/workflow.md` says for a review that returns to Execute.
