# Mobile-friendly Hotstrings + Hotkeys pages

## Context

The Hotstrings and Hotkeys pages use `MudDataGrid` with inline cell editing across all viewports. This is productive on desktop but cramped on phones/tablets — 8-10 columns force horizontal scroll, inline `MudTextField` inputs are fiddly on touch, and the toolbar wraps awkwardly. Users on mobile and tablet form factors need a layout that uses available width fully and avoids horizontal scrollbars.

Goal: ship a mobile-pattern view for both pages while leaving the desktop experience unchanged. User-configurable density/font preferences are a future backlog item, not part of this work.

## Decisions

| Topic | Decision |
|---|---|
| Breakpoint cutoff | `<960px` (xs+sm) → mobile pattern. `md+` keeps current grid. |
| Mobile read view | Compact 2-col list (trigger / replacement), tap row → inline expand all fields + Edit/Delete buttons. |
| Edit/Create UI | Full-screen `MudDialog`. |
| Bulk delete | "Select" toggle in top app bar → checkboxes appear + sticky bottom action bar. |
| Add | `MudFab` bottom-right, opens the same full-screen create dialog. |
| Category filter | Horizontally scrollable chip strip below search. |
| Tablet (sm) | Same single-column, wider rows (more chars before ellipsis). |
| Scope | Hotstrings + Hotkeys only. Categories/Profiles deferred. |
| Reuse | Inline per page first; extract a shared component only if duplication is real. |

## Architecture

Each page renders **two view branches** and gates visibility with page-scoped CSS:

- `<div class="desktop-branch">` — wraps existing `MudDataGrid` markup. Unchanged behavior.
- `<div class="mobile-branch">` — wraps new mobile view.

Both branches share the same backing state in the page codebehind: `_items`, search text, selected category ids, paging state, snackbar/error handling, and the `LoadServerData` callback. Only rendering differs.

Scoped `.razor.css` files hide `.desktop-branch` under `960px` and hide `.mobile-branch` at `960px+`. Do not combine this with `MudHidden`; double gating can hide the `MudDataGrid` on mid-sized viewports.

## Critical files

**Modify (Hotstrings):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — split into desktop branch (existing grid) + mobile branch (new markup).
- `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs` — reused as-is for the dialog.

**Create (Hotstrings):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor` — full-screen MudDialog for create/edit. Takes `Guid? id` and `HotstringDto?`.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor` — compact list + expand row + FAB + select-mode bar.

**Modify (Hotkeys):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` — same split treatment.

**Create (Hotkeys):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor`

**Reuse (existing patterns, no changes needed):**
- `Services/IHotstringsApiClient` and `IHotkeysApiClient` — Create/Update/Delete/BulkDelete already there.
- `IDialogService.ShowAsync<T>` — already wired in `MainLayout.razor`.
- `IDialogService.ShowMessageBoxAsync` — keep for single-row delete confirmation.
- `Validation/HotstringEditModel` and `HotkeyEditModel` — already map between DTO ↔ form model.
- `Preferences` service — used today for dark mode; **don't** extend in this PR (density/font lives in a separate backlog item).

## Mobile view layout

Order, top to bottom:

1. **Top app bar row** — page title + icon buttons: Reload, Select (toggles `_selectMode`), overflow menu.
2. **Search** — debounced `MudTextField` (reuse existing 300ms debounce logic from desktop branch).
3. **Category chip strip** — wrap a `MudChipSet` in `<div style="overflow-x:auto;white-space:nowrap">`. Filter chips swipe horizontally if numerous.
4. **List header** — small two-column header row (`Trigger`, `Replacement`).
5. **Compact rows** — for each item, a row with `<code>trigger</code>` left, ellipsized replacement right, chevron. Click toggles `_expandedId`. Expanded row shows: full replacement, description, profile chips, category chips, flags (✓/✗), `[Edit]` `[Delete]` buttons.
6. **Pager** — `MudPagination` below the list (driven by the same server paging state as desktop).
7. **FAB** — `MudFab Color="Primary" StartIcon="Icons.Material.Filled.Add"` positioned `fixed; bottom: 16px; right: 16px`.
8. **Select-mode bar (conditional)** — when `_selectMode` is true: rows show a leading `MudCheckBox`; a sticky bottom bar shows `[Cancel] Delete N`.

