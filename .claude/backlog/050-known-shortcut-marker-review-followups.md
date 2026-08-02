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

- [ ] An expanded mobile row announces the notice once, not twice — the collapsed-row
      `<span role="img" aria-label="@notice">` stays in the DOM when the row expands, and the panel
      then repeats the same sentence as text
      (`Components/Hotkeys/HotkeyMobileList.razor:68` and `:93`). Likely fix: `aria-hidden="true"`
      on the span while `expanded` is true
- [ ] The desktop marker stops repeating its own accessible name — `aria-label` and
      `MudTooltip.Text` carry the same string, so a keyboard user hears the sentence as the
      element's name and again as the tooltip (`Pages/Hotkeys.razor:117`). Decide whether
      `tabindex="0"` on a non-interactive `role="img"` element is wanted, and record the decision
      either way
- [ ] The mobile trigger cell is checked at about 400px wide with a marker present, and any
      squeeze on the description is fixed — `.trigger-cell` is `width: 30%; white-space: nowrap`
      (`Components/Hotkeys/HotkeyMobileList.razor.css:33`), so the added icon widens the column.
      Nothing has looked at this yet; the marker went to bUnit only
- [ ] A desktop edit or bulk delete refreshes the mobile branch too, or the gap is recorded as
      accepted — `CommitEditAsync` and the desktop `BulkDeleteAsync` call `_grid.ReloadServerData()`
      rather than `ReloadAllAsync()` (`Pages/Hotkeys.razor:534`), so `_mobileNotices` joins the
      pre-existing `_mobileItems` staleness. Only observable if the viewport crosses 959.95px
      without a reload
- [ ] The tooltip-per-row cost is measured or accepted — one `MudTooltip` popover is registered per
      marked desktop row (`Pages/Hotkeys.razor:113-121`), and `RowsPerPage` comes from user
      preferences, so a large page can register many on WebAssembly

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
