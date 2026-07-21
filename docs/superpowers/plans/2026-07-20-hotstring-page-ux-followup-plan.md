# Hotstrings page UX fixes — follow-up

## Context

The first pass (`2026-07-20-hotstring-page-ux-fixes-plan.md`, Sonnet) under-delivered. Live testing
shows Type chips and Category chips still render grey, and the inline category editor still truncates
to "C...". The user also wants at least two seed examples per hotstring kind and a sweep of UX gaps
the first plan missed.

This plan was stress-tested in a grilling session before implementation; four assumptions in the
first draft were wrong and are corrected below.

### Root causes (verified in code)

- **Category chips grey — genuine gap.** `Components/Common/EntityChips.razor:11` renders each per-id
  chip with **no `Color`**, so MudBlazor falls back to `Color.Default` = grey. The first plan added
  only `Variant.Outlined` (a shape), never a color.
- **Type chips grey — by design + all-Text data.** `KindColor` (`Pages/Hotstrings.razor:967-973`)
  colors DateTime/Macro/Raw, but `RenderTypeChip` (959-965) gives **Text** rows a grey *delivery* chip
  ("Hotstring"), and every seeded row is Text-kind — so the whole visible column is grey. A column
  titled "Type" never shows "Text". Possibly compounded by a stale PWA service-worker cache.
- **Dropdown "C..." truncation — pre-existing, not from `17ef225`.** Categories is pinned `width:10%`
  (`Hotstrings.razor.css:87-90`) under `table-layout:fixed`, and a blanket rule clips every cell
  (`overflow:hidden; text-overflow:ellipsis; white-space:nowrap`, lines 39-47). Edit mode must host a
  full `MudSelect` (Clearable X + arrow) in ~100px.
- **Seed gap.** `SeedHotstringsCommand.cs:32-43` has 10 Text + 2 DateTime, **0 Macro, 0 Raw**, and every
  row has `Description: null`. The array is duplicated verbatim in `ListHotstringsQuery.cs:78-89`.

### Corrections from the grilling session

1. **No per-category rainbow.** Giving each category its own hue would fight the Type channel and read
   as decorative. Categories get one accent.
2. **The brand triad constrains every hue.** `MainLayout.razor:63-72` sets Primary `#6AA84F` (green),
   Secondary `#3B8FC2` (blue), Tertiary `#8C3A3A` (brick) — the Add/Reload/Import buttons. The first
   plan claimed it avoided these, then chose Info (blue) and Success (green), colliding with two of
   them. Type hues must sit off green/blue/brick.
3. **App Launcher and Window Management are hotkey categories.** `SeedHotkeysCommand.cs:30-41` already
   fills them with 6 + 4 hotkeys. They are hotstring-empty *by design* — pressing Ctrl+Alt+N is the AHK
   idiom, not typing `/np`. The "fill empty categories" goal is void and is dropped. Every category
   hotstrings actually use is already populated.
4. **Categories is cramped because the width budget is misallocated**, not merely because of the clip
   rule: Description (14%) is empty on every row and Profiles (10%) shows an identical "Any" chip —
   24% of the grid rendering nothing useful, while Categories gets 10%.

## Color system

Three separate channels, no collisions:

| Channel | Treatment | Colors |
|---|---|---|
| Action buttons | saturated filled | brand green / blue / brick (unchanged) |
| **Type** (kind) | **soft hue tint** | violet ~300, teal ~200, rose ~350, amber ~70 |
| **Categories** | **outlined, one accent** | brand green via `Color.Primary` |

Type chips are tinted rather than saturated so data doesn't compete with the three saturated toolbar
buttons. Theme is handled without a dark-mode selector, reusing the `color-mix` pattern the first plan
already established for `.selected-row`:

```css
background: color-mix(in oklch, var(--mud-palette-surface) 85%, <hue>);
color:      color-mix(in oklch, var(--mud-palette-text-primary) 40%, <hue>);
```

## Approach

### 1. Type column: kind label, tinted, delivery as icon

