# Mobile-friendly Hotstrings + Hotkeys — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a mobile-friendly view for `/hotstrings` and `/hotkeys` that triggers under 960px width, using a compact 2-column list with expandable rows + a full-screen `MudDialog` for create/edit + a FAB for add + a select-mode toggle for bulk delete. Desktop (md+) keeps the existing `MudDataGrid` inline-edit experience unchanged.

**Architecture:** Each page renders two plain branch containers, `.desktop-branch` and `.mobile-branch`, with visibility gated by the page's scoped `.razor.css` at `959.95px`. Existing data-loading logic (`LoadServerData`) is split into a thin grid callback + a reusable `LoadAsync` method that the mobile branch also calls. Two new components per page: a full-screen edit/create dialog (`*EditDialog.razor`) and a mobile list component (`*MobileList.razor`). No backend or API client changes.

**Tech Stack:** Blazor WebAssembly (.NET 10), MudBlazor 9.3.0, FluentValidation via existing edit models, xUnit + bUnit + FluentAssertions + NSubstitute for unit tests, Playwright + WebApplicationFactory (`StackFixture`) for E2E.

**Source spec:** `docs/superpowers/specs/2026-05-24-mobile-hotstrings-hotkeys-design.md`

**Branch:** `feature/032-mobile-hotstrings-hotkeys` (already created).

---

## Defaults for spec's deferred questions

The implementer picks these defaults and flags them in the PR. The reviewer can push back per item.

| Question | Default |
|---|---|
| Pager UI | `MudPagination` |
| Page size on mobile | 10 (same as desktop default) |
| Hotkeys primary-line truncation | Description ellipsizes first; modifier+key stays intact |
| FAB scroll behavior | Always visible |
| Select-mode action bar | Sticky bottom |

---

## File map

**Create:**
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor`
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs`
- `tests/AHKFlowApp.E2E.Tests/HotstringsMobileFlowTests.cs`
- `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`

**Modify:**
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — split into desktop + mobile branches; extract `LoadAsync`; add dialog-opening helpers.
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` — same treatment.
- `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` — add note about the breakpoint pattern.

**Reuse unchanged:** `Validation/HotstringEditModel.cs`, `Validation/HotkeyEditModel.cs`, `Services/IHotstringsApiClient`, `Services/IHotkeysApiClient`, `Services/IProfilesApiClient`, `Services/ICategoriesApiClient`, all DTOs.

---

## Task 1: HotstringEditDialog — render in create mode

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringEditDialogTests : BunitContext
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringEditDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void CreateMode_RendersEmptyFields()
    {
        Render<MudDialogProvider>();

        IDialogReference reference = default!;
        InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            reference = await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        }).GetAwaiter().GetResult();

        WaitForAssertion(() => Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be(""));
        Find("input[data-test=\"replacement-input\"]").GetAttribute("value").Should().Be("");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringEditDialogTests" --no-restore`

Expected: FAIL — `HotstringEditDialog` type does not exist.

- [ ] **Step 3: Create the dialog component**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor

<MudDialog Class="hotstring-edit-dialog">
    <TitleContent>
        <MudStack Row="true" AlignItems="AlignItems.Center" Justify="Justify.SpaceBetween" Class="flex-grow-1">
            <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.ArrowBack" OnClick="Cancel" />
            <MudText Typo="Typo.h6">@(Item.Id is null ? "New hotstring" : "Edit hotstring")</MudText>
            <MudButton Class="commit-edit" Color="Color.Primary" Variant="Variant.Filled" OnClick="SaveAsync">Save</MudButton>
        </MudStack>
    </TitleContent>
    <DialogContent>
        <MudStack Spacing="3" Class="pa-2">
            <MudTextField T="string" Label="Trigger" @bind-Value="Item.Trigger"
                          Required="true" RequiredError="Trigger is required" MaxLength="50"
                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "trigger-input" })" />
            <MudTextField T="string" Label="Replacement" @bind-Value="Item.Replacement"
                          Lines="3" Required="true" RequiredError="Replacement is required" MaxLength="4000"
                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "replacement-input" })" />
            <MudTextField T="string" Label="Description" @bind-Value="Item.Description"
                          MaxLength="200"
                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "description-input" })" />

            <MudCheckBox T="bool" @bind-Value="Item.AppliesToAllProfiles" Label="Apply to all profiles"
                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "applies-to-all-checkbox" })" />
            @if (!Item.AppliesToAllProfiles)
            {
                <MudSelect T="Guid" MultiSelection="true" Label="Profiles"
                           SelectedValues="Item.ProfileIds"
                           SelectedValuesChanged="ids => Item.ProfileIds = [.. ids]"
                           ToStringFunc="@(id => Profiles.FirstOrDefault(p => p.Id == id)?.Name ?? id.ToString())"
                           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-select" })">
                    @foreach (ProfileDto p in Profiles)
                    {
                        <MudSelectItem T="Guid" Value="@p.Id">@p.Name</MudSelectItem>
                    }
                </MudSelect>
            }

            <MudCheckBox T="bool" @bind-Value="Item.IsEndingCharacterRequired" Label="Ending character required" />
            <MudCheckBox T="bool" @bind-Value="Item.IsTriggerInsideWord" Label="Trigger inside word" />

            <MudSelect T="Guid" MultiSelection="true" Label="Categories"
                       SelectedValues="Item.CategoryIds"
                       SelectedValuesChanged="ids => Item.CategoryIds = [.. ids]"
                       ToStringFunc="@(id => Categories.FirstOrDefault(c => c.Id == id)?.Name ?? id.ToString())"
                       UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "category-select" })">
                @foreach (CategoryDto c in Categories)
                {
                    <MudSelectItem T="Guid" Value="@c.Id">@c.Name</MudSelectItem>
                }
            </MudSelect>

            @if (_error is not null)
            {
                <MudAlert Severity="Severity.Error">@_error</MudAlert>
            }
        </MudStack>
    </DialogContent>
</MudDialog>

