# Import v1 Code-Body & Multi-Line Hotstrings — Design

**Date:** 2026-07-06
**Status:** Designed — awaiting implementation plan
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
| Converter aggressiveness | **Conservative send-only** — convert only if every body line is a Send-family command sending literal text; reject `%variables%`, other commands, modifier keystrokes |
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
`Services/AhkScriptGenerator.FormatHotstring`. Escape in order: `` ` ``→``` `` ```, newline→`` `n ``,
CR→`` `r ``, tab→`` `t ``. Output stays a single physical line.

### Part 2 — Parser decodes escapes + converts continuation sections
`Services/AhkHotstringParser`.

- **Decode** the matched single-line replacement (inverse of Part 1) so a literal backtick and
  embedded newlines round-trip through export→import.
- **Continuation section:** the existing branch detecting `::trigger::` (empty replacement)
  immediately followed by a lone `(` currently emits Invalid. Change to collect lines until the
  closing lone `)`, join with `\n`, run normal trigger/replacement validation → Ready.

### Part 3 — Parser detects & converts code bodies
Same file. When `::trigger::` has an empty replacement and is **not** followed by a lone `(`:

1. Peek next non-blank line. If none, or it is another hotstring (`^:...::`) → keep current
   behavior: Invalid "Replacement is required." (a genuinely empty hotstring).
2. Otherwise it is a **code body**. Scan forward, collecting body lines until (and consuming) the
   first line whose trimmed value equals `return`/`Return` (case-insensitive), tracking `( )`
   nesting so a `return` inside a block doesn't falsely terminate; stop at EOF if no `return`.
3. Classify via `TryConvertSendBody(bodyLines, out replacement, out reason)`:
   - Every non-blank body line must match
     `^\s*(Send|SendInput|SendText|SendRaw|SendEvent|SendPlay)\s*,?\s*(.*)$` (case-insensitive).
     Any other line (`FormatTime`, `Clipboard :=`, `sleep`, assignments, bare expressions) → reject.
   - Reject any send arg containing `%...%` (v1 variable deref → dynamic).
   - Interpreting sends (`Send/SendInput/SendEvent/SendPlay`): reject bare `^ ! + #` (modifier
     keystrokes) and any `{...}` token other than `{Enter}`/`{Return}`→`\n` and `{Tab}`→`\t`.
   - Literal sends (`SendText/SendRaw`): all chars literal; still reject `%...%`.
   - Success: concatenate each send's literal text **in order with no separator between sends**
     (only `{Enter}`/`{Return}` introduce newlines) → replacement, status Ready.
   - Failure: Invalid with an honest reason, e.g.
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
  (now Ready, converted); add send-body convert (mvgp, dbg), reject (d-time, li) cases; escape
  decode.
- Generator↔parser **round-trip** test: a multi-line replacement survives export→import unchanged.
- End-to-end (`playwright-cli`): paste the four-hotstring script into the import dialog; confirm
  mvgp Ready (2-line), dbg Ready + Duplicate, d-time/li Invalid with clear reasons; import; download
  script; re-import cleanly.

## Open items
- Mirror AHK v2 continuation-section defaults exactly (newline join + per-line leading-whitespace
  trim) — verify against docs; affects fidelity, not the examples here.
- Optional display polish: import/preview dialog cells collapse `\n`; add `white-space: pre-wrap`
  on the replacement cell, or defer to backlog.
- Reject-reason granularity: name the offending construct vs. one generic "runs logic" message.
