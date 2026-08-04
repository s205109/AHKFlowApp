# 051 - Hotstrings mobile branch goes stale after a desktop mutation

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI

## Summary

`Pages/Hotstrings.razor` renders a desktop branch and a mobile branch at the same time. Only the
scoped CSS decides which one the user sees. Two mutation paths reload the desktop grid alone, so
the mobile list keeps rows that were just changed or deleted.

This is the same bug that backlog 050 fixed on the hotkeys page.

## Acceptance criteria

- [x] `CommitEditAsync` refreshes both branches. Its create arm (`:559`) and its update arm (`:573`)
      each reload the grid alone today
- [x] The desktop bulk delete refreshes both branches. It reloads the grid alone today (`:659`)
- [x] Each fix replaces the whole `ClearListCache()` plus grid-reload block with a single
      `await ReloadAllAsync();`. `ReloadAllAsync` clears the cache itself, so keeping the original
      call would clear it twice
- [x] A bUnit test in `HotstringsPageTests` covers each of the two call sites, asserting on the
      `.mobile-branch` content rather than on a call count

## Out of scope

- The hotkeys page. Backlog 050 fixed it already
- Filter and search paths. Those already reload both branches

## Notes / dependencies

- Found during the review of backlog 050. See
  `docs/superpowers/specs/2026-08-03-known-shortcut-marker-followups-design.md`
- Line numbers were read on `main` at `e905d0ce`
- The cost is one extra mobile load per mutation, and at most one extra API request. `ListAsync`
  returns its cached page when the next request is equal, so a matching grid and mobile request
  costs nothing extra
- `Hotkeys.razor` still has two call sites, `DeleteAsync` and `MobileBulkDeleteAsync`, that call
  `ClearListCache()` right before `ReloadAllAsync()`. `ReloadAllAsync` clears the cache itself, so
  this clears it twice. It is harmless, but it does not match the convention this branch set at the
  two call sites it fixed. Worth a look next time someone touches reload logic on either page
- Task 3 of this branch found that `table-layout: fixed` sizes columns from the table's header row,
  not the data row. If `Components/Hotstrings/`'s mobile list table uses the same pattern — fixed
  layout with unclassed `<th>` header cells — its per-column CSS width rules may be equally inert.
  Worth a quick check before debugging the same symptom from scratch. This branch does not
  investigate or fix `Hotstrings.razor`; that stays out of scope here
