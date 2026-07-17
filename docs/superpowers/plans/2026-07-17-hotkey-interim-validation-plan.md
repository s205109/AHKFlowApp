# Issue #193 — Interim hotkey Key/Parameters validation

## Context

`AhkScriptGenerator.FormatHotkey` interpolates `Key` and `Parameters` into the generated AHK line with no escaping (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:100`). A `"` or backtick in either field produces invalid AHK v2 syntax, and AHK fails the **whole file** at load — one bad hotkey takes down the user's entire profile script.

Full fix (escape `Parameters`, whitelist `Key` against AHK key names) is deferred until after v1: escaping requires deciding whether `Parameters` is literal text or a raw AHK fragment, and that semantics decision isn't made yet. Interim approach: **reject** the dangerous characters at the validation boundary, mirroring the existing `ContextValue` precedent (`HotstringRules.AddWindowContextRules`, `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs:400-405`). This makes v1 unable to generate a load-breaking script; the later escaping work *relaxes* validation, which is non-breaking.

Decisions made with user (grilling session):
- Land Key + interim Parameters validation now; defer escaping/whitelist to a follow-up issue.
- No pre-release deadline on the literal-vs-raw semantics decision — it's the follow-up issue's first task (record in `CONTEXT.md`).
- Rejected chars: `Parameters` → `"`, backtick, control chars (ContextValue set). `Key` → same set **plus `:`** (Key=`a:` emits `a:::...` which AHK parses as hotstring syntax).
- No data cleanup for pre-existing rows (pre-v1, disposable data). Mention in PR that old rows aren't retroactively checked.
- Server-side only — no Blazor client-side mirror. Existing surfacing suffices: `HotkeyEditDialog.razor` shows 400 ValidationProblem errors in an inline MudAlert via `ApiErrorMessageFactory`. CLI has no hotkey commands at all — nothing to do there.
- Close #193 via the PR; open a follow-up issue for semantics decision + escaping + Key whitelist.

## Changes

### 1. `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs`

`ValidKey`: extend the existing chain. It already rejects `\n`/`\r`/`\t` and leading/trailing spaces. Add:
- no `"` — "Key must not contain double-quote characters."
- no `` ` `` — "Key must not contain backtick characters."
- no `:` — "Key must not contain colon characters."
- no control chars (`char.IsControl`) — subsumes the existing `\n\r\t` check; replace that rule with the broader one, keeping a message like "Key must not contain control characters."

`ValidParameters`: currently only max length. Add (mirror ContextValue rules, messages adapted):
- no `"`, no backtick, no control chars.

Both `CreateHotkeyCommandValidator` (`Commands/Hotkeys/CreateHotkeyCommand.cs:15-27`) and `UpdateHotkeyCommandValidator` (`Commands/Hotkeys/UpdateHotkeyCommand.cs:16-28`) already call `.ValidKey()` / `.ValidParameters()` — no changes there.

### 2. Tests — `tests/AHKFlowApp.Application.Tests/Hotkeys/CreateHotkeyCommandValidatorTests.cs`

Follow existing style: `Cmd(...)` factory, FluentAssertions, assert `PropertyName` (`"Input.Key"` / `"Input.Parameters"`) + message. Add:
- `Validate_WithKeyContainingForbiddenChars_Fails` (Theory: `"a\""`, `` "a`" ``, `"a:"`)
- `Validate_WithParametersContainingForbiddenChars_Fails` (Theory: `"he said \"hi\""`, `` "x`n" ``, `"x\n"`)
- Success counterparts: colon in Parameters stays valid (`"C:\\tools\\app.exe"`), `;` in Key stays valid.

Update the existing `Validate_WithKeyContainingControlChars_Fails` theory if the message text changes. `UpdateHotkeyCommandValidatorTests` doesn't re-test Key/Parameters details — leave as is.

### 3. Characterization test — `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs:422`

`Generate_Hotkey_EmitsParametersVerbatim_NoEscaping` stays (generator behavior is unchanged) but update its comment: such input is now rejected at the validation boundary; the test pins that the emitter still trusts validated input, per the project's no-defensive-validation rule.

### 4. Doc — `docs/development/ahk-v2-syntax.md` (Hotkeys section)

Update the "known sharp edge" note: Key/Parameters can no longer contain `"`, backtick, control chars (Key also `:`) — rejected at validation, emitter embeds raw, same trust model as `ContextValue`. Reference the follow-up issue for future escaping.

## Workflow

1. New branch from `main`: `fix/wt-193-hotkey-interim-validation` (worktree naming convention).
2. Implement + tests (TDD: validator tests first — pure functions).
3. `dotnet build` + `dotnet test tests/AHKFlowApp.Application.Tests`.
4. PR with `Closes #193`; note pre-existing rows aren't retroactively validated.
5. Open follow-up issue: "Hotkey Parameters escaping + Key whitelist" — first task: decide literal-vs-raw semantics for `Parameters`, record in `CONTEXT.md`; then escape at emission, whitelist Key, relax interim validation, update doc + tests.

## Verification

- `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyCommandValidator"` — new rules pass.
- Full `dotnet build` + `dotnet test` before PR.
- Optional end-to-end: POST a hotkey with `"` in Parameters via API → expect 400 ValidationProblem naming `Input.Parameters`.