@code {
    [CascadingParameter] private IMudDialogInstance Dialog { get; set; } = default!;
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;

    [Parameter] public HotstringEditModel Item { get; set; } = new();
    [Parameter] public IReadOnlyList<ProfileDto> Profiles { get; set; } = [];
    [Parameter] public IReadOnlyList<CategoryDto> Categories { get; set; } = [];

    private string? _error;

    private void Cancel() => Dialog.Cancel();

    private async Task SaveAsync()
    {
        _error = null;
        if (string.IsNullOrWhiteSpace(Item.Trigger) || string.IsNullOrWhiteSpace(Item.Replacement))
        {
            _error = "Trigger and Replacement are required.";
            return;
        }

        ApiResult<HotstringDto> result = Item.Id is null
            ? await Api.CreateAsync(Item.ToCreateDto(), CancellationToken.None)
            : await Api.UpdateAsync(Item.Id.Value, Item.ToUpdateDto(), CancellationToken.None);

        if (!result.IsSuccess)
        {
            _error = ApiErrorMessageFactory.Build(result.Status, result.Problem);
            return;
        }

        Dialog.Close(DialogResult.Ok(result.Value));
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringEditDialogTests" --no-restore`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs
git commit -m "feat: hotstring edit dialog (create mode)"
```

---

## Task 2: HotstringEditDialog — edit mode + save calls API

**Files:**
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`

- [ ] **Step 1: Add the failing tests**

Append to the test class:

```csharp
[Fact]
public void EditMode_PrefillsFieldsFromItem()
{
    HotstringEditModel item = new()
    {
        Id = Guid.NewGuid(),
        Trigger = "btw",
        Replacement = "by the way",
        Description = "polite filler",
    };

    Render<MudDialogProvider>();
    InvokeAsync(async () =>
    {
        IDialogService dialogService = Services.GetRequiredService<IDialogService>();
        await dialogService.ShowAsync<HotstringEditDialog>("Edit",
            new DialogParameters
            {
                [nameof(HotstringEditDialog.Item)] = item,
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            },
            new DialogOptions { FullScreen = true, CloseButton = false });
    }).GetAwaiter().GetResult();

    WaitForAssertion(() => Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be("btw"));
    Find("input[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way");
}

[Fact]
public async Task SaveInCreateMode_CallsCreateAsync()
{
    HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
    _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Ok(created));

    Render<MudDialogProvider>();
    await InvokeAsync(async () =>
    {
        IDialogService dialogService = Services.GetRequiredService<IDialogService>();
        await dialogService.ShowAsync<HotstringEditDialog>("New",
            new DialogParameters
            {
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            },
            new DialogOptions { FullScreen = true, CloseButton = false });
    });

    WaitForAssertion(() => Find("input[data-test=\"trigger-input\"]"));
    Find("input[data-test=\"trigger-input\"]").Input("btw");
    Find("input[data-test=\"replacement-input\"]").Input("by the way");
    Find("button.commit-edit").Click();

    WaitForAssertion(() => _api.Received(1).CreateAsync(
        Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
        Arg.Any<CancellationToken>()));
}

[Fact]
public async Task SaveInEditMode_CallsUpdateAsync()
{
    HotstringEditModel item = new()
    {
        Id = Guid.NewGuid(),
        Trigger = "btw",
        Replacement = "by the way",
    };
    _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Ok(
            new HotstringDto(item.Id.Value, [], true, "btw", "by the way!", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

    Render<MudDialogProvider>();
    await InvokeAsync(async () =>
    {
        IDialogService dialogService = Services.GetRequiredService<IDialogService>();
        await dialogService.ShowAsync<HotstringEditDialog>("Edit",
            new DialogParameters
            {
                [nameof(HotstringEditDialog.Item)] = item,
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            },
            new DialogOptions { FullScreen = true, CloseButton = false });
    });

    WaitForAssertion(() => Find("input[data-test=\"replacement-input\"]"));
    Find("input[data-test=\"replacement-input\"]").Input("by the way!");
    Find("button.commit-edit").Click();

    WaitForAssertion(() => _api.Received(1).UpdateAsync(
        item.Id.Value,
        Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"),
        Arg.Any<CancellationToken>()));
}
```

- [ ] **Step 2: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringEditDialogTests" --no-restore`

Expected: PASS (no code changes needed — Task 1 already supports both modes via `Item.Id`).

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs
git commit -m "test: hotstring edit dialog covers create + edit"
```

---

## Task 3: HotstringMobileList — collapsed list + Edit/Delete events

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs`

- [ ] **Step 1: Write the failing test**

```csharp
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringMobileListTests : BunitContext
{
    public HotstringMobileListTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private static HotstringEditModel Item(string trigger = "btw", string replacement = "by the way") =>
        new() { Id = Guid.NewGuid(), Trigger = trigger, Replacement = replacement };

    [Fact]
    public void Renders_TriggerAndReplacement_PerRow()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [Item("btw", "by the way"), Item("addr", "123 Main St")])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("btw");
        cut.Markup.Should().Contain("by the way");
        cut.Markup.Should().Contain("addr");
    }

    [Fact]
    public async Task EditButton_RaisesOnEdit()
    {
        HotstringEditModel item = Item();
        HotstringEditModel? edited = null;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnEdit, EventCallback.Factory.Create<HotstringEditModel>(this, m => edited = m)));

        // Expand the row first
        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        await cut.InvokeAsync(() => cut.Find("button.start-edit").Click());

        edited.Should().Be(item);
    }

    [Fact]
    public async Task DeleteButton_RaisesOnDelete()
    {
        HotstringEditModel item = Item();
        HotstringEditModel? deleted = null;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnDelete, EventCallback.Factory.Create<HotstringEditModel>(this, m => deleted = m)));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        await cut.InvokeAsync(() => cut.Find("button.delete").Click());

        deleted.Should().Be(item);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringMobileListTests" --no-restore`

Expected: FAIL — `HotstringMobileList` does not exist.

- [ ] **Step 3: Create the component**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor

<MudStack Spacing="0">
    @if (Items.Count == 0)
    {
        <MudText Class="pa-4 text-center" Typo="Typo.body2">No hotstrings yet.</MudText>
    }

    <table class="mobile-list">
        <thead>
            <tr class="mobile-header">
                <th>Trigger</th>
                <th>Replacement</th>
                <th></th>
            </tr>
        </thead>
        <tbody>
            @foreach (HotstringEditModel item in Items)
            {
                bool expanded = _expandedId == item.Id;
                <tr class="mobile-row" @onclick="() => ToggleExpand(item)">
                    <td class="trigger-cell"><code>@item.Trigger</code></td>
                    <td class="replacement-cell">@item.Replacement</td>
                    <td class="chevron-cell">@(expanded ? "▾" : "▸")</td>
                </tr>
                @if (expanded)
                {
                    <tr class="mobile-row-expanded">
                        <td colspan="3">
                            <MudStack Spacing="1" Class="pa-3">
                                @if (!string.IsNullOrWhiteSpace(item.Description))
                                {
                                    <MudText Typo="Typo.body2"><strong>Description:</strong> @item.Description</MudText>
                                }
                                <MudText Typo="Typo.body2"><strong>Profiles:</strong>
                                    @if (item.AppliesToAllProfiles)
                                    {
                                        <MudChip T="string" Size="Size.Small" Color="Color.Info">Any</MudChip>
                                    }
                                    else
                                    {
                                        @foreach (Guid pid in item.ProfileIds)
                                        {
                                            string name = Profiles.FirstOrDefault(p => p.Id == pid)?.Name ?? pid.ToString()[..8];
                                            <MudChip T="string" Size="Size.Small">@name</MudChip>
                                        }
                                    }
                                </MudText>
                                <MudText Typo="Typo.body2"><strong>Categories:</strong>
                                    @foreach (Guid cid in item.CategoryIds)
                                    {
                                        string name = Categories.FirstOrDefault(c => c.Id == cid)?.Name ?? cid.ToString()[..8];
                                        <MudChip T="string" Size="Size.Small">@name</MudChip>
                                    }
                                </MudText>
                                <MudText Typo="Typo.body2">
                                    <strong>End-char:</strong> @(item.IsEndingCharacterRequired ? "✓" : "✗") &nbsp;
                                    <strong>In-word:</strong> @(item.IsTriggerInsideWord ? "✓" : "✗")
                                </MudText>
                                <MudStack Row="true" Spacing="2" Class="mt-2">
                                    <MudButton Class="start-edit" Variant="Variant.Filled" Color="Color.Primary"
                                               StartIcon="@Icons.Material.Filled.Edit"
                                               OnClick="@(async () => await OnEdit.InvokeAsync(item))">Edit</MudButton>
                                    <MudButton Class="delete" Variant="Variant.Filled" Color="Color.Error"
                                               StartIcon="@Icons.Material.Filled.Delete"
                                               OnClick="@(async () => await OnDelete.InvokeAsync(item))">Delete</MudButton>
                                </MudStack>
                            </MudStack>
                        </td>
                    </tr>
                }
            }
        </tbody>
    </table>
</MudStack>

@code {
    [Parameter] public IReadOnlyList<HotstringEditModel> Items { get; set; } = [];
    [Parameter] public IReadOnlyList<ProfileDto> Profiles { get; set; } = [];
    [Parameter] public IReadOnlyList<CategoryDto> Categories { get; set; } = [];
    [Parameter] public EventCallback<HotstringEditModel> OnEdit { get; set; }
    [Parameter] public EventCallback<HotstringEditModel> OnDelete { get; set; }

    private Guid? _expandedId;

    private void ToggleExpand(HotstringEditModel item)
    {
        _expandedId = _expandedId == item.Id ? null : item.Id;
    }
}
```

Add minimal styles. Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor.css`:

```css
.mobile-list {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.9rem;
}

.mobile-list .mobile-header {
    background: var(--mud-palette-background-grey);
}

.mobile-list .mobile-header th {
    text-align: left;
    padding: 6px 12px;
    font-weight: 500;
    font-size: 0.75rem;
    color: var(--mud-palette-text-secondary);
}

.mobile-list .mobile-row {
    border-top: 1px solid var(--mud-palette-divider);
    cursor: pointer;
}

.mobile-list .mobile-row td {
    padding: 10px 12px;
    vertical-align: middle;
}

.mobile-list .trigger-cell {
    width: 30%;
    white-space: nowrap;
}

.mobile-list .replacement-cell {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 0;
}

.mobile-list .chevron-cell {
    width: 24px;
    text-align: right;
    color: var(--mud-palette-text-secondary);
}

.mobile-list .mobile-row-expanded {
    background: var(--mud-palette-background-grey);
}
```

- [ ] **Step 4: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringMobileListTests" --no-restore`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor.css tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs
git commit -m "feat: hotstring mobile list (collapsed + expand + edit/delete)"
```

---

## Task 4: HotstringMobileList — select mode + bulk delete

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs`

- [ ] **Step 1: Add the failing tests**

Append to `HotstringMobileListTests.cs`:

```csharp
[Fact]
public async Task SelectModeToggle_RevealsCheckboxes()
{
    IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
        .Add(c => c.Items, [Item()])
        .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
        .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

    cut.FindAll("input.row-checkbox").Should().BeEmpty();

    await cut.InvokeAsync(() => cut.Find("button.toggle-select-mode").Click());

    cut.WaitForAssertion(() => cut.FindAll("input.row-checkbox").Should().NotBeEmpty());
}

[Fact]
public async Task BulkDelete_RaisesOnBulkDelete_WithSelectedIds()
{
    HotstringEditModel a = Item("a", "x");
    HotstringEditModel b = Item("b", "y");
    IReadOnlyList<Guid>? deletedIds = null;

    IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
        .Add(c => c.Items, [a, b])
        .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
        .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
        .Add(c => c.OnBulkDelete, EventCallback.Factory.Create<IReadOnlyList<Guid>>(this, ids => deletedIds = ids)));

    await cut.InvokeAsync(() => cut.Find("button.toggle-select-mode").Click());

    cut.WaitForAssertion(() => cut.FindAll("input.row-checkbox").Count.Should().Be(2));
    cut.FindAll("input.row-checkbox")[0].Change(true);
    cut.FindAll("input.row-checkbox")[1].Change(true);

    await cut.InvokeAsync(() => cut.Find("button.bulk-delete-hotstrings").Click());

    deletedIds.Should().BeEquivalentTo(new[] { a.Id!.Value, b.Id!.Value });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringMobileListTests" --no-restore`

Expected: FAIL — `button.toggle-select-mode` and `button.bulk-delete-hotstrings` not found.

- [ ] **Step 3: Add select-mode to the component**

Replace `HotstringMobileList.razor` content with:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor

<MudStack Spacing="0">
    <MudStack Row="true" AlignItems="AlignItems.Center" Class="pa-2">
        <MudIconButton Class="toggle-select-mode"
                       Icon="@(_selectMode ? Icons.Material.Filled.Close : Icons.Material.Filled.CheckBox)"
                       OnClick="ToggleSelectMode" />
        <MudText Typo="Typo.subtitle2">@(_selectMode ? $"{_selectedIds.Count} selected" : "")</MudText>
    </MudStack>

    @if (Items.Count == 0)
    {
        <MudText Class="pa-4 text-center" Typo="Typo.body2">No hotstrings yet.</MudText>
    }

    <table class="mobile-list">
        <thead>
            <tr class="mobile-header">
                @if (_selectMode)
                {
                    <th style="width:36px"></th>
                }
                <th>Trigger</th>
                <th>Replacement</th>
                <th></th>
            </tr>
        </thead>
        <tbody>
            @foreach (HotstringEditModel item in Items)
            {
                bool expanded = !_selectMode && _expandedId == item.Id;
                <tr class="mobile-row" @onclick="() => OnRowClick(item)">
                    @if (_selectMode)
                    {
                        <td class="checkbox-cell" @onclick:stopPropagation="true">
                            <input type="checkbox" class="row-checkbox"
                                   checked="@(_selectedIds.Contains(item.Id!.Value))"
                                   @onchange="e => OnRowCheckboxChanged(item, (bool)e.Value!)" />
                        </td>
                    }
                    <td class="trigger-cell"><code>@item.Trigger</code></td>
                    <td class="replacement-cell">@item.Replacement</td>
                    <td class="chevron-cell">@(expanded ? "▾" : "▸")</td>
                </tr>
                @if (expanded)
                {
                    <tr class="mobile-row-expanded">
                        <td colspan="3">
                            <MudStack Spacing="1" Class="pa-3">
                                @if (!string.IsNullOrWhiteSpace(item.Description))
                                {
                                    <MudText Typo="Typo.body2"><strong>Description:</strong> @item.Description</MudText>
                                }
                                <MudText Typo="Typo.body2"><strong>Profiles:</strong>
                                    @if (item.AppliesToAllProfiles)
                                    {
                                        <MudChip T="string" Size="Size.Small" Color="Color.Info">Any</MudChip>
                                    }
                                    else
                                    {
                                        @foreach (Guid pid in item.ProfileIds)
                                        {
                                            string name = Profiles.FirstOrDefault(p => p.Id == pid)?.Name ?? pid.ToString()[..8];
                                            <MudChip T="string" Size="Size.Small">@name</MudChip>
                                        }
                                    }
                                </MudText>
                                <MudText Typo="Typo.body2"><strong>Categories:</strong>
                                    @foreach (Guid cid in item.CategoryIds)
                                    {
                                        string name = Categories.FirstOrDefault(c => c.Id == cid)?.Name ?? cid.ToString()[..8];
                                        <MudChip T="string" Size="Size.Small">@name</MudChip>
                                    }
                                </MudText>
                                <MudText Typo="Typo.body2">
                                    <strong>End-char:</strong> @(item.IsEndingCharacterRequired ? "✓" : "✗") &nbsp;
                                    <strong>In-word:</strong> @(item.IsTriggerInsideWord ? "✓" : "✗")
                                </MudText>
                                <MudStack Row="true" Spacing="2" Class="mt-2">
                                    <MudButton Class="start-edit" Variant="Variant.Filled" Color="Color.Primary"
                                               StartIcon="@Icons.Material.Filled.Edit"
                                               OnClick="@(async () => await OnEdit.InvokeAsync(item))">Edit</MudButton>
                                    <MudButton Class="delete" Variant="Variant.Filled" Color="Color.Error"
                                               StartIcon="@Icons.Material.Filled.Delete"
                                               OnClick="@(async () => await OnDelete.InvokeAsync(item))">Delete</MudButton>
                                </MudStack>
                            </MudStack>
                        </td>
                    </tr>
                }
            }
        </tbody>
    </table>

    @if (_selectMode && _selectedIds.Count > 0)
    {
        <div class="select-action-bar">
            <MudButton Variant="Variant.Text" OnClick="ToggleSelectMode">Cancel</MudButton>
            <MudButton Class="bulk-delete-hotstrings" Variant="Variant.Filled" Color="Color.Error"
                       StartIcon="@Icons.Material.Filled.DeleteSweep"
                       OnClick="RaiseBulkDelete">Delete @_selectedIds.Count</MudButton>
        </div>
    }
</MudStack>

@code {
    [Parameter] public IReadOnlyList<HotstringEditModel> Items { get; set; } = [];
    [Parameter] public IReadOnlyList<ProfileDto> Profiles { get; set; } = [];
    [Parameter] public IReadOnlyList<CategoryDto> Categories { get; set; } = [];
    [Parameter] public EventCallback<HotstringEditModel> OnEdit { get; set; }
    [Parameter] public EventCallback<HotstringEditModel> OnDelete { get; set; }
    [Parameter] public EventCallback<IReadOnlyList<Guid>> OnBulkDelete { get; set; }

    private Guid? _expandedId;
    private bool _selectMode;
    private readonly HashSet<Guid> _selectedIds = [];

    private void OnRowClick(HotstringEditModel item)
    {
        if (_selectMode)
        {
            if (item.Id is { } id) ToggleSelected(id);
        }
        else
        {
            _expandedId = _expandedId == item.Id ? null : item.Id;
        }
    }

    private void OnRowCheckboxChanged(HotstringEditModel item, bool isChecked)
    {
        if (item.Id is not { } id) return;
        if (isChecked) _selectedIds.Add(id);
        else _selectedIds.Remove(id);
    }

    private void ToggleSelected(Guid id)
    {
        if (!_selectedIds.Add(id)) _selectedIds.Remove(id);
    }

    private void ToggleSelectMode()
    {
        _selectMode = !_selectMode;
        _selectedIds.Clear();
        _expandedId = null;
    }

    private async Task RaiseBulkDelete()
    {
        IReadOnlyList<Guid> ids = [.. _selectedIds];
        await OnBulkDelete.InvokeAsync(ids);
        _selectMode = false;
        _selectedIds.Clear();
    }
}
```

Append to `HotstringMobileList.razor.css`:

```css
.mobile-list .checkbox-cell {
    width: 36px;
    text-align: center;
}

.select-action-bar {
    position: sticky;
    bottom: 0;
    background: var(--mud-palette-surface);
    border-top: 1px solid var(--mud-palette-divider);
    padding: 8px 12px;
    display: flex;
    justify-content: space-between;
    z-index: 10;
}
```

- [ ] **Step 4: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringMobileListTests" --no-restore`

Expected: PASS for all four tests.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor.css tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs
git commit -m "feat: select mode + bulk delete on hotstring mobile list"
```

---

## Task 5: Integrate mobile branch into Hotstrings.razor

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

- [ ] **Step 1: Add the failing test**

Append to `HotstringsPageTests.cs`:

```csharp
[Fact]
public void Page_RendersCssGatedDesktopAndMobileBranches()
{
    StubList(Page());

    IRenderedComponent<Hotstrings> cut = RenderPage();

    cut.WaitForAssertion(() =>
    {
        cut.Find(".desktop-branch button.add-hotstring").Should().NotBeNull();
        cut.Find(".mobile-branch button.add-hotstring-fab").Should().NotBeNull();
    });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotstringsPageTests.Page_RendersCssGatedDesktopAndMobileBranches" --no-restore`

Expected: FAIL — `.desktop-branch` / `.mobile-branch` / `add-hotstring-fab` not found.

- [ ] **Step 3: Wrap existing markup + add mobile branch**

In `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`, after line 11 (`<MudText Typo="Typo.h4" ...>Hotstrings</MudText>`), wrap the existing `<MudPaper Class="pa-4">...</MudPaper>` (lines 13-175) in:

```razor
<div class="desktop-branch">
    <!-- existing MudPaper + MudDataGrid block unchanged -->
</div>

<div class="mobile-branch">
    <MudPaper Class="pa-2" Style="position:relative;min-height:80vh;">
        <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="1" Class="mb-2">
            <MudIconButton Class="reload-hotstrings" Icon="@Icons.Material.Filled.Refresh"
                           OnClick="ReloadAsync" Disabled="@(!_isAuthenticated || _loading)" />
            <MudSpacer />
        </MudStack>

            <MudTextField T="string" @bind-Value="_search" @bind-Value:after="OnSearchChangedAsync"
                          DebounceInterval="300"
                          Placeholder="Search hotstrings"
                          Adornment="Adornment.Start"
                          AdornmentIcon="@Icons.Material.Filled.Search"
                          Class="search-hotstrings mb-2"
                          FullWidth="true" Immediate="true" />

            @if (_categories.Count > 0)
            {
                <div class="chip-strip mb-2" style="overflow-x:auto;white-space:nowrap;">
                    <MudChipSet T="Guid" SelectionMode="SelectionMode.MultiSelection"
                                SelectedValues="_selectedCategoryIds"
                                SelectedValuesChanged="OnCategoryFilterChangedAsync">
                        @foreach (CategoryDto c in _categories)
                        {
                            <MudChip T="Guid" Value="@c.Id" Variant="Variant.Outlined">@c.Name</MudChip>
                        }
                    </MudChipSet>
                </div>
            }

            @if (_loadError is not null)
            {
                <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
            }

            <HotstringMobileList Items="_mobileItems"
                                 Profiles="_profiles"
                                 Categories="_categories"
                                 OnEdit="OpenEditDialogAsync"
                                 OnDelete="DeleteAsync"
                                 OnBulkDelete="MobileBulkDeleteAsync" />

            <MudPagination Class="mt-2" Count="_mobileTotalPages" Selected="_mobilePage"
                           SelectedChanged="OnMobilePageChangedAsync" />

            <MudFab Class="add-hotstring-fab" Color="Color.Primary"
                    StartIcon="@Icons.Material.Filled.Add"
                    Style="position:fixed;right:16px;bottom:16px;z-index:100;"
                    OnClick="OpenCreateDialogAsync" />
    </MudPaper>
</div>
```

Add to `@code { ... }` block (after existing fields):

```csharp
private IReadOnlyList<HotstringEditModel> _mobileItems = [];
private int _mobilePage = 1;
private int _mobilePageSize = 10;
private int _mobileTotalPages;
```

Extract a shared loader. After `LoadServerData` add:

```csharp
private async Task LoadMobileAsync()
{
    _loading = true;
    _loadError = null;

    ApiResult<PagedList<HotstringDto>> result = await Api.ListAsync(
        new HotstringListRequest(
            Page: _mobilePage,
            PageSize: _mobilePageSize,
            Search: string.IsNullOrWhiteSpace(_search) ? null : _search,
            CategoryIds: _selectedCategoryIds.Count > 0 ? _selectedCategoryIds : null),
        _cts.Token);

    _loading = false;

    if (!result.IsSuccess)
    {
        _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        _mobileItems = [];
        _mobileTotalPages = 0;
        return;
    }

    _mobileItems = [.. result.Value!.Items.Select(HotstringEditModel.FromDto)];
    _mobileTotalPages = (int)Math.Ceiling((double)result.Value.TotalCount / _mobilePageSize);
}

private async Task OnMobilePageChangedAsync(int page)
{
    _mobilePage = page;
    await LoadMobileAsync();
}

private async Task OpenCreateDialogAsync()
{
    DialogParameters parameters = new()
    {
        [nameof(HotstringEditDialog.Item)] = new HotstringEditModel(),
        [nameof(HotstringEditDialog.Profiles)] = _profiles,
        [nameof(HotstringEditDialog.Categories)] = _categories,
    };

    IDialogReference dialog = await DialogService.ShowAsync<HotstringEditDialog>(
        "New hotstring", parameters,
        new DialogOptions { FullScreen = true, CloseButton = false });

    DialogResult? result = await dialog.Result;
    if (result?.Canceled == false)
    {
        Snackbar.Add("Hotstring created.", Severity.Success);
        await ReloadAllAsync();
    }
}

private async Task OpenEditDialogAsync(HotstringEditModel item)
{
    DialogParameters parameters = new()
    {
        [nameof(HotstringEditDialog.Item)] = HotstringEditModel.FromDto(new HotstringDto(
            item.Id!.Value, [.. item.ProfileIds], item.AppliesToAllProfiles,
            item.Trigger, item.Replacement, item.Description,
            item.IsEndingCharacterRequired, item.IsTriggerInsideWord,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)),
        [nameof(HotstringEditDialog.Profiles)] = _profiles,
        [nameof(HotstringEditDialog.Categories)] = _categories,
    };

    IDialogReference dialog = await DialogService.ShowAsync<HotstringEditDialog>(
        "Edit hotstring", parameters,
        new DialogOptions { FullScreen = true, CloseButton = false });

    DialogResult? result = await dialog.Result;
    if (result?.Canceled == false)
    {
        Snackbar.Add("Hotstring updated.", Severity.Success);
        await ReloadAllAsync();
    }
}

private async Task MobileBulkDeleteAsync(IReadOnlyList<Guid> ids)
{
    if (ids.Count == 0) return;

    bool? confirm = await DialogService.ShowMessageBoxAsync(
        title: "Delete hotstrings?",
        message: $"Delete {ids.Count} hotstring(s)? This cannot be undone.",
        yesText: "Delete", cancelText: "Cancel");
    if (confirm != true) return;

    ApiResult<BulkDeleteResultDto> result = await Api.BulkDeleteAsync(ids, _cts.Token);
    if (result.IsSuccess)
    {
        Snackbar.Add($"Deleted {result.Value!.DeletedCount} hotstring(s).", Severity.Success);
        await ReloadAllAsync();
    }
    else
    {
        Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }
}

private async Task ReloadAllAsync()
{
    if (_grid is not null) await _grid.ReloadServerData();
    await LoadMobileAsync();
}
```

Wire `OnInitializedAsync` to also call `LoadMobileAsync()`. After the existing `if (_isAuthenticated)` block:

```csharp
        if (_isAuthenticated)
            await LoadMobileAsync();
```

Update `OnSearchChangedAsync`, `OnCategoryFilterChangedAsync`, and `ReloadAsync` to also reload mobile data — wrap their bodies:

```csharp
    private async Task ReloadAsync()
    {
        if (_grid is not null) await _grid.ReloadServerData();
        await LoadMobileAsync();
    }

    private async Task OnSearchChangedAsync()
    {
        if (_grid is not null) await _grid.ReloadServerData();
        _mobilePage = 1;
        await LoadMobileAsync();
    }

    private async Task OnCategoryFilterChangedAsync(IReadOnlyCollection<Guid> ids)
    {
        _selectedCategoryIds = [.. ids];
        if (_grid is not null) await _grid.ReloadServerData();
        _mobilePage = 1;
        await LoadMobileAsync();
    }
```

Update single-row `DeleteAsync` to call `ReloadAllAsync()` instead of `_grid.ReloadServerData()`.

- [ ] **Step 4: Run all tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --no-restore`

Expected: PASS for all existing tests + the new branches test.

- [ ] **Step 5: Build the whole solution**

Run: `dotnet build --no-restore`

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs
git commit -m "feat: integrate mobile branch into hotstrings page"
```

---

## Task 6: E2E test for mobile hotstrings flow

**Files:**
- Create: `tests/AHKFlowApp.E2E.Tests/HotstringsMobileFlowTests.cs`

- [ ] **Step 1: Write the failing test**

```csharp
using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

public sealed class HotstringsMobileFlowTests(StackFixture fixture) : IClassFixture<StackFixture>
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    [Fact]
    public async Task CreateEditDelete_OnPhoneViewport_UsesFabAndFullScreenDialog()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");

        // Add via FAB
        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", "mob");
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "mobile by the way");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"mob\")");

        // Expand row, click edit, change, save
        await page.ClickAsync(".mobile-row:has-text(\"mob\")");
        await page.WaitForSelectorAsync(".mobile-row-expanded button.start-edit");
        await page.ClickAsync(".mobile-row-expanded button.start-edit");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "edited!");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring updated.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"edited!\")");

        // Delete via expanded row
        await page.ClickAsync(".mobile-row:has-text(\"mob\")");
        await page.WaitForSelectorAsync(".mobile-row-expanded button.delete");
        await page.ClickAsync(".mobile-row-expanded button.delete");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.GetByRole(AriaRole.Button, new() { Name = "Delete" }).Last.ClickAsync();

        await page.WaitForSelectorAsync("text=Hotstring deleted.");
    }

    [Fact]
    public async Task BulkDelete_OnPhoneViewport_UsesSelectMode()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        // Create two rows via FAB
        foreach (string trig in new[] { "bk1", "bk2" })
        {
            await page.ClickAsync("button.add-hotstring-fab");
            await page.WaitForSelectorAsync(".hotstring-edit-dialog");
            await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", trig);
            await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "x");
            await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");
            await page.WaitForSelectorAsync($".mobile-row:has-text(\"{trig}\")");
        }

        // Enter select mode + select both
        await page.ClickAsync("button.toggle-select-mode");
        await page.WaitForSelectorAsync("input.row-checkbox");
        ILocator boxes = page.Locator("input.row-checkbox");
        int count = await boxes.CountAsync();
        for (int i = 0; i < count; i++)
            await boxes.Nth(i).CheckAsync();

        await page.ClickAsync("button.bulk-delete-hotstrings");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.GetByRole(AriaRole.Button, new() { Name = "Delete" }).Last.ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotstring");
    }
}
```

- [ ] **Step 2: Publish Blazor for the SpaHost fixture**

Run: `dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c Release --no-restore`

Expected: Publish succeeds. `StackFixture` requires the published wwwroot at `bin/Release/net10.0/publish/wwwroot`.

- [ ] **Step 3: Run the new E2E test**

Run: `dotnet test tests/AHKFlowApp.E2E.Tests --filter "HotstringsMobileFlowTests" --no-restore`

Expected: PASS for both tests.

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.E2E.Tests/HotstringsMobileFlowTests.cs
git commit -m "test: e2e mobile hotstrings flow (fab + dialog + select mode)"
```

---

## Task 7: HotkeyEditDialog — mirror Task 1+2 for hotkeys

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`

Same shape as the hotstring dialog with these field differences:

| Hotstring dialog field | Hotkey dialog field |
|---|---|
| Trigger (text) | Key (text, max 20) + modifier checkboxes Ctrl/Alt/Shift/Win |
| Replacement (multiline text) | Parameters (multiline text, max 4000) |
| Description | Description (required, max 200) |
| IsEndingCharacterRequired | Action (`MudSelect<HotkeyAction>` with `Send` / `Run`) |
| IsTriggerInsideWord | (none) |
| Profiles, Categories | Profiles, Categories — identical |

API methods to call: `IHotkeysApiClient.CreateAsync(CreateHotkeyDto)` / `UpdateAsync(Guid, UpdateHotkeyDto)`. Reuse `HotkeyEditModel.ToCreateDto()` / `ToUpdateDto()`.

`data-test` attributes (match existing `Hotkeys.razor`): `description-input`, `key-input`, `ctrl-checkbox`, `alt-checkbox`, `shift-checkbox`, `win-checkbox`, `action-select`, `parameters-input`, `applies-to-all-checkbox`, `profile-select`, `category-select`.

CSS class on `<MudDialog>`: `hotkey-edit-dialog`.

Required fields validated inside `SaveAsync`: Description and Key.

- [ ] **Step 1: Write the failing tests** — mirror Task 1 Step 1 and Task 2 Step 1, substituting Hotkey types and field names. The three tests: `CreateMode_RendersEmptyFields`, `SaveInCreateMode_CallsCreateAsync`, `SaveInEditMode_CallsUpdateAsync`. Replace `IHotstringsApiClient` with `IHotkeysApiClient`. `data-test="key-input"` in place of `trigger-input`.

- [ ] **Step 2: Run tests — expect failures**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotkeyEditDialogTests" --no-restore`

Expected: FAIL.

- [ ] **Step 3: Create the dialog** — adapt Task 1 Step 3's razor file with the field substitutions above. Key fields block:

```razor
<MudTextField T="string" Label="Description" @bind-Value="Item.Description"
              Required="true" RequiredError="Description is required" MaxLength="200"
              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "description-input" })" />
<MudTextField T="string" Label="Key" @bind-Value="Item.Key"
              Required="true" RequiredError="Key is required" MaxLength="20"
              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "key-input" })" />
<MudStack Row="true" Spacing="2">
    <MudCheckBox T="bool" @bind-Value="Item.Ctrl" Label="Ctrl"
                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "ctrl-checkbox" })" />
    <MudCheckBox T="bool" @bind-Value="Item.Alt" Label="Alt"
                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "alt-checkbox" })" />
    <MudCheckBox T="bool" @bind-Value="Item.Shift" Label="Shift"
                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "shift-checkbox" })" />
    <MudCheckBox T="bool" @bind-Value="Item.Win" Label="Win"
                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "win-checkbox" })" />
</MudStack>
<MudSelect T="HotkeyAction" @bind-Value="Item.Action" Label="Action"
           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-select" })">
    <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Send">Send</MudSelectItem>
    <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Run">Run</MudSelectItem>
</MudSelect>
<MudTextField T="string" Label="Parameters" @bind-Value="Item.Parameters"
              Lines="3" MaxLength="4000"
              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "parameters-input" })" />
```

Use the same Profiles, Categories, error alert, and Save/Cancel header from Task 1.

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotkeyEditDialogTests" --no-restore`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs
git commit -m "feat: hotkey edit dialog (create + edit)"
```

---

## Task 8: HotkeyMobileList — mirror Tasks 3 + 4 for hotkeys

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor.css`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs`

Identical shape to `HotstringMobileList`, with these row-display differences:

**Primary line:**
- Trigger cell: format combo as `{Mods}+{Key}` where mods is `Ctrl/Alt/Shift/Win` joined by `+`. Example: `Ctrl+Shift+K`. Helper:

```csharp
private static string FormatCombo(HotkeyEditModel item)
{
    List<string> parts = [];
    if (item.Ctrl) parts.Add("Ctrl");
    if (item.Alt) parts.Add("Alt");
    if (item.Shift) parts.Add("Shift");
    if (item.Win) parts.Add("Win");
    parts.Add(item.Key);
    return string.Join("+", parts);
}
```

- Replacement cell: show `item.Description` (ellipsizes first if line wraps — default for the deferred question).

**Expanded row extra fields:**
- Action: `@item.Action`
- Parameters: `@item.Parameters` (if non-empty)
- Profiles, Categories — same as hotstring.

**CSS class on bulk-delete button:** `bulk-delete-hotkeys` (matches existing convention).

**Tests** — mirror Task 3 + 4 tests, substituting:
- `HotstringEditModel` → `HotkeyEditModel`
- Item factory: `new() { Id = Guid.NewGuid(), Description = "Open palette", Key = "K", Ctrl = true, Shift = true }`
- Assert primary line shows `Ctrl+Shift+K`
- Selector for bulk delete: `button.bulk-delete-hotkeys`

- [ ] **Step 1: Write failing tests** — mirror `HotstringMobileListTests` with substitutions above.
- [ ] **Step 2: Run — expect FAIL.** `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotkeyMobileListTests" --no-restore`
- [ ] **Step 3: Create the component + css.** Adapt `HotstringMobileList.razor` with the FormatCombo helper for the trigger cell and the extra field rendering.
- [ ] **Step 4: Run — expect PASS.** `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotkeyMobileListTests" --no-restore`
- [ ] **Step 5: Commit.**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor.css tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyMobileListTests.cs
git commit -m "feat: hotkey mobile list (collapsed + expand + select + bulk delete)"
```

---

## Task 9: Integrate mobile branch into Hotkeys.razor (mirror Task 5)

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`

Apply the same CSS-gated branch split + mobile branch + new helper methods (`LoadMobileAsync`, `OpenCreateDialogAsync`, `OpenEditDialogAsync`, `MobileBulkDeleteAsync`, `ReloadAllAsync`) to `Hotkeys.razor`. Substitutions:

- `HotstringMobileList` → `HotkeyMobileList`
- `HotstringEditDialog` → `HotkeyEditDialog`
- `add-hotstring-fab` → `add-hotkey-fab`
- `IHotstringsApiClient` (`Api`) returns `HotkeyDto`; `HotkeyListRequest` constructor uses different fields — only pass `Page`, `PageSize`, `Search`, `CategoryIds`.
- Title strings: "New hotkey" / "Edit hotkey".
- `HotkeyEditModel.FromDto(new HotkeyDto(...))` — construct the DTO from `item` fields. Look at existing `MapItem` in `Hotkeys.razor:393` for the shape.

- [ ] **Step 1: Add the failing test** — mirror Task 5 Step 1's test in `HotkeysPageTests.cs`. Selector: `button.add-hotkey-fab`.
- [ ] **Step 2: Run — expect FAIL.** `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "HotkeysPageTests.Page_RendersCssGatedDesktopAndMobileBranches" --no-restore`
- [ ] **Step 3: Modify `Hotkeys.razor`** with the same split treatment.
- [ ] **Step 4: Run all UI tests + build.** `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --no-restore && dotnet build --no-restore`
- [ ] **Step 5: Commit.**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs
git commit -m "feat: integrate mobile branch into hotkeys page"
```

---

## Task 10: E2E test for mobile hotkeys flow (mirror Task 6)

**Files:**
- Create: `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`

Mirror `HotstringsMobileFlowTests`. Substitutions:

- Route: `/hotkeys`
- FAB selector: `button.add-hotkey-fab`
- Dialog selector: `.hotkey-edit-dialog`
- Bulk delete selector: `button.bulk-delete-hotkeys`
- Field selectors: `description-input`, `key-input`, modifier checkboxes, `action-select`, `parameters-input`
- Sample data: description "Open palette", key "K", Ctrl=true, Shift=true
- Success snackbar: "Hotkey created." / "Hotkey updated." / "Hotkey deleted." / "Deleted 2 hotkey"
- Row text assertion: `.mobile-row:has-text(\"Ctrl+Shift+K\")` for the formatted combo

Two tests: `CreateEditDelete_OnPhoneViewport_UsesFabAndFullScreenDialog`, `BulkDelete_OnPhoneViewport_UsesSelectMode`.

- [ ] **Step 1: Write the tests.**
- [ ] **Step 2: Publish frontend** (already done in Task 6 — re-run if Blazor source changed since):

Run: `dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c Release --no-restore`

- [ ] **Step 3: Run E2E.** `dotnet test tests/AHKFlowApp.E2E.Tests --filter "HotkeysMobileFlowTests" --no-restore`

Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs
git commit -m "test: e2e mobile hotkeys flow"
```

---

## Task 11: Manual headed-browser verification

Drive both pages in headed Playwright at three viewports to confirm UX. Use the `playwright-cli` skill from a fresh Claude Code session, or run by hand.

- [ ] **Step 1: Start API**

Open a terminal, run:

```bash
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
```

Expected: API listening on `http://localhost:5600`.

- [ ] **Step 2: Start Blazor frontend**

Open a second terminal, run:

```bash
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
```

Expected: Frontend on `http://localhost:5601`.

- [ ] **Step 3: Invoke playwright-cli with three viewports**

Via the `playwright-cli` skill, drive these scenarios in **headed** mode (so the user sees the browser):

For each viewport (375×812 phone, 768×1024 tablet portrait, 1280×800 desktop):

1. Navigate to `http://localhost:5601/hotstrings`.
2. Verify **no horizontal scrollbar** on the page or table.
3. At 375 and 768 — confirm FAB visible bottom-right, category chip strip scrolls horizontally only within the strip.
4. At 1280 — confirm the desktop inline-edit grid renders, no FAB, original toolbar buttons present.
5. Repeat for `/hotkeys`.

- [ ] **Step 4: If anything looks wrong**, fix on a follow-up commit. Otherwise no commit needed.

---

## Task 12: Update frontend CLAUDE.md + open PR

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`

- [ ] **Step 1: Append a conventions note**

Add to `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` after the existing conventions list:

```markdown
- For list pages that need mobile support: render both branches as plain `.desktop-branch` and `.mobile-branch` containers, then gate visibility in the page's scoped `.razor.css` at `959.95px`. Desktop uses `MudDataGrid`; mobile uses a compact list component, full-screen `MudDialog`, and `MudFab`. See `Components/Hotstrings/` and `Components/Hotkeys/` for examples.
```

- [ ] **Step 2: Commit the note**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md
git commit -m "docs: note mobile branch convention for list pages"
```

- [ ] **Step 3: Run full check**

Run: `dotnet format && dotnet build --no-restore && dotnet test --no-restore`

Expected: all green.

- [ ] **Step 4: Push branch + open PR**

```bash
git push -u origin feature/032-mobile-hotstrings-hotkeys
gh pr create --title "Mobile-friendly hotstrings + hotkeys pages" --body "$(cat <<'EOF'
## Summary
- Mobile pattern (<960px): compact 2-col list, expandable rows, full-screen edit dialog, FAB, select-mode bulk delete
- Desktop (md+): inline-edit `MudDataGrid` unchanged
- Same pattern applied to Hotstrings + Hotkeys; Categories/Profiles deferred to a follow-up

Spec: `docs/superpowers/specs/2026-05-24-mobile-hotstrings-hotkeys-design.md`
Plan: `docs/superpowers/plans/2026-05-24-mobile-hotstrings-hotkeys.md`

## Deferred-question defaults (please confirm in review)
- Pager: `MudPagination`, page size 10 on mobile
- Hotkeys primary-line truncation: description ellipsizes first
- FAB: always visible (no scroll-hide)
- Select-mode action bar: sticky bottom

## Test plan
- [ ] CI green (`dotnet build`, `dotnet test`, `dotnet format --verify-no-changes`)
- [ ] Manual headed Playwright at 375×812, 768×1024, 1280×800 — verified no horizontal scroll, FAB reachable, desktop grid unchanged

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL.

---

## Self-Review

**Spec coverage check:**
- ✅ Breakpoint cutoff <960px → Tasks 5 + 9 (`Breakpoint.SmAndDown`)
- ✅ Compact 2-col list + expand → Tasks 3 + 8
- ✅ Full-screen MudDialog → Tasks 1 + 7
- ✅ Select-mode bulk delete → Tasks 4 + 8
- ✅ FAB → Tasks 5 + 9
- ✅ Horizontally scrollable chip strip → Task 5's mobile branch + Task 9
- ✅ Tablet (sm) wider rows → no breakpoint-specific code needed (single-column layout naturally widens)
- ✅ Hotstrings + Hotkeys only → Tasks cover both, nothing about Categories/Profiles
- ✅ Inline per page first (no shared abstraction) → two separate components per type
- ✅ Verify via headed playwright → Task 11
- ✅ Bunit + E2E tests → Tasks 1-4 + 6 (hotstrings); 7-8 + 10 (hotkeys)

**Type consistency check:** Method names and selectors are consistent throughout (e.g. `add-hotstring-fab` vs `add-hotkey-fab`, `commit-edit`/`cancel-edit`/`start-edit`/`delete` matching existing desktop conventions, dialog css classes `hotstring-edit-dialog` / `hotkey-edit-dialog` referenced in E2E selectors).

**Placeholder scan:** All `[ ]` steps contain either complete code, exact commands, or explicit substitution instructions for mirrored tasks.

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-05-24-mobile-hotstrings-hotkeys.md`. Pick an execution mode in the parent session.
