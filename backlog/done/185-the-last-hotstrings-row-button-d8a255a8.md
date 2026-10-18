# 185 - The last hotstrings row button is cut off

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

On the hotstrings grid, the last button in each row sticks out of the Actions column. At a
1280 px window, 8 px of it is cut off on the right. Its focus ring is cut off on that side too.

## User story

As an owner, I want every row button fully visible, so that I can see and use each one.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [x] At a 1280 px window, every button in a hotstrings row sits inside its cell, in view mode
      and in edit mode.
- [x] An E2E flow test asserts that the right edge of the last row button is not past the right
      edge of its cell, in both modes.

## Out of scope

- The hotkeys grid. Check it at pickup. If it has the same fault, file it as its own item.
- The focus ring itself. Backlog 168 owns it.

## Notes / dependencies

- Found while planning backlog 168, on 2026-10-16.
- Measured in Chromium at 1280×800 on `/hotstrings`, with the starter rows: the `delete` button's
  right edge is at 1248 px. Its cell and the table container both end at 1240 px. The container
  has `overflow: auto`, so it cuts off whatever sticks out.
- Likely cause, not yet proven: the Actions column is fixed at 160 px
  (`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:194`, "width:160px"). <!-- citation-check:ignore: the line before the fix; the column is now 184 px -->
  It holds three 48 px icon buttons in view mode (`edit`, `show-history`, `delete`) and three in
  edit mode (`commit-edit`, `cancel-edit`, `promote-edit`). That is 144 px of buttons before the
  cell padding. Confirm the cell padding at pickup before changing the width.
- Spec: none — a layout fault with a known place to look.
- Plan: `docs/superpowers/plans/2026-10-18-hotstrings-row-buttons-fit-their-cell-plan-185.md`
