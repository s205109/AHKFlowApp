# Hotstrings page UX fixes — follow-up

## Context

The first pass (`2026-07-20-hotstring-page-ux-fixes-plan.md`, Sonnet) under-delivered. Live
testing shows Type chips and Category chips still render grey, and the inline category editor
still truncates to "C...". The user also wants at least two seed examples per hotstring kind and
a broader UX sweep of gaps the first plan missed. Goal: real color coding on both chip families
(a deliberate two-channel system), a readable inline category editor, full kind coverage in seed
data, and four audit-driven UX fixes. All root causes below were verified in code, not assumed.

### Root causes (verified)

- **Category chips grey — genuine gap.** `Components/Common/EntityChips.razor:11` renders each
  per-id chip with **no `Color`**, so MudBlazor falls back to `Color.Default` = grey. The first
  plan added only `Variant.Outlined` (an outline shape), never a color. No per-category color logic
  exists anywhere.
- **Type chips grey — by design + all-Text data.** `KindColor` (`Pages/Hotstrings.razor:967-973`)
  correctly colors DateTime=Info, Macro=Success, Raw=Warning (filled variant renders color). But
  `RenderTypeChip` (lines 959-965) shows **Text** rows a grey *delivery* chip ("Hotstring"), and
  every seeded row is Text-kind, so the whole visible column is grey. The column titled "Type" never
  shows "Text" for text rows. Possibly compounded by a stale PWA service-worker cache.
- **Dropdown "C..." truncation — pre-existing, not from `17ef225`.** Categories column is pinned
  `width:10%` (`Hotstrings.razor.css:87-90`) under `table-layout:fixed`, and a blanket rule clips
  every cell: `overflow:hidden; text-overflow:ellipsis; white-space:nowrap` (lines 39-47). In edit
  mode that ~100px cell must host a full `MudSelect` whose Clearable (X) + dropdown arrow eat the
  width, leaving room for one character.
- **Seed gap.** `SeedHotstringsCommand.cs:32-43` has 10 Text + 2 DateTime, **0 Macro, 0 Raw**. The
  array is duplicated verbatim in `ListHotstringsQuery.cs:78-89` (lazy auto-seed) with a "update
  both" comment — a sync hazard. Categories `Window Management` and `App Launcher` have no examples.

## Design decisions (confirmed with user)

1. **Type column shows the kind, colored, delivery → icon.** Every row shows its kind
   (Text/DateTime/Macro/Raw), each a distinct color including Text (violet). Clipboard delivery
   becomes a small icon, not the chip label.
2. **Categories get an auto OKLCH palette**, outlined chips — a *distinct visual channel* from the
   filled Type chips. No schema change: 8 default categories hand-mapped to hues, custom categories
   hash into the same ring.
3. **Two color channels, deliberately different** (impeccable): Type = **filled** semantic/violet
   (the chip carries its own hue background, so it reads in both themes); Categories = **outlined**
   custom hues (border+text sit on the page background, so those hues must be dual-theme legible).

## Approach

### 1. Type column: kind label, colored, delivery as icon

`RenderTypeChip` (`Pages/Hotstrings.razor:959-965`) currently branches Text→delivery chip,
else→kind chip. Replace with: **always render a kind chip** via `KindLabel` (already exists, 947-954),
colored per kind, plus a small delivery icon when `DeliveryDisplay.IsClipboard(item.EffectiveDelivery)`.

Kind colors — one coherent 4-hue OKLCH set applied as **inline `Style`** on the filled chip (inline
style reliably overrides MudBlazor's filled background; a filled chip's own hue background reads in
both themes):

| Kind | Hue (approx OKLCH, tune at build) | Note |
|---|---|---|
| Text | violet `oklch(0.55 0.16 300)` | new distinct color, replaces grey |
| DateTime | blue `oklch(0.58 0.14 240)` | matches prior Info intent |
| Macro | green `oklch(0.56 0.13 150)` | matches prior Success intent |
| Raw | amber `oklch(0.62 0.14 70)` | + keep the existing `Warning` icon |

Foreground text near-white `oklch(0.98 0 0)` for contrast on all four. Keep the Raw warning icon and
its aria-label (`ScriptWarningText`, lines 994/1015-1018). Add the clipboard icon
(`Icons.Material.Filled.ContentPaste`, small, muted) only for Text-clipboard rows, inside the existing
Type-cell composition (chip + `.option-glyphs` + context icon, lines 168-179); mention delivery in the
per-row Type tooltip so the info stays discoverable. The dialog toggle
(`HotstringEditDialog.razor:22-44`) already colors kinds via icons — optionally align those icon hues
to the same set; not required.

