# Import v1 Code-Body & Multi-Line Hotstrings — Design

**Date:** 2026-07-06
**Status:** Designed — Codex-reviewed 2026-07-06 — awaiting implementation plan
**Parent:** [Import Existing `.ahk` Hotstrings](2026-07-05-ahk-hotstring-import-design.md)

## Purpose

AHKFlow is **AutoHotkey v2 only** (default template emits `#Requires AutoHotkey v2.0`; generator
emits v2 `Send("...")`/`Run("...")`; parser is the v2 inverse). Real users still have **v1
code-body hotstrings** — a trigger that fires a block of script instead of expanding to static
text. Today the importer rejects every one as **Invalid — "Replacement is required."** and rejects
the canonical multi-line form (`::sig::` + `( ... )`) as *"Multi-line replacements are not
supported."* Bodies are silently skipped.

Nothing is mis-imported, but the messages are wrong and convertible text is lost. This design makes
rejections honest and auto-converts *static text* bodies into multi-line replacements.

### Motivating examples (user's real hotstrings)

| Trigger | Body | Desired outcome |
|---|---|---|
| `::mvgp::` | two `send ...{Return}` lines | Convert → `"Met vriendelijke Groet,\nBart Segers"` |
| `::dbg::` | `send mocha --debug-brk` (twice in file) | Convert → `"mocha --debug-brk"`; 2nd is Duplicate |
| `::d-time::` | `FormatTime` + `SendInput %CurrentDateTime%` | Reject — runs time-dependent logic |
| `::li::` | clipboard save / `Send ^v` / restore | Reject — runs logic + keystrokes |

## Decisions (user-approved 2026-07-06)

