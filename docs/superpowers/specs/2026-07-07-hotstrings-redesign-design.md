# Hotstrings Page Redesign — Product & Implementation Plan

## Context

AHKFlow's Hotstrings page today supports only basic `trigger → replacement` with 2 of AHK v2's ~15 option flags (`*` ending-char, `?` inside-word). Users can't create date/time hotstrings, case-sensitive triggers, app-specific hotstrings, macros with cursor placement, or script hotstrings — all core AHK v2 capabilities and flagship features of TextExpander/Espanso. The import parser already *recognizes* advanced flags but discards them with warnings, proving demand. Goal: support the high-value AHK v2 scenarios while keeping the desktop grid fast and inline-editable for the 80% case (simple text replacement). Import changes are explicitly out of scope (follow-up plan).

**Decisions made with user:** raw Script kind allowed but gated to the last phase with warnings; fill-in forms deferred to a follow-up; advanced editor = modal dialog (extend `HotstringEditDialog`); Macro kind limited to text + special keys + single cursor marker (no clipboard, no Run/URL).

## 1. Prioritized hotstring types (kinds)

| Priority | Kind | What it covers | Generated AHK |
|---|---|---|---|
| P0 | **Text** (default) | Basic + long + multiline replacements | `::trig::text` (existing; `` `n `` for newlines) |
| P1 | **Date & time** | Current date/time, preset formats, date math (±N days/hours/…) | `:X*:trig::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`, offset via `DateAdd(A_Now, 7, "Days")` |
| P2 | **Macro** | Text with special keys (Enter, Tab) + one cursor-position marker | Brace-body: `SendText "…"` / `Send "{Enter}"` / trailing `Send "{Left N}"` |
| P3 | **Script** | Raw AHK v2 body for power users | Brace-body, verbatim, badged/warned |

**Option toggles** (all kinds, exposed as checkboxes, not syntax): case-sensitive (`C`), expand immediately (`*`, existing inverted as "ending character required"), trigger inside word (`?`, existing), omit ending character (`O`). Niche flags NOT exposed or stored: `B0`, `K`, `P`, `Z`, `SP/SE`, `C1`. `SendRaw`/`T` pending open question Q1.

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
1. **Kind selector** — `MudToggleGroup`: Text / Date & time / Macro / Script (warning icon). Switching preserves Trigger/Description/options; confirm before discarding kind-specific content.
2. **Basics** — Trigger, Description.
3. **Content panel** by kind:
   - Text: `MudTextField Lines=5 AutoGrow`.
   - Date & time: curated format picker (`MudSelect`, each option shows live example), optional "Adjust date" switch → amount + unit (`Days/Hours/Minutes/Seconds`), live preview line.
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
| 1 | Basic | Kind=Text, `btw` → `by the way` | `::btw::by the way` |
| 2 | Multiline | Kind=Text, `addr` → 3-line address | ``::addr::123 Main St`nSpringfield`n12345`` |
| 3 | Current date | Kind=DateTime, `dd`, format `yyyy-MM-dd`, immediate | `:X*:dd::SendText(FormatTime(A_Now, "yyyy-MM-dd"))` |
| 4 | Custom format + math | Kind=DateTime, `nextweek`, format `dddd d MMMM yyyy`, offset +7 Days | `:X*:nextweek::SendText(FormatTime(DateAdd(A_Now, 7, "Days"), "dddd d MMMM yyyy"))` |
| 5 | App-specific | Kind=Text, `sig` → work signature, context Executable=`outlook.exe` | `#HotIf WinActive("ahk_exe outlook.exe")` … `::sig::…` … `#HotIf` |
| 6 | Safe macro | Kind=Macro, `htag` → `<b>{{cursor}}</b>`, immediate | `:*:htag::` brace-body: `SendText "<b></b>"` + `Send "{Left 4}"` |
| 7 | Raw script | Kind=Script, `~ver`, body `MsgBox A_AhkVersion` | `:*:~ver::` + `{ MsgBox A_AhkVersion }` — warning-badged |

## 8. Data model & backend design (validated against codebase)

- **Enums** (Domain/Enums, stored as int like `HotkeyAction`): `HotstringKind {Text=0, DateTime, Macro, Script}`, `DateOffsetUnit {Seconds, Minutes, Hours, Days}`, `WindowMatchType {Executable, WindowClass, TitleContains}`. Mirror in `UI.Blazor/DTOs/`.
- **New flat columns on Hotstrings** (additive, defaults keep all existing rows valid Text): `Kind int=0`, `IsCaseSensitive bit=0`, `OmitEndingCharacter bit=0`, (`SendRaw bit=0` pending Q1), `DateTimeFormat nvarchar(50) null`, `DateOffsetAmount int null`, `DateOffsetUnit int null`, `ContextMatchType int null`, `ContextValue nvarchar(200) null`. No new tables (reusable ContextRule entity rejected — deferrable losslessly).
- **`HotstringDefinition` parameter record** (Domain) to keep `Create/Update/Restore` signatures sane; kind-conditional invariants in factory.
- **Unique index**: keep `IX_Hotstring_Owner_Trigger` until Phase 4, then swap to `(OwnerOid, Trigger, ContextMatchType, ContextValue)` — SQL Server allows one null-context row per trigger + one per distinct context. Update dup pre-checks + conflict message ("…already exists in the same context").
- **Emitter**: extract `HotstringEmitter` from `AhkScriptGenerator.FormatHotstring`; deterministic option order `X * ? C O T`; `O` suppressed when `*`. Macro literals use AHK string-literal escaping into `SendText "…"` (different from existing line `Escape()`). Cursor N = literal char count after marker (`\n` counts 1; validation forbids key tokens after cursor).
- **`#HotIf` grouping** in `Generate()`: null-context group first (unchanged output → zero diff for existing users), then groups ordered by (matchType, value), each closed with bare `#HotIf`; hotkeys after all blocks.
- **Validation** (`HotstringRules.cs`, shared extension): Replacement required for Text/Macro/Script, must be empty for DateTime; DateTimeFormat required+whitelist regex for DateTime kind, null otherwise; offset both-or-neither, amount ±3650; macro tokens must parse, ≤1 cursor, no keys after cursor; script ≤4000 + brace balance + no `#`-directive lines; context both-or-neither, value ≤200 no quotes/backticks/control chars.
- **DTOs**: extend `HotstringDto`/`Create`/`Update` records with defaulted members → existing API clients + CLI unaffected. `HotstringSnapshot` gets default parameter values → old history JSON deserializes as Text (revert resets new fields — acceptable, document in history dialog). `ListHotstringsQuery`: add `Kind` filter + sort; keep old bool params for API compat.
- **New endpoint** (Phase 3): `POST api/v1/hotstrings/preview` → `GetHotstringPreviewQuery` returning emitted snippet via real emitter (powers dialog preview).
- **Single source of truth**: `MacroTokenParser` (Application/Services) used by validator + emitter.

## 9. Phased implementation plan (import excluded)

Each phase shippable; `dck-verify` at end of each; tests per project conventions (validators TDD, emitter golden tests, Testcontainers integration, bUnit UI).

- **Phase 1 — Foundation + option toggles.** Enums, `HotstringDefinition`, migration #1 (Kind + 2-3 flag columns), EF config, DTOs/snapshot/mappings/handlers, `HotstringEmitter` extraction + options-order goldens, grid Type/Options badge column (replaces checkbox columns), dialog Options panel + kind selector (Text only enabled). Resolve Q1 first.
- **Phase 2 — Date & time kind.** Migration #2 (3 date columns), kind-conditional validation + format whitelist, `:X:` emission, dialog DateTime panel (curated picker + live preview), grid DateTime rendering, Kind filter/sort in list query.
- **Phase 3 — Macro kind + preview endpoint.** `MacroTokenParser`, brace-body emitter + cursor math + escaping goldens, macro validators, dialog Macro panel + insert-toolbar JS interop, `POST /preview` + preview panel.
- **Phase 4 — Window context.** Migration #3 (2 columns + unique index swap), dup-check/conflict updates, `#HotIf` grouping + ordering goldens, dialog Context panel, grid context indicator, `IsInlineEditable` excludes contexted rows.
- **Phase 5 — Script kind.** Enable in selector, script validators, verbatim emitter, warning UI, docs note.

**Non-goals:** import persistence of new fields (follow-up: parser already tokenizes C/O/T/X into `IgnoredFlags` — map to new columns then), fill-in forms, clipboard/Run macros, regex triggers, reusable context-rule library.

## 10. Critical files

- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (+ new Enums, HotstringDefinition)
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` (+ new HotstringEmitter, MacroTokenParser)
- `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`, `HistorySnapshots.cs`
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` (preview endpoint)
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs`
- `src/Backend/AHKFlowApp.Infrastructure/` — 3 additive migrations

## 11. Verification

- Per phase: `dotnet build` + `dotnet test` (unit + Testcontainers integration + bUnit); emitter golden tests assert exact generated AHK text.
- End-to-end: run API + Blazor locally, create one hotstring of each kind via UI, download profile script, inspect generated `.ahk` matches §7 examples; verify grid inline edit still works for plain Text rows; verify history revert of a pre-migration snapshot yields a valid Text hotstring.
- UI smoke via `playwright-cli` skill for grid badge column + dialog panels.

## Unresolved questions

1. **Q1 — `SendRaw`/`T` toggle**: v2 auto-replace hotstrings may already send raw by default → toggle could be a no-op. Verify against v2 docs before Phase 1; drop column if so.
2. **Q2 — Same trigger with different case-sensitivity**: allow duplicate triggers differing only by `C` flag? Recommend no in v1.
3. **Q3 — DateTime format list**: curated preset list only, or also free-text custom format (server-validated)? Recommend curated-only v1, custom later via preview endpoint.
4. **Q4 — Kind selector visibility in Phase 1**: show disabled "coming soon" kinds or hide selector until Phase 2? Recommend hide.
5. **Q5 — Cursor `{Left N}` and multiline**: `\n` counted as 1 — acceptable approximation, or forbid cursor marker in multiline macros v1?