### 2. Category color palette (auto, outlined, dual-theme)

New `CategoryPalette` helper (Frontend, e.g. `Components/Common/CategoryPalette.cs`):

```csharp
internal static class CategoryPalette
{
    private static readonly string[] Ring =
        ["cat-hue-0","cat-hue-1","cat-hue-2","cat-hue-3","cat-hue-4","cat-hue-5","cat-hue-6","cat-hue-7"];

    private static readonly Dictionary<string, string> Defaults = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Autocorrect"] = "cat-hue-0", ["Communication"] = "cat-hue-1", ["DateTime"] = "cat-hue-2",
        ["Email"] = "cat-hue-3", ["Code"] = "cat-hue-4", ["Symbols"] = "cat-hue-5",
        ["Window Management"] = "cat-hue-6", ["App Launcher"] = "cat-hue-7",
    };

    public static string ClassFor(string name) =>
        Defaults.TryGetValue(name, out string? c) ? c : Ring[StableHash(name) % Ring.Length];

    // Stable across sessions/platforms (string.GetHashCode is not) — FNV-1a, non-negative.
    private static int StableHash(string s) { /* ... */ }
}
```

Add an optional pass-through to the shared component — `Components/Common/EntityChips.razor`:

```razor
[Parameter] public Func<Guid, string?>? ColorClassFor { get; set; }
...
<MudChip T="string" Size="Size.Small" Variant="Variant" Class="@ColorClassFor?.Invoke(id)">@NameFor(id)</MudChip>
```

Profiles and every other caller pass nothing → unchanged. `RenderCategories`
(`Pages/Hotstrings.razor:944-945`) and `HotstringMobileList.razor:108` pass
`ColorClassFor="@(id => CategoryPalette.ClassFor(nameFor(id)))"` (resolve name via `_categoryOptions`).

Global CSS in `wwwroot/css/app.css` (not scoped — the chips render in two different components):
`.cat-hue-0` … `.cat-hue-7`, each setting **border-color + text color** to a mid-tone OKLCH hue chosen
to read on both light and dark page backgrounds. Selector specificity must beat MudBlazor's default
outlined-chip color (likely needs `.mud-chip.cat-hue-N` or a cascade layer) — verify live. Add a dark
override only for any hue that fails contrast in the live both-theme check.

### 3. Inline category editor: stop the "C..." clip

Two changes in `Hotstrings.razor.css`:
- **Un-clip editing rows.** The blanket clip (39-47) is meant for read-only text columns. Exclude the
  in-edit cell: `::deep .hotstrings-grid .edit-row .mud-table-cell,
  ::deep .hotstrings-grid .draft-row .mud-table-cell { overflow: visible; white-space: normal; }`
  (the `edit-row`/`draft-row` classes are already attached by `GetRowClass`, 427-428).
- **Give the editor room.** Modestly widen the Categories column (`nth-child(7)`, 87-90) from `10%`
  (rebalance a couple of the other `%` columns so the row still sums sanely), and ensure
  `EntityMultiSelect`'s `MudSelect` fills the cell (add a `FullWidth`/min-width via a class param, or a
  `.category-select` rule). Optionally set MudSelect `MultiSelectionTextFunc` to a compact
  "N selected" so multiple picks don't overflow. Verify live that the selected category name is fully
  readable.

### 4. Seed: +2 Macro, +2 Raw, fill empty categories, de-dupe the array

Add four samples. The seed tuple needs **no new fields** (Kind + Replacement carry Macro/Raw):

| Trigger | Replacement | Kind | Category |
|---|---|---|---|
| `htag` | `<b>{{cursor}}</b>` | Macro | Code |
| `alink` | `<a href="{{cursor}}"></a>` | Macro | Code |
| `/np` | `:X:/np::Run("notepad.exe")` | Raw | App Launcher |
| `/wmax` | `:X:/wmax::WinMaximize("A")` | Raw | Window Management |

Macro replacements use the documented token vocabulary (`{{cursor}}` with text but no keys after —
valid per `ahk-v2-syntax.md`). Raw replacements are the entire verbatim `:X:trigger::` definition with
the `X` execute flag. **Risk to resolve at build:** the seed path constructs `HotstringDefinition`
directly and bypasses `RawHotstringDefinitionParser.Prepare`. For Raw seeds, run the replacement
through `RawHotstringDefinitionParser.Prepare` (same as `CreateHotstringCommand`) so stored
`Replacement` = `NormalizedDefinition` and Trigger is consistent; Macro stores the token string
directly. Verify a seeded Raw/Macro row renders and its generated `.ahk` is valid.

