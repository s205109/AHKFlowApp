# 052 - Hotstrings mobile list column widths never apply

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Stage**: 9-ship

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

- [x] The trigger column and the chevron column get the widths the CSS asks for. Measured at 390px
      by `HotstringsMobileFlowTests.NarrowPhoneViewport_MobileList_GivesEachColumnTheWidthTheCssAsksFor`
- [x] The fix keeps `table-layout: fixed` and puts the width rules on the header row, which is the
      row that fixed layout measures. `HotstringMobileList.razor:42-44` now carries
      `trigger-cell`, `replacement-cell`, and `chevron-cell` on the three `<th>` elements. This is
      the same fix backlog 050 applied to `HotkeyMobileList.razor:42-44`, so the two mobile lists
      now match
- [x] The replacement column truncates with an ellipsis rather than wrapping at 390px. Covered by
      `HotstringsMobileFlowTests.NarrowPhoneViewport_LongReplacement_TruncatesWithAnEllipsisInsteadOfWrapping`,
      which asserts `white-space: nowrap`, `text-overflow: ellipsis`, and that the text really is
      wider than its column. A durable test was chosen over a screenshot, because a screenshot
      proves the behaviour once and this test proves it on every run

## Outcome

The chevron column was 114px wide before the fix and the trigger column was 114px — an even
three-way split of the 342px table. The column test fails with
`Chevron column was 114px wide, so the 24px rule did not apply` when the header classes are
removed, so it guards the defect.

The truncation test passes both before and after the fix. `.replacement-cell` on the data row
already carried `max-width: 0`, which forced the ellipsis on its own. That test does not guard this
bug. It pins acceptance criterion three, so the ellipsis is not lost by a later width change.

`.trigger-cell` keeps `white-space: nowrap`. Backlog 050 had to drop it on the hotkeys list, because
a long key combination overflowed 34% on the Linux CI runner but not on Windows. Hotstring triggers
are short, so the same change was not needed here. The column test will catch it if that stops
being true.

## Notes / dependencies

- Found during backlog 063 (filed as 051). See
  `docs/superpowers/specs/2026-08-04-hotstrings-mobile-branch-stale-design.md`
- Line numbers were read on `fix/wt-051-hotstrings-mobile-branch-stale` at `5d8583c2`
- The expanded row's `colspan="3"` (`:70`) was checked at the same time and is correct. The normal
  header has three cells (`:38-40`); the empty third `<th>` is the chevron column's header, not a
  spacer. Select mode adds a fourth column, but an expanded row cannot render while select mode is
  on — `expanded` is gated on `!_selectMode` (`:46`)
