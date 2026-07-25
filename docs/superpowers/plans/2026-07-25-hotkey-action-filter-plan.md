# Hotkey Action Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toolbar `Action` dropdown to the Hotkeys page (desktop + mobile) that filters by `HotkeyActionKind`, mirroring the Hotstrings `Type` filter, and port Hotstrings' filtered-empty-state handling to Hotkeys.

**Architecture:** Frontend-only. `Hotkeys.razor` gains a `_selectedAction` field bound to two `MudSelect<HotkeyActionKind?>` controls (desktop toolbar + mobile column) whose change handler reloads both the `MudDataGrid` and the mobile list. The `Action` column's funnel filter is disabled so exactly one control owns the value. `HotkeyMobileList.razor` gains the three empty-state parameters `HotstringMobileList` already has. No backend/DTO changes — `HotkeyListRequest.ActionKind` already exists.

**Tech Stack:** .NET 10, Blazor WebAssembly, MudBlazor 9.3.0, bUnit + xUnit + FluentAssertions + NSubstitute.

**Source spec:** `docs/superpowers/specs/2026-07-25-hotkey-action-filter-design.md`

## Global Constraints

- Target frontend project: `src/Frontend/AHKFlowApp.UI.Blazor`; test project: `tests/AHKFlowApp.UI.Blazor.Tests`.
- MudBlazor components only — no raw HTML inputs/buttons (project frontend convention).
- Verify any MudBlazor parameter against the MudMCP server (`mcp__mudblazor__get_component_parameters`) before adding it; pinned version is 9.3.0.
- Action labels are hardcoded literals that must match `HotkeyActionDisplay.Label` verbatim: `Send text`, `Send keys`, `Run`, `Window`, `Remap`, `Disable`, `Raw` (`src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs:24-34`). This duplication matches the existing Hotstrings convention (`Hotstrings.razor:45-48`); do not invent a new sourcing pattern.
- `HotkeyActionKind` has exactly 7 members: `SendText`, `SendKeys`, `Run`, `Window`, `Remap`, `Disable`, `Raw` (`DTOs/HotkeyActionKind.cs`).
- Empty-state copy, verbatim: filtered → `No hotkeys match these filters.` + button text `Clear filters`; true-empty → `No hotkeys yet.`
- `data-test` hooks, verbatim: `action-filter` (desktop), `action-filter-mobile` (mobile). Clear button uses CSS class `clear-filters`.
- No backend, DTO, or `ListHotkeysQuery` changes. Do not touch the `Description`/`Key` column funnels' own behavior.
- No mobile progress-bar indicator in this pass (`Loading` only suppresses the empty-state flash).
- Do not skip pre-commit hooks. Accept post-edit format-hook changes.
- Conventional commits, extremely concise messages.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` | Page: filter state, both toolbars, request wiring, clear-filters logic | Modify |
| `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor` | Mobile list rendering + its empty state | Modify |
| `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs` | Page-level filter + empty-state tests | Modify |
| `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs` | Mobile list empty-state tests | Modify |

---

### Task 1: Action filter dropdown (desktop + mobile) and funnel removal

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (lines 35-44 desktop toolbar, 99 Action column, 159-174 mobile, 274-308 `LoadServerData`, 344-356 `ActionFilter`, 541-566 `LoadMobileAsync`, 762-768 near `OnCategoryFilterChangedAsync`, field block 219-224)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`

**Interfaces:**
- Consumes: existing `HotkeyListRequest` positional/named record params (`Page`, `PageSize`, `Search`, `SortField`, `SortDescending`, `DescriptionFilter`, `KeyFilter`, `ActionKind`, `CategoryIds`); existing test helpers in `HotkeysPageTests`: `RenderPage()`, `StubList(PagedList<HotkeyDto>)`, `Page(params HotkeyDto[])`.
- Produces: `private HotkeyActionKind? _selectedAction;` and `private async Task OnActionFilterChangedAsync()` on `Hotkeys`; `data-test` hooks `action-filter` / `action-filter-mobile`; the `Action` `PropertyColumn` has `Filterable="false"`. Task 2 reads `_selectedAction`.

- [ ] **Step 1: Write the failing tests**

Append these four tests inside the `HotkeysPageTests` class in `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs` (before the closing brace). They follow the Hotstrings equivalents at `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs:798-995`.