For Hotkeys, the primary line is `<code>{modifiers}+{Key}</code> · Description` (e.g. `Ctrl+Shift+K · Open palette`). Expanded row shows Action, Parameters, profiles, categories.

## Edit/Create dialog

`HotstringEditDialog` (and `HotkeyEditDialog`):
- Opened with `IDialogService.ShowAsync<HotstringEditDialog>("Edit hotstring", parameters, new DialogOptions { FullScreen = true, CloseButton = false })`.
- Sticky `MudDialogTitle` row: `[← Cancel] Title [Save]`.
- Body: `MudForm` with `HotstringEditModel` instance; reuse `EditFormValidator` already in use.
- Profiles + Categories use `MudSelect` with `MultiSelection=true` (or `MudAutocomplete` if the list is long — match what desktop branch uses today).
- Save: calls `_api.CreateAsync(...)` or `UpdateAsync(...)`, returns the new/updated DTO via `MudDialog.Close(DialogResult.Ok(dto))`.
- Caller refreshes via `_grid.ReloadServerData()` (desktop) or by re-invoking `LoadServerData` (mobile branch keeps its own state).

Same component used for Create (no `id`) and Edit (`id` supplied). Same dialog opens whether the user tapped a row's Edit button or the FAB.

## Error handling

No new pathways. Reuse:
- `Ardalis.Result` → `ProblemDetails` mapping in API.
- `IHotstringsApiClient` typed error returns.
- `ISnackbar.Add(...)` for transient errors.
- Field-level errors (e.g. duplicate trigger conflict) surfaced via `MudForm` validation messages on the relevant input.

## Testing

**New E2E tests (Playwright via existing `StackFixture`):**

- `tests/AHKFlowApp.E2E.Tests/Hotstrings/HotstringsMobileFlowTests.cs`
- `tests/AHKFlowApp.E2E.Tests/Hotkeys/HotkeysMobileFlowTests.cs` (also fills today's gap — no hotkeys E2E exists)

Each browser context created with `ViewportSize = new ViewportSize(375, 812)` (phone) and a second test with `(768, 1024)` (tablet portrait). Coverage:
- Add via FAB → full-screen dialog → fill → save → row appears.
- Tap row → expand → tap Edit → modify → save → updated value visible.
- Single delete via expanded row → confirm dialog → row gone.
- Select mode → check 2 rows → Delete N → both gone.
- Duplicate trigger → conflict error visible inline.

**New bUnit component tests:**

- `tests/AHKFlowApp.UI.Blazor.Tests/Components/HotstringMobileListTests.cs` — render, expand toggle, select-mode toggle reveals checkboxes, FAB click raises event.
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/HotstringEditDialogTests.cs` — render with no id (create) and with id (edit), validation surfaces errors, save invokes API.
- Same pair for Hotkeys.

Existing `HotstringsCrudFlowTests` remains untouched — it runs at the default desktop viewport and covers the inline-edit grid.

## Verification

1. Build + test: `dotnet build` then `dotnet test`.
2. Run locally: `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"` (5600) and `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor` (5601).
3. **Manual headed-Playwright drive** via the `playwright-cli` skill, with `--headed`:
   - 375×812 viewport — verify no horizontal scrollbars, FAB reachable, expand/edit/delete flows.
   - 768×1024 viewport — verify same pattern, wider rows.
   - 1280×800 viewport — verify desktop grid unchanged.
4. Run new E2E tests headless: `dotnet test tests/AHKFlowApp.E2E.Tests --filter "Mobile"`.
5. Format + commit: `dotnet format`, commit on feature branch, open PR.

## Out of scope

- User-configurable font / font size / density preferences (separate backlog).
- Mobile pattern for Categories and Profiles pages (separate backlog).
- Bottom-sheet dialog variant (full-screen dialog covers this).
- Infinite scroll (paged behavior is kept).
- Backend changes — none required.

## Deferred to implementation (defaults if not raised)

These were left open during brainstorm; implementer picks the default and flags in PR for review:

1. **Pager UI** — default to `MudPagination`, page size 10 on mobile (same as desktop).
2. **Hotkeys primary-line truncation** — description ellipsizes first; modifier+key stays intact.
3. **FAB scroll behavior** — always visible.
4. **Select-mode action bar** — sticky bottom (matches mockup).
