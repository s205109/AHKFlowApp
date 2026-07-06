# 032 - Fix MudFab fixed-position CSS not applying (Blazor CSS isolation scope attribute missing)

## Metadata

- **Epic**: Frontend platform / bug fix
- **Type**: Bug
- **Interfaces**: UI

## Summary

Every `MudFab` styled via a page's scoped `.razor.css` with `position: fixed` silently fails to apply: the rendered root `<button>` never receives the Blazor CSS-isolation scope attribute (e.g. `b-igl1v33cge`), so the scoped selector (`.add-hotstring-fab[b-igl1v33cge]`, etc.) never matches. The FAB computes to `position: relative` and renders inline instead of floating in the corner.

## User story

As a mobile user, I want the floating action buttons (add/import hotstring, add hotkey) to float fixed in the bottom-right corner so that they stay reachable while scrolling a long list.

## Acceptance criteria

- [ ] `.add-hotstring-fab` (Hotstrings.razor.css), `.import-hotstring-fab` (Hotstrings.razor.css), and `.add-hotkey-fab` (Hotkeys.razor.css) render with `position: fixed` and the intended `bottom`/`right` offsets in a live browser (verified via `getComputedStyle`, not just visual inspection).
- [ ] The two Hotstrings FABs stack without overlapping (import above add).
- [ ] Fix generalizes — future MudFab-based fixed-position elements don't need a one-off workaround.

## Out of scope

- Any other MudBlazor CSS-isolation interaction not related to `position: fixed` FAB placement.

## Notes / dependencies

- Root cause: `MudFab` (and likely other MudBlazor components) render their own root element rather than the call site's tag, so Blazor's CSS-isolation scope attribute — which the compiler stamps onto elements written directly in the component's own markup — never reaches the component's internal root `<button>`.
- Confirmed via live `getComputedStyle`/`getBoundingClientRect` checks against the running app (2026-07-06): `add-hotstring-fab`, `import-hotstring-fab`, and the unrelated, pre-existing `add-hotkey-fab` (Hotkeys page) are all affected identically — this predates the `.ahk` hotstring import feature branch and is not caused by it.
- Candidate fixes to evaluate: (a) move these rules to the unscoped global `wwwroot/css/app.css` so they don't depend on the scope attribute; (b) set positioning via an inline `Style` parameter on the `MudFab` instead of a CSS class; (c) check whether `MudFab` forwards unmatched/splatted attributes (`CaptureUnmatchedValues`) to its root element, which — if true — might allow the scope attribute through with a different usage pattern.
- Discovered during code review of `docs/superpowers/plans/2026-07-05-ahk-hotstring-import.md` Task 8 (page entry points for hotstring import) — see that plan/PR for context on how it was found.
