# Hotstrings Redesign — Phase 2: Date & Time Kind

## Context

Phase 1 of the hotstrings redesign (spec: `docs/superpowers/specs/2026-07-07-hotstrings-redesign-design.md`) merged in PR #173: `HotstringKind` enum, `IsCaseSensitive`/`OmitEndingCharacter` flags, `HotstringDefinition` record, `HotstringEmitter`, grid badge column, dialog option toggles, CLI Kind column. This phase implements **Phase 2 (spec §9)**: the DateTime hotstring kind — users pick a date/time format (curated presets + custom, D3) and optional date offset; the generated script emits `:X:trig::SendText(FormatTime(A_Now, "fmt"))` (with `DateAdd` for offsets). The dialog kind selector appears this phase (D4). Per spec §8, the phase also round-trips the new fields through history snapshots and extends the CLI display.

Branch: `feature/hotstrings-datetime-kind` (worktree, clean at `b009dd8`).

**User-confirmed decisions:** convert `/today` + `/now` seeds to real DateTime rows; Kind filter = clearable toolbar `MudSelect` next to search. Offset amount `0` is allowed (harmless `DateAdd(A_Now, 0, "Days")`).

## Design

### New fields (all layers)
`string? DateTimeFormat` (nvarchar(50) null), `int? DateOffsetAmount`, `DateOffsetUnit? DateOffsetUnit` — new Domain enum `DateOffsetUnit { Seconds=0, Minutes=1, Hours=2, Days=3 }` (names exactly match AHK `DateAdd` unit strings). Appended as trailing defaulted params everywhere (DTOs, snapshot, `HotstringDefinition`) — wire/positional-call compatible.

### Curated presets (12 + "Custom…")
| Label | Format |
|---|---|
| ISO date | `yyyy-MM-dd` |
| European date | `dd-MM-yyyy` |
| US date | `MM/dd/yyyy` |
| Long date | `dddd d MMMM yyyy` |
| Short day + date | `ddd d MMM yyyy` |
| Month + year | `MMMM yyyy` |
| Time (24h) | `HH:mm` |
| Time (24h, seconds) | `HH:mm:ss` |
| Time (12h) | `h:mm tt` |
| Date + time | `yyyy-MM-dd HH:mm` |
| Timestamp | `yyyy-MM-dd HH:mm:ss` |
| Compact stamp | `yyyyMMdd-HHmmss` |

All 12 pass the server whitelist; presets and Custom share one validator (D3). Day/month names are locale-dependent in both AHK and .NET — preview is representative, not byte-identical (code comment).

### Format whitelist (server-authoritative)
Format lands inside AHK literal `FormatTime(A_Now, "…")` → security boundary: no `"`, backtick, `'`, `\`, `%`, `;`, `{}`, newlines; only tokens identical between AHK FormatTime and .NET custom formats (keeps client preview accurate):

```csharp
public const int DateTimeFormatMaxLength = 50;
// letters restricted to tokens shared by AHK FormatTime and .NET custom formats
[GeneratedRegex(@"^(?=.*[yMdHhmst])[yMdHhmst0-9 \-./:,()]+$")]
```

.NET preview pitfall: 1-char format (`d`) is a *standard* .NET specifier — preview must use `format.Length == 1 ? "%" + format : format`.

### Emitter output
Option order `X * ? C O` (never `T` with `X`, per D1; `O` still suppressed when `*`):
- defaults → `:X:dd::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`
- expand immediately → `:X*:dd::…`
- all options → `:X*?C:dd::…`
- offset → body `SendText(FormatTime(DateAdd(A_Now, 7, "Days"), "dddd d MMMM yyyy"))`; negative amounts pass through (`-7`).
Trigger still `Escape()`d; format embedded raw (whitelist guarantees safety — comment). `Replacement` validated empty (stored `""`, column stays non-null).

## Tasks (one conventional commit each; TDD for validators + emitter goldens)

### Task 0 — Commit this plan
Save to `docs/superpowers/plans/2026-07-08-hotstrings-redesign-phase2.md` (project convention). Commit: `docs: phase 2 plan (date/time kind)`.

### Task 1 — Domain
- New `src/Backend/AHKFlowApp.Domain/Enums/DateOffsetUnit.cs`
- `Domain/Entities/HotstringDefinition.cs` — 3 trailing defaulted params
- `Domain/Entities/Hotstring.cs` — 3 private-set props, assigned in `Apply`
- `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs` — `WithDateTimeFormat`, `WithDateOffset`
- Domain tests (`tests/AHKFlowApp.Domain.Tests/Entities/HotstringTests.cs`): Create/Restore round-trip new fields.
Commit: `feat: date/time fields on hotstring domain model`

### Task 2 — EF config + migration #2
- `Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`: `DateTimeFormat` `.HasMaxLength(50)`, `DateOffsetUnit` nullable `.HasConversion<int>()` (mirror Kind pattern)
- `dotnet ef migrations add AddHotstringDateTimeFields` (additive, 3 nullable columns; verify script)
- `tests/AHKFlowApp.Infrastructure.Tests/Persistence/HotstringPersistenceTests.cs`: column round-trip.
Commit: `feat: persist hotstring date/time columns`

### Task 3 — Emitter (goldens first)
- Tests in `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`: option-combo theory, offset ±/all 4 units, spec §7 examples #3/#4 exact strings, trigger escaping under `X`
- `Application/Services/HotstringEmitter.cs`: kind branch in `BuildOptions` (`X` prefix, skip `T`) + `BuildDateTimeBody`.
Commit: `feat: emit :X: date/time hotstrings via FormatTime/DateAdd`

### Task 4 — Validation (TDD)
- `Application/Validation/HotstringRules.cs`: `DateTimeFormatMaxLength=50`, `DateOffsetAmountMax=3650`, `[GeneratedRegex]` whitelist, `ValidDateTimeFormat<T>()`, shared `AddDateTimeKindRules<T>(...)` (mirrors `AddProfileAssociationRules` expression style)
- Create/Update validators: Kind rule → allow `Text or DateTime` (Macro/Script still rejected); Replacement `ValidReplacement().When(Kind != DateTime)` / must be empty when DateTime; DateTimeFormat required+whitelisted when DateTime, must be null otherwise; offset both-or-neither, `InclusiveBetween(-3650, 3650)`, `IsInEnum()`, null when not DateTime
- Update `Kind_NonText_Fails` tests → `Kind_MacroOrScript_Fails`; add acceptance theory (all 12 presets) + rejection theory (`"`, backtick, `'`, `\`, `%`, `;`, `{}`, newline, non-token letters `f z K n`, empty, 51 chars, separator-only).
Commit: `feat: kind-conditional hotstring validation + date format whitelist`

