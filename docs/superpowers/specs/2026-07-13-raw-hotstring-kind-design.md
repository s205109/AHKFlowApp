# Raw Hotstring Kind — Design

**Date:** 2026-07-13
**Status:** Approved (brainstorming session)
**Replaces:** the `Script` hotstring kind

## Problem

Experienced AHK users can't enter a hotstring definition verbatim. The Script kind
manages trigger and options through app fields, so definitions with exotic options
(e.g. `:K1000 SE*:ftw::for the win`) can't be expressed — `K1000` and `SE` have no
field and are silently unrepresentable. Import preserves the text expansion but drops
those flags with a warning. The primary audience knows AHK syntax; let them paste the
whole definition.

## Decision summary

| Decision | Choice |
|---|---|
| Script kind | **Replaced** by Raw (new enum value 4; `Script = 3` retired, kept for legacy snapshot conversion) |
| Entry granularity | Single hotstring per entry; multi-definition paste → error telling the user to paste one definition at a time |
| Window context | Kept — Raw participates in app-managed `#HotIf` grouping |
| Edit UX | Monospace textarea + live parsed summary (trigger, options) |
| Validation | Structural rules block save; option flags validated against known AHK v2 set; **restricted subset** (see Validation limits) |
| Bulk Import | Unchanged; importing exotic/code-body lines as Raw is a follow-up backlog item |
| Storage | `Replacement` holds the verbatim definition (column widened to `nvarchar(max)`); `Trigger` derived server-side |
| CLI | Explicit changes required (own enum); minimal Raw creation via `--raw` |

## Domain & storage

- `HotstringKind.Raw = 4` is a **new** enum value; `Script = 3` is retired but kept in
  the enum (marked `[Obsolete]`, rejected by validators) so historical snapshots with
  `Kind = 3` still deserialize. Reusing value 3 is not wire- or history-compatible:
  old clients read 3 as a body-only Script while the new API would read it as a
  complete definition, and restore/revert apply snapshots without a validation pass —
  a body-only snapshot persisted as Raw would emit its body as top-level script text.
  Backend, Blazor DTOs, CLI, and tests all change explicitly (the CLI has its own
  enum copy — see UI — lists & CLI).
- For Raw rows, `Replacement` stores the **entire verbatim definition** — first line
  `:options:trigger::…`, optional brace body below. Document the kind-dependent meaning
  on the entity.