**De-dupe while here:** extract the sample array to one shared static (e.g.
`Application/.../HotstringSeedSamples.cs`) and have both `SeedHotstringsCommand` and
`ListHotstringsQuery` consume it — removes the "update both files" hazard the current comment warns of.

### 5. Grid loading indicator

`_loading` is set around every load (`LoadServerData` 335/354, `LoadMobileAsync` 637/649) but bound to
nothing visible. Bind `Loading="_loading"` on the desktop `MudDataGrid` (70-77) with a `LoadingContent`;
add a `MudProgressLinear`/skeleton on the mobile branch gated on `_loading`.

### 6. "No results for filter" empty state

Both the grid `NoRecordsContent` (line 197) and the mobile empty block say "No hotstrings yet."
regardless of active filters. Add a computed `_hasActiveFilters` (search non-empty OR `_selectedKind`
set OR `_selectedCategoryIds` non-empty) and branch: filtered-empty → "No hotstrings match these
filters." plus a **Clear filters** action; true-empty → keep "No hotstrings yet." Apply to both
desktop and mobile.

### 7. Complete the glyph legend + confirm selection highlight

- Header legend tooltip (`Pages/Hotstrings.razor:161`) documents only `* ? C`. Add `O` (omit ending
  char) and the window-context icon meaning, matching what the cell actually renders (`OptionGlyphs`
  978-990) and the per-row `OptionsTooltip` (996-1013).
- Selection highlighting (`.selected-row`) already shipped in the first plan. Verify it's actually
  visible in both themes at the current 12% tint; bump the mix if too subtle.

## Test blast radius

- **bUnit** (`tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`): any assertion that the
  Type column shows delivery text ("Hotstring"/"Clipboard") for Text rows now expects the kind label
  "Text"; the first plan's chip-color assertions change from semantic `Color` classes to the new
  inline-style / kind-class scheme. Add: a category chip carries a `cat-hue-*` class; the filtered-empty
  state renders distinct text; the grid exposes a loading state.
- **E2E** (`HotstringsCrudFlowTests.cs`, `RawHotstringFlowTests.cs`, `VersionHistoryFlowTests.cs`):
  category-editor selector unaffected (`data-test="category-select"` preserved by `EntityMultiSelect`);
  re-check any assertion reading the Type column's text.
- **Backend**: a seeding test (if present) that counts samples per kind updates to expect Macro=2,
  Raw=2; the shared-array extraction must keep both seed paths byte-identical (assert they reference the
  same source).

## Verification

- `dotnet build` + `dotnet test` (UI.Blazor, then E2E, then the seed/backend tests touched).
- Playwright (`playwright-cli` skill) against the no-auth dev stack (`Docker SQL (No Auth)` API +
  `http (No Auth)` frontend). **Reset the PWA cache / hard-reload first** to rule out stale assets.
  1. Trigger a seed reset; confirm the grid shows Macro rows (`htag`, `alink`) and Raw rows
     (`/np`, `/wmax`), and that `Window Management` + `App Launcher` category filters now return rows.
  2. Type column: Text=violet, DateTime=blue, Macro=green, Raw=amber+warning icon — four visibly
     distinct filled chips; a Text-clipboard row shows the clipboard icon.
  3. Category chips: outlined, each category a distinct hue, clearly a different channel from Type
     chips. Toggle the theme switch — confirm both Type and Category colors stay legible in light and
     dark; fix any failing category hue.
  4. Inline-edit a row's categories: the `MudSelect` is fully readable (no "C..."), selected names
     visible.
  5. Force a load (reload) and confirm the loading indicator shows; apply a filter with no matches and
     confirm the filtered-empty text + Clear filters; clear it and confirm rows return.
  6. Hover the Type header help icon: legend lists `* ? C O` and the window-context icon.
  7. Select rows via checkboxes: highlight visible in both themes.
- Generate/download a profile `.ahk` (or use the preview) to confirm the seeded Macro/Raw emit valid
  AHK v2.

## Unresolved questions

1. Kind hues — violet/blue/green/amber ok, or swap any? (green Macro sits near the app's green Primary.)
2. Custom (non-default) categories: hash-into-8-hues acceptable, or only color the 8 defaults and leave
   custom ones neutral?
3. Inline multi-category editor: keep per-name chips in the closed anchor, or switch to "N selected"?
