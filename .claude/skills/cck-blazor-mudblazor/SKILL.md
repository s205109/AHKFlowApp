---
name: cck-blazor-mudblazor
description: >
  Blazor WebAssembly UI patterns with MudBlazor 9.x. Covers MudTable (client
  and server-side), MudForm validation, MudDialog CRUD workflows, MudSnackbar
  feedback, and component composition. Load when building Blazor UI pages,
  forms, tables, dialogs, or when the user mentions "MudBlazor", "MudTable",
  "MudForm", "MudDialog", "Blazor component", "UI page", "CRUD UI",
  "data table", "form validation", or "snackbar".
---

# Blazor + MudBlazor Patterns

## Core Principles

1. **MudBlazor components first** — Always use MudBlazor components (`MudTable`, `MudForm`, `MudDialog`, `MudButton`) over raw HTML. Consistent styling, accessibility, and behavior out of the box.
2. **Typed HttpClient for all API calls** — Use `IAHKFlowApiHttpClient` (registered via `AddHttpClient<T>`). Never create HttpClient manually.
3. **Dialogs for create/edit, snackbars for feedback** — `IDialogService.ShowAsync<T>` for forms, `ISnackbar.Add()` for success/error notifications.
4. **Loading states everywhere** — Set `_loading = true` before async calls, `false` after. Use `MudTable.Loading` and `MudProgressLinear` for visual feedback.
5. **CancellationToken propagation** — Pass tokens through all async paths to support cancellation.

## Patterns

### Page Layout (List View)

```razor
@page "/hotstrings"

<PageTitle>Hotstrings</PageTitle>

<MudContainer MaxWidth="MaxWidth.Large" Class="mt-4">
    <MudText Typo="Typo.h4" Class="mb-4">Hotstrings</MudText>

    <MudButton Variant="Variant.Filled" Color="Color.Primary"
               StartIcon="@Icons.Material.Filled.Add"
               OnClick="OpenCreateDialog" Class="mb-4">
        Add Hotstring
    </MudButton>

    <MudTable Items="_hotstrings" Hover Loading="_loading"
              Breakpoint="Breakpoint.Sm" LoadingProgressColor="Color.Primary">
        <HeaderContent>
            <MudTh>Trigger</MudTh>
            <MudTh>Replacement</MudTh>
            <MudTh Style="width: 120px;">Actions</MudTh>
        </HeaderContent>
        <RowTemplate>
            <MudTd DataLabel="Trigger">@context.Trigger</MudTd>
            <MudTd DataLabel="Replacement">@context.Replacement</MudTd>
            <MudTd>
                <MudIconButton Icon="@Icons.Material.Filled.Edit"
                               Size="Size.Small"
                               OnClick="() => OpenEditDialog(context)" />
                <MudIconButton Icon="@Icons.Material.Filled.Delete"
                               Size="Size.Small" Color="Color.Error"
                               OnClick="() => ConfirmDelete(context)" />
            </MudTd>
        </RowTemplate>
    </MudTable>
</MudContainer>

@code {
    [Inject] private IAHKFlowApiHttpClient Api { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;

    private List<HotstringDto> _hotstrings = [];
    private bool _loading = true;

    protected override async Task OnInitializedAsync()
    {
        await LoadDataAsync();
    }

    private async Task LoadDataAsync()
    {
        _loading = true;
        _hotstrings = await Api.GetHotstringsAsync();
        _loading = false;
    }
}
```

### MudDialog for Create/Edit

