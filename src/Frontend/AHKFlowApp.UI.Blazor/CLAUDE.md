# AHKFlowApp.UI.Blazor

Blazor WebAssembly PWA frontend for AHKFlowApp.

## Conventions

- MudBlazor components for all UI — no raw HTML inputs or buttons
- `[Inject]` properties with `= default!` for DI
- `_loading = true` before async calls, `false` after
- `ISnackbar.Add()` for success/error feedback
- `IDialogService.ShowAsync<T>` for create/edit forms
- No `StateHasChanged()` after standard event handlers — Blazor re-renders automatically

## Local Setup

`wwwroot/appsettings.Development.json` is gitignored. Copy the example and fill in your Azure AD values:

```bash
cp wwwroot/appsettings.Development.json.example wwwroot/appsettings.Development.json
```

## Adding a Page

1. Create `Pages/MyPage.razor` with `@page "/my-page"` directive
2. Add nav link in `Layout/NavMenu.razor`
3. Use `MudContainer` + `MudTable` / `MudForm` as the page structure
