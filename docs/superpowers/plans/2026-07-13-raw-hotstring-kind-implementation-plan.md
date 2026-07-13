# Plan: Raw hotstring kind — implementation

**Date:** 2026-07-13
**Spec:** [2026-07-13-raw-hotstring-kind-design.md](../specs/2026-07-13-raw-hotstring-kind-design.md)
**Tracker:** [2026-07-13-raw-hotstring-kind-plan.md](2026-07-13-raw-hotstring-kind-plan.md)
**Status:** Ready to implement; awaiting user go-ahead on pacing

File-level, dependency-ordered tasks. TDD where the spec marks it (parser,
validators, composer). Each phase is a candidate atomic commit (feature + its tests).

## Dependency order

```
P0 enum/domain
  └─ P1 parser ──┬─ P2 validation
                 └─ P3 shared composer ─┬─ P4 emitter
                                        ├─ P6 migration
                                        └─ P7 history
P2+P4 ─ P5 commands/queries ─ P8 DTOs ─ P9 dialog ─ P10 promote ─ P11 lists
P5 ─ P12 CLI
P5/P9 ─ P13 docs/OpenAPI ─ P14 E2E + verify
```

## P0 — Enum & domain (no tests; compile gate)

- `Domain/Enums/HotstringKind.cs`: add `Raw = 4`; mark `Script = 3` `[Obsolete("Legacy; accepted only when deserializing history snapshots")]`.
- `Domain/Entities/Hotstring*` (`HotstringDefinition`): XML-doc the kind-dependent meaning of `Replacement` (verbatim definition for Raw).
- Constants in `Validation/HotstringRules.cs`: add `RawDefinitionMaxLength = 4200`, `RawTriggerMaxLength = 40`.

## P1 — RawHotstringDefinitionParser (TDD)

