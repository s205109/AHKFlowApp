# Hotkeys Page Redesign — Product & Implementation Plan

## Context

The Hotkey feature is primitive and carries known safety debt. A hotkey is today just four
modifier booleans + a free-text `Key` (≤20, unchecked) + a `HotkeyAction {Send, Run}` + one
opaque `Parameters` string, emitted by an inline `FormatHotkey` (`AhkScriptGenerator.cs:85`) that
concatenates `Key`/`Parameters` **raw** into `{^!+#}{Key}::{Send|Run}("{Parameters}")`. A `"` or
backtick breaks the **entire** generated profile at AHK load, so an interim denylist (`HotkeyRules`,
PRs #196/#197) merely *rejects* `"`, backtick, control chars and `:` — the full fix (escaping,
key whitelist, semantics) is deferred to **issue #195**.

Meanwhile the Hotstring feature was redesigned into a mature reference: an extracted
`HotstringEmitter` with real escaping, a flat `HotstringDefinition` value object, per-kind typed
fields, `#HotIf` window context, a stateless preview endpoint, and a polished dual desktop/mobile UI.

This redesign brings hotkeys to that level of maturity, supports the most common real-world hotkey
scenarios (power-user-first is acceptable), and **resolves #195 by construction** — a typed action
model where each action self-escapes at emission and the only verbatim path is an explicit `Raw`
action. Vocabulary and one ADR are captured as the model settles.

Scope was fixed through a grilling session (2026-07-21); the 14 resolved decisions are recorded in
the final section. CLI parity is intentionally a **separate follow-up spec**, not part of this arc.

## 1. Prioritized hotkey action kinds

