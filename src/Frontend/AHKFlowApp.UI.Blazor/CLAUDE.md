# AHKFlowApp.UI.Blazor

Blazor WebAssembly PWA frontend for AHKFlowApp.

## Conventions

- MudBlazor components for all UI — no raw HTML inputs or buttons
- `[Inject]` properties with `= default!` for DI
- `_loading = true` before async calls, `false` after
- `ISnackbar.Add()` for success/error feedback
- `IDialogService.ShowAsync<T>` for create/edit forms with non-trivial layouts (multi-section, tabs, file upload, etc.)
- Inline `MudTable` row editing is acceptable for simple tabular CRUD (≤6 short fields). Example: categories page.
- `MudDataGrid` with server-side sort/filter for larger list pages. Examples: hotstrings, hotkeys pages.
- Bulk-select + delete toolbar for multi-row deletion. Examples: hotstrings, hotkeys pages.
- `IDialogService.ShowMessageBox(...)` for delete confirmations
- No `StateHasChanged()` after standard event handlers — Blazor re-renders automatically
- For list pages that need mobile support: render both branches gated by CSS `@media` query (breakpoint 960px). Desktop branch uses `MudDataGrid` with inline editing inside `<div class="desktop-branch">`; mobile branch uses a compact list component + full-screen `MudDialog` for edit/create + `MudFab` for add inside `<div class="mobile-branch">`. Visibility is controlled by a co-located `.razor.css` file (not `MudHidden` — bUnit doesn't apply CSS). See `Components/Hotstrings/` and `Components/Hotkeys/` for examples.

## Local Setup

`wwwroot/appsettings.Development.json` is gitignored. Copy the example and fill in your Azure AD values:

```bash
cp wwwroot/appsettings.Development.json.example wwwroot/appsettings.Development.json
```

## Adding a Page

1. Create `Pages/MyPage.razor` with `@page "/my-page"` directive
2. Add nav link in `Layout/NavMenu.razor`
3. Use `MudContainer` + `MudTable` / `MudForm` as the page structure
