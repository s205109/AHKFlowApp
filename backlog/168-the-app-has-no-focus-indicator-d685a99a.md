# 168 - The app has no focus indicator and unnamed icon buttons

## Metadata

- **Epic**: Accessibility
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

A nav link does not change appearance when it takes keyboard focus, and no file in the repository
sets a focus-ring policy. Twenty icon-only buttons have no accessible name: both app-bar buttons,
and every button on the categories, hotstrings and profiles rows. The hotkeys rows and the
Recycle Bin rows already name theirs, so the fix follows a pattern the app already uses. There is
also no skip link, so reaching page content costs fourteen tab presses on every page.

## User story

As an owner who uses a keyboard or a screen reader, I want to see where I am and hear what each
button does, so that I can use the app without a mouse.

## Acceptance criteria

- [ ] A nav link is visibly different focused and unfocused.
- [ ] The repository states a focus-ring policy in one place, and that policy covers nav links,
      grid buttons, toolbar buttons and form fields.
- [ ] The drawer toggle and the dark-mode toggle each have an accessible name, and the dark-mode
      name reflects what pressing it will do.
- [ ] Each of the twenty buttons listed under Notes has an accessible name that includes its
      target, following the pattern the hotkeys rows and the Recycle Bin rows already use.
- [ ] A skip link reaches the page content, and it becomes visible when it takes focus.
- [ ] An E2E flow test asserts the accessible name of at least one app-bar button and one row
      button, so the pattern cannot silently regress.

## Out of scope

- A full accessibility audit against WCAG. This item fixes four specific findings.
- Colour contrast, which the sweep did not measure.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F6 and F12 (S3), F27 (S3) and F28 (S4).
  Full evidence in `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and
  gitignored.
- **F27, the focus indicator.** Checked four ways before it was written down. The computed style
  of a nav link is identical focused and not focused: outline `none 3px`, box-shadow none,
  background transparent. The outline has a width of 3 pixels and a style of `none`, so it draws
  nothing. After fourteen real Tab presses the focused element matched `:focus-visible`, so the
  browser agreed a focus style should show, and still drew nothing. `::before` and `::after` both
  have `content: none` and there is no overlay child, which rules out the way MudBlazor often
  draws focus. A screenshot is saved beside the report as `screenshots/c9-focus-navlink.png`.
- **The measurement covers one control.** The four checks above were all run on a nav link, so
  "no focus indicator anywhere in the app" was a generalisation and the summary no longer says it.
  What supports the wider worry is that no file in the repository sets a focus-ring policy, which
  is also part of why this went unnoticed. Measure a grid button, a toolbar button and a form
  field at pickup, and write down what each one does today before changing any CSS.
- **F6 and F12, the names.** The app bar's two `MudIconButton`s have no `aria-label`, no `Title`
  and no text, so the accessibility tree shows a button containing only an image. Read directly, a
  hotstring row's three buttons return `aria=[NONE] title=[NONE]`.
- **The hotkeys rows were already done**, under item 035, whose last acceptance criterion reads
  "Add accessible names to icon-only controls and mobile row checkbox labels". All six buttons in
  `Pages/Hotkeys.razor`'s row template carry an `aria-label`, and so do the Recycle Bin rows, the
  hotkeys mobile list, the hotkeys history dialog, the edit dialog, the code-preview copy button,
  the quickstart copy button, the known-shortcut use actions, the hotstrings `promote-edit` button
  and the hotstrings glyph-legend button. The sweep read the hotstrings rows and generalised to
  both pages, which was wrong. That part of the finding is not new work.
- **The twenty buttons that still have no accessible name**, counted by reading every
  `MudIconButton` in the project:
  - `Layout/MainLayout.razor` — the drawer toggle and the dark-mode toggle.
  - `Pages/Categories.razor` — `commit-edit`, `cancel-edit`, `start-edit`, `delete`.
  - `Pages/Hotstrings.razor` — `reload-hotstrings-mobile`, `commit-edit`, `cancel-edit`, `edit`,
    `show-history`, `delete`.
  - `Pages/Profiles.razor` — `commit-edit`, `cancel-edit`, `toggle-expand`, `start-edit`,
    `delete`.
  - `Components/Hotstrings/HotstringMobileList.razor` — `toggle-select-mode`.
  - `Components/Hotstrings/HotstringHistoryDialog.razor` — `close-history`.
  - `Components/Hotstrings/HotstringImportDialog.razor` — `cancel-import`.
- The pattern to copy is in the same two files twice over. `HotkeyMobileList.razor` names its
  `toggle-select-mode` button and `HotstringMobileList.razor` does not. `HotkeyHistoryDialog.razor`
  names its `close-history` button and `HotstringHistoryDialog.razor` does not. So this is the
  hotkey work never reaching the hotstring side, not a missing decision. `MudIconButton` has no
  `AriaLabel` parameter, so every existing label rides along through `UserAttributes`.
- **F28, the skip link.** The real tab order from the top of `/hotstrings` is: two app-bar
  buttons, then all eleven nav links, then Add, Reload and Import at stops 14 to 16. So content
  starts at the fourteenth press, on every page. A search for a link whose text contains "skip"
  found none. The order itself follows the visual order exactly, with no jumps — that part
  passed.
- Fix order matters. A skip link that is hidden until it takes focus only works once F27 is
  fixed, so do the focus indicator first.
- Spec: none — the work is four known fixes, not a design question.
- Plan: none — moderate work, goes straight to Plan at pickup.