### Task 5 — DTOs, mapping, handlers, list query, API
- `Application/DTOs/HotstringDto.cs`: 3 fields on all three records
- **Both** mapping sites: `Application/Mapping/HotstringMappings.cs` `ToDto` AND inline projection in `ListHotstringsQueryHandler.ExecuteAsync` (known duplication)
- Create/Update handlers: thread fields into `HotstringDefinition`
- `Application/Queries/Hotstrings/ListHotstringsQuery.cs`: `HotstringKind? Kind = null` as last param; `"kind"` in `AllowedSortFields` + `ApplySorting` case; `Where(h => h.Kind == kind)` filter
- `API/Controllers/HotstringsController.cs` `List`: `[FromQuery] HotstringKind? kind = null`, threaded positionally
- Tests: API `Post_DateTimeKind_ReturnsCreatedWithDateFields`, Script-still-400 (update existing `Post_NonTextKind_Returns400`), list `?kind=` filter + `sortField=kind`; handler filter/sort tests; validator sort-field test.
Commit: `feat: date/time DTO fields + kind filter/sort in list query`

### Task 6 — History round-trip
- `HistorySnapshots.cs` `HotstringSnapshot`: 3 defaulted members (legacy JSON → nulls)
- `EntityHistoryRecorder.RecordHotstringsAsync` snapshot construction; `RestoreHotstringCommand.cs` + `RevertHotstringCommand.cs` → thread into `HotstringDefinition`
- Tests (templates exist): `History/HotstringNewFieldHistoryTests.cs` — revert restores date fields, restore-after-delete rehydrates; `HotstringSnapshotCompatibilityTests.cs` — legacy JSON → nulls, Kind=Text.
Commit: `feat: round-trip date/time fields through history snapshots`

### Task 7 — Seed conversion (confirmed)
- `ListHotstringsQuery` `s_lazySeed` + `Commands/Dev/SeedHotstringsCommand.cs` `s_samples` (update both): `/today` → DateTime, `yyyy-MM-dd`; `/now` → DateTime, `HH:mm`; Replacement `""`. Verify seed tests still pass (none pin `{{date:` text).
Commit: `feat: seed /today and /now as date/time hotstrings`

### Task 8 — CLI (display-only, D6)
- `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`: mirror `DateOffsetUnit`, 3 fields on CLI `HotstringDto` (Create DTO stays Text-only)
- `Output/HotstringTableFormatter.cs`: DateTime rows render Replacement column as `yyyy-MM-dd` / `yyyy-MM-dd (+7 days)` / `(-2 hours)` (lowercase unit, singular at |1|; `—` fallback if format null)
- `tests/AHKFlowApp.CLI.Tests/Output/HotstringTableFormatterTests.cs`: with/without/negative offset.
Commit: `feat: date/time summary in CLI hotstring table`

