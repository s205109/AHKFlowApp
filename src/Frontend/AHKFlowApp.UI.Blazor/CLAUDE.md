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
- Reuse shared selection/chip components in `Components/Common/` — `EntityMultiSelect` (multi-select over an `EntityOption` list), `EntityChips` (read-only id→name chips; its `AppliesToAllProfiles` parameter renders a single "All profiles" chip), `CategoryFilterChips` (category filter chipset). Don't hand-roll `MudSelect`/`MudChip` blocks for profiles/categories.
- Never put hover text in a `title` attribute on a control that can be disabled. MudBlazor sets `pointer-events: none` on a disabled control, so the browser never fires the hover and the text never appears. Wrap the control in a `MudTooltip` instead. The tooltip root is a plain `<div>` that is never disabled, so it still receives the hover. Keep `aria-label` and any `data-*` hooks on the control itself — a `<div>` has no role, so a screen reader ignores a label on the wrapper. Example: `Components/KnownShortcuts/KnownShortcutUseActions.razor`.
- When a control is off **for a reason a person needs to read**, use `Components/Common/BlockedIconButton.razor` instead of `Disabled="true"`. It marks the button `aria-disabled="true"` rather than disabling it, so the button keeps focus and pointer events. A keyboard user reads the reason on focus, and a tap shows it in a snackbar. A plain `MudTooltip` cannot do this: a disabled button takes no focus and no tap, and `ShowOnClick="true"` does not help, because a tap fires `pointerenter`, `pointerup`, then `pointerleave`, which opens the tooltip and closes it again inside one tap. A short busy state is not a reason — keep `Disabled="true"` there. Example: `Pages/Profiles.razor` (blocked download button).
- Testing that pattern: MudBlazor mounts every tooltip popover open or shut, and each one carries its tooltip's class, so assert on `.mud-popover-open` **and** the class, and assert the closed state first. In Playwright, `ToBeDisabledAsync` counts `aria-disabled="true"` as disabled, so it cannot tell the two mechanisms apart — check `el.hasAttribute('disabled')` instead.
- Focus rings have one policy, at the end of `wwwroot/css/app.css` under "Focus ring policy". A new focusable control follows that policy, including its exceptions. Do not set `outline` on a control anywhere else.
- A field in an inline edit row has no visible `Label`, because the words around it already name it. Give it an `aria-label` through `UserAttributes`, next to its `data-test`. `EntityMultiSelect` and `KeyPicker` build their own `UserAttributes`, so pass the name through their `AriaLabel` parameter instead. Use the words a sighted owner reads for that field: its column header, or the section title above it. When the header does not say what the field holds, use the text of the chip beside the field instead. When the column holds more than one control, use the label the edit dialog gives the same field. Without a name, a screen reader says only that it is on an edit field. When those words change, change the `aria-label` with them. Examples: `trigger-input` in `Pages/Hotstrings.razor` uses its column header, `run-target-input` in `Pages/Hotkeys.razor` uses its action chip, and `key-input` in `Pages/Hotkeys.razor` uses the dialog label `Key`.
- In a bUnit test, fire an event on a snapshot element only inside `InvokeAsync`, together with the lookup that found it. A snapshot element comes from `FindAll(...)`, or from a child lookup such as `QuerySelector`, `Closest`, `Children`, or `ParentElement`. bUnit never refreshes a snapshot. When the component renders again before the event, the snapshot still holds a handler ID that the renderer has removed, and the test throws `UnknownEventHandlerIdException`. Write `await cut.InvokeAsync(() => cut.FindAll("button")[0].Click());`. An element from `Find(...)` does not need this, because bUnit runs its selector again after every render. `SnapshotEventGuardTests` fails on a bare event on a snapshot element. It cannot see a snapshot kept in a variable and fired in a later statement, so do not write that form. Backlog item 187 holds the probe behind this rule.

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

**No-auth (test provider, always signed in):** run

```powershell
pwsh .\scripts\run-frontend.ps1 -NoAuth
```

This builds with `WasmApplicationEnvironmentName=NoAuth`, so the app loads committed
`wwwroot/appsettings.NoAuth.json` with `Auth:UseTestProvider=true`. Pair it with the API's
`Docker SQL (No Auth)` profile. Git worktrees get no-auth automatically via
`setup-worktree-local-dev.ps1` (no example copy, no script needed).

## Adding a Page

1. Create `Pages/MyPage.razor` with `@page "/my-page"` directive
2. Add nav link in `Layout/NavMenu.razor`
3. Use `MudContainer` + `MudTable` / `MudForm` as the page structure
