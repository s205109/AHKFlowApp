# Hotstrings Redesign — Phase 3: Macro Kind + Preview Endpoint

## Context

Phases 1–2 of the hotstrings redesign (spec: `docs/superpowers/specs/2026-07-07-hotstrings-redesign-design.md`, §9) are merged: kinds enum, option flags, `HotstringEmitter`, DateTime kind, dialog kind selector. This phase implements **Phase 3 (spec §9)**: the Macro kind — replacements with `{{cursor}}` / `{{key:...}}` tokens emitted as an AHK v2 brace body — plus the stateless `POST api/v1/hotstrings/preview` endpoint powering a Generated-AHK preview panel in the dialog (all kinds, zero drift with the real emitter).

Branch: `feature/wt-hotstrings-macro-kind` (worktree, clean).

**Key exploration finding:** macros need **no migration, no new columns, no snapshot/restore/revert changes** — the entire macro payload lives in `Replacement` (already round-trips). The CLI DTO already carries all fields. The spec's per-phase snapshot/CLI boilerplate is a near-no-op this phase.

**User-confirmed decisions (grilling, 2026-07-10):**
1. Key whitelist = **Enter + Tab only** (matches toolbar; extensible later).
2. **Strict parser**: any `{{...}}` that isn't exactly a known token → validation error naming the bad token. Single/unmatched braces stay literal. Literal `{{cursor}}` output → use Text kind (document).
3. **Grouped-runs emission**: consecutive text → one `SendText "..."`; consecutive same keys merged → `Send "{Enter 2}"`; cursor → trailing `Send "{Left N}"` (omitted when N=0). Allman braces, tab-indented.
4. Preview endpoint: **dedicated request DTO, full validation** via `ValidatingUseCase` → invalid input = 400 ProblemDetails; panel shows first error.
5. JS interop: **ES module + `IJSObjectReference`** (lazy import; must work in Blazor WASM — `IJSRuntime.InvokeAsync<IJSObjectReference>("import", "./js/macro-editor.js")` is WASM-supported).
6. CLI shows the **raw replacement as-is** for Macro rows (formatter needs no Macro arm; add a pinning test).
7. Token lexing: **case-insensitive names, no interior whitespace** (`{{ cursor }}` = error); toolbar inserts canonical lowercase.
8. Degenerate cursor-only macro **allowed** → empty brace body (valid AHK no-op; user sees it in preview).
9. Preview panel: **calls only while expanded**, 400 ms debounce.
10. Kind auto-suggestion: **"Use Macro?" alert ships this phase** (detection reuses the token grammar); "Use Script?" waits for Phase 5.

## Design

### Token grammar (single source of truth: `MacroTokenParser`)
- Tokens: `{{cursor}}`, `{{key:Enter}}`, `{{key:Tab}}` — names case-insensitive, no whitespace inside `{{...}}`.
- New `src/Backend/AHKFlowApp.Application/Services/MacroTokenParser.cs` (internal static). Scans `Replacement`, candidate spans = `\{\{.*?\}\}` (non-greedy); each candidate must match a known token or is reported as an error with its raw text. Everything else = literal text runs.
- Result model: `MacroParseResult(IReadOnlyList<MacroToken> Tokens, IReadOnlyList<string> Errors)`; `MacroToken` = discriminated by kind (TextRun(string), Key(name canonical "Enter"/"Tab"), Cursor).
- Used by: validator (parse errors, ≤1 cursor, no keys after cursor), emitter (token stream → statements), preview (indirectly).

