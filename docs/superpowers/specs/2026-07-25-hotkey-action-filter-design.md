# Hotkey Action Filter — Design

## Problem

Hotstrings page has a toolbar `Type` dropdown (`_selectedKind`) for quick filtering by kind.
Hotkeys page has no equivalent for `ActionKind` — the only way to filter by action is the
column-funnel menu on the `Action` header (`Filterable="true" FilterMode="ColumnFilterMenu"`),
which is less discoverable and has no mobile equivalent at all. Backend and DTO plumbing for
`ActionKind` filtering already exist and are exercised by that funnel path, so this is a
frontend-only gap.

## Goal

Add a toolbar `Action` dropdown to the Hotkeys page (desktop + mobile), mirroring the Hotstrings
`Type` filter pattern exactly, including its filtered-empty-state handling.

## Non-goals

- No backend or DTO changes — `ListHotkeysQuery.ActionKind`, `HotkeyListRequest.ActionKind` already
  exist and are covered by existing tests.
- No change to the `Description`/`Key` column funnel filters' own behavior.

## Design

### Disable the Action column funnel

Hotstrings never actually runs a toolbar dropdown next to a live column funnel for the same field:
its `Type` `TemplateColumn` sets `Filterable="false"` (Hotstrings.razor:158) specifically to avoid
two controls fighting over one filter value. Follow that precedent — add `Filterable="false"` to
the `Action` `PropertyColumn` (Hotkeys.razor:99) and delete the now-dead `ActionFilter` helper
(Hotkeys.razor:344-356) and its use in `LoadServerData`. `Description` and `Key` columns keep their
funnels unchanged; only `Action` moves to toolbar-only.

### State

Add `private HotkeyActionKind? _selectedAction;` to `Hotkeys.razor`, alongside the existing
`_selectedCategoryIds` field.

### UI

**Desktop** — in the toolbar `MudStack`, after `MudSpacer` and before the search field (same slot
Hotstrings uses for its Type select):

```razor
<MudSelect T="HotkeyActionKind?" @bind-Value="_selectedAction" @bind-Value:after="OnActionFilterChangedAsync"
           Label="Action" Placeholder="All" Clearable="true"
           Class="action-filter" Style="max-width: 200px;"
           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-filter" })">
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.SendText">Send text</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.SendKeys">Send keys</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Run">Run</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Window">Window</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Remap">Remap</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Disable">Disable</MudSelectItem>
    <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Raw">Raw</MudSelectItem>
</MudSelect>
```

Labels are hardcoded literals matching `HotkeyActionDisplay.Label(HotkeyActionKind)`'s output
verbatim — this duplicates the helper's strings, but so does Hotstrings' own Type select
(Hotstrings.razor:45-48 vs `HotstringKindDisplay.Label`); matching that existing convention rather
than introducing a new sourcing pattern on a single page.

