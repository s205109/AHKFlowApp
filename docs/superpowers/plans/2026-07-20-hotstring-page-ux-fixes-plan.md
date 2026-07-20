# Hotstrings page UX fixes

## Context

The user tested the Hotstrings page and found several UX regressions/rough edges, captured
in 7 annotated screenshots plus one written bug report. The core functional bug: rows now
have **two different edit affordances** (a pencil "start inline edit" icon and an "EditNote"
icon that opens a popup), but the pencil only appears for plain Text-kind hotstrings with no
window context (`HotstringEditModel.IsInlineEditable`). For every other kind (Raw, Date &
time, Macro, or anything with a context match), the popup is the *only* edit entry point —
and the popup that opens for it (`OpenEditDetailsDialogAsync`, `MaxWidth.Medium`,
non-fullscreen) makes the profile selector easy to miss, unlike the inline row editor which
shows it immediately. The user wants exactly one edit button per row, whose *behavior*
branches by type (inline for Text, popup for everything else), with the popup giving full
parity (including profile changes).

The screenshots also flag: an undiscoverable glyph legend (`*`/`?`/`C`/`O`) next to the Type
chip, a genuine CSS bug where the Actions column clips icons behind a fake "..." at higher
browser zoom, weak color differentiation between Type/Categories chips, and a request for
stronger selected-row highlighting.

Code exploration confirmed: the profile/category data actually round-trips correctly
(`HotstringEditModel.Clone/ToCreateDto/ToUpdateDto` all carry `ProfileIds`/
`AppliesToAllProfiles`), and `HotstringEditDialog.razor` *does* already render a profile
selector (lines 253–261) — so the "can't change profile in the popup" complaint is a
visibility/layout issue in the compact Medium-width dialog, not a data bug. Standardizing
on the fullscreen dialog (already used on mobile and by the inline-edit "promote" escape
hatch) resolves it directly.

User decisions from clarifying questions: skip formal `impeccable teach` (treat this as
scoped bug-fix/consistency work, not a new design direction); standardize the popup on the
fullscreen dialog; give each hotstring Kind a distinct semantic color; add a legend/help
icon to the Type column header rather than replacing the glyphs with icons.

This document is the pre-Ultraplan draft, committed for reference before the plan is
refined remotely via Ultraplan.

## Approach

### 1. Single edit button per row

