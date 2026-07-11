# Phase 4 — Window Context for Hotstrings

## Context

Phase 4 of the approved hotstrings redesign (`docs/superpowers/specs/2026-07-07-hotstrings-redesign-design.md`, §8/§9, decisions D2/D7). Phases 1–3 (kinds, options, DateTime, Macro, preview endpoint) are merged; Phase 4 is entirely unstarted. It adds an optional per-hotstring window criterion (match by executable / window class / title-contains + value) so hotstrings can fire only in specific apps; the generator groups them into `#HotIf WinActive(...)` blocks (context groups **before** the global group per D7).

**Brainstorm decisions (record in spec as D9/D10 in step 0):**
- **D9** — Dialog AHK preview wraps the snippet in `#HotIf WinActive(...)` … `#HotIf` when context is set.
- **D10** — CLI table gains a `Context` column (`exe:notepad.exe` / `class:X` / `title:X`, blank = global).

**Key design facts:**
- SQL Server unique indexes treat NULLs as equal → composite index `(OwnerOid, Trigger, ContextMatchType, ContextValue)` yields exactly one global row per trigger + one per distinct context. New index name: `IX_Hotstring_Owner_Trigger_Context`. Loosening-only — always creates cleanly over existing data.
- WinActive mapping: Executable→`"ahk_exe {v}"`, WindowClass→`"ahk_class {v}"`, TitleContains→`"{v}"`. Safe to embed raw because validation rejects `"`, backtick, control chars.
- No-context users must get **byte-identical** script output (no `#HotIf` lines).
- Conflict message appears at **5 sites in 4 handlers** (Create pre-check l.58 + catch l.113; Update l.126; Restore l.97; Revert l.103) → shared const, new text: `"A hotstring with this trigger already exists in the same context."`
- EF translates null-valued parameters in the Create pre-check predicate to `IS NULL` — works as-is.

## Step 0 — Spec amendment
- Append D9/D10 to the spec's resolved-decisions section. Commit.

## Task 1 — Domain
- New `src/Backend/AHKFlowApp.Domain/Enums/WindowMatchType.cs`: `Executable=0, WindowClass=1, TitleContains=2` (mirror `DateOffsetUnit.cs` style).
- `HotstringDefinition.cs`: trailing params `WindowMatchType? ContextMatchType = null, string? ContextValue = null`.
- `Hotstring.cs`: two properties + assignments in private `Apply` (l.71–85).
- `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs`: `WithContext(WindowMatchType, string)`.

## Task 2 — DTOs + validation (TDD)
- Failing tests first: `Validate_ContextMatchTypeWithoutValue_Fails`, `Validate_ContextValueWithoutMatchType_Fails`, `Validate_ContextBothNull_Passes`, `Validate_ContextMatchTypeOutOfRange_Fails`, `Validate_ContextValueOver200Chars_Fails`, `Validate_ContextValueWithDoubleQuote_Fails`, `Validate_ContextValueWithBacktick_Fails`, `Validate_ContextValueWithControlChar_Fails`, `Validate_ContextOnDateTimeKind_Passes`.
- `Application/DTOs/HotstringDto.cs`: trailing context fields on `HotstringDto`, `CreateHotstringDto`, `UpdateHotstringDto`, `HotstringPreviewRequestDto`.
- `Application/Validation/HotstringRules.cs`: `AddWindowContextRules` extension (follow `AddDateTimeKindRules` compiled-expression pattern): both-or-neither, `IsInEnum`, max 200, reject `"` / backtick / `char.IsControl`. Kind-agnostic. Wire into Create/Update/Preview validators.

