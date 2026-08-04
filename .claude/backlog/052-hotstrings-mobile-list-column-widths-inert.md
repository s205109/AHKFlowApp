# 052 - Hotstrings mobile list column widths never apply

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI

## Summary

`Components/Hotstrings/HotstringMobileList.razor.css` sets `table-layout: fixed` on `.mobile-list`
(`:62`). Under fixed layout the browser sizes columns from the table's first row. That is the header
row at `HotstringMobileList.razor:33`.

The header cells are one `<th class="checkbox-column">` plus three unclassed `<th>` (`:38-40`). But
the per-column width rules sit on data-row classes, so they never apply:

- `.trigger-cell { width: 34% }` (`:35-38`)
- `.chevron-cell { width: 24px }` (`:51-55`)
- `.checkbox-cell { width: 36px }` (`:65-68`)

The three unclassed `<th>` split the remaining width equally instead. Only `.checkbox-column`
(`:19-21`) works, because it is the one width rule on a header cell.

This is the same defect that backlog 050 found on the known-shortcuts page.

## Acceptance criteria

- [ ] The trigger column and the chevron column get the widths the CSS asks for
- [ ] The fix puts the width rules on cells in the row that `table-layout: fixed` measures, or drops
      fixed layout, whichever reads better
- [ ] A screenshot at 390px wide shows the replacement column still truncating with an ellipsis
      rather than wrapping

## Notes / dependencies

- Found during backlog 051. See
  `docs/superpowers/specs/2026-08-04-hotstrings-mobile-branch-stale-design.md`
- Line numbers were read on `fix/wt-051-hotstrings-mobile-branch-stale` at `5d8583c2`
- The expanded row's `colspan="3"` (`:70`) was checked at the same time and is correct. The normal
  header has three cells (`:38-40`); the empty third `<th>` is the chevron column's header, not a
  spacer. Select mode adds a fourth column, but an expanded row cannot render while select mode is
  on — `expanded` is gated on `!_selectMode` (`:46`)
