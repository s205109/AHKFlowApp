# 050 - Known-shortcut marker review follow-ups

## Metadata

- **Epic**: Known shortcuts
- **Type**: Chore
- **Interfaces**: UI

## Summary

The whole-branch review of the known-shortcut list marker (backlog 038, PR #249) raised five Minor
findings. None blocked the merge, so they were deferred rather than folded into the fix commit.
Two are real accessibility defects, one is an unchecked layout risk, and two are notes that may
need no work at all.

## Acceptance criteria

- [x] An expanded mobile row announces the notice once. The collapsed-row span now carries
      `aria-hidden="true"` while the row is expanded, so the icon leaves the accessibility tree and
      the panel text is the only named copy. Covered by
      `HotkeyMobileListTests.ExpandedRow_WithAKnownShortcut_HidesTheMarkerFromScreenReaders`
- [x] The desktop marker keeps `aria-label`, `role="img"`, and `tabindex="0"`. The finding's premise
      was wrong: MudTooltip 9.3.0 sets no `aria-describedby` and no `role="tooltip"`, so the tooltip
      text is never announced as a second name. `tabindex="0"` stays because the grid has no notice
      line, so the tooltip is the only keyboard path to the sentence. The extra tab stop is accepted,
      and it lands in the tab sequence for screen reader users too. Recorded in the comment at
      `Pages/Hotkeys.razor:109`
- [x] The mobile trigger cell was measured at 375px with a marked `Ctrl+Shift+Escape` row — the
      longest combination in the catalog. Measured `scrollWidth` 167 against `clientWidth` 167 (fits
      exactly after the fix). A CSS-only fix on `.trigger-cell` alone did not work, because
      `table-layout: fixed` sizes columns from the header row, not the data row. The fix widens
      `.trigger-cell` to 51%. It also adds matching `trigger-cell`, `replacement-cell`, and
      `chevron-cell` classes to the three header `<th>` cells in `HotkeyMobileList.razor`. The
      original plan did not call for the header-row classes.
      Guarded by
      `HotkeysMobileFlowTests.PhoneViewport_MarkedRowWithTheLongestCombo_KeepsTheTriggerCellInsideItsColumn`
- [x] A desktop edit or bulk delete now refreshes the mobile branch. `CommitEditAsync` and
      `BulkDeleteAsync` call `ReloadAllAsync()` instead of reloading the grid alone. Covered by
      `Page_CommitInlineEdit_RefreshesTheMobileBranch` and `Page_BulkDelete_CallsApiAndReloads`
- [x] The tooltip-per-row cost is accepted. One `MudPopover` per marked row costs a holder, a div,
      and a JS connection even while closed; only the text waits for the popover to open. Accepted
      on the upper bound: a page shows at most 100 rows, and only catalog matches are marked.
      Recorded in the comment at `Pages/Hotkeys.razor:109`

## Out of scope

- Any change to how a notice is resolved. `Helpers/KnownShortcutNotices.cs` is settled and covered
  by tests
- Any change to which rows carry a marker, or to the marker's icon, colour, or wording

## Notes / dependencies

- Source: whole-branch review of `feature/wt-038-known-shortcut-indicator` at `ce3585d2`, 2026-08-02.
  The two Important findings from the same review were fixed on that branch in `6e4f8451`
- Line numbers were recorded at `ce3585d2`. The fix commit added lines in `OnInitializedAsync`, so
  references below that point have shifted slightly
- The last two criteria may close as "no change needed". Record the reasoning rather than deleting
  the line