### Task 9 — Frontend plumbing
Under `src/Frontend/AHKFlowApp.UI.Blazor/`:
- New `DTOs/DateOffsetUnit.cs` mirror; 3 trailing params on `HotstringDto`/`CreateHotstringDto`/`UpdateHotstringDto`; `HotstringListRequest` + `Kind`
- `Services/HotstringsApiClient.ListAsync`: kind query param
- `Validation/HotstringEditModel.cs`: 3 props; update `FromDto`/`Clone`/`ToCreateDto`/`ToUpdateDto` (force `Replacement=""` for DateTime); **drop `[Required]` from Replacement** (requiredness → dialog field `Required` param + server); add `IsInlineEditable => Kind == HotstringKind.Text`, `DateTimeSummary` (shared grid/mobile), `static SafePreview(format)` (try/catch, `%`-prefix for 1-char)
- `Validation/HotstringEditModelTests.cs` updates.
Commit: `feat: mirror date/time fields in Blazor DTOs and edit model`

### Task 10 — Dialog: kind selector + DateTime panel
`Components/Hotstrings/HotstringEditDialog.razor` (verify `MudToggleGroup`/`MudToggleItem` params via `mcp__mudblazor__get_component_parameters` — no existing usage in codebase; frontend CLAUDE.md mandates MudMCP verification):
- `MudToggleGroup<HotstringKind>` at top, items Text + Date & time only (`data-test="kind-selector"`). Kind switch preserves Trigger/Description/options/profiles/categories; confirm via message box before discarding non-empty kind-specific content; DateTime→Text nulls format/offset (else server 400s)
- Replacement field only when `Kind != DateTime`; `Required="@(Item.Kind != HotstringKind.DateTime)"`
- DateTime panel: format `MudSelect<string>` over 12 presets (`Label — live example`) + "Custom…" sentinel revealing `MudTextField` MaxLength 50 (`data-test="datetime-format-select"` / `-custom`); on edit-open select matching preset else Custom; `MudSwitch` "Adjust date" (`data-test="date-offset-switch"`, on → Amount=1/Days defaults, off → nulls) with `MudNumericField<int?>` (−3650…3650) + `MudSelect<DateOffsetUnit?>`; live preview `MudText` (`data-test="datetime-preview"`) via `SafePreview`, offset applied, "Invalid format" fallback
- bUnit tests per existing dialog pattern (selector renders; switch hides Replacement/shows panel; preset sets format; Custom reveals field; preview valid/invalid; offset toggle; save posts DateTime DTO with empty Replacement; switch-away confirm clears fields).
Commit: `feat: dialog kind selector + date/time panel`

### Task 11 — Grid + mobile rendering, kind filter/sort, inline-edit gating
- `Pages/Hotstrings.razor`: Replacement read-mode renders `DateTimeSummary` for DateTime rows; hide `.start-edit` pencil when `!IsInlineEditable` (edit-details button stays on all rows); toolbar clearable `MudSelect<HotstringKind?>` "Type" (`data-test="kind-filter"`) feeding `Kind` into both `HotstringListRequest` builds (desktop + mobile) with reload à la `OnCategoryFilterChangedAsync`; Type column `Sortable` with `GetSort` mapping → `"kind"` (verify TemplateColumn sort params via MudMCP)
- `Components/Hotstrings/HotstringMobileList.razor`: DateTime summary in replacement cell + "Format:" line in expanded row
- bUnit page tests: summary rendering, pencil hidden, filter reload with Kind, mobile summary.
Commit: `feat: grid/mobile date-time rendering, kind filter/sort, inline-edit gating`

### Task 12 — Verify + changelog
- `dck-verify` skill (build, all tests incl. Testcontainers + bUnit, format, diagnostics)
- Changelog entry + regenerate changelog.json (repo convention)
- E2E smoke (spec §11): run API + Blazor, create DateTime hotstring via dialog, download script, confirm `:X*:dd::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`; `playwright-cli` smoke of DateTime panel; verify inline edit still works for Text rows.
Commit: `docs: changelog for date/time hotstring kind`

Then PR to `main` via `gh`.

## Edge cases covered
Negative offset; bounds ±3650; amount 0 allowed; amount/unit both-or-neither; format injection rejections; 1-char format preview (`%d`); DateTime+non-empty Replacement → 400; Text+date fields → 400; kind transitions in Update; `O` suppressed under `*` with `X`; `T` never with `X`; legacy snapshots → nulls; CLI against old API → graceful fallback; pencil hidden for DateTime rows.

## Verification
Per-task: `dotnet build` + targeted `dotnet test` project. End: full `dck-verify`, E2E smoke above.

## Unresolved questions
None — seeds conversion + toolbar-select filter confirmed by user; offset 0 allowed by default.