```razor
<MudDialog>
    <TitleContent>
        <MudText Typo="Typo.h6">@(IsEdit ? "Edit Hotstring" : "Add Hotstring")</MudText>
    </TitleContent>
    <DialogContent>
        <MudForm @ref="_form" Model="_model" Validation="_validator.ValidateValue">
            <MudTextField @bind-Value="_model.Trigger"
                          For="() => _model.Trigger"
                          Label="Trigger" Variant="Variant.Outlined"
                          Immediate />
            <MudTextField @bind-Value="_model.Replacement"
                          For="() => _model.Replacement"
                          Label="Replacement" Variant="Variant.Outlined"
                          Lines="3" Immediate />
        </MudForm>
    </DialogContent>
    <DialogActions>
        <MudButton OnClick="Cancel">Cancel</MudButton>
        <MudButton Variant="Variant.Filled" Color="Color.Primary"
                   OnClick="Submit">Save</MudButton>
    </DialogActions>
</MudDialog>

@code {
    [CascadingParameter] private MudDialogInstance MudDialog { get; set; } = default!;
    [Parameter] public HotstringDto? Existing { get; set; }

    private bool IsEdit => Existing is not null;
    private MudForm _form = default!;
    private CreateHotstringDto _model = new();
    private CreateHotstringDtoValidator _validator = new();

    protected override void OnParametersSet()
    {
        if (Existing is not null)
        {
            _model = new() { Trigger = Existing.Trigger, Replacement = Existing.Replacement };
        }
    }

    private async Task Submit()
    {
        await _form.Validate();
        if (_form.IsValid)
        {
            MudDialog.Close(DialogResult.Ok(_model));
        }
    }

    private void Cancel() => MudDialog.Cancel();
}
```

### Opening Dialogs from Pages

```csharp
private async Task OpenCreateDialog()
{
    var dialog = await DialogService.ShowAsync<HotstringDialog>("Add Hotstring");
    var result = await dialog.Result;

    if (result is { Canceled: false, Data: CreateHotstringDto dto })
    {
        await Api.CreateHotstringAsync(dto);
        Snackbar.Add("Hotstring created", Severity.Success);
        await LoadDataAsync();
    }
}

private async Task OpenEditDialog(HotstringDto hotstring)
{
    var parameters = new DialogParameters { ["Existing"] = hotstring };
    var dialog = await DialogService.ShowAsync<HotstringDialog>("Edit Hotstring", parameters);
    var result = await dialog.Result;

    if (result is { Canceled: false, Data: CreateHotstringDto dto })
    {
        await Api.UpdateHotstringAsync(hotstring.Id, dto);
        Snackbar.Add("Hotstring updated", Severity.Success);
        await LoadDataAsync();
    }
}
```

### Delete Confirmation

```csharp
private async Task ConfirmDelete(HotstringDto hotstring)
{
    var confirmed = await DialogService.ShowMessageBox(
        "Delete Hotstring",
        $"Delete trigger '{hotstring.Trigger}'? This cannot be undone.",
        yesText: "Delete", cancelText: "Cancel");

    if (confirmed == true)
    {
        await Api.DeleteHotstringAsync(hotstring.Id);
        Snackbar.Add("Hotstring deleted", Severity.Success);
        await LoadDataAsync();
    }
}
```

### MudForm Validation with FluentValidation

```csharp
// Validator adapter for MudForm — wraps FluentValidation for @bind-Value + For
public static class FluentValidationExtensions
{
    public static Func<object, string, Task<IEnumerable<string>>> ValidateValue<T>(
        this IValidator<T> validator) where T : class
    {
        return async (model, propertyName) =>
        {
            var result = await validator.ValidateAsync(
                ValidationContext<T>.CreateWithOptions(
                    (T)model, x => x.IncludeProperties(propertyName)));

            return result.IsValid
                ? []
                : result.Errors.Select(e => e.ErrorMessage);
        };
    }
}
```

### Server-Side Table (Pagination/Search)

