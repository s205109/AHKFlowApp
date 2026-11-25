# Plan progress: backlog 219

Plan: `docs/superpowers/plans/2026-11-24-run-the-fast-mode-test-assemblies-side-by-side-plan-219.md` (frozen in plans commit `b1b4bc9`)

- Task 1 (a Fast test host crash is a run failure): done at ddfc810f. Tests: `MeasureEvidence.Tests.ps1` passes alone, 16 cases; the new case failed first for the stated reason. Deferrals: none.
- Task 2 (Fast Mode passes its Slice count to VSTest): done at 3cbe2b97. Tests: `TestFastDotnetProgress.Tests.ps1` 17 cases, `CoverageRunnerProgress.Tests.ps1` 29, `SliceRunner.Tests.ps1` 32, all pass alone; the four new or changed cases failed first. Real Fast Mode: pwsh 7 at Budget ran 3 at once, Windows PowerShell 5.1 with no count ran 1; both wrote one `slices.json` row. Deferrals: none.
- Task 3 (measure-test-modes times Fast settings): done at c542524d. Tests: `MeasureTestModes.Tests.ps1` 46 cases and `MeasureEvidence.Tests.ps1` 16 cases pass alone; the new case failed first on the `-Setting` refusal, and `Two measurements in one Mode keep both sessions` passed throughout (D10). Ruling: the doc says the Fast `slices.json` holds one row for the whole call, not one row per assembly, to match D4. Deferrals: none.
- Task 4 (time the Fast Mode): done at f5411ee7. Session `session-20261125-045217` at 7ce48ea5 finished all runs, on mains power by the event log check. Medians: 1 21.50 s, 2 17.95 s, Budget 16.00 s. Neither 2 nor Budget saves time by D7, so no candidate and no D12 figures. Tests: no suite; the power check printed `Done:`. Deferrals: none.
- Task 5 (Soak the candidate): done at 86d3ce27. No setting is a candidate, so no Soak ran; the record says so with the reason for each setting. Tests: none, docs only. Deferrals: none.