## Task 3 — Emitter/generator goldens (TDD)
- `HotstringEmitter.cs`: internal `EmitHotIfOpen(WindowMatchType, string)` + `HotIfClose = "#HotIf"` — single source shared with preview handler.
- `AhkScriptGenerator.cs` (flat loop at l.36–37): group by `(ContextMatchType, ContextValue)`; context groups first ordered by `(int)matchType` then `ContextValue` ordinal, each wrapped open/close; global group last, unwrapped. Trigger-ordinal sort within groups preserved (l.24 pre-sort + stable GroupBy).
- Goldens in `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (exact full-output style): `Generate_NoContextHotstrings_OutputByteIdenticalToFlatEmission`, `Generate_ExecutableContext_WrapsInHotIfWinActiveAhkExe`, `Generate_WindowClassContext_WrapsInHotIfWinActiveAhkClass`, `Generate_TitleContainsContext_WrapsInHotIfWinActiveBareValue`, `Generate_MixedContextAndGlobal_EmitsContextGroupsBeforeGlobalGroup`, `Generate_MultipleContexts_OrdersGroupsByMatchTypeThenValueOrdinal`, `Generate_SameContextTwoHotstrings_SharesOneHotIfBlock`, `Generate_OnlyContextHotstrings_ClosesLastGroupBeforeHotkeysSection`.

## Task 4 — Persistence
- `Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`: `ContextMatchType` int conversion (mirror `DateOffsetUnit` l.43–44), `ContextValue` `HasMaxLength(200)`; replace index (l.50–52) with unique `(OwnerOid, Trigger, ContextMatchType, ContextValue)` named `IX_Hotstring_Owner_Trigger_Context`; update l.49 comment.
- `dotnet ef migrations add AddHotstringWindowContext --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API` — verify scaffold: 2 AddColumn + DropIndex + CreateIndex; Down reverses.
- Testcontainers tests (`Infrastructure.Tests`): `SaveAndReload_ContextFields_RoundTrip`, `Save_SameTriggerDifferentContext_Succeeds`, `Save_SameTriggerSameContext_ThrowsDuplicateKey`, `Save_TwoGlobalRowsSameTrigger_ThrowsDuplicateKey`.

## Task 5 — Thread through commands/queries/mapping/history
- `HotstringMappings.ToDto` + **`ListHotstringsQuery.cs` l.200–217 manual projection (easy to miss — grid would silently show null context)**.
- `CreateHotstringCommand.cs`: pre-check predicate gains `&& h.ContextMatchType == input.ContextMatchType && h.ContextValue == input.ContextValue`; definition args; messages → shared const.
- `UpdateHotstringCommand.cs`: definition args + message.
- `HistorySnapshots.cs`: `HotstringSnapshot` trailing defaulted context fields ("pre-Phase-4" doc note). `EntityHistoryRecorder` snapshot construction. `RestoreHotstringCommand` / `RevertHotstringCommand`: thread snapshot fields into definitions + messages.
- Tests: `ExecuteAsync_DuplicateTriggerSameContext_ReturnsConflict`, `ExecuteAsync_DuplicateTriggerDifferentContext_Succeeds`, `ExecuteAsync_DuplicateTriggerGlobalVsContexted_Succeeds`, `ExecuteAsync_Conflict_MessageMentionsContext`; `Deserialize_LegacyJsonWithoutContextFields_DefaultsToNullContext` (SnapshotCompatibility); `RecordHotstringAsync_ContextFields_CapturedInSnapshot`, `ExecuteAsync_RevertToContextedVersion_RestoresContextFields`, `ExecuteAsync_RestoreContextedHotstring_RestoresContextFields`; list-query projection assertion `ExecuteAsync_ContextedHotstring_ProjectsContextFields`.

## Task 6 — Preview endpoint (D9)
- `GetHotstringPreviewQuery.cs` handler: pass context into transient definition; when `ContextMatchType is not null`, wrap snippet: `EmitHotIfOpen(...)` + newline + snippet + newline + `#HotIf`. Validator already wired in Task 2.
- Tests (`API.Tests/Hotstrings/HotstringPreviewEndpointsTests.cs`): `Preview_WithExecutableContext_WrapsSnippetInHotIfLines`, `Preview_WithoutContext_SnippetUnwrapped`, `Preview_ContextValueWithoutMatchType_ReturnsValidationProblem`.