```csharp
    [Fact]
    public async Task Page_ActionFilter_ReloadsDataWithSelectedAction()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> desktopActionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => desktopActionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r => r.ActionKind == HotkeyActionKind.Remap),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Page_MobileActionFilter_ReloadsDataWithSelectedAction()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter-mobile\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> mobileActionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter-mobile\""));
        await cut.InvokeAsync(() => mobileActionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Window));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r => r.ActionKind == HotkeyActionKind.Window),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_ActionFilter_ListsAllSevenKinds()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        // Desktop + mobile selects each render all HotkeyActionKind items - 7 kinds x 2 selects.
        IReadOnlyList<HotkeyActionKind?> allValues = [.. cut.FindComponents<MudSelectItem<HotkeyActionKind?>>()
            .Select(c => c.Instance.Value)];

        allValues.Should().HaveCount(14);
        allValues.Distinct().Should().BeEquivalentTo(
        [
            HotkeyActionKind.SendText, HotkeyActionKind.SendKeys, HotkeyActionKind.Run,
            HotkeyActionKind.Window, HotkeyActionKind.Remap, HotkeyActionKind.Disable,
            HotkeyActionKind.Raw,
        ]);
    }

    [Fact]
    public void Page_ActionColumn_FunnelFilterDisabled()
    {
        // The toolbar dropdown owns ActionKind. A live column funnel on the same field would be a
        // second control writing the same request value - keep it off (Hotstrings does the same
        // for its Type column).
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<PropertyColumn<HotkeyEditModel, HotkeyActionKind>> actionColumn =
            cut.FindComponents<PropertyColumn<HotkeyEditModel, HotkeyActionKind>>().Single();

        actionColumn.Instance.Filterable.Should().BeFalse();
    }
```

`PropertyColumn<HotkeyEditModel, HotkeyActionKind>` is unique on the page — the other two property columns are `<HotkeyEditModel, string>`. `MudSelect`, `MudSelectItem`, and `PropertyColumn` all come from the already-imported `MudBlazor` namespace; `HotkeyEditModel` from `AHKFlowApp.UI.Blazor.Validation`, `HotkeyActionKind` from `AHKFlowApp.UI.Blazor.DTOs` — both already imported in this file.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysPageTests.Page_ActionFilter|FullyQualifiedName~HotkeysPageTests.Page_MobileActionFilter|FullyQualifiedName~HotkeysPageTests.Page_ActionColumn_FunnelFilterDisabled"
```

Expected: all 4 FAIL — the two `ReloadsData` and `ListsAllSevenKinds` tests fail finding `data-test="action-filter"` / getting 0 select items; `Page_ActionColumn_FunnelFilterDisabled` fails because `Filterable` is currently `true` (inherited from the grid's `Filterable="true"`).

- [ ] **Step 3: Add the state field**

In `Hotkeys.razor`, in the field block after `_selectedCategoryIds` (line 219):

```csharp
    private IReadOnlyList<Guid> _selectedCategoryIds = [];
    private HotkeyActionKind? _selectedAction;
```

- [ ] **Step 4: Add the desktop toolbar select**

In `Hotkeys.razor`, between `<MudSpacer />` (line 35) and the desktop `MudTextField` search field (line 36) — the same slot Hotstrings uses:

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

- [ ] **Step 5: Add the mobile select**

In `Hotkeys.razor`, between the mobile search `MudTextField` (ends line 165) and the `@if (_categories.Count > 0)` category-chip block (line 167):

```razor
        <MudSelect T="HotkeyActionKind?" @bind-Value="_selectedAction" @bind-Value:after="OnActionFilterChangedAsync"
                   Label="Action" Placeholder="All" Clearable="true"
                   Class="action-filter-mobile mb-2" FullWidth="true"
                   UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-filter-mobile" })">
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.SendText">Send text</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.SendKeys">Send keys</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Run">Run</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Window">Window</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Remap">Remap</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Disable">Disable</MudSelectItem>
            <MudSelectItem T="HotkeyActionKind?" Value="HotkeyActionKind.Raw">Raw</MudSelectItem>
        </MudSelect>
```

- [ ] **Step 6: Add the change handler**

In `Hotkeys.razor`, directly after `OnCategoryFilterChangedAsync` (ends line 768):

```csharp
    private async Task OnActionFilterChangedAsync()
    {
        if (_grid is not null) await _grid.ReloadServerData();
        _mobilePage = 1;
        await LoadMobileAsync();
    }
