Task 1; a9cf9907; red before fix: TimeoutException in both new tests, the Description td intercepts the row checkbox click and the next header th intercepts select-all; green after: 13 of 13 hotkey flow tests; deferrals: none

## Failure edge to 4-execute (2026-10-14)

**Red evidence:**

```
PR 433 review thread PRRT_kwDOR18K486sJbpd: SelectAll_OnDesktopViewport_SelectsEveryRowOnThePage (HotkeysCrudFlowTests.cs:296-297) asserts only the toolbar count, never the row checkboxes.
```

**Recovery task:** R1: after select-all, assert both seeded rows' select checkboxes are checked.

R1; 6a9af057; select-all test now asserts both rows unticked before and ticked after; test-only, no red run (no app behavior change); green: 13 of 13 hotkey flow tests; deferrals: none