- **Test first:** `tests/AHKFlowApp.Application.Tests/Services/RawHotstringDefinitionParserTests.cs`
  - structure split (`:opts:trigger::` + optional brace body), option tokenization incl. `K1000 SE*`
  - longest-match goldens `SE*` / `S0` / `SI` / `SP`, case-insensitivity, `K-1`, `P9`
  - multi-definition detection, brace bodies, escaped-trigger decode (`` `; ``)
  - unknown-token capture (`X0`)
- **Impl:** `src/Backend/AHKFlowApp.Application/Services/RawHotstringDefinitionParser.cs`
  - `internal static class`, pure; `RawParseResult Parse(string)` → `IsValid, Trigger, string[] OptionTokens, string[] UnknownOptionTokens, string? Error`
  - known-option set + longest-match tokenizer; cite `autohotkey.com/docs/v2/Hotstrings.htm` in a comment.

## P2 — Validation: AddRawKindRules (TDD)

- **Test first:** extend `CreateHotstringCommandValidatorTests`, `UpdateHotstringCommandValidatorTests`, `GetHotstringPreviewQueryValidatorTests` — all 8 rules; `X0` rejected; OTB + continuation-section rejection; 41-char trigger rejected; empty client trigger passes for Raw.
- **Impl:** `Validation/HotstringRules.cs`
  - add `AddRawKindRules<T>(kind, replacement)` (rules 1-8 from spec §Validation), XML-doc the restricted-subset limits.
  - **Delete `AddScriptKindRules` outright** — no `[Obsolete]`; its only callers are the three validators, all swapped to `AddRawKindRules` in P5.
  - **Gate `ValidTrigger()`**: in the three validators wrap `RuleFor(x => x.Input.Trigger).ValidTrigger()` in `.When(x => x.Input.Kind != HotstringKind.Raw)`.
  - Update the `Kind` allow-list `Must(...)` to `Text/DateTime/Macro/Raw` (drop `Script`), message reworded.

## P3 — Shared Script→Raw composer (TDD, golden fixtures)

The Script→Raw transform lives in **one** place, reused by migration SQL parity test, history composer, and dialog compose.

- **Fixtures:** `tests/AHKFlowApp.TestUtilities/` — shared golden set: option matrix × triggers with backtick/`;`, CRLF bodies, blank-edged bodies, 4,000-char body.
- **Test first:** `ScriptToRawComposerTests` asserting each fixture → expected verbatim definition (byte-identical to today's emitter output).
- **Impl:** `Application/Services/ScriptToRawComposer.cs` — compose `:opts:trigger::\n{\n<body>\n}` mirroring `HotstringEmitter.BuildOptions` (X/*/?/C/O) + `HotstringEmitter.Escape` on trigger. Pure, static. Lives in `Application` (not `TestUtilities`) so P7 restore/revert and P9 dialog can call it directly. The migration SQL (P6) is a **separate hand-written T-SQL copy** — SQL can't call C#; the P6 parity test is what enforces they agree.

## P4 — Emitter Raw branch + save normalization

- `Application/Services/HotstringEmitter.cs`
  - **`Emit()` top-level guard** (not a `BuildBody` change): Raw returns `hs.Replacement` verbatim, bypassing the `:{options}:{trigger}::{body}` template entirely — Raw's `Replacement` already contains the full `:opts:trigger::` definition, so re-prefixing would double it. `BuildOptions`/`Escape`/`BuildBody` are never reached for Raw.
    ```csharp
    public static string Emit(Hotstring hs) =>
        hs.Kind == HotstringKind.Raw
            ? hs.Replacement
            : $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{BuildBody(hs)}";
    ```
    (Safe: `AhkScriptGenerator` adds each `Emit` result to a line list joined with `\n`, so a multi-line verbatim definition slots in as multiple physical lines.)
  - Emitter never sees `Kind=Script` (snapshots convert at restore/revert, P7). **Delete `BuildScriptBody`** and its `Script` switch arm outright — no `[Obsolete]`.
- Save-time normalization (CRLF→LF, trim leading/trailing blank lines + per-line trailing WS): apply in create/update handlers (P5) before persisting Raw `Replacement`.
- **Test:** `AhkScriptGeneratorTests` — verbatim emission + `#HotIf` wrap; round-trip paste→save→generate byte-identical.

## P5 — Commands / queries wiring

- `Commands/Hotstrings/CreateHotstringCommand.cs` & `UpdateHotstringCommand.cs` handlers:
  - when `Kind == Raw`: parse via `RawHotstringDefinitionParser`, **derive+decode trigger**, normalize `Replacement`, use derived trigger for the duplicate check + `HotstringDefinition` construction.
  - validators: swap `AddScriptKindRules` → `AddRawKindRules`; gate `ValidTrigger` (P2).
- `Queries/Hotstrings/GetHotstringPreviewQuery.cs`:
  - validator: same swap + gate.
  - handler: for Raw, parse to derive trigger before building the transient `Hotstring`; populate `RawSummary` (P8).
- **Test:** `CreateHotstringCommandHandlerTests`, `UpdateHotstringCommandHandlerTests`, preview handler — Raw payload with empty client trigger derives server-side; duplicate detection on derived trigger; normalization applied.

## P6 — Migration (schema + data)

- `dotnet ef migrations add RawHotstringKind` (Infrastructure project).
- Schema: `Replacement` `nvarchar(4000)` → `nvarchar(max)`; update `HotstringConfiguration` + snapshot.
- Data: raw SQL rewriting `Kind=3` → `Kind=4`, `Replacement` = emitted form (mirror `BuildOptions` + `Escape`). No down-migration (documented).
- **Test:** `Infrastructure.Tests` Testcontainers — seed Script rows from shared fixtures; assert generated scripts byte-identical pre/post migration; include 4,000-char body row (proves no truncation).

## P7 — History restore/revert legacy conversion

- `Commands/Hotstrings/RestoreHotstringCommand.cs` & `RevertHotstringCommand.cs`:
  - after deserializing snapshot, if `snapshot.Kind == HotstringKind.Script`: compose Raw definition via `ScriptToRawComposer`, set `Kind = Raw`, derived trigger, composed `Replacement`; else use snapshot as-is.
- **Test:** restore + revert of a legacy `Kind=3` snapshot → valid Raw row (composed definition, derived trigger); post-change `Kind=4` snapshot round-trips unchanged. Keep `HotstringSnapshotCompatibilityTests` green.

## P8 — DTOs (preview RawSummary)

- `Application/DTOs/HotstringPreviewDto` (+ Blazor `DTOs/HotstringPreviewDtos.cs`): add optional `RawSummary(string Trigger, string[] OptionTokens)`, populated for Raw only.
- Ensure serialization parity backend ↔ Blazor.

## P9 — UI edit dialog

- `Components/Hotstrings/HotstringEditDialog.razor`
  - kind toggle `Script` → `Raw`.
  - Raw selected: monospace 8-line textarea "Raw definition", placeholder `:K1000 SE*:ftw::for the win`; hide Trigger field + 4 option checkboxes; keep description/profiles/categories/context.
  - parsed summary from `RawSummary` via existing debounced preview; errors via existing preview error path.
  - multi-def paste error under textarea (no Import referral).
  - kind switch: →Raw composes via shared composer; Raw→other confirms discard of unexpressible options, then moves trigger+body into fields.
  - Text "looks like AHK code" hint → "Switch to Raw".
- **Test (bUnit):** `HotstringEditDialogTests` — textarea, hidden fields, summary, multi-def error, kind-switch compose/decompose + confirm.

## P10 — UI promote inline row → dialog

- Desktop grid component: add third inline action (`Tune` icon, "More options / change type") next to ✓/✗.
- Promote carries typed values into `HotstringEditDialog`; draft cancel restores inline draft; existing-row cancel restores in-row values. Add still defaults to inline Text draft.
- **Test (bUnit):** promote from draft + existing row; cancel restores.

## P11 — UI lists

- Desktop grid + mobile list: Trigger column via derived trigger.
- Mobile list: "Raw" kind chip; suppress the 4 option checkmarks for Raw rows.

## P12 — CLI

- `Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`: enum `Raw = 4`, drop `Script`; `CreateHotstringDto` gains `Kind`; table/JSON labels.
- `Commands/Hotstrings/NewHotstringCommand.cs`: add `--raw "<definition>"`, mutually exclusive with `--trigger`/`--replacement`; sends `Kind=Raw`, definition as `Replacement`; relays ProblemDetails.
- **Test:** `NewHotstringCommandTests` — `--raw` happy path, mutual-exclusion error, server-error relay.

## P13 — Docs & OpenAPI

- `docs/cli/hotstrings.md`: `new` gains `--raw`; Kind/Replacement-summary column Script→Raw (summary = first line, ≤40 chars); rewrite "Script validation limitations" → Raw restricted subset.
- `API/OpenApi/Examples/HotstringExamples.cs`: history example Script→Raw.
- `HotstringKind` XML docs: `Script = 3` = rejected legacy (deserialize-only).
- **Test:** CLI docs example output regression; example serialization.

## P14 — E2E + final verify

- `tests/AHKFlowApp.E2E.Tests`: rename `ScriptHotstringFlowTests` → `RawHotstringFlowTests` — paste `:K1000 SE*:ftw::for the win`, verify summary, save, downloaded script contains exact line; add promote-flow coverage.
- `dotnet build` + `dotnet test` full; `dotnet format`; `dck-verify`.

## Verification checklist

- All 6 review findings covered: overflow (P6), enum compat (P0/P7), trigger gating (P2/P5), restricted-subset docs (P2), no-Import-referral + discard-confirm (P9), CLI `--raw` (P12).
- Shared composer single-sourced across P3/P6/P7/P9.
- No live caller of `AddScriptKindRules` / `BuildScriptBody` after P4/P5.

## Resolved decisions (grilling, 2026-07-13)

1. **Delete `AddScriptKindRules` + `BuildScriptBody` outright** — no `[Obsolete]`. Internal-only, zero live callers after P4/P5; git history preserves them.
2. **Composer in `Application/Services`**, called by P7/P9. Migration SQL is a separate T-SQL copy; P6 Testcontainers parity test enforces agreement (raw-SQL path, not a C#-driven data migration).
3. **`Emit()` top-level guard returns `hs.Replacement` verbatim for Raw** — no `:opts:trigger::` re-wrap. Template pieces never reached for Raw.
