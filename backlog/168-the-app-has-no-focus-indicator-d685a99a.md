# 168 - The app has no focus indicator and unnamed icon buttons

## Metadata

- **Epic**: Accessibility
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

No element changes appearance when it takes keyboard focus, anywhere in the app. Icon buttons in
the app bar and in every data row have no accessible name. There is also no skip link, so
reaching page content costs thirteen tab presses on every page.

## User story

As an owner who uses a keyboard or a screen reader, I want to see where I am and hear what each
button does, so that I can use the app without a mouse.

## Acceptance criteria

- [ ] A focused control is visibly different from the same control unfocused, on nav links, grid
      buttons, toolbar buttons and form fields.
- [ ] The drawer toggle and the dark-mode toggle each have an accessible name, and the dark-mode
      name reflects what pressing it will do.
- [ ] Every icon-only button in the categories, hotstrings and hotkeys rows has an accessible
      name that includes its target, as the Recycle Bin rows already do.
- [ ] The inline `commit-edit`, `cancel-edit` and `promote-edit` controls have accessible names.
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
- No file in the repository sets a focus-ring policy. That is part of why this went unnoticed.
- **F6 and F12, the names.** The app bar's two `MudIconButton`s have no `aria-label`, no `Title`
  and no text, so the accessibility tree shows a button containing only an image. The same holds
  for two buttons on every categories row, three on every hotstrings and hotkeys row, and the
  inline edit controls. Read directly, a hotstring row's three buttons return `aria=[NONE]
  title=[NONE]`.
- **The app already does this correctly in places**, so the fix is a pattern that exists:
  the Recycle Bin rows use `aria-label="Restore /ghub"` and `aria-label="Delete /ghub forever"`,
  the dialog close button says `Close without saving`, and the quickstart buttons say
  `Copy command`.
- **F28, the skip link.** The real tab order from the top of `/hotstrings` is: two app-bar
  buttons, then all eleven nav links, then Add, Reload and Import at stops 14 to 16. So content
  starts at the fourteenth press, on every page. A search for a link whose text contains "skip"
  found none. The order itself follows the visual order exactly, with no jumps — that part
  passed.
- Fix order matters. A skip link that is hidden until it takes focus only works once F27 is
  fixed, so do the focus indicator first.
- Spec: none — the work is four known fixes, not a design question.
- Plan: none — moderate work, goes straight to Plan at pickup.