## Task 7 — Frontend
- DTO copies: new `UI.Blazor/DTOs/WindowMatchType.cs`; trailing fields on `HotstringDto`, `CreateHotstringDto`, `UpdateHotstringDto`, `HotstringPreviewDtos.cs`, and the `HotstringSnapshot` mirror in `HistoryDtos.cs` (add only context fields — mirror already intentionally omits some backend fields).
- `Validation/HotstringEditModel.cs`: fields + `[MaxLength(200)]`; thread `FromDto`/`Clone`/`ToCreateDto`/`ToUpdateDto`; `IsInlineEditable => Kind == HotstringKind.Text && ContextMatchType is null`; `ContextSummary` helper (`exe:` / `class:` / `title:` prefix) reused by grid tooltip + mobile.
- `HotstringEditDialog.razor`: new "Window context" section (subtitle pattern like "Trigger options" l.158): `MudSwitch` **Only in specific windows** (on → default `Executable`; off → clear both); when on: `MudSelect<WindowMatchType>` **Match by** (Program / Window class / Title contains) + `MudTextField` **Value** with per-type placeholder (`notepad.exe` / `Chrome_WidgetWin_1` / `- Visual Studio`); `data-test` attrs. `BuildPreviewRequest()` (l.469) gains both fields so preview re-fires on context edits.
- `Pages/Hotstrings.razor`: `MudIcon` (DesktopWindows) in Type column when contexted; extend `OptionsTooltip` (l.853) with `Only in exe:...`. Inline-edit gating already uses `IsInlineEditable`.
- `HotstringMobileList.razor`: "Context" row in expanded detail (~l.76–79), hidden when global.
- bUnit: `IsInlineEditable_TextKindWithContext_ReturnsFalse`, `IsInlineEditable_TextKindNoContext_ReturnsTrue`, `ToCreateDto_WithContext_MapsContextFields`, `FromDto_WithContext_PopulatesContextFields`, `Clone_WithContext_CopiesContextFields`; dialog: `ContextSwitch_TurnedOn_ShowsMatchTypeAndValueFields`, `ContextSwitch_TurnedOff_ClearsContextFields`, `ContextValueField_ExecutableSelected_ShowsExePlaceholder`, `Save_WithContext_SendsContextInCreateDto`, `PreviewRequest_ContextChanged_TriggersNewPreview`; mobile: `ExpandedDetail_ContextedHotstring_ShowsContextRow`.

## Task 8 — CLI (D10)
- `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`: CLI-local `WindowMatchType` enum + trailing context fields on CLI `HotstringDto` (CLI `CreateHotstringDto` untouched — display-only per D6).
- `Output/HotstringTableFormatter.cs`: `Context` column (~22 wide), `exe:`/`class:`/`title:` prefixes, blank global; header + separators. Check `HotstringJsonFormatter` (fields flow automatically if it serializes the DTO).
- Tests: `Write_ContextedHotstring_ShowsExePrefixedContextColumn`, `Write_WindowClassContext_ShowsClassPrefix`, `Write_TitleContext_ShowsTitlePrefix`, `Write_GlobalHotstring_ContextColumnBlank`.

## Task 9 — OpenAPI examples + docs
- `API/OpenApi/Examples/HotstringExamples.cs`: add contexted example (`sig` → Outlook signature, spec §7 ex. 5).
- `CHANGELOG.md` entry.

## Risks
1. `ListHotstringsQuery` manual projection is the silent-failure hotspot — has its own test.
2. Byte-identical golden must be written against current output **before** touching the generator.
3. Task order: 1 → (2,3 parallel) → 4 → 5 → 6 → **checkpoint: pause for user review** → (7,8 parallel) → 9. Migration (4) before any integration run.
4. Frontend `HotstringSnapshot` mirror intentionally differs from backend — add only context fields.

## Verification
- Per task: `dotnet build` + targeted `dotnet test`; full suite + `dotnet format --verify-no-changes` at end (`dck-verify`).
- E2E: run API + Blazor (no-auth worktree profiles), create contexted hotstring via dialog, confirm preview shows `#HotIf` wrapper, download profile script → matches spec §7 ex. 5 (context block before global); verify inline edit disabled on contexted Text row; UI smoke via `playwright-cli`.
- CLI: `ahkflow hotstrings list` shows Context column.

## Unresolved questions
- None — D9/D10 resolved during brainstorm; all other decisions inherited from spec.
