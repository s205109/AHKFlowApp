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

- [x] A sighted keyboard user can read why a button is disabled, without a screen reader
- [x] A touch user can read the same reason
- [x] One shared way to do this, used by every disabled action that has a reason — no per-page
      variation
- [x] A test covers the keyboard path

      Done with `aria-disabled` rather than a focusable wrapper. The button is no longer disabled,
      so it keeps focus and pointer events, and `Components/Common/BlockedIconButton.razor` renders
      the button itself, so no page can apply half the pattern. Activating it shows the reason in a
      snackbar, which is what carries the touch path — a tap cannot rely on a tooltip, because
      `pointerenter`, `pointerup`, and `pointerleave` all fire inside one tap and cancel each other
      out. The keyboard path is covered by `BlockedIconButtonTests.FocusingTheButton_ShowsTheReason`
      and by `ProfileScriptDownloadFlowTests.BlockedDownload_ReachableByKeyboard_ShowsWhyItRefuses`,
      which presses `Tab` until the button is `document.activeElement`.

      `Shared/LoginDisplay.razor` lost its permanently disabled button instead of adopting the
      component. That state can never work, so it is now plain text.

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