**Mobile** — same `MudSelect`, `data-test="action-filter-mobile"`, `FullWidth="true"`, placed after
the mobile search field and before the category filter chips (Hotstrings' mobile slot for Type).

### Request wiring

`LoadServerData` (desktop grid): replace the funnel-only read with the toolbar value directly (no
fallback needed now that the funnel is disabled):

```csharp
ActionKind: _selectedAction,
```

`LoadMobileAsync` currently has no `ActionKind` argument — add the same.

### Change handler

Mirror `OnCategoryFilterChangedAsync`:

```csharp
private async Task OnActionFilterChangedAsync()
{
    if (_grid is not null) await _grid.ReloadServerData();
    _mobilePage = 1;
    await LoadMobileAsync();
}
```

### Filtered-empty state

Hotkeys' `NoRecordsContent` is static `"No hotkeys yet."` regardless of active filters
(Hotkeys.razor:142) — a pre-existing gap (already reachable today via search, category, or the
`Description`/`Key` funnels), but adding another filter path makes hitting it more likely, so this
pass ports Hotstrings' `HasActiveFilters` / `ClearFiltersAsync` pattern (Hotstrings.razor:944-962)
into Hotkeys wholesale rather than adding one more filter that a user can't easily back out of.

**Desktop** `NoRecordsContent`:

```razor
<NoRecordsContent>
    @if (HasActiveFilters)
    {
        <MudStack AlignItems="AlignItems.Center" Spacing="2" Class="pa-4">
            <MudText>No hotkeys match these filters.</MudText>
            <MudButton Variant="Variant.Text" Color="Color.Primary" Class="clear-filters"
                       OnClick="ClearFiltersAsync">Clear filters</MudButton>
        </MudStack>
    }
    else
    {
        <MudText>No hotkeys yet.</MudText>
    }
</NoRecordsContent>
```

**Code-behind**, mirroring Hotstrings exactly:

```csharp
private bool _hasColumnFilters;

private bool HasActiveFilters =>
    !string.IsNullOrWhiteSpace(_search)
    || _selectedAction is not null
    || _selectedCategoryIds.Count > 0
    || _hasColumnFilters;

private async Task ClearFiltersAsync()
{
    _search = "";
    _selectedAction = null;
    _selectedCategoryIds = [];
    _grid?.FilterDefinitions.Clear();
    _hasColumnFilters = false;
    if (_grid is not null) await _grid.ReloadServerData();
    _mobilePage = 1;
    await LoadMobileAsync();
}
```

`_hasColumnFilters` is computed in `LoadServerData` from the two remaining funnels (`Description`,
`Key`), same as Hotstrings computes it from its three text funnels:

```csharp
string? descriptionFilter = StringFilter(state, "description");
string? keyFilter = StringFilter(state, "key");
_hasColumnFilters = !string.IsNullOrWhiteSpace(descriptionFilter)
    || !string.IsNullOrWhiteSpace(keyFilter);
```

**Mobile** — `HotkeyMobileList.razor` gains the same three parameters `HotstringMobileList` already
has (`HasActiveFilters`, `OnClearFilters`, `Loading`) and the matching empty-state branch:

```razor
[Parameter] public bool HasActiveFilters { get; set; }
[Parameter] public EventCallback OnClearFilters { get; set; }
[Parameter] public bool Loading { get; set; }
```

```razor
@if (Items.Count == 0 && !Loading)
{
    @if (HasActiveFilters)
    {
        <MudStack AlignItems="AlignItems.Center" Spacing="2" Class="pa-4">
            <MudText Typo="Typo.body2">No hotkeys match these filters.</MudText>
            <MudButton Variant="Variant.Text" Color="Color.Primary" Class="clear-filters"
                       OnClick="OnClearFilters">Clear filters</MudButton>
        </MudStack>
    }
    else
    {
        <MudText Class="pa-4 text-center" Typo="Typo.body2">No hotkeys yet.</MudText>
    }
}
else
{
    ...existing table...
}
```

`Hotkeys.razor`'s mobile branch passes `HasActiveFilters="HasActiveFilters"`,
`OnClearFilters="ClearFiltersAsync"`, `Loading="_loading"` into `HotkeyMobileList`. `Loading` only
suppresses the empty-state flash mid-fetch (matches `HotstringMobileList`'s existing use) — this
pass does not add a mobile progress-bar indicator; that's a separate, unrelated gap.

## Testing

Add to `HotkeysPageTests.cs`:

1. `Page_ActionFilter_ReloadsDataWithSelectedAction` — set the desktop `[data-test="action-filter"]`
   select, assert `Api.Received().ListAsync(Arg.Is<HotkeyListRequest>(r => r.ActionKind == ...))`.
2. `Page_MobileActionFilter_ReloadsDataWithSelectedAction` — same via
   `[data-test="action-filter-mobile"]`.
3. `Page_ActionFilter_ListsAllSevenKinds` — desktop + mobile selects each render all 7
   `HotkeyActionKind` values (14 `MudSelectItem` total, 7 distinct).
4. `Page_ActionColumn_FunnelFilterDisabled` — assert the `Action` column no longer exposes a filter
   icon/menu (guards against the funnel silently coming back).
5. `Page_EmptyFilteredResults_ShowsClearFiltersButton` — stub an empty page with `_selectedAction`
   set, assert `.clear-filters` renders and `"No hotkeys match these filters."` shows instead of
   `"No hotkeys yet."`.
6. `Page_ClearFilters_ResetsSearchActionAndCategoryAndReloads` — set search + action + category,
   click `.clear-filters`, assert all three reset and `ListAsync` is called with all filters cleared.
