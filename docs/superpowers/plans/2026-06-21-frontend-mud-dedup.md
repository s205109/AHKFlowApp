# Frontend MudBlazor Dedup + UX Polish — Implementation Plan

**Date:** 2026-06-21
**Status:** Completed
**Spec:** [2026-06-21-frontend-mud-dedup-design.md](../specs/2026-06-21-frontend-mud-dedup-design.md)

## Build sequence

1. **Shared infra + components** (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Common/`)
   - `EntityOption.cs` — `record EntityOption(Guid Id, string Name)`.
   - `EntityChips.razor`, `CategoryFilterChips.razor`, `EntityMultiSelect.razor`.
   - Register namespace in `_Imports.razor`.
2. **bUnit tests** (`tests/AHKFlowApp.UI.Blazor.Tests/Components/Common/`) — render,
   selection callbacks, `DataTest` forwarding, `Any` chip. `EntityMultiSelect`
   tests wrap the component with `MudPopoverProvider` (required by `MudSelect`).
3. **Replace usages** (preserve every `data-test` value + CSS class):
   - `Components/Hotstrings/HotstringEditDialog.razor`,
     `Components/Hotkeys/HotkeyEditDialog.razor` — both multi-selects.
   - `Pages/Hotstrings.razor`, `Pages/Hotkeys.razor` — category filters
     (desktop + mobile), `RenderProfiles`/`RenderProfileEditor`/
     `RenderCategoryEditor`/`RenderCategories`, `_profileOptions`/`_categoryOptions`
     projections, and `Clearable` on the search fields.
   - `Components/Hotstrings/HotstringMobileList.razor`,
     `Components/Hotkeys/HotkeyMobileList.razor` — expanded-row chips.
4. **Convention docs** — MudMCP-verification note added to the Blazor `CLAUDE.md`
   and the `cck-blazor-mudblazor` skill; documents reuse of `Components/Common/`.
5. **Verify** — build, bUnit, E2E (below).

## Verification (actual results)

- `dotnet build src/Frontend/AHKFlowApp.UI.Blazor -c Release` → 0 errors, 0 warnings.
- `dotnet test tests/AHKFlowApp.UI.Blazor.Tests -c Release` → 212/212 pass.
- `dotnet test tests/AHKFlowApp.E2E.Tests -c Release` → 10/10 pass.

## Notes

- E2E never interacts with `profile-select`/`category-select`, so adding
  `SelectAll`/`Clearable` to the multi-selects is behavior-additive and safe.
- The `DuplicateTrigger` mobile E2E asserts `.hotstring-edit-dialog .mud-alert`
  count is 0 — the dialog keeps `MudAlert` only on the error path (unchanged).
