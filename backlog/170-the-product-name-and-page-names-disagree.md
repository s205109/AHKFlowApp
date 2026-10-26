# 170 - The product name and page names disagree

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

The product has four spellings across the app bar, the home page, the browser tab and the web app
manifest. The Health page has three names.

## User story

As an owner, I want one product name and one name for each page, so that I can trust what the app
tells me.

## Acceptance criteria

- [ ] One product spelling appears in `index.html`, the app bar, the home page heading, the home
      page browser tab and `manifest.webmanifest`.
- [ ] The Health page uses one name in its nav link, its browser tab and its heading.
- [ ] `manifest.webmanifest` has a `short_name` shorter than its `name`, and a `description`.
- [ ] Either the UI's action labels match the seven Action names in `CONTEXT.md`, or `CONTEXT.md`
      blesses the display form.

## Out of scope

- Renaming the repository, the solution or the project folders.
- Wording of messages and validation errors, which item 169 covers.
- The commands on the CLI quickstart card. Backlog 197 owns them.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F5, F7, F13 and F25. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
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
- **Split at pickup on 2026-10-26, one pull request per outcome.** The sweep put two outcomes in
  this item, and they share nothing beyond being text an owner reads. This item keeps outcome 2,
  one product name and one page name, because that is what its title says. Outcome 1, the
  quickstart commands that do not run (F1, S2), moved to backlog 197. It has its own worktree from
  `main`, so it can ship first, as this item asked.
- Spec: none — the only open question is F13, and it is a one-line decision.
- Plan: none — moderate work, goes straight to Plan at pickup.
