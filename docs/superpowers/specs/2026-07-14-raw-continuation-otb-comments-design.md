# Design: Raw hotstring continuation sections, OTB & comments

**Date:** 2026-07-14
**Builds on:** [2026-07-13-raw-hotstring-kind-design.md](2026-07-13-raw-hotstring-kind-design.md) (implemented, PR #182)
**Status:** Approved

## Problem

The Raw hotstring kind rejects valid AHK v2 forms users paste from real scripts:

1. **Continuation sections** — `:*:col::` followed by `( … )` holding literal multi-line
   replacement text. Rejected today with "Put `{` on its own line below the trigger",
   which is wrong advice: a brace body is *code*, the user wanted *literal text*.
2. **OTB** — `{` at the end of the definition line.

Separately, there is no way to get a comment into the generated script for a specific
hotstring or hotkey, even though both entities already store a `Description` that the
generator ignores.

## Scope

In: continuation-section bodies, OTB acceptance (normalized), Description-as-comment
emission for hotstrings and hotkeys, comment-line lifting on Raw paste, example chips
in the Raw editor, error-copy update.

Out (still rejected by design): multiple definitions per paste, `#Hotstring` directives,
`Hotstring()` calls, interpreting continuation options, any schema change.

## 1. Parser: continuation sections

`RawHotstringDefinitionParser` accepts, after a bare `:opts:trigger::` first line, a
**continuation section** as an alternative to the existing brace body:

- Opens with a line whose first non-blank character is `(`. Anything after the `(`
  (continuation options such as `Join`, `LTrim`, `%`, `` ` ``, `C`) is accepted
  **verbatim and not interpreted**.
- Body lines are literal text, stored verbatim.
- Closes at the first line that is exactly `)` (after trim). No nesting.
- Unclosed section → error. Non-blank content after the closing `)` → same
  "content after close" rule as braces.
- `RawParseResult` gains `BodyKind` enum: `None | Inline | Braces | Continuation`,
  so the preview summary can distinguish "code block" from "multi-line text (N lines)".

Docs: continuation sections per <https://www.autohotkey.com/docs/v2/Scripts.htm#continuation-section>.

## 2. Parser: OTB, normalized on save

- `:X:trigger::{` (line ends with `{`, nothing after it) is accepted as a brace-body
  opener. Any other trailing content stays rejected.
- `Normalize()` rewrites OTB to the canonical form — `{` on its own line below the
  trigger — so stored/emitted definitions have one shape (consistent with existing
  CRLF/whitespace normalization). Preview shows the normalized result.

## 3. Comments = Description

No new field. `Description` becomes the script comment:

- **Emission:** `AhkScriptGenerator` emits `; <description>` on the line(s) above each
  hotstring **and hotkey** whose Description is non-empty. Multi-line description →
  one `; ` line per line. Applies to all kinds (Text/DateTime/Macro/Raw) and hotkeys.
- **Paste lifting (Raw only):** leading `; …` comment lines above the pasted definition
  are stripped from the stored definition and lifted into the Description field —
  only when Description is currently empty (never clobber an existing value; when
  non-empty the comment lines are still stripped). Parsed summary notes
  "comment moved to Description".
- Comment lines *inside* a `( … )` or `{ … }` body are body content and stay verbatim.

## 4. Error copy

Rule-6 message becomes:

> Add a replacement after `::`, or put `{` (code) or `(` (multi-line text) on its own
> line below the trigger.

## 5. UX: example chips

Row of four chips above the Raw textarea in `HotstringEditDialog`:

| Chip | Inserts |
|---|---|
| Inline | `:*:btw::by the way` |
| Multi-line text ( ) | `:*:col::` + `(` + sample lines + `)` |
| Code block { } | `:X:run::` + `{` + `Run "notepad.exe"` + `}` |
| With options | `:K1000 SE*:ftw::for the win` |

Clicking a chip fills the textarea; if it already holds non-template content, confirm
before overwriting. Chips are bUnit-tested.

## 6. Validation & limits (unchanged)

4200-char max, single definition per paste, unknown-option rejection, trigger
derivation + dedup, `#HotIf` context wrapping — all as-is. Continuation bodies count
toward the same length limit. Lifted comment lines do not count (they leave the
definition).

## 7. Testing

- **Parser (TDD):** continuation happy path incl. `(Join` and `(LTrim`, unclosed `)`,
  content after `)`, blank lines inside body preserved, OTB accept + Normalize goldens,
  comment-lift (empty vs non-empty Description), `BodyKind` classification.
- **Generator:** comment emission for hotstring + hotkey + multi-line description;
  none emitted when Description empty; byte-identical output for rows without
  descriptions (regression).
- **Round-trip:** paste `:*:col::` + `( … )` → save → generate → script contains the
  section byte-identical.
- **bUnit:** chips insert templates, overwrite confirm, summary shows
  "multi-line text (N lines)" and comment-lift notice.
- **E2E:** paste the colors continuation hotstring, save, download, assert exact lines.
