# 180 - No desktop test selects hotstring rows

## Metadata

- **Epic**: Hotstrings
- **Type**: Chore
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

No E2E test ticks a row checkbox on the hotstrings grid at desktop width. Row selection works
there today, but nothing would catch it if the select column collapsed again, the same way it
did on the hotkeys grid in backlog 167.

## User story

As an owner, I want hotstring row selection on desktop to stay working, so that bulk delete
does not break without anyone noticing.

## Acceptance criteria

- [x] An E2E flow test runs the hotstrings page at a desktop viewport, ticks two row checkboxes,
      and sees the bulk-delete button say "Delete 2 selected".
      Met by `HotstringsCrudFlowTests.BulkDelete_OnDesktopViewport_SelectsRowsWithTheirCheckboxes`.
- [x] The same test, or a second one, ticks the header select-all checkbox at desktop viewport
      and sees every row on the page selected.
      Met by `HotstringsCrudFlowTests.SelectAll_OnDesktopViewport_SelectsEveryRowOnThePage`.
- [x] The new tests never pass `Force` to a Playwright action, so a covered checkbox makes them
      fail.
      Proven on 2026-10-14. With the select column's width removed, both tests failed with a
      `TimeoutException` at their `CheckAsync`: `HotstringsCrudFlowTests.cs:88` for the row tick
      and `HotstringsCrudFlowTests.cs:124` for the select-all tick. The Trigger cell took the row
      click, and the next header cell took the select-all click. The progress file that recorded
      this is deleted at Ship. Read it with `git show deb57afd:PLAN-PROGRESS.md`.

## Out of scope

- Any change to `Pages/Hotstrings.razor`. Its select column already has an explicit width.
- The phone select mode. No E2E test covers it, but the bUnit tests in
  `HotstringMobileListTests` do: `SelectModeToggle_RevealsCheckboxes` and
  `BulkDelete_RaisesOnBulkDelete_WithSelectedIds`.
- Removing the unused 56-pixel rule from the grids' style sheets.

## Notes / dependencies

- Follow-up from backlog 167, grilling decision 5. That item fixed the hotkeys grid and added
  `HotkeysCrudFlowTests.BulkDelete_OnDesktopViewport_SelectsRowsWithTheirCheckboxes` and
  `SelectAll_OnDesktopViewport_SelectsEveryRowOnThePage`. Those two tests are the model for
  this item.
- Proof of the gap. The hotkeys bug survived because the only bulk-delete test ran at phone
  width, where the page shows a list with its own select mode. The hotstrings grid has the same
  shape: no desktop test touches its select column.
- The new tests belong in `HotstringsCrudFlowTests`, which runs in E2E group C.
- Spec: none — the hotkeys tests from backlog 167 are the pattern.
- Plan: `docs/superpowers/plans/2026-10-14-no-desktop-test-selects-hotstring-rows-plan-180.md`
