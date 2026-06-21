# Frontend MudBlazor Dedup + UX Polish — Design

**Date:** 2026-06-21
**Status:** Implemented
**Branch:** `feature/frontend-mud-dedup`

## Context

A MudMCP-informed audit of the Blazor WASM frontend (21 `.razor` files, 366
MudBlazor component usages) found the MudBlazor API usage already **correct for
v9.3.0** — no deprecated parameters, no invalid enums. The real problems were
structural duplication in the Hotstrings/Hotkeys feature cluster, plus a few
verified-but-unused MudBlazor UX features.

This design extracts the highest-value shared UI components and folds in the free
UX wins, deliberately leaving the entangled page-level grid/cache logic for a
follow-up.

## Findings

**Duplication (representative copies):**

- **Entity multi-select** (`MudSelect T="Guid"` + `SelectedValues`/`ToStringFunc`
  + `MudSelectItem` loop): ~8 copies across both edit dialogs and both pages'
  inline grid editors.
- **Entity chip display** (`@foreach id → name → <MudChip Size=Small>`, plus the
  profiles "Any" chip): ~8 copies across both pages and both mobile lists.
- **Category filter chipset** (`MudChipSet T="Guid" SelectionMode=MultiSelection`
  guarded by `_categories.Count > 0`): 4 copies (desktop + mobile, both pages).

**Verified UX features unused (confirmed present in 9.3.0 via MudMCP):**

- `MudTextField.Clearable` on the 4 search fields.
- `MudSelect.SelectAll` / `MudSelect.Clearable` on the multi-selects.
- `MudChipSet` Guid equality already correct via the default comparer — no
  `Comparer` needed.

## Design

New folder `Components/Common/` with a shared projection record and three leaf
components, each with one clear purpose and well-defined inputs:

- **`EntityOption(Guid Id, string Name)`** — lightweight projection so the shared
  components don't depend on concrete DTO types. Callers project
  `Profiles`/`Categories` once into `_profileOptions` / `_categoryOptions`.
- **`EntityMultiSelect`** — wraps `MudSelect T="Guid" MultiSelection`. Inputs:
  `Options`, `SelectedIds`, `SelectedIdsChanged`, `Label`, `Placeholder`,
  `Dense`, `DataTest`. Adds `Clearable` + `SelectAll`. Forwards `DataTest` via
  `UserAttributes` so E2E selectors (`profile-select`, `category-select`) survive.
- **`EntityChips`** — read-only chip strip. Inputs: `Ids`, `Options`, `Any`
  (renders a single `Color.Info` "Any" chip for the all-profiles case). Keeps the
  existing truncated-guid fallback.
- **`CategoryFilterChips`** — wraps the `Count > 0` guard + `MudChipSet`. Inputs:
  `Categories`, `SelectedIds`, `SelectedIdsChanged`, `Class`.

### Isolation / interfaces

Each component is a pure leaf: render-only (`EntityChips`) or a thin two-way
binding wrapper (`EntityMultiSelect`, `CategoryFilterChips`) communicating solely
through parameters + `EventCallback`. No shared state; each is independently
unit-testable with bUnit.

## Out of scope (follow-ups)

- Unify the two ~95%-identical mobile list components into one generic component.
- Extract duplicated page-level grid plumbing (`StringFilter`/`BoolFilter`/
  `GetSort`, same-request cache, `_dialogOpen` guard) into a shared base/helper —
  higher risk, no desktop bUnit coverage.
- Port MudMCP's Copilot expert agent to a Claude subagent (only if Copilot CLI is
  adopted). Convention instead documented in the Blazor `CLAUDE.md` and the
  `cck-blazor-mudblazor` skill.

## Verification

- `dotnet build` (Release): 0 errors, 0 warnings.
- bUnit: 212/212 (incl. 8 new `Components/Common` tests).
- E2E Playwright: 10/10 — exercises the refactored components through a real
  browser (hotstrings CRUD desktop + mobile, hotkeys mobile), confirming
  `data-test` attributes and CSS classes are preserved.
