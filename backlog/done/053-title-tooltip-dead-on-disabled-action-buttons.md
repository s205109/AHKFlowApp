# 053 - Known-shortcut action buttons show no tooltip while they are disabled

## Metadata

- **Epic**: Known shortcuts
- **Type**: Bug
- **Interfaces**: UI

## Summary

`KnownShortcutUseActions.razor` puts a `title` attribute on each of its three action buttons
(`:52`, through the `Attributes` helper at `:48-54`). The same three buttons take
`Disabled="@Busy"` (`:15`, `:21`, `:27`), where `Busy` is true while any write on the page is in
flight (`:34-35`).

MudBlazor 9.3.0 sets `pointer-events: none` on every disabled button. The rule is
`.mud-button-root:disabled{color:var(--mud-palette-action-disabled) !important;cursor:default;pointer-events:none}`
in `MudBlazor.min.css`, shipped inside the `MudBlazor` 9.3.0 package.

A disabled button therefore receives no hover event, so the browser never shows its `title`
tooltip. While `Busy` is true, the button dims and its hover text disappears at the same moment.
That is the moment a person is most likely to hover it, because the button just stopped responding
to clicks.

The `aria-label` at `:53` is not affected. A screen reader still announces a disabled button's
name.

## Acceptance criteria

- [x] Hovering a disabled known-shortcut action button shows its short text
- [x] The fix wraps the button rather than styling the disabled state. `LoginDisplay.razor:17-19`
      is the pattern already in the repo — a disabled `MudButton` inside a `MudTooltip`. The
      tooltip root is a plain div, it is not disabled, so it receives the hover
- [x] The `aria-label` at `:53` keeps naming the use in full, so the desktop table and the mobile
      list can still tell the Chrome row from the Edge row on the same combination
- [x] A bUnit test renders the component with `Busy="true"` and asserts the wrapper is present and
      carries the text. Assert on markup that is always rendered, not on `MudTooltip Text` — that
      text only reaches the DOM once a `MudPopoverProvider` is rendered and the popover opens

      Done as written: the wrapper is found by `data-test="use-action-tooltip"`, and the text is
      read out of the popover after a real `PointerEnter`, not off `MudTooltip.Text`. The bUnit
      test renders `MudPopoverProvider` first, because the popover text renders into that tree.
      An E2E flow test repeats the same hover in a real browser while a write is held open.
      The E2E test needed one more step: a preceding click leaves the pointer inside the tooltip
      root, so `HoverAsync` alone would move to a point the pointer already occupies and fire no
      `pointerenter`. The test parks the pointer with `Mouse.MoveAsync(0, 0)` first, then hovers,
      and asserts on `.mud-popover-open.use-action-tooltip-text` because MudBlazor keeps every
      matching popover mounted and the search text matches more than one row.

## Out of scope

- The two other `title` attributes in the UI. `Hotstrings.razor:1042` and `Hotkeys.razor:947` also
  pass `title` through `UserAttributes`, but neither button takes a `Disabled` parameter, so both
  are correct as written
- Any change to what `Busy` disables, or to how long it stays true

## Notes / dependencies

- Found while revising `docs/superpowers/specs/2026-08-05-profiles-page-download-design.md`. Its
  section 4.3 hit the same MudBlazor rule and settled on the `MudTooltip` wrapper. That spec's
  reasoning applies here unchanged
- Line numbers were read on `feature/wt-profiles-page-download` at `9210dad3`
