# Plan: Raw hotstring continuation sections, OTB & comments

**Date:** 2026-07-14
**Spec:** [2026-07-14-raw-continuation-otb-comments-design.md](../specs/2026-07-14-raw-continuation-otb-comments-design.md)
**Branch:** `feature/wt-raw-continuation-otb-comments` (worktree)

## Key files

| Area | File |
|---|---|
| Parser | `src/Backend/AHKFlowApp.Application/Services/RawHotstringDefinitionParser.cs` |
| Validation | `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs` (`AddRawKindRules`) |
| Save handlers | `Commands/Hotstrings/CreateHotstringCommand.cs`, `UpdateHotstringCommand.cs` |
| Preview | `Queries/Hotstrings/GetHotstringPreviewQuery.cs`, `DTOs/HotstringDto.cs` (`RawSummaryDto`, `HotstringPreviewRequestDto`) |
| Generator | `Services/AhkScriptGenerator.cs`, `Services/HotstringEmitter.cs` |
| UI | `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`, `DTOs/HotstringPreviewDtos.cs` |
| Tests | `tests/AHKFlowApp.Application.Tests/Services/RawHotstringDefinitionParserTests.cs`, generator tests, bUnit dialog tests, `tests/AHKFlowApp.E2E.Tests/RawHotstringFlowTests.cs` |

## Task 1 — Parser: structural rework (TDD)

The parser currently computes `DefinitionCount` as a flat line scan before body
classification, and `HotstringRules` rule 5 does its own flat directive scan. Both must
become body-aware, so the parser takes ownership of line classification:

1. **`RawParseResult` grows:** `BodyKind` enum (`None | Inline | Braces | Continuation`),
   `BodyLineCount`, `HasDirectiveOutsideBody` (rule 5 moves in here — the validator keeps
   only the message), and `LiftedComment` (Task 3; declare now to avoid churn).
2. **Parse flow:** find first non-blank line → match `:opts:trigger::` → classify body
   with the parsed option tokens (`ClassifyBody(optionTokens, inlineRest, trailing)`):
   - Inline (unchanged), brace body (unchanged scan), **continuation section**: first
     non-blank trailing line starts with `(` → continuation. Opener-line remainder is
     pass-through, but reject if it contains `)`. Body = verbatim lines until first line
     that is exactly `)` after trim (no nesting). Unclosed → error; non-blank content
     after close → "content after close" error.
   - `DefinitionCount` and the directive check skip lines inside brace/continuation
     bodies — count/scan only structural lines.
3. Update the class doc comment (it currently says continuation sections are rejected).

**Tests first** (parser test file): continuation happy path, `(Join`, `(LTrim` openers,
opener containing `)` rejected, unclosed section, content after `)`, interior blank lines
preserved, `::example::text` and `# Heading` inside body not counted as definition or
directive, `BodyKind`/`BodyLineCount` for all four shapes.

## Task 2 — Parser: OTB + body-aware Normalize (TDD)

1. **OTB classification (option-sensitive):** in `ClassifyBody`, `inlineRest.Trim() == "{"`
   is a brace-body opener **only when** neither `T` nor `R` is active (`T0`/`R0` don't
   suppress). With `T`/`R` active it's an inline literal `{` replacement. OTB opener →
   validate the brace body starting from that `{` plus trailing lines.
2. **`Normalize` becomes parse-aware:**
   - Per-line `TrimEnd()` and blank-line trimming skip lines inside a continuation body
     (byte-for-byte preservation, `RTrim0`). Requires a light structural pass inside
     Normalize (reuse the same body-boundary logic as Parse — extract a shared helper).
   - Genuine OTB → rewritten to `{` on its own line below the trigger.
   - Invalid input passes through with only the existing line-ending/trim behavior on
     structural lines (validator reports errors on the normalized text as today).

**Tests first:** OTB accept + Normalize golden (`:X:run::{` → canonical), `:T:brace::{`
and `:R:brace::{` inline-literal (not OTB) while `:*:x::{` is OTB, `:T0:x::{` is OTB,
`RTrim0` regression — trailing spaces/tabs inside `( … )` survive Normalize byte-for-byte,
structural lines outside the body still trimmed.

## Task 3 — Comment lifting (parser + validator + handlers)

1. **Parser:** leading `; …` lines above the first definition line are consumed, joined
   with `\n` (strip `;` + one following space per line), exposed as `LiftedComment`
   (null when none). They no longer count as content for "first line" matching.
   `Normalize` also strips them so the persisted definition never contains them —
   **decide ordering:** Normalize strips + returns them, or handlers call
   `Parse` first and persist `definition-without-comments` (pick: Normalize keeps
   signature `string → string` but skips comment lines; Parse exposes `LiftedComment`
   and `DefinitionWithoutComments` — handlers persist the latter).