```

- [ ] **Step 7: Disable the Action column funnel**

In `Hotkeys.razor` line 99, change:

```razor
<PropertyColumn Property="x => x.ActionKind" Title="Action">
```

to:

```razor
@* The toolbar Action dropdown owns this filter value; a column funnel here would be a second
   control writing the same request field. Same reason Hotstrings' Type column sets it. *@
<PropertyColumn Property="x => x.ActionKind" Title="Action" Filterable="false">
```

- [ ] **Step 8: Wire the request on both paths and delete the dead helper**

In `LoadServerData` (line 290) replace:

```csharp
                ActionKind: ActionFilter(state, "actionkind"),
```

with:

```csharp
                ActionKind: _selectedAction,
```

Delete the whole `ActionFilter` method (lines 344-356), which now has no callers:

```csharp
    private static HotkeyActionKind? ActionFilter(GridState<HotkeyEditModel> state, string identifier)
    {
        object? value = state.FilterDefinitions
            .FirstOrDefault(filter => ColumnKey(filter) == NormalizeColumnKey(identifier))?
            .Value;

        return value switch
        {
            HotkeyActionKind typed => typed,
            string text when Enum.TryParse(text, ignoreCase: true, out HotkeyActionKind parsed) => parsed,
            _ => null,
        };
    }
```

Keep `StringFilter`, `ColumnKey`, and `NormalizeColumnKey` — `StringFilter` still serves the `Description`/`Key` funnels and uses the other two.

In `LoadMobileAsync` (lines 546-552) add the same value to the request:

```csharp
        ApiResult<PagedList<HotkeyDto>> result = await ListAsync(
            new HotkeyListRequest(
                Page: _mobilePage,
                PageSize: _mobilePageSize,
                Search: string.IsNullOrWhiteSpace(_search) ? null : _search,
                ActionKind: _selectedAction,
                CategoryIds: _selectedCategoryIds.Count > 0 ? _selectedCategoryIds : null),
            _cts.Token);
```

- [ ] **Step 9: Run the tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysPageTests"
```

Expected: PASS — the 4 new tests plus every pre-existing `HotkeysPageTests` test (nothing there asserted on the Action funnel).

- [ ] **Step 10: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs
git commit -m "feat: toolbar Action filter on hotkeys page, funnel off"
```

---

### Task 2: Desktop filtered-empty state with Clear filters

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (`NoRecordsContent` line 142, `LoadServerData` lines 279-292, field block, handler area near `OnActionFilterChangedAsync`)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`

**Interfaces:**
- Consumes: `_selectedAction`, `OnActionFilterChangedAsync` (Task 1); existing `_search`, `_selectedCategoryIds`, `_grid`, `_mobilePage`, `LoadMobileAsync()`, `StringFilter(state, identifier)`.
- Produces: `private bool _hasColumnFilters;`, `private bool HasActiveFilters { get; }`, `private async Task ClearFiltersAsync()` on `Hotkeys`. Task 3 passes both into `HotkeyMobileList`.

- [ ] **Step 1: Write the failing tests**

Append to `HotkeysPageTests`:

```csharp
    [Fact]
    public async Task Page_EmptyFilteredResults_ShowsClearFiltersButton()
    {
        // "You have no hotkeys" and "your filters matched nothing" need different copy, and only
        // the second can offer a way out.
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> actionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => actionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("No hotkeys match these filters.");
            cut.Markup.Should().NotContain("No hotkeys yet.");
            cut.FindAll(".hotkeys-grid button.clear-filters").Should().ContainSingle();
        });
    }

    [Fact]
    public async Task Page_ClearFilters_ResetsSearchActionAndCategoryAndReloads()
    {
        var categoryId = Guid.NewGuid();
        StubCategories(new CategoryDto(categoryId, "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudTextField<string>> search = cut
            .FindComponents<MudTextField<string>>()
            .First(c => c.Markup.Contains("search-hotkeys"));
        await cut.InvokeAsync(() => search.Instance.ValueChanged.InvokeAsync("term"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> actionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => actionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        IRenderedComponent<CategoryFilterChips> chips = cut.FindComponents<CategoryFilterChips>().First();
        await cut.InvokeAsync(() => chips.Instance.SelectedIdsChanged.InvokeAsync([categoryId]));

        cut.WaitForAssertion(() => cut.Find(".hotkeys-grid button.clear-filters"));
        await cut.InvokeAsync(() => cut.Find(".hotkeys-grid button.clear-filters").Click());

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r =>
                r.Search == null && r.ActionKind == null && r.CategoryIds == null),
            Arg.Any<CancellationToken>()));
    }
```

