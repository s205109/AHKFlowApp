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
- For list pages that need mobile support: render both branches as plain `.desktop-branch` and `.mobile-branch` containers, then gate visibility in the page's scoped `.razor.css` at `959.95px`. Desktop uses `MudDataGrid`; mobile uses a compact list component, full-screen `MudDialog`, and `MudFab`. See `Components/Hotstrings/` and `Components/Hotkeys/` for examples.
- Reuse shared selection/chip components in `Components/Common/` — `EntityMultiSelect` (multi-select over an `EntityOption` list), `EntityChips` (read-only id→name chips, with `Any` for "all profiles"), `CategoryFilterChips` (category filter chipset). Don't hand-roll `MudSelect`/`MudChip` blocks for profiles/categories.

## MudBlazor API Verification

Before adding or changing MudBlazor markup, verify component parameters and enum
values against the MudMCP server (tools prefixed `mcp__mudblazor__`, e.g.
`get_component_parameters`, `get_enum_values`). It serves docs for the pinned
MudBlazor version (currently 9.3.0) and prevents hallucinated or deprecated
params. The server is optional and configured locally (per-developer MCP setup).

## Local Setup

`wwwroot/appsettings.Development.json` is gitignored. Two paths:

**MSAL (real Azure AD):** copy the example and fill in your Azure AD values:

```bash
cp wwwroot/appsettings.Development.json.example wwwroot/appsettings.Development.json
```

**No-auth (test provider, always signed in):** run with the `http (No Auth)` launch profile
(`ASPNETCORE_ENVIRONMENT=NoAuth` → loads committed `wwwroot/appsettings.NoAuth.json` with
`Auth:UseTestProvider=true`), paired with the API's `Docker SQL (No Auth)` profile. Git worktrees
get this automatically via `setup-worktree-local-dev.ps1` (no example copy needed).

## Adding a Page

1. Create `Pages/MyPage.razor` with `@page "/my-page"` directive
2. Add nav link in `Layout/NavMenu.razor`
3. Use `MudContainer` + `MudTable` / `MudForm` as the page structure