### Emitter (`HotstringEmitter`)
- `BuildOptions`: **`T` becomes Text-kind-only** (today it's "non-DateTime" — Macro must not emit `T`; brace-body hotstrings have no auto-replace text). Default macro = `::htag::`, expand-immediately = `:*:htag::`.
- `BuildBody` ternary → switch; Macro branch returns a multi-line brace body appended after the header line:
  ```
  :*:htag::
  {
  	SendText "<b></b>"
  	Send "{Enter 2}"
  	Send "{Left 4}"
  }
  ```
  (tab-indented; spec §7 ex. 6 golden). Text runs merge into minimal `SendText` statements (cursor splits a run but emits no text); consecutive identical keys merge to `{Enter N}`; distinct keys = separate `Send` lines.
- **Cursor math**: `N` = total character count of text runs *after* the cursor token (`\n` counts 1, per D5); keys after cursor are impossible (validation). `N=0` → no `Send "{Left ...}"` line.
- **New string-literal escape helper** (distinct from line-level `Escape()`): for AHK v2 double-quoted strings — `` ` `` → ```` `` ````, `"` → `` `" ``, `\n` → `` `n ``, `\r` → `` `r ``, `\t` → `` `t ``. No `;`/brace escaping needed inside quotes.
- `AhkScriptGenerator` keeps calling `HotstringEmitter.Emit(hs)`; the returned string is now multi-line for macros (verify join/newline style in goldens).

### Validation (`HotstringRules`)
- Widen kind rule in Create/Update validators: `Text or DateTime or Macro` (message: "Only Text, Date & time and Macro hotstrings are supported.").
- New `AddMacroKindRules<T>(...)` extension (mirror `AddDateTimeKindRules` expression style), applied `.When(IsMacro)`:
  - Replacement parses cleanly (surface first parser error verbatim, e.g. `Unknown token '{{key:Escape}}'. Allowed: {{cursor}}, {{key:Enter}}, {{key:Tab}}.`),
  - ≤ 1 `{{cursor}}`,
  - no key tokens after the cursor.
- Existing rules already cover: Replacement required non-empty for Macro (`When(!IsDateTime)`), date fields must be null when not DateTime.

### Preview endpoint (stateless)
- `POST api/v1/hotstrings/preview` on `HotstringsController` (model after `ImportPreview`, `HotstringsController.cs:172-180`): `[HttpPost("preview")]`, body = new `HotstringPreviewRequestDto` (emission-relevant fields only: `Kind`, `Trigger`, `Replacement`, `IsCaseSensitive`, `OmitEndingCharacter`, `IsEndingCharacterRequired`, `IsTriggerInsideWord` — match existing DTO property names — plus `DateTimeFormat`, `DateOffsetAmount`, `DateOffsetUnit`). Response: `HotstringPreviewDto(string Snippet)`.
- `GetHotstringPreviewQuery` + `GetHotstringPreviewQueryValidator` (reuses `HotstringRules`: trigger rules + DateTime rules + Macro rules — identical failure surface to Save) + handler: build a transient `Hotstring.Create(Guid.Empty, definition, timeProvider)` (never persisted, no DbContext) → `HotstringEmitter.Emit` → `Result.Success`.
- Register in `Application/DependencyInjection.cs` `.AddUseCase<...>()` chain; validator auto-registered.

### Dialog (`HotstringEditDialog.razor`)
- Add **Macro** `MudToggleItem` to the kind selector. Kind-switch confirmation (existing `OnKindChangedAsync` message-box pattern): switching away from Macro with tokens present → confirm; Macro→Text keeps Replacement verbatim (tokens become literal text — the confirm text says so).
- **Macro panel** (`@if Kind == Macro`): keep the multiline Replacement editor, add an **insert toolbar** above it — `Insert: Cursor · Enter · Tab` buttons (`data-test="macro-toolbar"`).
- **Caret insertion JS**: new `wwwroot/js/macro-editor.js` **ES module**: `insertAtCaret(elementId, text)` — finds the textarea, splices text at selection, restores caret, dispatches `input` event so the Mud binding updates. Small `MacroEditorJs` service (`Services/`) lazily imports via `IJSObjectReference`, implements `IAsyncDisposable`, follows the `dn-use-js-interop` skill. Give the Replacement `MudTextField` a stable input id for lookup.
- **"Use Macro?" suggestion**: when `Kind == Text` and Replacement contains a well-formed known token → dismissible `MudAlert` with a "Switch to Macro" action (`data-test="macro-suggestion"`). Detection via the frontend token helper (below). Dismissal is per-dialog-instance.
- **Preview panel**: collapsed `MudExpansionPanel` "Generated AutoHotkey code" (`data-test="ahk-preview"`), last panel. While expanded: debounced (400 ms) `PreviewAsync` on any emission-relevant field change + once on expand; renders snippet in a monospace `<pre>`; 400 → show the first validation message instead. No calls while collapsed.

### Frontend plumbing
- `IHotstringsApiClient`/`HotstringsApiClient`: `PreviewAsync(HotstringPreviewRequestDto, ct)`; mirror request/response DTOs in `UI.Blazor/DTOs/`.
- Small frontend token helper (`Validation/MacroTokens.cs` or similar): regex-based known-token detection + token splitting for chips — a deliberate lightweight mirror of the backend parser (same pattern as enum mirrors); used by suggestion alert + grid/mobile chip rendering.
- `HotstringEditModel`: no new fields (macro payload = Replacement). `IsInlineEditable => Kind == Text` already gates macros out of inline editing.

### Grid + mobile
- `Pages/Hotstrings.razor` Replacement read-mode: Macro rows render text with inline **token chips** (small `MudChip`s: `⌖ cursor`, `Enter`, `Tab`) via the frontend token helper; `HotstringMobileList.razor` same treatment in its replacement cell.
- Kind filter/sort already handle Macro (enum-driven, Phase 2).

### CLI
- DTO already complete; formatter falls through to raw replacement (decision 6). Add a pinning test: Macro row renders `Kind=Macro` + raw `<b>{{cursor}}</b>{{key:Enter}}` truncated like Text.

### History
- No new fields → no snapshot/handler changes. Add one cheap round-trip test: revert of a Macro snapshot restores `Kind=Macro` + token-bearing Replacement intact.

## Tasks (one conventional commit each; TDD for parser, validators, emitter goldens)

### Task 0 — Commit this plan
Commit: `docs: phase 3 plan (macro kind + preview endpoint)`

### Task 1 — MacroTokenParser (TDD)
- Tests first: `tests/AHKFlowApp.Application.Tests/Services/MacroTokenParserTests.cs` — plain text (no tokens), each token, case-insensitivity, `{{ cursor }}`/`{{oops}}`/`{{key:Escape}}`/`{{field:name}}` → named errors, unmatched `{{`/single braces literal, adjacent tokens, multiline text runs, token positions for cursor-math.
- `src/Backend/AHKFlowApp.Application/Services/MacroTokenParser.cs` + result/token types.
Commit: `feat: macro token parser ({{cursor}}, {{key:Enter|Tab}})`

### Task 2 — Emitter macro brace body (goldens first)
- Goldens in `AhkScriptGeneratorTests.cs`: spec §7 ex. 6 exact (`:*:htag::` + brace body + `{Left 4}`); merged `{Enter 2}`; mixed Enter/Tab; cursor at end → no `{Left}`; cursor-only → empty body; multiline text (`` `n `` inside `SendText`, counts 1 for Left); quote/backtick escaping in `SendText`; **`T` no longer emitted for Macro** (and still emitted for Text — regression golden).
- `HotstringEmitter`: `BuildOptions` `T` restricted to `Kind == Text`; `BuildBody` switch + `BuildMacroBody` (grouped runs, merged keys, cursor math) + `EscapeStringLiteral` helper.
Commit: `feat: emit macro hotstrings as AHK brace bodies`

### Task 3 — Validation (TDD)
- Validator tests: widen `Kind_MacroOrScript_Fails` → Script-only; Macro acceptance; parse-error, 2-cursor, key-after-cursor rejections; Macro + date fields → 400 (existing rule, pin it); cursor-only macro passes.
- `HotstringRules.AddMacroKindRules<T>()`; wire into Create/Update validators; widen kind rule.
Commit: `feat: macro kind validation (strict tokens, cursor rules)`

### Task 4 — Preview endpoint
- `Application/DTOs/HotstringDto.cs` (or new file): `HotstringPreviewRequestDto`, `HotstringPreviewDto`; `Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs` + validator + handler (transient `Hotstring.Create`, no DbContext); DI registration; controller action `[HttpPost("preview")]` + `ProducesResponseType` annotations.
- API integration tests (`AHKFlowApp.API.Tests`): Text/DateTime/Macro previews return exact snippets; invalid macro → 400 ProblemDetails with parser message; anonymous → 401 (matches controller auth).
Commit: `feat: stateless hotstring preview endpoint`

### Task 5 — Frontend plumbing
- Mirror preview DTOs; `HotstringsApiClient.PreviewAsync`; frontend token helper (`MacroTokens`) + unit tests (detection + splitting).
- `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`: `PreviewAsync` route (`api/v1/hotstrings/preview`) + request payload + 400 ProblemDetails mapping, per existing client test pattern.
Commit: `feat: preview API client + frontend macro token helper`

### Task 6 — Dialog: Macro panel + toolbar + JS + suggestion
- `wwwroot/js/macro-editor.js` ES module + `MacroEditorJs` service (lazy import, `IAsyncDisposable`), registered scoped in `Program.cs` (mirror `JsFileSaver` at line 47 — Blazor services are not auto-discovered).
- Dialog: Macro toggle item, toolbar buttons (insert canonical tokens at caret), kind-switch confirm arms, "Use Macro?" alert with switch action.
- bUnit tests (JS mocked via bUnit's `JSInterop`): toggle renders, toolbar visible only for Macro, insert calls module with canonical token, suggestion appears for Text+token / dismisses / switches kind, switch-away confirm.
Commit: `feat: dialog macro panel with insert toolbar and kind suggestion`

### Task 7 — Dialog preview panel
- Collapsed expansion panel + 400 ms debounce (only while expanded) + snippet/error rendering.
- bUnit: expand triggers call, field change while expanded re-calls (debounce advanced via test timer or immediate-flush hook), 400 renders message, collapsed = no calls.
Commit: `feat: generated AHK preview panel in hotstring dialog`

### Task 8 — Grid + mobile token chips
- `Hotstrings.razor` + `HotstringMobileList.razor` Macro replacement rendering with chips; bUnit tests.
Commit: `feat: macro token chips in grid and mobile list`

### Task 9 — CLI + history pinning tests
- CLI formatter test (raw macro replacement, Macro kind label); history revert/restore round-trip test for a Macro snapshot. No production code expected.
Commit: `test: pin macro CLI output and history round-trip`

### Task 10 — Verify + changelog
- `dck-verify` (build, all tests incl. Testcontainers + bUnit, format, diagnostics).
- Changelog entry + regenerate changelog.json (repo convention).
- E2E smoke (spec §11): run API + Blazor, create `htag` macro via dialog (toolbar-inserted cursor), expand preview panel and confirm snippet, save, download script, diff against spec §7 ex. 6; verify Text inline edit untouched; `playwright-cli` smoke of Macro panel + preview panel.
Commit: `docs: changelog for macro hotstring kind`

Then PR to `main` via `gh`.

## Edge cases covered
Strict unknown/malformed token errors; case-insensitive tokens; whitespace-in-token rejected; 2 cursors rejected; key after cursor rejected; cursor-only macro → empty body allowed; cursor at end → no `{Left}`; merged repeated keys; multiline text runs (`` `n ``, counts 1); quote/backtick in macro text; `T` regression (Text keeps it, Macro never); Macro + date fields rejected; preview 400 surface identical to Save; preview panel silent while collapsed; Macro rows excluded from inline edit (existing gate); CLI renders raw tokens; legacy/new snapshots round-trip unchanged.

## Verification
Per-task: `dotnet build` + targeted `dotnet test` project. End: full `dck-verify` + E2E smoke above.

## Unresolved questions
1. Seed a sample Macro hotstring (like Phase 2's `/today`)? Default: no.
2. Preview snippet in dialog: plain `<pre>` OK, or want copy-button? Default: plain.