`CategoryFilterChips` comes from `AHKFlowApp.UI.Blazor.Components.Common`, already imported in this test file. Check `StubCategories`'s signature in the file before use (it exists and is called from the constructor with no args at line 48) — if it is not `params CategoryDto[]`, match its actual shape.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysPageTests.Page_EmptyFilteredResults|FullyQualifiedName~HotkeysPageTests.Page_ClearFilters"
```

Expected: FAIL — markup still says `No hotkeys yet.`, and no `.clear-filters` element exists.

- [ ] **Step 3: Add the state field**

In `Hotkeys.razor`, after `private string _search = "";`:

```csharp
    private bool _hasColumnFilters;
```

- [ ] **Step 4: Add HasActiveFilters and ClearFiltersAsync**

In `Hotkeys.razor`, after `OnActionFilterChangedAsync` (added in Task 1):

```csharp
    // Separates "you have no hotkeys" from "your filters matched nothing" - the two empty states
    // need different copy, and only the second one can offer a way out. Column filters count too:
    // they reach the API, so they can produce an empty result on their own.
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

- [ ] **Step 5: Compute `_hasColumnFilters` in `LoadServerData`**

In `Hotkeys.razor`, replace the request block's inline funnel reads (lines 281-292) so the two remaining funnel values are captured into locals first:

```csharp
        // Column filters live in the grid's state, not in page fields - capture them here so the
        // empty state can tell "no hotkeys" from "no matches" for these too.
        string? descriptionFilter = StringFilter(state, "description");
        string? keyFilter = StringFilter(state, "key");
        _hasColumnFilters = !string.IsNullOrWhiteSpace(descriptionFilter)
            || !string.IsNullOrWhiteSpace(keyFilter);

        ApiResult<PagedList<HotkeyDto>> result = await ListAsync(
            new HotkeyListRequest(
                Page: state.Page + 1,
                PageSize: state.PageSize,
                Search: string.IsNullOrWhiteSpace(_search) ? null : _search,
                SortField: sortField,
                SortDescending: sortDescending,
                DescriptionFilter: descriptionFilter,
                KeyFilter: keyFilter,
                ActionKind: _selectedAction,
                CategoryIds: _selectedCategoryIds.Count > 0 ? _selectedCategoryIds : null),
            ct);
```

- [ ] **Step 6: Branch the desktop `NoRecordsContent`**

In `Hotkeys.razor`, replace line 142:

```razor
        <NoRecordsContent><MudText>No hotkeys yet.</MudText></NoRecordsContent>
```

with:

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

- [ ] **Step 7: Run the tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysPageTests"
```

Expected: PASS, all `HotkeysPageTests`.

If `Page_EmptyFilteredResults_ShowsClearFiltersButton` fails on the `NotContain("No hotkeys yet.")` assertion, the mobile branch is still rendering its own true-empty text — that is expected until Task 3 and means the assertion should be scoped: replace it with `cut.Find(".hotkeys-grid").InnerHtml.Should().NotContain("No hotkeys yet.")`. Do not weaken the positive assertions.

- [ ] **Step 8: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs
git commit -m "feat: filtered-empty state + clear filters on hotkeys grid"
```

---

### Task 3: Mobile list filtered-empty state

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor` (empty state lines 15-18, parameter block lines 95-100)
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (`HotkeyMobileList` usage lines 181-186)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs`

**Interfaces:**
- Consumes: `HasActiveFilters`, `ClearFiltersAsync` (Task 2), existing `_loading` on `Hotkeys`.
- Produces: `HotkeyMobileList` parameters `bool HasActiveFilters`, `EventCallback OnClearFilters`, `bool Loading` — the same three `HotstringMobileList` already has.

- [ ] **Step 1: Write the failing tests**

Append to `HotkeyMobileListTests` in `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs`, mirroring `HotstringMobileListTests.cs:61-105`. Read the file's existing `Render<HotkeyMobileList>(...)` calls first and match its item-builder helper name and parameter style exactly (the Hotstrings equivalents add `Profiles`/`Categories` as `(IReadOnlyList<ProfileDto>)[]` / `(IReadOnlyList<CategoryDto>)[]`).

