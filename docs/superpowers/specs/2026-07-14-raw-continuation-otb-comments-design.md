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

- Opens with a line whose first non-blank character is `(`. The remainder of the
  opener line (continuation options such as `Join`, `LTrim`, `RTrim0`, `C`, `` ` ``)
  is **unvalidated pass-through** — stored verbatim, not interpreted — with one
  exception: an opener line containing `)` is rejected (AHK itself treats such a
  line as an expression, not a continuation opener).
- Body lines are literal text, stored verbatim — including trailing whitespace and
  interior blank lines (significant under `RTrim0`).
- Closes at the first line that is exactly `)` (after trim). No nesting.
- Unclosed section → error. Non-blank content after the closing `)` → same
  "content after close" rule as braces.
- **Existing checks become body-aware:** `DefinitionCount` (rule 2) and the
  directive rejection (rule 5, `HotstringRules.cs`) skip lines inside a
  continuation-section body — literal text like `::example::text` or `# Heading`
  must not be misread as another definition or a directive.
- `RawParseResult` gains `BodyKind` enum (`None | Inline | Braces | Continuation`)
  and `BodyLineCount`, so the preview summary can distinguish "code block" from
  "multi-line text (N lines)".

Docs: continuation sections per <https://www.autohotkey.com/docs/v2/Scripts.htm#continuation-section>.

## 2. Parser: OTB, normalized on save

- `:X:trigger::{` (line ends with `{`, nothing after it) is accepted as a brace-body
  opener. Any other trailing content stays rejected.
- **Option-sensitive:** a trailing lone `{` is an OTB opener only when neither `T`
  nor `R` (text/raw mode) is in effect on the definition line (`T0`/`R0` cancel the
  mode, so they do not suppress OTB). With `T` or `R` active, `:T:brace::{` is an
  **inline literal replacement** that types `{` — per the official hotstring brace
  rule. `ClassifyBody` therefore receives the parsed option tokens.
- `Normalize()` rewrites genuine OTB to the canonical form — `{` on its own line
  below the trigger — so stored/emitted definitions have one shape (consistent with
  existing CRLF/whitespace normalization). Preview shows the normalized result.
- **Normalization is body-aware:** per-line trailing-whitespace trimming and blank-line
  trimming apply only *outside* a continuation-section body; lines between `(` and `)`
  are preserved byte-for-byte (trailing spaces/tabs are significant under `RTrim0`).

## 3. Comments = Description

No new field. `Description` becomes the script comment:

- **Emission:** `AhkScriptGenerator` emits `; <description>` on the line(s) above each
  hotstring **and hotkey** whose Description is non-empty. Multi-line description →
  one `; ` line per line. Applies to all kinds (Text/DateTime/Macro/Raw) and hotkeys.
- **Paste lifting (Raw only):** leading `; …` comment lines above the pasted definition
  are stripped from the stored definition and lifted into Description with an explicit
  merge policy — no silent data loss:
  - Description empty → lifted comment becomes the Description.
  - Description equals the lifted comment → dropped as a duplicate.
  - Description differs → lifted comment is **appended** on a new line.
  - If the merged Description would exceed `DescriptionMaxLength` (200), validation
    fails with an explicit error ("Pasted comment does not fit in Description
    (200-char max) — shorten it or remove the comment lines") and nothing is saved.
  The parsed summary notes "comment moved to Description".
- Comment lines *inside* a `( … )` or `{ … }` body are body content and stay verbatim.

### Preview contract

The existing preview endpoint carries the new facts end-to-end (backend DTO +
mirrored Blazor DTO):

- `RawSummary` grows from `(Trigger, OptionTokens)` to
  `(Trigger, OptionTokens, BodyKind, BodyLineCount, LiftedComment)` —
  `LiftedComment` is the comment text the save would move into Description
  (null when none), letting the dialog render the "comment moved to Description"
  notice and the merge outcome before saving.
- The preview request gains `Description`, and `GetHotstringPreviewQuery`'s handler
  passes it into the transient hotstring (today it hardcodes `Description: null`),
  so the preview script shows the emitted `; comment` lines exactly as the download
  will.
- One shared comment formatter (Description → `; ` lines) is used by both
  `AhkScriptGenerator` and the preview path — single source of truth.

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

- **Parser (TDD):** continuation happy path incl. `(Join` and `(LTrim`, opener line
  containing `)` rejected, unclosed `)`, content after `)`, blank lines inside body
  preserved, `RTrim0` regression with significant trailing spaces/tabs surviving
  Normalize byte-for-byte, body lines like `::example::text` / `# Heading` not
  counted as definitions or directives, OTB accept + Normalize goldens,
  `:T:brace::{` and `:R:brace::{` classified as inline literal (not OTB) while
  `:*:x::{` is OTB, comment-lift merge matrix (empty / equal / differing Description)
  + 200-char overflow error, `BodyKind` + `BodyLineCount` classification.
- **Generator:** comment emission for hotstring + hotkey + multi-line description;
  none emitted when Description empty; byte-identical output for rows without
  descriptions (regression).
- **Round-trip:** paste `:*:col::` + `( … )` → save → generate → script contains the
  section byte-identical.
- **bUnit:** chips insert templates, overwrite confirm, summary shows
  "multi-line text (N lines)" and comment-lift notice.
- **E2E:** paste the colors continuation hotstring, save, download, assert exact lines.
