# 170 - The product name and page names disagree

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

The product has four spellings across the app bar, the home page, the browser tab and the web app
manifest. The Health page has three names. The home page also offers two CLI commands that do not
exist, each with its own Copy button.

## User story

As an owner, I want one product name and commands that run, so that I can trust what the app
tells me.

## Acceptance criteria

- [ ] One product spelling appears in `index.html`, the app bar, the home page heading, the home
      page browser tab and `manifest.webmanifest`.
- [ ] The Health page uses one name in its nav link, its browser tab and its heading.
- [ ] Every command on the CLI quickstart card runs as printed against the current CLI.
- [ ] A test or a check proves each quickstart command names a command the CLI actually defines.
- [ ] `manifest.webmanifest` has a `short_name` shorter than its `name`, and a `description`.
- [ ] Either the UI's action labels match the seven Action names in `CONTEXT.md`, or `CONTEXT.md`
      blesses the display form.

## Out of scope

- Renaming the repository, the solution or the project folders.
- Wording of messages and validation errors, which item 169 covers.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F1 (S2), F5, F7, F13 and F25. Full
  evidence in `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and
  gitignored.
- **F1, the quickstart card.** `Components/Home/CliQuickstartCard.razor` prints
  `ahkflow new "yw" "you're welcome" --profile work` and `ahkflow list --profile work --grep
  "typo"`. The CLI's own `--help` defines four commands: `login`, `logout`, `hotstring` and
  `download`. There is no root `new` and no root `list`, and `NewHotstringCommand` takes
  `--trigger` and `--replacement` as options, never as positional arguments. The third line,
  `ahkflow download ahk --profile work`, is correct.
- The correct forms are `ahkflow hotstring new --trigger "yw" --replacement "you're welcome"
  --profile work` and `ahkflow hotstring list --profile work --grep "typo"`.
- The app already documents the right syntax elsewhere. `changelog.json` says
  "`ahkflow hotstring list` shows a Kind column". Only the quickstart card is wrong.
- **F5 and F25, the four spellings.** `AHKFlowApp` in `wwwroot/index.html` and
  `Layout/MainLayout.razor`; `AHKFlow` in the home page's browser tab from `Pages/Home.razor`;
  `AHKflow` in the hero heading from `Components/Home/HeroSection.razor`, which comes from
  `AHK<em>flow</em>` and is a deliberate two-tone treatment but still reads as a third spelling;
  and `AHKFlowApp.UI.Blazor` in `wwwroot/manifest.webmanifest`, which is the Blazor project name
  the template generated. The manifest value is what a browser install prompt shows and what the
  installed app is called on the Start menu.
- The manifest has nine keys and no `description`, so an install dialog that would show one shows
  nothing. `short_name` is the same twenty characters as `name`, so it serves no purpose. No icon
  declares `"purpose": "maskable"`, and `index.html` has no `<meta name="theme-color">` even
  though the manifest sets `theme_color`. Those last two are polish.
- **F7, the Health page.** The nav link says Health, the browser tab says Health Check, the
  heading says System Health.
- **F13, the action labels.** `CONTEXT.md` names the seven Actions SendText, SendKeys, Run,
  Window, Remap, Disable and Raw. `Helpers/HotkeyActionDisplay.cs` shows "Send text" and "Send
  keys". The other five match. This one is a question rather than a defect: the UI form is
  consistent across every filter, chip and dialog, and it is more readable, which Plain English
  favours. But `CONTEXT.md` permits shortening a term by removing words, never by re-casing or
  splitting one. Decide which side moves.
- No file in the repository states what the manifest name must be, and `CONTEXT.md` does not
  cover the manifest. That part is plain reasonableness, not a sourced rule.
- Spec: none — the only open question is F13, and it is a one-line decision.
- Plan: none — moderate work, goes straight to Plan at pickup.
