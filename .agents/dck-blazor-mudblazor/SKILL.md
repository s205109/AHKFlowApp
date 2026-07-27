---
name: dck-blazor-mudblazor
description: Use when building AHKFlowApp Blazor WebAssembly UI with MudBlazor pages, forms, tables, dialogs, or snackbars.
---

# Blazor + MudBlazor Patterns

## Core Principles

1. **MudBlazor components first** — Always use MudBlazor components (`MudTable`, `MudForm`, `MudDialog`, `MudButton`) over raw HTML. Consistent styling, accessibility, and behavior out of the box.
2. **Typed API client per entity** — Use the per-entity interface in `src/Frontend/AHKFlowApp.UI.Blazor/Services/` (`ICategoriesApiClient`, `IHotstringsApiClient`, `IHotkeysApiClient`, etc.), each extending `ApiClientBase` and exposing `ListAsync`/`GetAsync`/`CreateAsync`/`UpdateAsync`/`DeleteAsync` returning `ApiResult`/`ApiResult<T>`. `IAhkFlowAppApiHttpClient` only exposes `GetHealthAsync` — never route entity CRUD through it. Never create `HttpClient` manually.
3. **Dialogs for create/edit, snackbars for feedback** — `IDialogService.ShowAsync<T>` for forms, `ISnackbar.Add()` for success/error notifications.
4. **Loading states everywhere** — Set `_loading = true` before async calls, `false` after. Use `MudTable.Loading` and `MudProgressLinear` for visual feedback.
5. **CancellationToken propagation** — Pass tokens through all async paths to support cancellation.
6. **Verify APIs against MudMCP + reuse shared components** — Before adding or changing MudBlazor markup, confirm parameters and enum values against the MudMCP server (`mcp__mudblazor__get_component_parameters`, `get_enum_values`) for the pinned version (9.3.0); it prevents hallucinated/deprecated params. For profile/category selection and chip display, reuse `Components/Common/` (`EntityMultiSelect`, `EntityChips`, `CategoryFilterChips`) instead of hand-rolling `MudSelect`/`MudChip` blocks. MudMCP is optional and configured locally.

## Patterns

### Page Layout (List View)

This app uses two shapes depending on list complexity (documented in `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`, "Conventions"):
- **Simple list, ≤6 short fields, inline edit** — `MudTable` with inline row editing. See `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Categories.razor`.
- **Larger list needing sort/filter/bulk-select** — `MudDataGrid` with `ServerData`, inline row editing, and a bulk-select toolbar. See `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:70-78` (the `MudDataGrid` declaration) and `Pages/Hotkeys.razor` for a second example.

Pages needing mobile support render both a `.desktop-branch` and `.mobile-branch`, gated by scoped CSS at 959.95px — see `Components/Hotstrings/` and `Components/Hotkeys/` for the mobile-branch components.

### MudDialog for Create/Edit

Full-screen `MudDialog` for create/edit is the **mobile-branch** pattern in this app, not the default — desktop list pages edit inline in the table/grid (previous section). See `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor` for the live shape: a `MudDialog` with a `TitleContent` back-button + save button, an `EditModel` (`Validation/HotstringEditModel.cs`) bound via `@bind-Value`, and per-field `Func<string,string?>` validators (see "Form Validation" below — no FluentValidation adapter is involved).

### Opening Dialogs / Delete Confirmation

See `HotstringEditDialog.razor`'s caller in `Pages/Hotstrings.razor` for `IDialogService.ShowAsync<T>` and result handling. For delete confirmation, the real method is `IDialogService.ShowMessageBoxAsync(...)`, not `ShowMessageBox(...)` — see `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Categories.razor:222-225` (`bool? confirm = await DialogService.ShowMessageBoxAsync(title: ..., message: ..., yesText: "Delete", cancelText: "Cancel"); if (confirm != true) return;`).

### Form Validation (per-field delegates, not a FluentValidation adapter)

There is no `FluentValidationExtensions.ValidateValue` adapter in this codebase — real forms validate with a plain `Func<string, string?>` delegate per field, defined as a method on an `EditModel` class in `Validation/` (e.g. `Validation/HotstringEditModel.cs`), wired up as `Validation="@(new Func<string, string?>(Item.ValidateReplacement))"` (see `Components/Hotstrings/HotstringEditDialog.razor:90`). Don't introduce a FluentValidation-to-MudForm adapter — follow the `EditModel` pattern instead.

### Server-Side Table (Pagination/Search)

`Pages/Categories.razor` (`MudTable`) and `Pages/Hotstrings.razor` / `Pages/Hotkeys.razor` (`MudDataGrid`) all use `ServerData` — see "Page Layout" above for which shape applies to a new page.

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

### Don't Skip Field-Level Validation

Real forms in this app don't use a `For` lambda at all — `Validation/HotstringEditModel.cs`'s fields validate through a `Func<string, string?>` delegate passed directly to `Validation`, with `Error`/`ErrorText` bound to the same check (see `Components/Hotstrings/HotstringEditDialog.razor:89-94`, no `For` present). `For` only matters if a field is linked into `MudForm`'s `EditContext`-based validation, which this codebase doesn't use.

```razor
@* BAD — no validation wired up at all *@
<MudTextField @bind-Value="_model.Trigger" Label="Trigger" />

@* GOOD — Validation delegate + Error/ErrorText, matching HotstringEditDialog.razor *@
<MudTextField @bind-Value="_model.Trigger" Label="Trigger"
              Validation="@(new Func<string, string?>(ValidateTrigger))"
              Error="@(ValidateTrigger(_model.Trigger) is not null)"
              ErrorText="@ValidateTrigger(_model.Trigger)" />
```

### Don't Skip Loading States

```csharp
// BAD — UI freezes with no feedback during API calls
ApiResult<PagedList<HotstringDto>> result = await Api.ListAsync(request, ct);

// GOOD — loading indicator visible during fetch (Api is IHotstringsApiClient)
_loading = true;
ApiResult<PagedList<HotstringDto>> result = await Api.ListAsync(request, ct);
_loading = false;
```

### Don't Use `StateHasChanged()` After Every Operation

```csharp
// BAD — unnecessary, Blazor re-renders after event handlers
await Api.CreateAsync(dto, ct);
StateHasChanged(); // redundant

// GOOD — only call StateHasChanged after non-UI-thread operations
// Blazor auto-renders after event handlers and OnInitializedAsync
await Api.CreateAsync(dto, ct);
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
| List of items, simple (≤6 fields) | `MudTable` inline row editing (see `Categories.razor`) |
| List of items, larger/sortable/bulk-select | `MudDataGrid` with `ServerData` (see `Hotstrings.razor`, `Hotkeys.razor`) |
| Create/Edit form | Inline edit (`MudTable`/`MudDataGrid`) by default; `MudDialog` + `EditModel` only for the mobile branch |
| Delete confirmation | `DialogService.ShowMessageBoxAsync()` |
| Success/error feedback | `ISnackbar.Add()` with `Severity` |
| Search with debounce | `MudTextField` with `DebounceInterval` + `OnDebounceIntervalElapsed` |
| Sorting | `MudTableSortLabel` with `SortLabel` |
| Pagination | `MudTablePager` (server-side) or built-in (client-side) |
| Form validation | `EditModel` with per-field `Func<string,string?>` delegates on `Validation`/`Error`/`ErrorText` (no `For`) |
| Loading indicator | `MudTable.Loading` or `MudProgressLinear` |
| Navigation | `MudNavMenu` + `MudNavLink` |
