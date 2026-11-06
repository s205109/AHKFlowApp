# PLAN-PROGRESS - backlog 206

Plan: docs/superpowers/plans/2026-11-06-recycle-bin-shows-hotstring-kinds-plan-206.md

- Ruling: this file is the executing-plans ledger, because workflow.md names PLAN-PROGRESS.md. No separate .superpowers/sdd ledger.
- Task 1: done at 69aeba58. Tests: ListDeletedQueryTests 8/8 pass, red was the expected CS1061 on Kind and the date fields. Deferrals: none.
- Task 2: done at c25f8707. Tests: RecycleBinPageTests 10/10 pass, red was the Macro row showing {{cursor}}; VersionHistoryFlowTests 4/4 pass, red was 0 Macro chips. Deferrals: none.
- Simplify: nothing to simplify. The diff reuses MacroReplacementDisplay and the grid summaries (Decision 4); the CSS copy is Decision 5 and names its source.
- Verify: artifacts are ListDeletedQueryTests 8/8, RecycleBinPageTests 10/10, VersionHistoryFlowTests 4/4 (the flow test proves the wire). Live drive after a Release rebuild and restart: the Raw row computes the monospace font and shows only its first line; screenshot .superpowers/206-recycle-bin-raw-row.png.
- Document: CHANGELOG.md Fixed entry and changelog.json regenerated (-Check current) at 46e6347b; all three acceptance boxes ticked; CONTEXT.md needs nothing, no new term.

## Failure edge to 4-execute (2026-11-06)

**Red evidence:**

```
Review round 1, Claude reviewer finding 1 (required), reproduced live at 869f37b3 (Release build, API and UI restarted, playwright-cli, viewport 1280x720).
Deleted Raw hotstring: ::rbsig::Best regards, Alex Example, Senior Engineer, Example Department, 123 Long Street Name, Some City, Some Country
.script-summary span: clientWidth 994, scrollWidth 994 (never clipped, no ellipsis)
table width 1391 inside a 960 px .mud-table-container (overflow-x: auto): the table scrolls sideways
Delete button right edge 1652 > paper right edge 1256: Restore and Delete are out of view
Suggested fix max-width: 40vw also fails at 1024 px with the drawer open: table 807 in a 704 px container
Finding 2 (optional), same run: a Text replacement line one\nline two renders as "line one line two" (white-space: normal)
```

**Recovery task:** Task 3: a long Raw first line stays inside the Recycle Bin table, shown as one line cut with an ellipsis (round 1, finding 1, required). Task 4: a multi-line Text replacement keeps its line breaks in the Recycle Bin, as in the grid (round 1, finding 2, optional, fixed in the same pass).

- Task 3: done at ccaff0e5. Tests: VersionHistoryFlowTests 4/4 pass, red was the long Raw line not cut short at 1024 px. Deferrals: none.
- Task 3: Ruling: a line-clamp rule replaces the copied grid rule (plan Decision 5) and the suggested 40vw. The copy needs table-layout: fixed, and 40vw failed live at 1024 px (table 807 px in a 704 px container). Cost if wrong: one CSS rule to swap.
- Task 4: done at b03626a9. Tests: RecycleBinPageTests 10/10 pass, red was no pre-wrap span on the Text row. Deferrals: none.
