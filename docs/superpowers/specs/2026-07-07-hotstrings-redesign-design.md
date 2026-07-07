# Hotstrings Page Redesign — Product & Implementation Plan

## Context

AHKFlow's Hotstrings page today supports only basic `trigger → replacement` with 2 of AHK v2's ~15 option flags (`*` ending-char, `?` inside-word). Users can't create date/time hotstrings, case-sensitive triggers, app-specific hotstrings, macros with cursor placement, or script hotstrings — all core AHK v2 capabilities and flagship features of TextExpander/Espanso. The import parser already *recognizes* advanced flags but discards them with warnings, proving demand. Goal: support the high-value AHK v2 scenarios while keeping the desktop grid fast and inline-editable for the 80% case (simple text replacement). Import changes are explicitly out of scope (follow-up plan).

**Decisions made with user:** raw Script kind allowed but gated to the last phase with warnings; fill-in forms deferred to a follow-up; advanced editor = modal dialog (extend `HotstringEditDialog`); Macro kind limited to text + special keys + single cursor marker (no clipboard, no Run/URL).

## 1. Prioritized hotstring types (kinds)

| Priority | Kind | What it covers | Generated AHK |
|---|---|---|---|
| P0 | **Text** (default) | Basic + long + multiline replacements | `:T:trig::text` (always Text mode → WYSIWYG, braces/carets literal; `` `n `` for newlines) |
| P1 | **Date & time** | Current date/time, preset formats, date math (±N days/hours/…) | `:X*:trig::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`, offset via `DateAdd(A_Now, 7, "Days")` |
| P2 | **Macro** | Text with special keys (Enter, Tab) + one cursor-position marker | Brace-body: `SendText "…"` / `Send "{Enter}"` / trailing `Send "{Left N}"` |
| P3 | **Script** | Raw AHK v2 body for power users | Brace-body, verbatim, badged/warned |

**Option toggles** (all kinds, exposed as checkboxes, not syntax): case-sensitive (`C`), expand immediately (`*`, existing inverted as "ending character required"), trigger inside word (`?`, existing), omit ending character (`O`). Niche flags NOT exposed or stored: `B0`, `K`, `P`, `Z`, `SP/SE`, `C1`. No `SendRaw` toggle: v2 default mode interprets `{Enter}`/`^c` in replacements (verified in docs), so Text kind **always emits `T`** for WYSIWYG — users wanting key presses use the Macro kind.

**Context sensitivity** (orthogonal to kind): optional per-hotstring window criterion — match by executable / window class / title contains + value. Generator groups into `#HotIf WinActive(...)` blocks.

## 2. Information architecture

- **One page, one grid, one dialog.** No new pages.
- Grid = browse/search/filter/bulk ops + inline edit for simple Text hotstrings.
- Modal dialog = single editor for everything (create advanced, edit any kind, mobile). Progressive disclosure: kind selector → content panel per kind → collapsed panels for Options / Window context / Organization / AHK preview.
- Kind + options surface in the grid as **one compact badge column** (replaces the two checkbox columns) — no column explosion.
- Placeholders (`{{cursor}}`, `{{key:Enter}}`) live inside the Replacement string, interpreted only for Macro kind — future fill-ins slot in as `{{field:name}}` with zero schema change.

## 3. Desktop UI approach (inline editing preserved)

- `MudDataGrid` per-cell inline editing stays exactly as-is, but only for rows where `Kind == Text && Context == null` (`IsInlineEditable` helper on edit model).
- **Type/Options column**: `MudChip` kind badge (Text/Date/Macro/Script color-coded) + muted glyphs for active options (`* ? C O`) + window icon when context set; `MudTooltip` spells it out. Sortable by kind.
- **Replacement column rendering per kind**: DateTime → format + offset summary (`yyyy-MM-dd (+7 days)`); Macro → text with token chips; Script → first line, monospace, ellipsis.
- **Actions**: pencil (inline edit) for simple rows; "Edit details" (`EditNote` icon) on all rows opens the dialog (`FullScreen=false, MaxWidth.Medium` on desktop).
- **Add button becomes a split button**: "Add text" (inline draft row, current behavior) / "Add advanced…" (dialog).
- Mobile branch: kind badge added to `HotstringMobileList`; edit already goes through the dialog.

## 4. Advanced editor flow (dialog)

Extend `Components/Hotstrings/HotstringEditDialog.razor`:
1. **Kind selector** — `MudToggleGroup`: Text / Date & time / Macro / Script (warning icon). Hidden in Phase 1 (Text-only); appears in Phase 2. Switching preserves Trigger/Description/options; confirm before discarding kind-specific content.
2. **Basics** — Trigger, Description.
3. **Content panel** by kind:
   - Text: `MudTextField Lines=5 AutoGrow`.
   - Date & time: curated format picker (`MudSelect`, ~12 presets, each option shows live example) + **"Custom…" option** revealing a free-text format field (same server whitelist validates both paths); optional "Adjust date" switch → amount + unit (`Days/Hours/Minutes/Seconds`); live preview line via .NET `ToString()` (accurate for all whitelisted tokens).
   - Macro: multiline editor + **insert-placeholder toolbar** (Cursor / Enter / Tab buttons; caret insertion via small JS interop module).
   - Script: monospace editor under persistent `MudAlert` warning.
4. **Trigger options** panel — 4 checkboxes.
5. **Window context** panel — switch "Only in specific windows" → match type select + value field with per-type placeholder (`notepad.exe` / `Chrome_WidgetWin_1` / `- Visual Studio`).
6. **Organization** — profiles/categories (existing `EntityMultiSelect`).
7. **Generated AHK preview** (Phase 3+) — collapsed panel, debounced server call to new preview endpoint (real emitter, zero drift).

**Kind auto-suggestion** (suggest, never auto-switch): Replacement contains known `{{…}}` token → "Use Macro?" chip; looks like AHK code (lines starting `Send`/`::`/`#`/braces) → "Use Script?" — dismissible `MudAlert` with action button. Multiline paste stays Text (natively supported).

## 5. Safe feature model

| Tier | Features | Control |
|---|---|---|
| **Default (safe)** | Text, Date & time, Macro, option toggles, window context | User text only ever lands inside `SendText("…")` string literals / escaped replacement — escaping + whitelist validation is the security boundary. Date format is whitelist-validated (injection control for the string literal). Macro keys from a fixed whitelist. Context value rejects `"`, backtick, control chars. |
| **Advanced (gated, Phase 5)** | Script kind | Clearly badged warning chip in grid; persistent warning alert in editor; brace-balance lint; lines starting with `#` rejected (directives would corrupt `#HotIf` grouping). Not a sandbox — AHKFlow never executes scripts; users download and run their own. Excluded from future import/sharing by default. |
| **Avoided** | Run/URL/app launch, clipboard-set commands, shell/exec placeholders, regex triggers, rich text, arbitrary expressions in DateTime format | Espanso's under-communicated shell risk is the anti-pattern; AHKFlow stays structured-by-default. |

## 6. UI labels, buttons, field names

- Kind labels: **Text**, **Date & time**, **Macro**, **Script**
- Buttons: **Add text** / **Add advanced…** (split), **Edit details** (icon tooltip), **Insert: Cursor · Enter · Tab** (macro toolbar)
- Option checkboxes: **Case sensitive**, **Expand immediately (no ending character)**, **Trigger inside words**, **Omit ending character**
- Context: **Only in specific windows** (switch), **Match by** (Program / Window class / Title contains), **Value**
- Date panel: **Format**, **Adjust date** (switch), **Amount**, **Unit**, **Preview**
- Script warning: "Runs arbitrary AutoHotkey code in the generated script. A syntax error here can break the whole profile script."
- Preview panel: **Generated AutoHotkey code**

## 7. Example hotstring records

| # | Example | Fields | Generated AHK |
|---|---|---|---|
| 1 | Basic | Kind=Text, `btw` → `by the way` | `:T:btw::by the way` |
| 2 | Multiline | Kind=Text, `addr` → 3-line address | ``:T:addr::123 Main St`nSpringfield`n12345`` |
| 3 | Current date | Kind=DateTime, `dd`, format `yyyy-MM-dd`, immediate | `:X*:dd::SendText(FormatTime(A_Now, "yyyy-MM-dd"))` |
| 4 | Custom format + math | Kind=DateTime, `nextweek`, format `dddd d MMMM yyyy`, offset +7 Days | `:X*:nextweek::SendText(FormatTime(DateAdd(A_Now, 7, "Days"), "dddd d MMMM yyyy"))` |
| 5 | App-specific | Kind=Text, `sig` → work signature, context Executable=`outlook.exe` | `#HotIf WinActive("ahk_exe outlook.exe")` … `:T:sig::…` … `#HotIf` (context blocks precede the global group) |
| 6 | Safe macro | Kind=Macro, `htag` → `<b>{{cursor}}</b>`, immediate | `:*:htag::` brace-body: `SendText "<b></b>"` + `Send "{Left 4}"` |
| 7 | Raw script | Kind=Script, `~ver`, body `MsgBox A_AhkVersion` | `:*:~ver::` + `{ MsgBox A_AhkVersion }` — warning-badged |

## 8. Data model & backend design (validated against codebase)

- **Enums** (Domain/Enums, stored as int like `HotkeyAction`): `HotstringKind {Text=0, DateTime, Macro, Script}`, `DateOffsetUnit {Seconds, Minutes, Hours, Days}`, `WindowMatchType {Executable, WindowClass, TitleContains}`. Mirror in `UI.Blazor/DTOs/`.
- **New flat columns on Hotstrings** (additive, defaults keep all existing rows valid Text): `Kind int=0`, `IsCaseSensitive bit=0`, `OmitEndingCharacter bit=0`, `DateTimeFormat nvarchar(50) null`, `DateOffsetAmount int null`, `DateOffsetUnit int null`, `ContextMatchType int null`, `ContextValue nvarchar(200) null`. No `SendRaw` column (Text kind always emits `T`; resolved decision D1). No new tables (reusable ContextRule entity rejected — deferrable losslessly).
- **`HotstringDefinition` parameter record** (Domain) to keep `Create/Update/Restore` signatures sane; kind-conditional invariants in factory.
- **Unique index**: keep `IX_Hotstring_Owner_Trigger` until Phase 4, then swap to `(OwnerOid, Trigger, ContextMatchType, ContextValue)` — SQL Server allows one null-context row per trigger + one per distinct context. Update dup pre-checks + conflict message ("…already exists in the same context").
- **Emitter**: extract `HotstringEmitter` from `AhkScriptGenerator.FormatHotstring`; deterministic option order `X * ? C O T`; `O` suppressed when `*`; `T` always present for Text kind (WYSIWYG — v2 default mode interprets `{Enter}`/`^c`, verified in docs), never combined with `X` kinds. Macro literals use AHK string-literal escaping into `SendText "…"` (different from existing line `Escape()`). Cursor N = literal char count after marker (`\n` counts 1 — exact in mainstream editors; document caveat for auto-indent/autocomplete apps; validation forbids key tokens after cursor).
- **`#HotIf` grouping** in `Generate()`: **context groups first, global (null-context) group last.** AHK hotstring variant precedence is "closest to the top of the script wins" and the global-lowest-precedence exception *does not apply to hotstrings* (per `#HotIf` docs) — global-first would shadow every context-specific override. Context groups ordered by (matchType, value ordinal), each closed with bare `#HotIf`; hotkeys after all blocks. Users without contexts still get byte-identical output (single global group).
- **Validation** (`HotstringRules.cs`, shared extension): Replacement required for Text/Macro/Script, must be empty for DateTime; DateTimeFormat required+whitelist regex for DateTime kind, null otherwise; offset both-or-neither, amount ±3650; macro tokens must parse, ≤1 cursor, no keys after cursor; script ≤4000 + brace balance + no `#`-directive lines; context both-or-neither, value ≤200 no quotes/backticks/control chars.
- **DTOs**: extend `HotstringDto`/`Create`/`Update` records with defaulted members → API/wire stays backward-compatible (unknown JSON ignored). `ListHotstringsQuery`: add `Kind` filter + sort; keep old bool params for API compat.
- **CLI (first-class, must not silently degrade)**: the CLI carries its **own** reduced DTOs (`src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`) and table output (`HotstringTableFormatter.cs`) — it will keep deserializing (STJ ignores the new JSON fields) but won't *show* Kind/date-format/macro/script/context, and DateTime rows (empty `Replacement`) render blank. Per-kind CLI handling: in each backend phase, extend the CLI DTO with that phase's fields and render a per-kind Replacement summary (DateTime → format+offset, Macro → tokens, Script → first line) plus a Kind column/badge, mirroring the grid. Until a field's CLI phase lands, treat the CLI as **read-only/degraded** for that kind and say so in `--help`/docs. Add CLI output tests per phase.
- **History (round-trip new fields, not just Text-default legacy)**: `HotstringSnapshot` gains the new members with default parameter values so **pre-migration** JSON deserializes as Text. But `RestoreHotstringCommand` and `RevertHotstringCommand` reconstruct entities by **explicitly enumerating every snapshot field** into `Hotstring.Restore`/`entity.Update` — so each phase that adds a field MUST also: (1) add it to `EntityHistoryRecorder.RecordHotstringAsync` snapshot construction, (2) thread it through the `Restore`/`Update` calls in both handlers, and (3) add a snapshot round-trip test proving a **post-migration** snapshot restores/reverts the new field intact while a legacy snapshot defaults to Text. Only legacy snapshots reset new fields to defaults.
- **New endpoint** (Phase 3): `POST api/v1/hotstrings/preview` → `GetHotstringPreviewQuery` returning emitted snippet via real emitter (powers dialog preview).
- **Single source of truth**: `MacroTokenParser` (Application/Services) used by validator + emitter.

## 9. Phased implementation plan (import excluded)

Each phase shippable; `dck-verify` at end of each; tests per project conventions (validators TDD, emitter golden tests, Testcontainers integration, bUnit UI).

Every phase that adds a persisted field also, in the same phase: updates the snapshot + both revert/restore handlers to round-trip it (see §8 History), and extends the CLI DTO + output for that field (see §8 CLI).

- **Phase 1 — Foundation + option toggles.** Enums, `HotstringDefinition`, migration #1 (Kind + `IsCaseSensitive` + `OmitEndingCharacter`), EF config, DTOs/snapshot/mappings/handlers, snapshot + revert/restore round-trip for new flags, `HotstringEmitter` extraction (incl. always-`T` for Text) + options-order goldens, grid Type/Options badge column (replaces checkbox columns), dialog Options panel (kind selector hidden until Phase 2), CLI DTO + Kind column.
- **Phase 2 — Date & time kind.** Migration #2 (3 date columns), kind-conditional validation + format whitelist, `:X:` emission, dialog kind selector + DateTime panel (curated picker + Custom field + live preview), grid DateTime rendering, Kind filter/sort in list query.
- **Phase 3 — Macro kind + preview endpoint.** `MacroTokenParser`, brace-body emitter + cursor math + escaping goldens, macro validators, dialog Macro panel + insert-toolbar JS interop, `POST /preview` + preview panel.
- **Phase 4 — Window context.** Migration #3 (2 columns + unique index swap), dup-check/conflict updates, `#HotIf` grouping (contexts first, global last) + ordering goldens, dialog Context panel, grid context indicator, `IsInlineEditable` excludes contexted rows.
- **Phase 5 — Script kind.** Enable in selector, script validators, verbatim emitter, warning UI, docs note.

**Non-goals:** import persistence of new fields (follow-up: parser already tokenizes C/O/T/X into `IgnoredFlags` — map to new columns then), fill-in forms, clipboard/Run macros, regex triggers, reusable context-rule library.

## 10. Critical files

- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (+ new Enums, HotstringDefinition)
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` (+ new HotstringEmitter, MacroTokenParser)
- `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`, `HistorySnapshots.cs`
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RestoreHotstringCommand.cs`, `RevertHotstringCommand.cs` (thread new snapshot fields through `Restore`/`Update`)
- `src/Backend/AHKFlowApp.Application/Services/EntityHistoryRecorder.cs` (snapshot construction) — round-trip new fields
- `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`, `src/Tools/AHKFlowApp.CLI/Output/HotstringTableFormatter.cs` (CLI DTO + per-kind output)
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` (preview endpoint)
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs`
- `src/Backend/AHKFlowApp.Infrastructure/` — 3 additive migrations

## 11. Verification

- Per phase: `dotnet build` + `dotnet test` (unit + Testcontainers integration + bUnit); emitter golden tests assert exact generated AHK text.
- End-to-end: run API + Blazor locally, create one hotstring of each kind via UI, download profile script, inspect generated `.ahk` matches §7 examples; verify grid inline edit still works for plain Text rows; verify history revert of a pre-migration snapshot yields a valid Text hotstring.
- UI smoke via `playwright-cli` skill for grid badge column + dialog panels.

## Resolved decisions (design review, 2026-07-07)

1. **D1 — Text kind always emits `T`** (v2 default mode interprets `{Enter}`/`^c` per docs — verified, not a no-op). No `SendRaw` column/toggle; key presses are the Macro kind's job. Fixes the latent WYSIWYG surprise in current output.
2. **D2 — No case-variant duplicate triggers in v1**: uniqueness ignores the `C` flag; revisit on demand.
3. **D3 — Date formats: curated presets + "Custom…" free-text field, both Phase 2**, one shared server-side whitelist validator (required regardless of UI), client-side .NET preview.
4. **D4 — Kind selector hidden in Phase 1**, appears in Phase 2.
5. **D5 — Cursor marker allowed in multiline macros**; `\n` counts as 1 `{Left}` (exact in mainstream editors); documented caveat for auto-indent/autocomplete apps.
6. **D6 — CLI is display-only for advanced kinds** (per-phase read DTO + per-kind output); advanced create flags are a follow-up alongside import.
7. **D7 — `#HotIf` context groups emitted before the global group** — hotstring variant precedence is topmost-wins with no global exception (per docs); global-first would shadow context overrides.
8. **D8 — Script guardrails are hard validation errors**: ≤4000 chars, no `#`-directive lines, brace-balance check; plus persistent editor warning. No AHK syntax validation (not a script IDE).