```csharp
    [Fact]
    public void EmptyState_WithActiveFilters_OffersClearFilters()
    {
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.HasActiveFilters, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("No hotkeys match these filters.");
        cut.Markup.Should().NotContain("No hotkeys yet.");
        cut.FindAll("button.clear-filters").Should().ContainSingle();
    }

    [Fact]
    public async Task EmptyState_ClearFiltersButton_RaisesCallback()
    {
        bool cleared = false;

        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.HasActiveFilters, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnClearFilters, EventCallback.Factory.Create(this, () => cleared = true)));

        await cut.InvokeAsync(() => cut.Find("button.clear-filters").Click());

        cleared.Should().BeTrue();
    }

    [Fact]
    public void EmptyState_WhileLoading_ShowsNoEmptyMessage()
    {
        // An empty list mid-load is not yet known to be empty - "No hotkeys yet." rendered during
        // a fetch reads as a result the user does not actually have.
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.Loading, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().NotContain("No hotkeys yet.");
        cut.Markup.Should().NotContain("No hotkeys match these filters.");
    }
```

`EventCallback` needs `using Microsoft.AspNetCore.Components;` — add it if the file lacks it.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyMobileListTests.EmptyState"
```

Expected: FAIL to compile — `HotkeyMobileList` has no `HasActiveFilters`, `OnClearFilters`, or `Loading` parameter.

- [ ] **Step 3: Add the parameters**

In `HotkeyMobileList.razor`, after `OnBulkDelete` (line 100):

```csharp
    /// <summary>Drives the empty state: filtered-empty offers a way out, true-empty does not.</summary>
    [Parameter] public bool HasActiveFilters { get; set; }
    [Parameter] public EventCallback OnClearFilters { get; set; }

    /// <summary>Suppresses the empty state while a load is in flight - an empty list mid-load is
    /// not yet known to be empty, and "No hotkeys yet" during a fetch reads as a result.</summary>
    [Parameter] public bool Loading { get; set; }
```

- [ ] **Step 4: Branch the empty state**

In `HotkeyMobileList.razor`, replace lines 15-18:

```razor
    @if (Items.Count == 0)
    {
        <MudText Class="pa-4 text-center" Typo="Typo.body2">No hotkeys yet.</MudText>
    }
```

with:

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
```

The existing `else { <table class="mobile-list"> ... }` branch stays exactly as it is.

- [ ] **Step 5: Pass the three parameters from the page**

In `Hotkeys.razor`, replace the `HotkeyMobileList` usage (lines 181-186):

```razor
        <HotkeyMobileList Items="_mobileItems"
                         Profiles="_profiles"
                         Categories="_categories"
                         HasActiveFilters="HasActiveFilters"
                         OnClearFilters="ClearFiltersAsync"
                         Loading="_loading"
                         OnEdit="OpenEditDialogAsync"
                         OnDelete="DeleteAsync"
                         OnBulkDelete="MobileBulkDeleteAsync" />
```

- [ ] **Step 6: Run the mobile list tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyMobileListTests"
```

Expected: PASS. Note `Loading` now gates the pre-existing true-empty test too: if an older test renders with `Items` empty and asserts `No hotkeys yet.`, it still passes because `Loading` defaults to `false`.

- [ ] **Step 7: Run the whole frontend test project**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release
```

Expected: PASS, no failures.

- [ ] **Step 8: Format and build the solution**

```bash
dotnet format --verify-no-changes
dotnet build --configuration Release
```

Expected: format reports no changes needed; build succeeds with no new warnings. If `dotnet format --verify-no-changes` fails, run `dotnet format` and include the result in the commit.

- [ ] **Step 9: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs
git commit -m "feat: filtered-empty state on hotkey mobile list"
```

---

## Manual verification (optional, after Task 3)

The worktree runs no-auth, so this needs no login. Ports come from this worktree's `launchSettings.json` — read them rather than assuming.

1. Start the API and the frontend (see `AGENTS.md` commands).
2. Open the hotkeys page, pick `Remap` in the toolbar `Action` dropdown → only remap rows remain; the `Action` column header shows no funnel icon.
3. Combine it with a search term that matches nothing → `No hotkeys match these filters.` plus a `Clear filters` button; clicking it restores the full list and empties the search box and dropdown.
4. Narrow the browser below 960px → the same dropdown appears above the category chips and behaves identically.

## Unresolved questions

None.
