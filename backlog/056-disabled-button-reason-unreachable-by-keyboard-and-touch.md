# 056 - A disabled button's reason is unreachable by keyboard and touch

## Metadata

- **Epic**: Accessibility
- **Type**: Defect
- **Interfaces**: UI

## Summary

The app explains a disabled button by wrapping it in a `MudTooltip`. A mouse user hovers the
wrapper and reads the reason. A screen reader user hears the reason, because it is also appended to
the button's `aria-label`.

A sighted keyboard user and a touch user get neither. The wrapper is a plain div, so it cannot take
focus, and the disabled button inside it cannot take focus either. `MudTooltip.ShowOnFocus` is
`true` by default, but nothing in the pair can ever receive focus. `ShowOnClick` is `false` by
default, so a tap shows nothing.

Found while reviewing the Profiles page download button (backlog 055). The same pattern is already
used at `src/Frontend/AHKFlowApp.UI.Blazor/Shared/LoginDisplay.razor:17-19`, so this is a
repository-wide gap, not one page's bug.

## Acceptance criteria

- [ ] A sighted keyboard user can read why a button is disabled, without a screen reader
- [ ] A touch user can read the same reason
- [ ] One shared way to do this, used by every disabled action that has a reason — no per-page
      variation
- [ ] A test covers the keyboard path

## Out of scope

- Enabling the buttons themselves. The reasons they are disabled are correct

## Notes / dependencies

- Related: backlog 053, which covers the `title` attribute being dead on a disabled MudBlazor
  button. Both come from the same MudBlazor rule: `pointer-events: none` on a disabled button
- Current examples of the pattern:
  `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor:304-317` and
  `src/Frontend/AHKFlowApp.UI.Blazor/Shared/LoginDisplay.razor:17-19`
- Options worth weighing: visible helper text next to the control, a focusable wrapper with the
  right role, or `ShowOnClick="true"` plus a focusable element