2. **Merge policy helper** (new small static, e.g. `RawCommentLift.Merge(description,
   lifted)`): empty → lifted; equal → drop; differs → append on new line. Shared by
   validator (length check) and both save handlers.
3. **Validator (`AddRawKindRules`):** gains a `description` expression parameter; after
   structural checks, compute merged Description and fail with the spec's message when
   it exceeds `DescriptionMaxLength` (200). Lifted lines excluded from the 4200 length
   check (they leave the definition) — but rule 8 runs on raw input before parsing;
   adjust to check the definition-minus-comments length.
4. **Handlers (Create/Update):** for Raw, persist `DefinitionWithoutComments` (normalized)
   and the merged Description. Comment lines inside `{…}`/`(…)` bodies stay verbatim.

**Tests first:** merge matrix (empty / equal / differing), 200-char overflow error
message, comments inside bodies untouched, lifted comment excluded from 4200 count,
handler persists stripped definition + merged Description (Create + Update).

## Task 4 — Comment emission (generator + preview)

1. **Shared formatter:** `HotstringEmitter` (or a tiny `DescriptionComment` helper) —
   Description → one `; <line>` per line; empty/null → nothing.
2. **`AhkScriptGenerator`:** emit comment lines above each hotstring (context groups and
   global group) and each hotkey with non-empty Description. All kinds.
3. **Preview:** `HotstringPreviewRequestDto` (+ Blazor mirror) gains `Description`;
   `GetHotstringPreviewQueryHandler` passes it into the transient hotstring and prepends
   the formatted comment lines to the snippet via the shared formatter.
4. **`RawSummaryDto`** (+ Blazor mirror) → `(Trigger, OptionTokens, BodyKind,
   BodyLineCount, LiftedComment)`. Preview handler fills from the parse result.
   `BodyKind` enum must exist client-side too (Blazor DTOs file).

**Tests:** generator emits for hotstring + hotkey + multi-line Description; nothing when
empty; byte-identical output for description-less rows (regression against existing
goldens); preview snippet includes `; comment` lines; preview `RawSummary` carries new
fields.

## Task 5 — Error copy

Rule-6 `BraceRequiredError` becomes:
> Add a replacement after `::`, or put `{` (code) or `(` (multi-line text) on its own line below the trigger.

Update the parser constant + every test asserting the old copy (parser tests, any
validator/E2E assertions on "Put `{` on its own line").

## Task 6 — UI: example chips + summary

In `HotstringEditDialog.razor` (Raw kind only), a `MudChipSet`/chip row above the
textarea with the four spec templates (Inline / Multi-line text `( )` / Code block `{ }` /
With options). Clicking fills `Item.Replacement`; if the field holds non-template,
non-empty content, confirm via the existing `ConfirmSwitchAsync`-style dialog before
overwriting. Summary row renders "code block" / "multi-line text (N lines)" from
`BodyKind`/`BodyLineCount` and the "comment moved to Description" notice from
`LiftedComment`.

**bUnit tests:** each chip inserts its template, overwrite-confirm path, summary shows
body-kind text + N lines + comment-lift notice.

## Task 7 — Round-trip + E2E

- **Round-trip integration test:** paste `:*:col::` + `( … )` colors sample → save via
  Create handler → `AhkScriptGenerator.Generate` → script contains the section
  byte-identical.
- **E2E (`RawHotstringFlowTests`):** paste the colors continuation hotstring, save,
  download, assert exact lines (extend the existing promote-flow pattern).

## Task 8 — Verify

`dotnet build` + `dotnet test` + `dotnet format --verify-no-changes`; run E2E project;
then PR per GitHub Flow.

## Sequencing

Tasks 1→2→3 are parser-layer and strictly ordered (TDD each). Task 4 is independent of
2 but needs 3's `LiftedComment`. Task 5 anytime after 1. Task 6 needs 4's DTO shape.
Commit per task (feature + its tests together).

## Unresolved questions

1. `RawDefinition.Decompose` (client, Raw→structured switch): treat `( … )` body like a
   brace body (lines between `(` and `)`), or leave untouched (whole text becomes body)?
   Spec silent — plan assumes: handle it, minimal.
2. Rule 8 (4200) on definition-minus-comments — OK that a paste >4200 chars *with*
   comments now passes if the definition alone fits?
3. Chip overwrite confirm: reuse the existing MessageBox confirm, or inline MudPopover?
   Plan assumes MessageBox (matches kind-switch confirms).
