# 176 - The changelog page shows raw markdown

## Metadata

- **Epic**: Frontend platform / bug fix
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 8-review

## Summary

`changelog.json` stores markdown spans, and the Changelog page renders each entry with plain
interpolation. So backtick characters appear literally on screen wherever an entry mentions a
command or an identifier.

## User story

As an owner, I want the changelog to read cleanly, so that identifiers look like code rather than
text with stray punctuation.

## Acceptance criteria

- [x] The item records what a finished entry should look like on screen, before a renderer is
      chosen. The two options in the notes below lead to different answers, so this comes first.
- [x] The rendered page holds no literal backtick characters.
- [x] A command or an identifier in an entry reads as one, by whichever means the decision above
      chose.
- [x] The page escapes anything it does not deliberately render, so a changelog entry cannot
      inject markup.

## Decision: what a finished entry looks like

Recorded at Plan on 2026-10-15, before the renderer was chosen. This answers the first
acceptance criterion.

- A command or an identifier appears in a `<code>` element. The backticks around it do not
  appear. It uses the app's existing `code` style, which other pages already use.
- Text between `**` markers appears in a `<strong>` element. The asterisks do not appear. One
  entry has this today: "Trigger inside words".
- All other text appears exactly as `CHANGELOG.md` writes it. The page writes it as text, so a
  `<` in an entry shows as `<` and never becomes markup.
- A marker without a partner stays on screen as the character it is. The page does not guess.
- So `CHANGELOG.md` keeps a narrower format than the page can render. The second acceptance
  criterion says the page shows no backtick, and a marker without a partner would show one. In
  that format, a code span holds no backtick and no `**`. A `**` span holds no backtick and no
  `*`. No backtick or `*` appears outside a span. Two spans of the same kind never touch, so text
  must separate them: the page reads `` `a``b` `` as one code span, not two. `ChangelogFlowTests`
  checks the real file against this format, and its failure message names any entry outside it.
- Why not plain text: `CHANGELOG.md` is the source of `changelog.json`, and GitHub shows
  `CHANGELOG.md` as markdown. Removing the markers from that file makes it worse on GitHub.
  Removing them in the generator loses the difference between a command and a word. The user
  story asks for identifiers that look like code, and only a `<code>` element does that.
- Why `**` too: the same list shows literal asterisks around "Trigger inside words". It is the
  same fault, on the same page, caused by the same line of code.

## Out of scope

- Generating `changelog.json` from git history.
- Any other page's rendering.
- Markdown beyond code spans and `**` spans: links, single `*` or `_` emphasis, and headings
  inside an entry. `CHANGELOG.md` uses none of them today.

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
- Spec: none — moderate work, and the decision above stands in for a spec.
- Plan: `docs/superpowers/plans/2026-10-15-changelog-raw-markdown-plan-176.md`
