# Hotkey Action Type Filter — Design

## Problem

Hotstrings page has a toolbar `Type` dropdown (`_selectedKind`) for quick filtering by kind.
Hotkeys page has no equivalent for `ActionKind` — the only way to filter by action is the
column-funnel menu on the `Action` header (`Filterable="true" FilterMode="ColumnFilterMenu"`),
which is less discoverable and has no mobile equivalent at all. Backend and DTO plumbing for
`ActionKind` filtering already exist and are exercised by that funnel path, so this is a
frontend-only gap.

## Goal

Add a toolbar `Action` dropdown to the Hotkeys page (desktop + mobile), mirroring the Hotstrings
`Type` filter pattern exactly. Keep the existing column funnel filter working alongside it.

## Non-goals

- No backend or DTO changes — `ListHotkeysQuery.ActionKind`, `HotkeyListRequest.ActionKind` already
  exist and are covered by existing tests.
- No `HasActiveFilters` / "Clear filters" empty-state infra — Hotkeys page doesn't have this pattern
  today (Hotstrings does); out of scope, not part of this ask.
- No change to the column funnel's own behavior.

## Design

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

Labels match `HotkeyActionDisplay.Label(HotkeyActionKind)` exactly (already used by the chip).

**Mobile** — same `MudSelect`, `data-test="action-filter-mobile"`, `FullWidth="true"`, placed after
the mobile search field and before the category filter chips (Hotstrings' mobile slot for Type).

### Request wiring

`LoadServerData` (desktop grid) currently reads the funnel value only:

```csharp
ActionKind: ActionFilter(state, "actionkind"),
```

Change to prefer the toolbar value, falling back to the column funnel when the toolbar is cleared:

```csharp
ActionKind: _selectedAction ?? ActionFilter(state, "actionkind"),
```

`LoadMobileAsync` currently has no `ActionKind` argument — add:

```csharp
ActionKind: _selectedAction,
```

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

### Filter precedence

Toolbar and funnel both target the same `ActionKind` field. Precedence is toolbar-wins: if
`_selectedAction` is set, the funnel's own filter value on the `Action` column is ignored for the
request (though the funnel UI itself is untouched — a user could still have a stale funnel value
set that doesn't affect results while the toolbar is active). This is the same "add dropdown, keep
funnel" tradeoff accepted for this pass — no reconciliation between the two UI states, no dedup.

## Testing

Add to `HotkeysPageTests.cs`, mirroring the three existing Hotstrings kind-filter tests:

1. `Page_ActionFilter_ReloadsDataWithSelectedAction` — set the desktop `[data-test="action-filter"]`
   select, assert `Api.Received().ListAsync(Arg.Is<HotkeyListRequest>(r => r.ActionKind == ...))`.
2. `Page_MobileActionFilter_ReloadsDataWithSelectedAction` — same via
   `[data-test="action-filter-mobile"]`.
3. `Page_ActionFilter_ListsAllSevenKinds` — desktop + mobile selects each render all 7
   `HotkeyActionKind` values (14 `MudSelectItem` total, 7 distinct).