```razor
<MudTable ServerData="LoadServerData" @ref="_table" Hover
          Loading="_loading" LoadingProgressColor="Color.Primary">
    <ToolBarContent>
        <MudTextField @bind-Value="_searchString" Placeholder="Search..."
                      Adornment="Adornment.Start"
                      AdornmentIcon="@Icons.Material.Filled.Search"
                      Immediate DebounceInterval="300"
                      OnDebounceIntervalElapsed="OnSearch" />
    </ToolBarContent>
    <HeaderContent>
        <MudTh><MudTableSortLabel SortLabel="trigger" T="HotstringDto">Trigger</MudTableSortLabel></MudTh>
        <MudTh><MudTableSortLabel SortLabel="replacement" T="HotstringDto">Replacement</MudTableSortLabel></MudTh>
    </HeaderContent>
    <RowTemplate>
        <MudTd DataLabel="Trigger">@context.Trigger</MudTd>
        <MudTd DataLabel="Replacement">@context.Replacement</MudTd>
    </RowTemplate>
    <PagerContent>
        <MudTablePager />
    </PagerContent>
</MudTable>

@code {
    private MudTable<HotstringDto> _table = default!;
    private string _searchString = string.Empty;
    private bool _loading;

    private async Task<TableData<HotstringDto>> LoadServerData(TableState state,
        CancellationToken ct)
    {
        _loading = true;
        var response = await Api.SearchHotstringsAsync(
            _searchString, state.Page + 1, state.PageSize, state.SortLabel,
            state.SortDirection == SortDirection.Descending, ct);
        _loading = false;

        return new TableData<HotstringDto>
        {
            Items = response.Items,
            TotalItems = response.TotalCount
        };
    }

    private void OnSearch() => _table.ReloadServerData();
}
```

## Anti-patterns

### Don't Use Raw HTML Instead of MudBlazor Components

```razor
@* BAD — breaks consistent styling, accessibility *@
<input type="text" @bind="Model.Name" />
<button @onclick="Submit">Save</button>

@* GOOD — MudBlazor components *@
<MudTextField @bind-Value="Model.Name" Label="Name" Variant="Variant.Outlined" />
<MudButton Variant="Variant.Filled" OnClick="Submit">Save</MudButton>
```

### Don't Forget `For` Lambda on Form Fields

```razor
@* BAD — validation messages won't display for this field *@
<MudTextField @bind-Value="_model.Trigger" Label="Trigger" />

@* GOOD — For links the field to FluentValidation *@
<MudTextField @bind-Value="_model.Trigger" For="() => _model.Trigger" Label="Trigger" />
```

### Don't Skip Loading States

```csharp
// BAD — UI freezes with no feedback during API calls
_hotstrings = await Api.GetHotstringsAsync();

// GOOD — loading indicator visible during fetch
_loading = true;
_hotstrings = await Api.GetHotstringsAsync();
_loading = false;
```

### Don't Use `StateHasChanged()` After Every Operation

```csharp
// BAD — unnecessary, Blazor re-renders after event handlers
await Api.CreateHotstringAsync(dto);
StateHasChanged(); // redundant

// GOOD — only call StateHasChanged after non-UI-thread operations
// Blazor auto-renders after event handlers and OnInitializedAsync
await Api.CreateHotstringAsync(dto);
```

### Don't Nest Dialogs

```csharp
// BAD — opening a dialog from a dialog confuses users
// and creates complex cascading parameter issues

// GOOD — close the current dialog, then open the next from the page
MudDialog.Close(DialogResult.Ok(result));
// Page handles opening the next dialog
```

## Decision Guide

| Scenario | Recommendation |
|----------|---------------|
| List of items | `MudTable` with `Items` (client) or `ServerData` (server) |
| Create/Edit form | `MudDialog` + `MudForm` + FluentValidation |
| Delete confirmation | `DialogService.ShowMessageBox()` |
| Success/error feedback | `ISnackbar.Add()` with `Severity` |
| Search with debounce | `MudTextField` with `DebounceInterval` + `OnDebounceIntervalElapsed` |
| Sorting | `MudTableSortLabel` with `SortLabel` |
| Pagination | `MudTablePager` (server-side) or built-in (client-side) |
| Form validation | `MudForm` + `Validation` + `For` lambdas |
| Loading indicator | `MudTable.Loading` or `MudProgressLinear` |
| Navigation | `MudNavMenu` + `MudNavLink` |