In `Pages/Hotstrings.razor`, `RenderActions` (~996–1021): collapse `edit-details` +
`start-edit` into one `Edit` icon button per row:
- `item.IsInlineEditable` → `OnClick="() => StartEditAsync(item)"` (current pencil behavior).
- otherwise → `OnClick="() => OpenEditDialogAsync(item)"` (fullscreen dialog — see #2).

Keep `show-history` and `delete` as-is. Leave the in-progress inline-edit toolbar
(`commit-edit`/`cancel-edit`/`promote-edit`) untouched — the `Tune` "promote to full dialog"
button is a different mechanism (escalating an in-flight inline edit), not a second entry
point into editing, and isn't part of the complaint.

### 2. Standardize the popup on the fullscreen dialog

Remove `OpenEditDetailsDialogAsync` (the `MaxWidth.Medium`, non-fullscreen variant) and route
the new single Edit button (for non-inline-editable rows) through the existing
`OpenEditDialogAsync` (`FullScreen = true`), the same method mobile's `OnEdit` and
`PromoteInlineRowAsync` already use. This gives the profile selector, category selector, and
kind-specific fields (Raw templates, Macro toolbar, Date & time format picker) full-height
room, consistent with every other edit-dialog entry point in the app.

### 3. Actions column CSS: stop the fake "..." clipping

`Pages/Hotstrings.razor.css:39-43` applies `overflow: hidden; text-overflow: ellipsis` to
*every* grid cell, including Actions. At higher browser zoom the fixed `132px` Actions column
(`:nth-child(8)`, line 92-95) can't fit its icon buttons, so the browser renders a literal
truncation ellipsis where the last icon should be — this is what screenshots read as a
non-functional "..." menu. Fix: exclude the Actions column from the ellipsis rule (add an
`:nth-child(8)` override with `overflow: visible`), and size its width for exactly 3 icons
(Edit, History, Delete) now that #1 removed the 4th. Verify at 150%/200% browser zoom.

### 4. Type-badge color coding

`RenderTypeChip` (Hotstrings.razor ~943-949) and the kind toggle in
`HotstringEditDialog.razor` (~22-34) only color Raw (`Color.Warning`); Text/DateTime/Macro
are all `Color.Default`. Give each Kind a distinct, stable `MudBlazor` `Color`, consistent in
both places — proposed: `Text = Default`, `DateTime = Info`, `Macro = Success`,
`Raw = Warning` (avoids reusing `Primary`/`Secondary`/`Tertiary`, which the page's action
buttons already use, to keep badge color meaning separate from button color meaning). Text's
existing delivery-based color (Info if clipboard) is a different, orthogonal signal — leave
it as-is.

### 5. Differentiate Categories chips from Type chips

Today, Type ("Hotstring"), Profile-specific, and Category chips can all render as the same
plain grey filled `MudChip`, so the columns blur together — this is likely what the
"color coding" screenshot arrows are really pointing at, alongside Type. Add an optional
`Variant` parameter to `Components/Common/EntityChips.razor` (default `Variant.Filled`,
unchanged for existing callers), and pass `Variant.Outlined` where Categories render in
`Hotstrings.razor` (`RenderCategories`, ~928). Since `EntityChips` is shared, this
automatically keeps Category chips visually distinct everywhere it's used, not just here.

### 6. Selected-row highlighting

Add explicit CSS in `Hotstrings.razor.css` for `MudDataGrid`'s selected-row state (verify the
exact class MudBlazor 9.x emits, e.g. via the MudBlazor MCP or a quick render inspection) —
a subtle background tint using `--mud-palette-primary` at low opacity, working in both light
and dark theme (the page has a theme toggle).

### 7. Type column glyph legend

Add a small `HelpOutline`/`InfoOutlined` `MudIcon` next to the "Type" column header in
`Pages/Hotstrings.razor` (~153), wrapped in a `MudTooltip` with static text listing what each
glyph means (`* = expands immediately`, `? = triggers inside words`, `C = case sensitive`).
Leave the existing per-row hover tooltip (`OptionsTooltip`, row-specific) as-is — the header
icon is a persistent, discoverable legend; the per-row tooltip stays the row-specific detail.

### Test/verification blast radius

Removing `edit-details`/`start-edit` as separate classes and `OpenEditDetailsDialogAsync`
touches selectors used by:
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs` (bUnit)
- `tests/AHKFlowApp.E2E.Tests/HotstringsCrudFlowTests.cs`, `RawHotstringFlowTests.cs`,
  `VersionHistoryFlowTests.cs` (Playwright)

These need their edit-button selectors/flows updated to match the single-button behavior.

## Verification

- `dotnet build` + `dotnet test` (bUnit + E2E) after updating the affected test files above.
- Playwright (`playwright-cli` skill), against the local no-auth dev stack:
  - Text-kind row: click the single Edit icon → inline row editor opens (not a dialog).
  - Raw/Date & time/Macro row, and a context-matched row: click the single Edit icon → full
    screen dialog opens with the profile selector visible without scrolling; change the
    profile assignment and save; confirm it persists (grid reflects the new profile chips).
  - Zoom browser to 150% and 200%: Actions column shows all 3 icons, no clipped "...".
  - Type column: each Kind shows a distinct chip color; hover header info icon shows glyph
    legend.
  - Categories column chips visually distinct (outlined) from Type/Profile chips.
  - Select a few rows via the checkbox column: selected rows visibly highlighted, in both
    light and dark theme.

## Unresolved questions

1. Macro color = Success (green) ok, or prefer different hue (Secondary/Tertiary despite reuse w/ buttons)?
2. Legend icon: static tooltip on hover, or click-to-open popover (more discoverable, more code)?
3. Selected-row highlight: also wanted on hover, or selection-only?
4. OK to touch shared `EntityChips` (affects Hotkeys/Categories pages too via outlined-category variant), or scope strictly to Hotstrings usage only?