`RenderTypeChip` (`Pages/Hotstrings.razor:959-965`) currently branches Text→delivery chip, else→kind
chip. Replace with **always a kind chip** via the existing `KindLabel` (947-954), tinted per kind, plus
a small clipboard icon when `DeliveryDisplay.IsClipboard(item.EffectiveDelivery)`.

| Kind | Hue | Note |
|---|---|---|
| Text | violet ~300 | replaces the grey delivery chip |
| DateTime | teal ~200 | off Secondary blue |
| Macro | rose ~350 | off Primary green |
| Raw | amber ~70 | keep the existing `Warning` icon + `ScriptWarningText` aria-label |

Applied as a per-kind class (`kind-chip--text` etc.) in `Hotstrings.razor.css` using the `color-mix`
formula above. Delivery is shown only for the exception (clipboard, which overwrites the user's
clipboard); default keystroke rows show no mark. Mention delivery in the per-row Type tooltip and the
header legend so it stays discoverable. Keep the existing cell composition (chip + `.option-glyphs` +
context icon, 168-179) and watch the 130px width — verify no overflow at 150%/200% zoom.

### 2. Categories: one brand-green accent

Minimal change — no custom CSS, no palette helper. Add an optional `Color` to the shared component
(`Components/Common/EntityChips.razor`) and let MudBlazor track the theme:

```razor
[Parameter] public Color? Color { get; set; }
...
<MudChip T="string" Size="Size.Small" Variant="Variant" Color="@(Color ?? MudBlazor.Color.Default)">@NameFor(id)</MudChip>
```

Pass `Color="Color.Primary"` from the two category call sites — `RenderCategories`
(`Pages/Hotstrings.razor:944-945`) and `HotstringMobileList.razor:108`. Profiles and every other caller
pass nothing and are unchanged. Outlined + Primary gives a green border/text chip, structurally
distinct from the tinted Type fills. Verify legibility in dark theme.

### 3. Inline category editor: fix the "C..." clip

Three changes:
- **Un-clip editing rows.** `::deep .hotstrings-grid .edit-row .mud-table-cell,
  ::deep .hotstrings-grid .draft-row .mud-table-cell { overflow: visible; white-space: normal; }` —
  those classes are already attached by `GetRowClass` (427-428).
- **Rebalance the width budget** (`Hotstrings.razor.css`), same 70% total:

  | Column | Now | New |
  |---|---|---|
  | Description (`nth-child(4)`) | 14% | 13% |
  | Profiles (`nth-child(5)`) | 10% | **7%** |
  | Categories (`nth-child(7)`) | 10% | **14%** |

- **Compact selection text.** Set `MultiSelectionTextFunc` on `EntityMultiSelect`'s `MudSelect`:
  none → placeholder, exactly one → the category name, more than one → "N selected". Structurally
  cannot truncate. Add the parameter to `EntityMultiSelect` so other callers are unaffected.

### 4. Seed: kind coverage, descriptions, de-duplication

Add four samples (the tuple needs no new fields — Kind + Replacement carry Macro/Raw):

| Trigger | Replacement | Kind | Category |
|---|---|---|---|
| `htag` | `<b>{{cursor}}</b>` | Macro | Code |
| `alink` | `<a href="{{cursor}}"></a>` | Macro | Code |
| *(tbd)* | hand-authored verbatim definition | Raw | Code / Symbols |
| *(tbd)* | hand-authored verbatim definition | Raw | Code / Symbols |

Macro replacements use the documented token vocabulary (`{{cursor}}` with text but no keys after — valid
per `ahk-v2-syntax.md`). Raw examples must showcase what Raw is *for* — a hand-authored definition the
structured kinds can't express — and land in Code/Symbols, **not** App Launcher/Window Management.
Finalize the exact Raw text at build; keep it single-line where possible (the brace-balance check is
naive) and confirm it survives `RawHotstringDefinitionParser` and emits valid AHK v2.

Also:
- **Add a `Description` to every seed row** (existing 12 + new 4). A blank Description column on every
  row looks unfinished and wastes its 13%.
