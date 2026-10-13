# 176 - The changelog page shows raw markdown

## Metadata

- **Epic**: Frontend platform / bug fix
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

`changelog.json` stores markdown spans, and the Changelog page renders each entry with plain
interpolation. So backtick characters appear literally on screen wherever an entry mentions a
command or an identifier.

## User story

As an owner, I want the changelog to read cleanly, so that identifiers look like code rather than
text with stray punctuation.

## Acceptance criteria

- [ ] The item records what a finished entry should look like on screen, before a renderer is
      chosen. The two options in the notes below lead to different answers, so this comes first.
- [ ] The rendered page holds no literal backtick characters.
- [ ] A command or an identifier in an entry reads as one, by whichever means the decision above
      chose.
- [ ] The page escapes anything it does not deliberately render, so a changelog entry cannot
      inject markup.

## Out of scope

- Generating `changelog.json` from git history.
- Any other page's rendering.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F4, S3. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- The page renders `` `ahkflow hotstring list` `` and `` `SendText(FormatTime(...))` `` with the
  backticks visible. Measured on the rendered page: **0** `<code>` elements and **6** literal
  backticks in the HTML.
- `Pages/Changelog.razor` renders each item with plain interpolation inside a `MudListItem`,
  which escapes the text rather than parsing it.
- The page is `[AllowAnonymous]` and reads the static `wwwroot/changelog.json` rather than calling
  the API, so nothing about this depends on sign-in.
- **Decide the output before the renderer.** Two options, and they do not produce the same page.
  Render a small markdown subset, and a command appears in a `<code>` element. Store the entries
  without markup, and the same command appears as plain text with no backticks. Both satisfy "no
  literal backticks", so the first acceptance criterion asks which one this item wants. Rendering
  raw HTML from a data file would need escaping care, which is why the last acceptance criterion
  is there.
- Spec: none — pick one of the two options above at Plan.
- Plan: none — moderate work, goes straight to Plan at pickup.