| Decision | Choice |
|---|---|
| Outcome | **Honest reject + convert static text** — logic bodies rejected with accurate reason; static-text bodies imported |
| Converter aggressiveness | **Conservative send-only** — convert only if every body line is a Send-family command sending literal text; reject any `%` character (not just paired `%var%` dereferences), other commands, modifier keystrokes |
| Continuation-section form | **Convert** the canonical `::trigger::` + `( ... )` block (was rejected) into a multi-line replacement |
| Generator encoding | **Single-line backtick escaping** (`` `n ``) — keeps one-line-per-hotstring layout |

## Latent bug (fixed here)

The replacement field is already multi-line (`HotstringEditDialog.razor` `Lines="3"`; domain and
validation allow `\n` within the 4000-char cap), but `AhkScriptGenerator.FormatHotstring` emits
`:{options}:{trigger}::{replacement}` on **one physical line with no escaping**. Any replacement
containing a newline — entered via the UI *today*, or produced by this feature — generates a broken
`.ahk` file. Fixing the generator is a prerequisite that also closes this pre-existing bug.

## Architecture

Three cohesive changes, all in the Application layer; server-side parser/generator remain the
single source of truth. No DTO, domain, validation, or UI-form changes.

```
Replacement text (may contain \n)
   ─ generate ─►  :opts:trigger::escaped        (Part 1: `n / `t / `r / `` escaping)
   ◄─ parse ───   decode escapes back           (Part 2: round-trip symmetry)

::trigger:: + ( ... )    ─ parse ─► multi-line replacement   (Part 2)
::trigger:: + send body  ─ parse ─► convert or honest reject (Part 3)
```

### Part 1 — Generator escapes replacements
`Services/AhkScriptGenerator.FormatHotstring`. Escape the replacement so each hotstring stays on one
physical line. The generator emits **five** escape sequences, applied in this order (backtick first
so it isn't double-escaped): `` ` ``→``` `` ```, newline→`` `n ``, CR→`` `r ``, tab→`` `t ``,
`;`→`` `; ``. The `;` escape is required because AHK v2 treats a whitespace-preceded `;` as an
end-of-line comment even on a hotstring's replacement side (`https://www.autohotkey.com/docs/v2/misc/EscapeChar.htm`);
escaping every `;` unconditionally is lossless since the decoder normalises `` `; `` back to `;`.
Every other character (spaces, `%`, `{`, `}`, `!`, `^`, `+`, `#`) is written literally — none of
those are special on the replacement side.

### Escape grammar & decoding contract (Part 1 ↔ Part 2)

This is the exact grammar the parser MUST implement so export→import→export is lossless. Decoding
follows AHK v2 semantics: the backtick is the escape character and escapes the **single** next
character.

**Decode algorithm** — one left-to-right pass over the replacement text captured after `::`:

```
for each position:
  if char != '`' -> emit char verbatim
  else (backtick), look at next char x:
      x == '`' -> emit '`'        (doubled backtick, consume both)
      x == 'n' -> emit LF
      x == 'r' -> emit CR
      x == 't' -> emit TAB
      x == 's' -> emit SPACE
      x == ';' -> emit ';'
      x is any other char -> emit x verbatim   (AHK: backtick escapes next char)
      trailing lone '`' at end of string -> drop it
```

Handling doubled backtick inline in the same pass removes the "literal backtick before n/r/t" hazard:
`` ``n `` decodes to a literal backtick then `n`, never a newline. Because no backtick ever survives
decoding, re-generation is deterministic. The set the *generator* re-escapes (backtick/LF/CR/TAB) is a
subset of what the *decoder* accepts, so text that arrives with `` `s ``/`` `; `` normalises to a
literal space/semicolon and still round-trips to the same final text. **Known limitation:** exotic AHK
escapes with no text meaning (`` `a `` bell, `` `b `` backspace, `` `f ``, `` `v ``) decode to the
literal letter, not the control char — acceptable for a text-replacement tool; documented, not a bug.

### Part 2 — Parser decodes escapes + converts continuation sections
`Services/AhkHotstringParser`.

- **Decode** the matched single-line replacement per the grammar above, applied *after* the regex
  splits trigger/replacement.
- **Continuation section:** the existing branch detecting `::trigger::` (empty replacement)
  immediately followed by a lone `(` currently emits Invalid. Change to collect lines until the
  closing lone `)`, join with `\n`, run normal trigger/replacement validation → Ready. A continuation
  section is **not** escape-decoded line-by-line (its lines are already literal text); only the
  single-line `::trigger::replacement` form is decoded. If EOF is reached before a lone `)`, mark
  Invalid "Unterminated continuation section." and do not consume beyond EOF.

### Part 3 — Parser detects & converts code bodies
Same file. When `::trigger::` has an empty replacement and is **not** followed by a lone `(`:

1. Peek next non-blank line. If none, or it is another hotstring (`^:...::`) → keep current
   behavior: Invalid "Replacement is required." (a genuinely empty hotstring).
2. Otherwise it is a **code body**. Scan forward collecting body lines with these **hard
   boundaries** (in priority order), so a malformed body never swallows the next entry:
   - A line matching the hotstring pattern (`^:...::`) **before** any `return` → stop, mark the
     current entry Invalid "Unterminated code body (no `return` before next hotstring).", and **do
     not consume** that line — the loop re-processes it as its own row.
   - A lone `(` line opens a nested continuation block; ignore `return`/`)`/hotstring-looking lines
     until the matching lone `)`. (Only lone-`(`…lone-`)` lines are tracked; parentheses inside code
     expressions are not balanced — they never appear as a lone line.)
   - The first line whose trimmed value equals `return`/`Return` (case-insensitive) outside a nested
     block → consume it and stop; this is the terminated body.
   - EOF before a `return` → mark Invalid "Unterminated code body (no `return`)." Consume to EOF.
     Blank lines and comment lines (`;`) inside the body are skipped, not terminators.
3. Classify a **terminated** body via `TryConvertSendBody(bodyLines, out replacement, out reason)`:
   - Every non-blank, non-comment body line must be a Send-family command:
     `^\s*(Send|SendInput|SendText|SendRaw|SendEvent|SendPlay)\b\s*,?\s*(.*)$` (case-insensitive).
     Any other line (`FormatTime`, `Clipboard :=`, `sleep`, assignments, bare expressions) → reject.
   - **v1 argument parsing** for the captured arg region:
     - Strip a single optional leading `,` and the leading whitespace after the command (v1 trims
       leading whitespace of the first parameter). Internal and trailing literal spaces are kept.
     - **Inline comments are ambiguous → reject the whole body.** If the arg contains an unescaped
       `;` preceded by whitespace/tab (v1 comment start), reject with reason "Inline comment in Send
       — not imported." Only `` `; `` (escaped) is a literal semicolon.
     - Reject if the arg is itself a continuation opener (a lone `(` as the argument).
   - **Reject any arg containing a bare `%` character.** This is intentionally broader than
     detecting a paired `%identifier%` dereference: a v1 script has no reliable way to distinguish a
     literal percent sign (`Send, 100% done`) from a variable dereference (`Send, %CurrentDateTime%`)
     without a full v1 expression parser, which this converter deliberately does not implement.
     Conservative-reject wins over silently importing wrong text — a literal-percent hotstring is
     rejected with an honest reason and can be re-entered manually.
   - Interpreting sends (`Send/SendInput/SendEvent/SendPlay`): reject bare `^ ! + #` (modifier
     keystrokes) and any `{...}` token other than `{Enter}`/`{Return}`→`\n` and `{Tab}`→`\t`.
   - Literal sends (`SendText/SendRaw`): all chars literal (braces/modifiers included); still reject
     any `%` for the same reason.
   - Success: concatenate each send's literal text **in order with no separator between sends**
     (only `{Enter}`/`{Return}` introduce newlines) → replacement, status Ready.
   - Failure: Invalid with an honest reason naming the blocker, e.g.
     `"Code-body hotstrings that run logic aren't supported (found: FormatTime)."`; generic
     fallback `"Code-body hotstrings that run logic aren't supported."`

### Unchanged (verified)
- **Status enum / DTOs** — Ready/Warning/Duplicate/Invalid already sufficient.
- **Duplicate detection** — `HotstringImportClassifier.MarkDuplicates` already flags the repeated
  `::dbg::` (intra-batch) and existing triggers.
- **Domain / validation** — `Hotstring.Replacement` and the rules already allow `\n` ≤ 4000 chars.
- **UI edit form** — replacement field already multi-line.

## Error handling
Conversion is best-effort and total: a body is either converted (Ready) or rejected (Invalid) with
a reason — never a hard failure. Continues the existing preview contract: every source line surfaces
with a status; nothing throws.

## Testing
- `AhkScriptGeneratorTests` — newline/backtick/tab/CR escaping produce single-line output.
- `AhkHotstringParserTests` — **update** `Parse_MultiLineContinuation_IsInvalidAndConsumesInnerLines`
  (now Ready, converted); add send-body convert (mvgp, dbg) and reject (d-time, li) cases.
- **Negative / adversarial tests** (from Codex review — must reject or preserve, never silently
  change text):
  - Escape decode: doubled backtick → single backtick; `` ``n `` (literal backtick + n) stays two
    chars, not a newline; unknown `` `q `` → literal `q`; trailing lone backtick dropped;
    `` `s ``→space, `` `; ``→`;`.
  - Round-trip ordering: replacement containing backtick + newline + tab survives
    generate→parse→generate unchanged.
  - Send arg: `Send, hello ; note` → inline comment rejected (not imported as "hello ; note");
    `` Send, a`;b `` → literal `a;b` kept; leading whitespace after comma trimmed.
  - Scan boundary: code body with no `return` followed by another `::trigger::` → first row Invalid
    "Unterminated…", second hotstring still parsed as its own row; nested lone-`(`…`)` block
    containing a `return`/`)` doesn't falsely terminate; comment/blank lines inside body skipped.
- Generator↔parser **round-trip** integration test: a multi-line replacement survives export→import
  unchanged.
- End-to-end (`playwright-cli`): paste the four-hotstring script into the import dialog; confirm
  mvgp Ready (2-line), dbg Ready + Duplicate, d-time/li Invalid with clear reasons; import; download
  script; re-import cleanly.

## Review

Codex adversarial review (2026-07-06) on the first draft returned *needs-attention* with three
findings, all now folded in above: (1) v1 Send argument/inline-comment parsing — resolved by
explicit arg-parsing rules and rejecting inline comments; (2) underspecified escape/decode contract —
resolved by the *Escape grammar & decoding contract* section; (3) `return`-scan swallowing later
entries — resolved by the *hard boundaries* in Part 3 step 2.

## Resolved open items (2026-07-06)
- **Continuation-section defaults:** mirror AHK v2 defaults — LF join, per-line leading-whitespace
  trim. Verify against docs during impl with an indented-block test.
- **`;` in replacements:** confirmed NOT literal-safe — AHK v2 treats a whitespace-preceded `;` as
  a comment, so the generator escapes it (`` `; ``) as its fifth escape sequence (see Part 1 above).
- **Preview display:** include `white-space: pre-wrap` on the replacement cell in
  `HotstringImportDialog.razor` now — one-line CSS; converted multi-line rows must read as such.
- **Reject reasons:** granular — name the offending construct (e.g. "found: FormatTime", "Inline
  comment in Send"); generic fallback only when nothing specific is known.