- `Trigger` is **server-derived** for Raw: create/update handlers parse it from the raw
  text and ignore the client-sent value. Because FluentValidation runs before handlers
  (`ValidatingUseCase`), the client-trigger rules (`ValidTrigger()`) in
  `CreateHotstringCommand`, `UpdateHotstringCommand`, and `GetHotstringPreviewQuery`
  are **gated to non-Raw kinds** (`When(Kind != Raw)`) — otherwise a Raw payload with
  the trigger field hidden would be rejected before reaching the handler. The parsed
  trigger is validated by rule 3 instead, and handlers parse/canonicalize it **before**
  the duplicate check, entity construction, and preview emission. Escaped characters in
  the trigger (e.g. `` `; ``) are decoded for storage, matching import. Per-owner
  uniqueness and duplicate detection work unchanged.
- Option flag columns (`IsCaseSensitive`, `IsEndingCharacterRequired`,
  `IsTriggerInsideWord`, `OmitEndingCharacter`) are ignored for Raw (left at defaults);
  the raw text is the single source of truth. Same pattern as `DateTimeFormat` being
  null for non-DateTime kinds.
- `ContextMatchType` / `ContextValue` stay active for Raw.

## Migration (schema + data)

**Schema:** `Replacement` widens from `nvarchar(4000)` to `nvarchar(max)` (not indexed,
so no index rebuild). Required for losslessness: a 4,000-character Script body grows by
the trigger line and braces when embedded in a complete definition, which would
overflow the old column for near-limit rows. Validation limits (rule 8) keep user input
bounded; the column change only removes the hard truncation point.

**Data:** the same migration rewrites `Kind = 3` rows to `Kind = 4` and sets
`Replacement` to the exact text today's emitter produces for that row, e.g.
`Send String(Random(1, 100))` with `*` set →

```
:*:rng::
{
Send String(Random(1, 100))
}
```

Implemented as raw SQL mirroring `HotstringEmitter.BuildOptions` (X/*/?/C/O logic; no
`T` for brace-body kinds) so generated scripts are **byte-identical** before and after
migration. Down-migration unsupported (documented in the migration). Migration test
must include a row with a 4,000-character body (the old max) to prove no truncation.

## Parsing

New `RawHotstringDefinitionParser` (Application/Services, static, pure — sibling of
`AhkHotstringParser`, intentionally simpler: no Send-body conversion, no v1 rescue, no
normalization):

```csharp
internal static class RawHotstringDefinitionParser
{
    public static RawParseResult Parse(string rawDefinition);
}
// RawParseResult: IsValid, Trigger, string[] OptionTokens,
//                 string[] UnknownOptionTokens, string? Error
```

Responsibilities: split options/trigger/body structurally, tokenize the options block,
count definitions in the paste.

## Validation

`HotstringRules.AddRawKindRules` replaces `AddScriptKindRules` in
`CreateHotstringCommand`, `UpdateHotstringCommand`, and `GetHotstringPreviewQuery`.
All rules `When(Kind == Raw)`:

| # | Rule | Message |
|---|---|---|
| 1 | First non-blank line matches `:options:trigger::` | "Not a valid hotstring definition — expected `:options:trigger::replacement`." |
| 2 | Exactly one definition in the paste | "Multiple hotstrings detected — paste one definition at a time." |
| 3 | Parsed trigger non-empty, ≤ `TriggerMaxLength`, no line breaks/tabs | existing trigger messages |
| 4 | Every option token in the known AHK v2 set | "Unknown hotstring option '{token}'." |
| 5 | No line starting with `#` | carried over from Script rules |
| 6 | Brace body (when present) has balanced braces — **not** applied to inline replacements | "Raw definition must have balanced braces." |
| 7 | First line ending in bare `::` (no inline replacement) requires a `{` brace body; inline replacement forbids further lines; no content after the closing `}` | "Raw definition has content after the closing brace." |
| 8 | Total length ≤ `RawDefinitionMaxLength` (4200) | new message |

Rule 8 uses a Raw-specific constant (4,200 = 4,000 body + trigger, options, and brace
overhead) so migrated near-limit Script rows remain editable; other kinds keep
`ReplacementMaxLength` (4000).

**Known AHK v2 option set (rule 4):** `*`/`*0`, `?`/`?0`, `B`/`B0`, `C`/`C0`/`C1`,
`K<n>` (incl. `K-1`), `O`/`O0`, `P<n>`, `R`/`R0`, `S`/`S0`, `SI`/`SP`/`SE`, `T`/`T0`,
`X`/`X0`, `Z`/`Z0`. Case-insensitive; whitespace between tokens allowed. `S`/`S0`
(suspend-exempt) are confirmed valid per the official v2 docs. Re-verify the final set
against <https://www.autohotkey.com/docs/v2/Hotstrings.htm> during implementation and
cite the URL in a code comment.

**Validation limits — Raw supports a restricted subset of AHK v2 (deliberate):**

- Rule 6 counts `{`/`}` characters in the brace body with no string-literal, comment,
  or continuation-section awareness — the same D12 limitation as the old Script rules.
  A brace inside a quoted string or comment can false-positive reject a valid body.
  Restricting the check to brace bodies (rule 6) already accepts inline definitions
  like `:*:brace::{{}` that pure character counting would reject.
- Triggers containing escaped tab/newline (`` `t ``/`` `n ``, valid per the AHK docs)
  are rejected by rule 3 — the `Trigger` column and duplicate detection assume
  single-line triggers.
- These limits are documented in the code (`AddRawKindRules` XML docs) and in the edit
  dialog's help text; lifting them (a real lexer for strings/comments/continuation
  sections) is explicitly out of scope.

## Emission & preview

- `HotstringEmitter.Emit()` gains a Raw branch returning `hs.Replacement` **verbatim**
  — no option building, no escaping, no wrapping. `AhkScriptGenerator` joins entries
  with `\n`, so multi-line definitions drop in unchanged.
- Save-time normalization (the only mutation): CRLF→LF, trim leading/trailing blank
  lines and trailing whitespace. Interior lines and indentation preserved exactly.
- `#HotIf` context grouping in `AhkScriptGenerator` unchanged — Raw rows group by
  `(ContextMatchType, ContextValue)` like every kind. Trigger-ordinal sorting works via
  the derived `Trigger`.
- Preview pipeline works as-is: `GetHotstringPreviewQueryHandler` → `Emit()` echoes the
  raw text plus the `#HotIf` wrap when a context is set. The dialog keeps its
  "Generated AutoHotkey code" panel for Raw.

## UI — edit dialog

- Kind toggle item `Script` → `Raw`.
- Raw selected: monospace (`ahk-mono`) 8-line textarea labeled **"Raw definition"**,
  placeholder `:K1000 SE*:ftw::for the win`. Trigger field and the four trigger-option
  checkboxes hidden. Description, profiles, categories, window context stay.
- **Parsed summary** below the textarea (`Trigger: ftw` / `Options: K1000 SE *`),
  server-authoritative: extend `HotstringPreviewDto` with optional
  `RawSummary(Trigger, OptionTokens)` populated for Raw; the client renders it from the
  existing debounced preview call. Validation failures surface through the existing
  preview error path.
- Multi-definition paste: rule-2 error rendered under the textarea, telling the user to
  paste one definition at a time. **No Import referral** — Import drops the exotic
  flags Raw exists to preserve; a link there would silently lose data. Revisit once
  Raw-aware import ships (backlog follow-up).
- Kind switching mid-edit: **→ Raw** composes a starting definition from current fields
  (same shape as the migration); **Raw → other** shows a confirmation first when the
  definition carries option flags the structured fields can't express ("Options
  `K1000 SE` will be discarded — continue?"), then moves the parsed trigger into the
  Trigger field and the body (brace content or inline replacement) into Replacement;
  option checkboxes reset to defaults.