A hotkey runs exactly one **Action** (parallel to a hotstring's Kind). v1 ships seven, each with
known semantics and known-safe emission:

| Action | Purpose | Stored | Emits |
|--|--|--|--|
| **SendText** | type literal text | `Text` | `SendText("<escaped>")` |
| **SendKeys** | press a key / combo | `SendKeysContent` token | `Send("^c")` / `Send("{Volume_Up}")` |
| **Run** | launch app / URL / folder | `RunTarget` + `RunTargetKind` | `Run("<escaped>")` |
| **Window** | manipulate active window | `WindowOp` | `WinMinimize("A")`, `WinSetAlwaysOnTop -1,"A"`, … |
| **Remap** | key behaves as another | `RemapDest` token | `origin::dest` |
| **Disable** | key does nothing | — | `origin::return` |
| **Raw** | verbatim action body (escape hatch) | `Body` | `origin::{ <body> }` |

**Deferred** (Raw covers them until built): Macro multi-step sequences; double-tap / hold activation.

## 2. Information architecture

A hotkey record has three orthogonal parts:

1. **Key + modifiers (the activating input).** Per the glossary, hotkeys have *no Trigger* — they
   have a key and modifiers. This part is: modifier flags `Ctrl/Alt/Shift/Win`; a `Key` from the
   canonical registry (or a `vkNN`/`scNNN` token); an optional `ComboPrefixKey` for two-key
   combinations (`a & b`); and three toggles `* ` (wildcard), `~` (passthrough), ` Up` (key-up).
2. **Action.** One of the seven kinds above, with its own typed field(s).
3. **Window context.** Optional `#HotIf` restriction (executable / window class / title substring),
   identical to the hotstring mechanism.

Mouse buttons and wheel are ordinary registry entries (grouped "Mouse" in the picker), so a mouse
hotkey needs no separate model.

## 3. Desktop UI approach

Preserve the existing dual desktop-grid / mobile-list layout. The desktop `MudDataGrid` keeps
server-side load, multi-select + bulk delete, category filter chips, history and recycle bin.
Inline editing is retained **only for the simplest rows** — mirror the hotstring `IsInlineEditable`
predicate: inline-edit when `ActionKind ∈ {SendText, Run}`, no combo, no toggles, no context; every
other row opens the fullscreen dialog (single edit button routes by capability, per PR #204).

A combined **Action** column shows the action chip (color-coded per kind) + a compact modifier/key
combo label + a window-context indicator, single-sourced through a `HotkeyActionDisplay` helper so
grid and mobile can't drift.

## 4. Advanced editor flow (dialog)

One fullscreen `HotkeyEditDialog` edits every action. Field flow:

- **Key + modifiers** — modifier checkboxes; a **key picker** backed by the registry (grouped:
  letters/digits, F-keys, named, numpad, media/browser, mouse), plus free-typed `vkNN`/`scNNN`.
- **Combo** — optional prefix-key picker; when set, modifier checkboxes disable (combo forbids
  modifiers in v1) and a prefix-suppression note appears.
- **Toggles** — `*` wildcard, `~` passthrough, `Up` key-up (hidden for Remap/Disable; `Up` disabled
  for wheel keys).
- **Action selector** — `MudToggleGroup` of the 7 kinds (icon + color), each revealing its own panel:
  SendText textarea; SendKeys mini-picker (mods + one key); Run target + kind; Window op select;
  Remap dest mini-picker; Disable (no fields); Raw body textarea (mono, brace-lint).
- **Window context** — switch → match-by select + value with per-type placeholder.
- **Generated AutoHotkey code** — live debounced preview panel (byte-identical to download) with a
  copy button and inline field-mapped errors, plus the safety warnings (self-lockout, prefix
  suppression, Raw brace-lint).
- **Description**, **Apply-to-all + Profiles**, **Categories** (shared `EntityMultiSelect`).

## 5. Safe feature model (resolves #195 by construction)

Every action either embeds no free user text, or escapes it at emission:

- **SendText, Run** embed free text → run through `HotkeyEmitter.EscapeStringLiteral` (a clone of the
  hotstring routine: backtick first, then `"`, `\n`, `\r`, `\t`).
- **SendKeys, Remap** persist a **validated token** (`^!+#*` prefixes + exactly one registry key,
  e.g. `^c`, `{Volume_Up}`, `^LButton`), composed by the picker → safe by construction.
- **Window** emits from a `WindowOp` enum → no free text.
- **Disable** emits `return` → no free text.
- **Raw** is the **sole verbatim path**: structured (validated) trigger + a user-owned action `Body`,
  emitted as `origin::{ <body> }`. Brace-balanced, `#`-directive rejected, warned in the UI.

Because the trigger LHS is *always* structured and validated (registry key or `vk`/`sc`), Raw cannot
reintroduce the load-breaking hazard on the left side — only the action body is verbatim, and a
malformed body affects only its own binding, not the whole file (single-statement/brace-block body).

The interim `HotkeyRules` denylist relaxes into **per-action validation**: `"` and backtick are no
longer rejected in text fields (they are escaped), while `Key` gains real registry/`vk`/`sc`
validation (closing #195 tasks 2–4).

## 6. UI labels & vocabulary

Honor the glossary: **"Trigger" stays hotstring-only**; the hotkey input is described by its parts
(key, modifiers, combo, toggles). New/updated `CONTEXT.md` terms (Wave 4):

- **Hotkey** (update) — a key or mouse/combo press, with any of Ctrl/Alt/Shift/Win and optional
  wildcard/passthrough/key-up, that runs one **Action**. Still has no Trigger.
- **Action** (new) — what a Hotkey does: one of SendText, SendKeys, Run, Window, Remap, Disable, Raw.
  _Avoid: type, command._
- **Remap** (new) — a Hotkey Action making one key/button behave as another.
- **Combo / custom combination** (new) — a two-key Hotkey (`a & b`); exactly two keys.
- **Passthrough** (`~`) and **Wildcard** (`*`) (new) — trigger toggles.
- **Run target** (new) — the application, URL, or folder a Run Hotkey launches.
- **Window context** (extend) — now applies to Hotkeys too.
- **Raw** (extend) — also a Hotkey Action holding a verbatim action body.

## 7. Example hotkey records (golden fixtures)

These drive scope and become emitter goldens + test data.

| # | AHK v2 | Action | Trigger features |
|--|--|--|--|
| 1 | `#n::Run "notepad"` | Run (app) | Win+N |
| 2 | `^!c::Run "calc.exe"` | Run (app) | Ctrl+Alt+C |
| 3 | `*#e::Run "explorer.exe"` | Run (app) | `*` wildcard |
| 4 | `#j::Run "https://github.com"` | Run (URL) | Win+J |
| 5 | `^Space::WinSetAlwaysOnTop -1,"A"` | Window (always-on-top) | Ctrl+Space |
| 6 | `#Down::WinMinimize "A"` | Window (minimize) | Win+Down |
| 7 | `#Up::WinMaximize "A"` | Window (maximize) | Win+Up |
| 8 | `^!w::WinClose "A"` | Window (close) | Ctrl+Alt+W |
| 9 | `^!s::SendText "Jane Smith` + "`n" + `Acme"` | SendText | multiline literal |
| 10 | `^+v::SendText A_Clipboard` | SendText (clipboard var) | Ctrl+Shift+V |
| 11 | `#p::Send "{Media_Play_Pause}"` | SendKeys | media key |
| 12 | `^!Up::Send "{Volume_Up}"` | SendKeys | volume key |
| 13 | `CapsLock::Ctrl` | Remap | bare key |
| 14 | `RAlt::RButton` | Remap (→ mouse) | modifier key origin |
| 15 | `F1::return` | Disable | bare key |
| 16 | `#WheelUp::Send "{Volume_Up}"` | SendKeys | mouse wheel |
| 17 | `~MButton::Run "chrome.exe"` | Run (app) | `~` passthrough, mouse |
| 18 | `Numpad0 & Numpad1::Run "notepad"` | Run (app) | combo |
| 19 | `CapsLock & j::Send "{Down}"` | SendKeys | combo |
| 20 | `#HotIf WinActive("ahk_exe notepad.exe")` `^s::MsgBox …` | Raw | window context |

Note #9/#10: `SendText A_Clipboard` sends a variable, not a literal — modeled as a SendText variant
or covered by Raw (see open question 3).

## 8. Data model & backend design

### Enums (all `int`-backed, EF `HasConversion<int>()`)

- `HotkeyActionKind` — `SendText, SendKeys, Run, Window, Remap, Disable, Raw` (replaces `HotkeyAction`).
- `WindowOp` — `Minimize, Maximize, Restore, Close, ToggleAlwaysOnTop, Center`.
- `RunTargetKind` — `Application, Url, Folder`.
- Reuse `WindowMatchType` (`Executable/WindowClass/TitleContains`) for context.

### Columns on `Hotkey` (additive per wave)

- Keep: `Ctrl/Alt/Shift/Win` (trigger mods), `Key`, `Description`, `AppliesToAllProfiles`, timestamps,
  join collections. **Drop** `Parameters` (superseded by typed columns) and `Action` (→ `ActionKind`).
- W1 action columns (nullable, gated by `ActionKind`): `ActionKind` (int); `Text` (nvarchar max);
  `SendKeysContent` (validated token); `RunTarget` (string) + `RunTargetKind` (int); `WindowOp` (int);
  `RemapDest` (validated token); `Body` (nvarchar max).
- W2 trigger columns: `ComboPrefixKey` (string, nullable), `IsKeyUp`, `IsWildcard`, `IsPassthrough` (bool).
- W3 context columns: `ContextMatchType` (int, nullable) + `ContextValue` (string, nullable).

### Value object & entity

- `HotkeyDefinition` — flat `sealed record` grouping every definitional field, funneled through a
  private `Hotkey.Apply(definition)`; replaces today's 10-arg positional `Create`/`Restore`/`Update`.
  Mirrors `HotstringDefinition` exactly (EF-friendly flat columns, trivial history snapshots).

### Emitter

- New `HotkeyEmitter` (internal static, single emission point; generator delegates, preview reuses).
  - **LHS**: `{*}{~}` + (`{^}{!}{+}{#}` mods **xor** `{ComboPrefixKey} & `) + `Key` + (` Up` if key-up).
  - **RHS**: per `ActionKind` (table §1); `EscapeStringLiteral` for SendText/Run; validated tokens for
    SendKeys/Remap; `return` for Disable; `{ <body> }` for Raw; `WinMove` helper for Window `Center`.
  - Join with `::`.
- `AhkScriptGenerator`: delete inline `FormatHotkey`; group hotkeys in the Hotkeys section by
  `(ContextMatchType, ContextValue)` — **context groups first (each wrapped `#HotIf…`/`#HotIf`),
  global group last** (correct for hotkey first-match-wins precedence); prepend the `Center` helper
  once if any Window/Center row exists (same pattern as the hotstring paste helper).

### Validation (`HotkeyRules`, static partial extension methods)

- `Key` ∈ registry **or** matches `^(vk[0-9a-f]{1,2})(sc[0-9a-f]{1,4})?$` / `^sc[0-9a-f]{1,4}$` (case-insensitive).
- Kind-conditional (both-or-neither / must-be-null-unless): each action requires its field(s) and
  forbids the others' (SendText→`Text`; SendKeys→valid `SendKeysContent`; Run→`RunTarget`+`RunTargetKind`;
  Window→`WindowOp`; Remap→valid `RemapDest`; Disable→none; Raw→`Body` brace-balanced, no `#` directive).
- `SendKeysContent` / `RemapDest` token rule: optional `^!+#*` prefixes + exactly one registry key.
- Combo: `ComboPrefixKey` set ⇒ modifiers empty, prefix ∈ registry, `≠ Key`.
- `IsKeyUp` forbidden for wheel keys.
- Context: both-or-neither; `ContextValue` rejects `"`/backtick/control (embedded raw in `WinActive`).
- **Relax** the interim `"`/backtick rejection on text fields (now escaped at emission).

### Persistence & identity

- EF composite **unique index**
  `(OwnerOid, Ctrl, Alt, Shift, Win, Key, ComboPrefixKey, IsKeyUp, ContextMatchType, ContextValue)`
  with `.HasFilter(null)` (SQL Server treats NULLs as equal → global/no-combo rows still collide).
  `*`/`~` are **excluded** from identity (behavior modifiers, not variant-forming). Update the handler
  dup-check + `Result.Conflict()`.
- Migrations **additive per wave**; the W1 action migration **clears legacy Send/Run rows** rather
  than mapping (pre-v1 disposable data; matches the interim plan's "no cleanup" precedent).

### Preview & history

- `GetHotkeyPreviewQuery` — build a transient never-saved `Hotkey` from the dialog draft, run
  `HotkeyEmitter`, wrap `#HotIf`, prepend helpers → snippet byte-identical to download. Clone of
  `GetHotstringPreviewQuery`.
- `HotkeySnapshot` extends per wave with each new field (defaulted trailing members for back-compat).

## 9. Phased implementation plan (each wave = its own PR, independently shippable)

- **W0 — Safety + foundation.** Extract `HotkeyEmitter` (behavior-preserving for current Send/Run,
  but now **escaped** via `EscapeStringLiteral`); add `HotkeyDefinition` record + `Apply` refactor;
  add the canonical key registry (`Constants/HotkeyKeys.cs`) + registry/`vk`/`sc` validation in
  `HotkeyRules`; relax the interim text denylist. **Closes #195** (escaping + key whitelist). No new
  actions or columns. Update the `Generate_Hotkey_EmitsParametersVerbatim_NoEscaping` characterization
  test to assert escaping.
- **W1 — Typed actions + preview.** `HotkeyActionKind` + `WindowOp` + `RunTargetKind`; additive action
  columns (clear legacy rows); per-action validation + emitter branches; `HotkeyDefinition`/DTOs/
  snapshot/mappings extended; dialog action panels; `GetHotkeyPreviewQuery` + preview panel; grid
  Action column.
- **W2 — Trigger expansion.** Combo/toggle/key-up columns; mouse + wheel registry entries + picker
  grouping; combo + toggle UI; self-lockout + prefix-suppression warnings; **unique-index rework**
  (add combo-key + key-up).
- **W3 — Window context.** Context columns; `#HotIf` grouping in the hotkey section; dialog context
  panel; reuse `AddWindowContextRules`; **index finalize** (add context columns).
- **W4 — UX + vocabulary.** `HotkeyActionChip` + OKLCH tints + `HotkeyActionDisplay` helper; single
  edit button routing; combined Action column + glyph legend; `CONTEXT.md` terms; **ADR 0004**;
  `docs/development/ahk-v2-syntax.md` hotkey section; backlog-034 label sweep for the hotkey mirror
  components.

## 10. Critical files

- **Domain**: `Entities/Hotkey.cs`, new `Entities/HotkeyDefinition.cs`, new
  `Enums/{HotkeyActionKind,WindowOp,RunTargetKind}.cs` (retire `Enums/HotkeyAction.cs`).
- **Application**: new `Services/HotkeyEmitter.cs`, new `Constants/HotkeyKeys.cs`,
  `Services/AhkScriptGenerator.cs` (remove `FormatHotkey`, add grouping), `Validation/HotkeyRules.cs`,
  `DTOs/HotkeyDto.cs`, `DTOs/HistorySnapshots.cs`, `Mapping/HotkeyMappings.cs`,
  `Commands/Hotkeys/*`, `Queries/Hotkeys/*` + new `Queries/Hotkeys/GetHotkeyPreviewQuery.cs`.
- **Infrastructure**: `Persistence/Configurations/HotkeyConfiguration.cs`, per-wave migrations.
- **API**: `Controllers/HotkeysController.cs` (+ preview endpoint).
- **UI**: `Pages/Hotkeys.razor`, `Components/Hotkeys/HotkeyEditDialog.razor`,
  `Components/Hotkeys/HotkeyMobileList.razor`, `Validation/HotkeyEditModel.cs`, new action panels +
  `HotkeyActionChip.razor` + `Helpers/HotkeyActionDisplay.cs`.
- **Docs**: `CONTEXT.md`, new `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md`,
  `docs/development/ahk-v2-syntax.md`.
- **Tests**: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`, `AhkScriptGeneratorTests`,
  `HotkeyRules`/validator tests, `HotkeysEndpointsTests`, bUnit dialog/grid tests, `E2E.Tests` hotkey flow.

## 11. Verification

- `dotnet build` + `dotnet test` green each wave; emitter **goldens** for all 20 examples (§7).
- Validator unit tests per action (TDD-first, pure functions): kind-conditional rules, token rules,
  combo/key-up/context edges, relaxed denylist.
- Integration (WebApplicationFactory + Testcontainers): POST each action kind → 201 + correct DB
  state; duplicate identity → 409; malformed → 400 naming the field.
- Preview parity: `GetHotkeyPreviewQuery` output == the corresponding line in the profile download.
- bUnit: dialog action-panel switching, warnings, preview debounce; grid inline-edit gating.
- `playwright-cli` smoke of the Hotkeys page (worktree runs no-auth on UI 5603 / API 5602).

## Resolved decisions (grilling, 2026-07-21)

1. Action data = discriminated typed columns (not string/JSON).
2. Safe emission = per-action escaping; Raw the sole verbatim path → #195 closed structurally.
3. Flat `HotkeyDefinition` record + `Apply`; extracted `HotkeyEmitter`.
4. Key validation = canonical registry (single source for validation + picker) + `vk`/`sc` pattern.
5. Remap and Disable are two dedicated actions → v1 set = 7.
6. Mouse buttons + wheel in v1; soft self-lockout warning.
7. Combo = `ComboPrefixKey`, 2 keys, modifiers forbidden when set, prefix-suppression warning.
8. Toggles = `*`, `~`, ` Up`; defer `$`, left/right modifiers, AltGr.
9. Window context in v1, reuse hotstring `#HotIf` stack, own grouping (context-first/global-last).
10. Binding identity = `(Owner, Ctrl,Alt,Shift,Win, Key, ComboPrefixKey, IsKeyUp, ContextMatchType, ContextValue)`; `*`/`~` excluded.
11. Additive migrations per wave; clear (don't map) legacy rows at the action migration.
12. Hotkey preview endpoint = clone of `GetHotstringPreviewQuery`, byte-identical to download.
13. CLI vertical = separate follow-up spec, not this arc.
14. Keep "Trigger" hotstring-only; add Action/Remap/Combo/Passthrough/Wildcard/Run-target terms,
    extend Window-context + Raw; one ADR (0004).

## Unresolved questions

1. Raw model = structured (validated) trigger + verbatim action `Body` (chosen) vs whole-verbatim line — confirm.
2. Window `Center` op needs a prepended `WinMove` helper (like the paste helper). Keep in v1 or defer, leaving Minimize/Maximize/Restore/Close/ToggleAlwaysOnTop?
3. `SendText` of a variable (`A_Clipboard`, examples 9/10) — a SendText "clipboard/plain-paste" sub-option, or push variable sends to Raw?
4. W0 as a behavior-preserving intermediate (Send/Run through the new escaped emitter *before* W1 replaces the enum) — acceptable, or fold W0 into W1?
5. `SendKeysContent`/`RemapDest` stored as single validated token strings (vs discrete key + mod-bool columns) — confirm the token approach.
