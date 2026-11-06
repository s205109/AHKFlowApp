# PLAN-PROGRESS - backlog 206

Plan: docs/superpowers/plans/2026-11-06-recycle-bin-shows-hotstring-kinds-plan-206.md

- Ruling: this file is the executing-plans ledger, because workflow.md names PLAN-PROGRESS.md. No separate .superpowers/sdd ledger.
- Task 1: done at 69aeba58. Tests: ListDeletedQueryTests 8/8 pass, red was the expected CS1061 on Kind and the date fields. Deferrals: none.
- Task 2: done at c25f8707. Tests: RecycleBinPageTests 10/10 pass, red was the Macro row showing {{cursor}}; VersionHistoryFlowTests 4/4 pass, red was 0 Macro chips. Deferrals: none.
- Simplify: nothing to simplify. The diff reuses MacroReplacementDisplay and the grid summaries (Decision 4); the CSS copy is Decision 5 and names its source.
- Verify: artifacts are ListDeletedQueryTests 8/8, RecycleBinPageTests 10/10, VersionHistoryFlowTests 4/4 (the flow test proves the wire). Live drive after a Release rebuild and restart: the Raw row computes the monospace font and shows only its first line; screenshot .superpowers/206-recycle-bin-raw-row.png.
- Document: CHANGELOG.md Fixed entry and changelog.json regenerated (-Check current) at 46e6347b; all three acceptance boxes ticked; CONTEXT.md needs nothing, no new term.