- The Text-kind "looks like AHK code" suggestion becomes **"Switch to Raw"** using the
  compose behavior.

## UI — promote inline row to full editor

Desktop grid only (mobile FAB already opens the full dialog):

- While a row is inline-editing (new draft or existing row), a third action button
  (`Tune` icon, tooltip "More options / change type") appears next to ✓ commit and
  ✗ cancel.
- Clicking promotes the row to `HotstringEditDialog`, carrying over everything typed
  (trigger, replacement, description). The kind toggle is immediately available.
- **Draft row:** create dialog seeded with draft values; inline draft removed; dialog
  cancel **restores the inline draft with its values**.
- **Existing row:** edit dialog seeded with current in-row (possibly modified) values;
  cancel returns to the inline edit state with those values intact.
- Save follows the dialog's normal create/update path. **Add** still defaults to an
  inline Text draft.

## UI — lists & CLI

- Trigger column works via derived trigger (desktop grid + mobile list).
- Mobile list: show kind chip "Raw"; suppress the four option checkmarks
  (`End-char / In-word / Case / Omit end-char`) for Raw rows — they're meaningless.
- **CLI requires explicit changes** — it has its own `HotstringKind` copy and table
  labels (`IHotstringsApiClient.cs`), and its `CreateHotstringDto` has no `Kind`:
  - Mirror the enum change (`Raw = 4`, drop `Script`) and table/JSON label.
  - Minimal Raw creation: `ahkflow hotstrings new --raw "<definition>"` — mutually
    exclusive with `--trigger`/`--replacement`; sends `Kind = Raw` with the definition
    as `Replacement` (CLI `CreateHotstringDto` gains `Kind`); server does all parsing
    and validation, CLI just relays ProblemDetails errors. Keeps the first-class CLI
    at feature parity for create; richer Raw UX (edit, summary) stays out of scope.

## Error handling

- Raw validation runs server-side via the existing `ValidatingUseCase` decorator →
  `Result.Invalid` → RFC 9457 ProblemDetails.
- Duplicate derived trigger → existing unique-constraint conflict handling.
- History: existing snapshots keep `Kind=3` (body-only `Replacement`) — they are
  **not** rewritten. Restore/revert handlers apply snapshots without a validation
  pass, so they gain a **legacy conversion step**: on deserializing a snapshot with
  `Kind == Script`, compose the full Raw definition from the snapshot's body + option
  flags (same transform as the migration, shared composer) and persist it as
  `Kind = Raw`. Snapshots written after the change store `Kind=4` + verbatim
  `Replacement` and restore as-is.

## Security notes

- The app never executes AHK; it generates text the owner downloads. Raw adds no new
  code-execution surface (Script already emitted arbitrary AHK verbatim).
- Structural rules 2/5/6/7 prevent a paste from smuggling extra definitions or
  directives that would corrupt `#HotIf` grouping or the script structure.
- Blazor auto-encodes output; never render raw content via `MarkupString`.
- If sharing between users is ever added, revisit the threat model (applies to all
  kinds, not just Raw).

## Testing

- **TDD first:** `RawHotstringDefinitionParser` unit tests (structure, flag
  tokenization incl. `K1000 SE*`, multi-definition detection, brace bodies, escaped
  triggers); `AddRawKindRules` validator tests (all 8 rules; flag edge cases `K-1`,
  `P9`, case-insensitivity, `*0`).
- **Emitter:** verbatim emission + context wrapping in `AhkScriptGeneratorTests`;
  round-trip test — paste → save → generate → byte-identical line.
- **Migration:** Testcontainers integration test asserting a seeded Script row's
  generated script is byte-identical before/after migration — including a row with a
  4,000-character body (old column max) proving no truncation after the widen.
- **History:** restore/revert of a legacy `Kind=3` snapshot converts to a valid Raw
  row (composed definition, derived trigger); post-change snapshots round-trip as-is.
- **API integration:** create/update/preview with Raw payloads (valid,
  multi-definition, unknown flag, directive line, empty client trigger — must pass
  validation and derive server-side).
- **bUnit:** dialog Raw mode (textarea, hidden fields, parsed summary, import-referral
  error, kind-switch compose/decompose); grid promote action (draft + existing row,
  cancel restores).
- **E2E:** rewrite `ScriptHotstringFlowTests` → `RawHotstringFlowTests` (paste
  `:K1000 SE*:ftw::for the win`, verify summary, save, download contains the exact
  line); add promote-flow coverage.
- Existing suites (`HotstringSnapshotCompatibilityTests`, import tests) stay green —
  Import behavior intentionally untouched.

## Out of scope

- Raw rows in bulk Import (follow-up backlog item).
- CLI Raw UX beyond minimal `--raw` creation (edit, parsed summary, listing details).
- Semantic validation of the AHK body — only structure and option flags are checked;
  a string/comment/continuation-aware lexer (see Validation limits) is likewise out.