- **De-duplicate.** Extract the sample array into one shared static consumed by both
  `SeedHotstringsCommand` and `ListHotstringsQuery`, removing the "update both files" hazard.

### 5. Grid loading indicator

`_loading` is set around every load (`LoadServerData` 335/354, `LoadMobileAsync` 637/649) but bound to
nothing visible. Bind `Loading="_loading"` on the desktop `MudDataGrid` (70-77); add a
`MudProgressLinear` on the mobile branch gated on `_loading`.

### 6. Filtered-empty state

`NoRecordsContent` (197) and the mobile empty block both say "No hotstrings yet." regardless of filters.
Add a computed `_hasActiveFilters` (search non-empty OR `_selectedKind` set OR `_selectedCategoryIds`
non-empty) and branch: filtered → "No hotstrings match these filters." plus a **Clear filters** action;
otherwise keep "No hotstrings yet." Apply to desktop and mobile.

### 7. Glyph legend + selection highlight

- Header legend tooltip (161) lists only `* ? C`. Add `O` (omit ending char) and the window-context
  icon, matching `OptionGlyphs` (978-990) and `OptionsTooltip` (996-1013). Mention clipboard delivery.
- `.selected-row` already shipped; verify it's actually visible at 12% tint in both themes, bump if not.

## Constraints

- Per `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`: verify MudBlazor parameters against the MudMCP
  server (`mcp__mudblazor__*`, pinned 9.3.0) before changing markup — specifically
  `MultiSelectionTextFunc`, `MudDataGrid.Loading`, and `MudChip` `Class`/`Variant`/`Color`.
- Reuse `Components/Common/` shared components; don't hand-roll `MudSelect`/`MudChip` blocks.
- `HotstringMobileList.razor:169-176` deliberately shows raw replacement text for Macro in *collapsed*
  rows (token chips live in the expanded detail). This is a documented density decision — do not
  "fix" it. But Macro rows have never existed before, so check how `<b>{{cursor}}</b>` reads once
  seeded and report back rather than changing it unilaterally.

## Test blast radius

- **bUnit** (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`): assertions expecting
  delivery text ("Hotstring"/"Clipboard") in the Type column now expect the kind label; the first plan's
  chip-color assertions move to the new tint classes. Add coverage for the category accent, the
  filtered-empty state, and the grid loading state.
- **E2E** (`HotstringsCrudFlowTests.cs`, `RawHotstringFlowTests.cs`, `VersionHistoryFlowTests.cs`):
  `data-test="category-select"` is preserved; re-check assertions reading Type column text.
- **Backend**: any test counting seed samples per kind updates to Macro=2, Raw=2; assert both seed paths
  consume the same shared array.

## Verification

- `dotnet build` + `dotnet test` (UI.Blazor, E2E, touched backend tests).
- Playwright (`playwright-cli` skill) against the no-auth dev stack (`Docker SQL (No Auth)` API +
  `http (No Auth)` frontend). **Hard-reload / unregister the service worker first** to rule out stale
  PWA assets.
  1. Seed reset; confirm Macro and Raw rows appear and every row shows a Description.
  2. Type column: four visibly distinct tinted chips (violet/teal/rose/amber); a Text-clipboard row
     shows the clipboard icon; Raw keeps its warning icon. Confirm chips read as *data*, not competing
     with the saturated toolbar buttons.
  3. Category chips: green outlined, clearly a different channel from Type. Toggle the theme — confirm
     both channels stay legible in light and dark.
  4. Inline-edit categories: no truncation; 0/1/many render placeholder / name / "N selected".
  5. Reload to confirm the loading indicator; filter to zero matches for the filtered-empty state +
     Clear filters; clear and confirm rows return.
  6. Hover the Type header help icon: legend covers `* ? C O`, the context icon, and clipboard delivery.
  7. Select rows: highlight visible in both themes.
  8. Zoom 150% / 200%: Type and Actions columns don't overflow.
- Generate a profile `.ahk` and confirm the seeded Macro/Raw emit valid AHK v2.
