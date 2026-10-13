# 167 - Hotkey rows cannot be selected on desktop

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The select column on the hotkeys grid collapses to zero width at desktop size, so the next cell
covers the checkbox and no row can be selected. Bulk delete is therefore unreachable on desktop.
The hotstrings grid already carries the fix and a comment explaining it.

## User story

As an owner, I want to select hotkey rows and delete them together, so that I do not have to
delete nineteen rows one at a time.

## Acceptance criteria

- [ ] Clicking the select checkbox on a hotkey row at desktop width selects that row.
- [ ] With rows selected, the bulk-delete button appears and names the count.
- [ ] The select column on the hotkeys grid has an explicit width, as the hotstrings grid does.
- [ ] An E2E flow test selects hotkey rows and bulk-deletes them at desktop viewport, not only at
      phone viewport.

## Out of scope

- The mobile select mode, which already works.
- Row selection on the hotstrings grid, which already works.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F14, S2. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- Root cause, proven at runtime. The select column on `Pages/Hotkeys.razor` measures 0 pixels
  wide, so its 32-pixel checkbox overflows into the Description cell and that cell sits on top.
  A hit test at the checkbox's own centre point returns `TD.mud-table-cell` rather than the
  `INPUT`. On `Pages/Hotstrings.razor` the same column measures 56 pixels and the hit test
  returns the `INPUT`.
- **The repository already knows about this.** `Pages/Hotstrings.razor` carries a comment that
  describes the bug exactly and fixes it with `<SelectColumn T="HotstringEditModel"
  HeaderStyle="width:56px" />`. `Pages/Hotkeys.razor` has the bare `<SelectColumn
  T="HotkeyEditModel" />`. Both grids set `table-layout: fixed` in their own CSS, so the
  precondition applies equally to both.
- Why no test caught it. The only hotkey bulk-delete test,
  `HotkeysMobileFlowTests.BulkDelete_OnPhoneViewport_UsesSelectMode`, runs at phone viewport,
  where the mobile branch uses its own select mode rather than the grid's select column.
- Workaround for an owner today: delete hotkeys one row at a time, or use a narrow window. So
  this is S2 and not S1 — nothing is lost, but a shipped feature is unusable on desktop.
- Worth checking whether any other grid repeats the bare form.
- Spec: none — the fix and its reason are already written down in the hotstrings comment.
- Plan: `docs/superpowers/plans/2026-10-13-hotkey-rows-cannot-be-selected-plan-167.md`
