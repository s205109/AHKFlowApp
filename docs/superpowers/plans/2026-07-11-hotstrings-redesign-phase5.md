# Phase 5 — Script Kind for Hotstrings

## Context

Phase 5 (final phase) of the approved hotstrings redesign (`docs/superpowers/specs/2026-07-07-hotstrings-redesign-design.md`, §§4-9, D8). Phases 1-4 (Text/DateTime/Macro kinds, options, window context) are merged. `HotstringKind.Script` (=3) already exists in the enum on both backend and frontend/CLI mirrors, but it's gated out everywhere: three backend validators reject it (`Must(k => k is Text or DateTime or Macro)`), the emitter has no Script case, and the UI kind selector never offers it. Script content needs **no new persisted field** — it reuses the existing `Replacement` column/DTO field (confirmed: `HotstringDefinition`, `HotstringDto`, `HotstringSnapshot` already carry it generically). This makes Phase 5 lighter than Phase 4: no migration, no new snapshot/restore/revert threading.

**Brainstorm decisions (record in spec as D11-D15 in step 0):**
- **D11** — Script reuses `Replacement`; no new domain/DTO/snapshot columns, no migration.
- **D12** — Brace-balance check is naive `{`/`}` character counting (no string-literal awareness) — consistent with D8's "not a script IDE, no AHK syntax validation" boundary. Known limitation: a `{` inside a quoted string (e.g. `SendText "{"`) counts toward the balance. Documented, not fixed.
- **D13** — CLI table Replacement-summary switch gets both a Script first-line branch **and** a Macro token-summary branch (Macro's summary was spec'd in the original design but never implemented — fixed alongside Script since it's the same switch statement).
- **D14** — Grid + mobile kind-filter dropdowns gain Macro and Script items (pre-existing gap: only Text/DateTime were listed) — same edit block as the Script UI work.
- **D15** — Phase 5 "docs note" = CHANGELOG entry + new `docs/cli/hotstrings.md` per-kind CLI reference doc (first one created; prior phases only did CHANGELOG entries).

**Key design facts:**
- Verbatim example (spec §7 ex. 7): Kind=Script, trigger `~ver`, body `MsgBox A_AhkVersion` → `:*:~ver::` + brace-body `{ MsgBox A_AhkVersion }`, warning-badged. This is the golden-test target.
- `HotstringEmitter.BuildOptions` already excludes `T` for Script correctly (comment already lists Script among brace-body kinds) — no change needed there, just confirm with a test.
- Script validation errors surface automatically via the dialog's existing `_previewReplacementError` mapping (keyed off `Replacement`) — no new error-field plumbing needed in `ApplyPreviewResult`.
- CLI: `HotstringDto`, `HotstringKind`, `KindLabel` already Script-ready; only `FormatReplacementColumn` needs a new branch.
- Warning copy (spec §6, exact): *"Runs arbitrary AutoHotkey code in the generated script. A syntax error here can break the whole profile script."* — persistent (non-dismissible) `MudAlert Severity.Warning`, unlike the dismissible macro-suggestion alert it's modeled after.

## Step 0 — Spec amendment
- Append D11-D15 to the spec's resolved-decisions section. Commit.

## Task 1 — Validation & gating (TDD)
- Failing tests first: `Validate_ScriptWithUnbalancedBraces_Fails`, `Validate_ScriptWithDirectiveLine_Fails`, `Validate_ScriptWellFormedMultiline_Passes`, `Validate_ScriptOver4000Chars_Fails`, `Validate_ScriptEmptyReplacement_Fails` (reuses existing "Replacement required" rule — confirm it fires for Script), `CreateHotstringCommandValidator_ScriptKind_Accepted`, `UpdateHotstringCommandValidator_ScriptKind_Accepted`, `GetHotstringPreviewQueryValidator_ScriptKind_Accepted`.
- `HotstringRules.cs`: new `AddScriptKindRules<T>` extension (mirror `AddMacroKindRules` structure) — when `Kind == Script`: reject any line starting with `#` (after trim) via `Must(...)`; brace-balance check (count `{` vs `}`, must be equal and never go negative mid-scan) via `Must(...)`. `ReplacementMaxLength` (4000) already applies generically — confirm, don't duplicate.
- `CreateHotstringCommand.cs` L24-26, `UpdateHotstringCommand.cs` L24-26, `GetHotstringPreviewQuery.cs` L19-21: extend `Must(k => k is Text or DateTime or Macro or Script)`; update message to `"Only Text, Date & time, Macro and Script hotstrings are supported."`. Wire `AddScriptKindRules` into all three validators alongside the existing `Add*KindRules` calls.

## Task 2 — Emitter goldens (TDD)
- `HotstringEmitter.cs` `BuildBody` switch: add `HotstringKind.Script => BuildScriptBody(hs)`. New `BuildScriptBody(hs)`: wrap `hs.Replacement` verbatim in the same brace-body shape `BuildMacroBody` uses (`\n{...}\n}`), but **no tokenization or escaping** — raw text passthrough (only structural indentation, no character escaping).
- Goldens in `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (or `HotstringEmitterTests.cs` if that's where Macro's live): `Emit_ScriptKind_WrapsBodyVerbatimInBraces` (exact match to spec §7 ex. 7), `Emit_ScriptKindMultilineBody_PreservesLinesVerbatim`, `Emit_ScriptKind_NeverEmitsTOption`, `Emit_ScriptKindWithContext_WrapsInHotIfAroundBraceBody` (Script + Phase 4 context combo — confirm no interaction bug).

## Task 3 — Backend docs cleanup
- `HotstringDto.cs`: update the 3 doc-comment lines that say "Script is domain-only" (on `HotstringDto`, `CreateHotstringDto`, `UpdateHotstringDto` / `HotstringPreviewRequestDto` — whichever carry it) to reflect Script now being a supported API kind.

## Task 4 — Frontend dialog
- `HotstringEditDialog.razor`: 4th `<MudToggleItem Value="HotstringKind.Script" Text="Script" />` with a warning icon (spec §4 step 1) in the kind-selector `MudToggleGroup`. `OnKindChangedAsync`: add a Script branch following the existing confirm-before-discard pattern used for Macro/DateTime (switching *into* Script from a kind with incompatible content, or *out of* Script, should confirm via `DialogService.ShowMessageBoxAsync` before clearing `Replacement` — verify against the existing Macro/DateTime branches for exact clear-vs-keep semantics before implementing, since Script and Text both use raw `Replacement` text but mean different things).
- Persistent (non-dismissible) `MudAlert Severity="Severity.Warning"` shown unconditionally when `Item.Kind == HotstringKind.Script`, with the exact copy from spec §6. Model structurally on the existing macro-suggestion alert but drop the dismiss button/dismissal state.
- Replacement field: apply a monospace styling hook (new CSS class, e.g. `ahk-mono`) conditionally when `Item.Kind == HotstringKind.Script`, matching spec §4 step 3 ("Script: monospace editor").
- `HotstringEditModel.cs`: new `ScriptSummary` computed property (first line of `Replacement`, trimmed/ellipsized) analogous to `DateTimeSummary`/`ContextSummary`, for grid/mobile reuse.
- bUnit: `KindToggle_SelectScript_ShowsPersistentWarningAlert`, `KindToggle_SelectScript_AppliesMonospaceClass`, `Save_ScriptKind_SendsReplacementVerbatimInCreateDto`, `PreviewError_ScriptBraceImbalance_ShownInlineOnReplacementField`, `ScriptSummary_MultilineBody_ReturnsFirstLineOnly`.

## Task 5 — Grid + mobile rendering
- `Hotstrings.razor`: kind-filter `MudSelect` (desktop L40-46, mobile L200-206) — add Macro and Script `MudSelectItem`s (D14). Replacement column per-kind switch (L94-119) — add `else if (Kind == Script)` branch rendering `ScriptSummary` in monospace with CSS ellipsis (`text-overflow: ellipsis; white-space: nowrap; overflow: hidden`).
- `HotstringMobileList.razor`: `RenderReplacementCell` switch — add `HotstringKind.Script => ScriptSummary` arm. Expanded detail — add a Script branch showing the full raw body in a monospace block plus the same warning copy used in the dialog.
- bUnit: `Grid_ScriptRow_ShowsFirstLineMonospaceEllipsis`, `KindFilter_ListsAllFourKinds`, `MobileList_ScriptRow_ShowsFirstLineInCollapsedView`, `MobileList_ScriptExpanded_ShowsFullBodyAndWarningText`.

## Task 6 — CLI
- `HotstringTableFormatter.cs` `FormatReplacementColumn`: extend the switch — Script branch takes first line of `Replacement` before truncating (D13); Macro branch renders a token summary. **Before implementing the Macro branch, verify whether the CLI project can reference `MacroTokenParser` (Application layer) or needs its own lightweight token-summary formatter** — CLI currently only depends on its own DTOs/services, so this may require either a project reference addition or a small CLI-local duplicate parser; flag and resolve this at task start, don't assume.
- No DTO changes needed (`HotstringDto`, `HotstringKind`, `KindLabel` already Script-ready in the CLI).
- Tests: `Write_ScriptRow_ShowsFirstLineOnlySummary`, `Write_ScriptRowMultilineBody_TruncatesToFirstLine`, `Write_MacroRow_ShowsTokenSummary` (replaces/updates the existing Macro pinning test that documents raw-truncate behavior).

## Task 7 — Docs
- `CHANGELOG.md` entry.
- New `docs/cli/hotstrings.md`: per-kind CLI table reference — Kind column values, Replacement-summary behavior per kind (Text/DateTime/Macro/Script), Context column, and explicit note that CLI create/update remains display-only for DateTime/Macro/Script (D6) — advanced create flags are a future follow-up.
- `API/OpenApi/Examples/HotstringExamples.cs`: add the Script example (spec §7 ex. 7, `~ver` / `MsgBox A_AhkVersion`).

## Risks
1. CLI Macro token-summary fix may require a new project reference (CLI → Application) or a duplicated parser — resolve at Task 6 start before writing the formatter branch.
2. `OnKindChangedAsync` Script transition semantics (keep vs. clear `Replacement` when switching in/out of Script) aren't explicitly spec'd — verify against the existing Macro/DateTime branches' behavior before implementing, to stay consistent.
3. Naive brace-balance check (D12) will false-positive on braces inside string literals — acceptable per D8, but document the limitation in the validator's XML comment and in `docs/cli/hotstrings.md`/dialog helper text if relevant.
4. Task order: 1 → 2 → 3 (parallel with 2) → 4 → 5 → **checkpoint: pause for user review** → 6 → 7. No migration step, so no DB ordering constraint like Phase 4 had.

## Verification
- Per task: `dotnet build` + targeted `dotnet test`; full suite + `dotnet format --verify-no-changes` at end (`dck-verify`).
- E2E: run API + Blazor (no-auth worktree profile), create a Script hotstring via the dialog matching spec §7 ex. 7, confirm the persistent warning alert and monospace editor render, confirm preview shows the exact brace-body, download profile script → byte-match the golden. Verify grid/mobile Script rows show first-line monospace summaries. UI smoke via `playwright-cli`.
- CLI: `ahkflow hotstrings list` shows Script rows with first-line summaries and Macro rows with token summaries.

## Unresolved questions
- CLI Macro-token-summary parser reuse vs duplication — resolve at Task 6 start (see Risk 1).
- Script kind-switch keep-vs-clear semantics — resolve at Task 4 start by reading existing Macro/DateTime branches (see Risk 2).
