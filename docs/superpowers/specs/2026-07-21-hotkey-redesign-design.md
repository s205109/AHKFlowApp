# Hotkeys Page Redesign — Design Specification

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

`RunTarget` is a **command line**, not a path: AHK's `Run` accepts arguments, and legacy rows
already rely on it (the dev seed ships `Run "rundll32.exe user32.dll,LockWorkStation"`). So v1 has
no separate arguments column and **no path-shaped validation** — a rule requiring an existing file
or a bare executable would reject data the app itself created. `RunTargetKind` is a display label
that picks the icon and the field's placeholder; it does not change emission. Splitting target from
arguments is deferred.
| **Window** | manipulate active window | `WindowOp` | `WinMinimize("A")`, `WinSetAlwaysOnTop(-1, "A")`, … |
| **Remap** | key behaves as another | `RemapDest` token | `origin::dest` |
| **Disable** | key does nothing | — | `origin::return` |
| **Raw** | verbatim action body (escape hatch) | `Body` | `origin::{ <body> }` |

**Emission style is the parenthesized call form** (`Run("notepad")`, not `Run "notepad"`) for every
action that emits a call — it is what today's `FormatHotkey` already produces, so W0 stays
behavior-preserving and the goldens don't churn twice. `Remap` (`origin::dest`) and `Disable`
(`origin::return`) are not calls and keep their bare form. Note this deliberately differs from
`HotstringEmitter`, which emits command syntax (`SendText "…"`); the two emitters are not required
to agree on style, only each with itself.

**Deferred** (Raw covers them until built): Macro multi-step sequences; double-tap / hold
activation; Window `Center`; variable/clipboard sends (`SendText A_Clipboard`, paste-as-plain).

## 2. Information architecture

A hotkey record has three orthogonal parts:

1. **Key + modifiers (the activating input).** Per the glossary, hotkeys have *no Trigger* — they
   have a key and modifiers. This part is: modifier flags `Ctrl/Alt/Shift/Win`; a `Key` from the
   canonical registry (or a `vkNN` **or** `scNNN` token — never the combined `vkNNscNNN` form, which
   AHK rejects in a hotkey definition); an optional `ComboPrefixKey` for two-key combinations
   (`a & b`); and three toggles `*` (wildcard), `~` (passthrough), ` Up` (key-up).
2. **Action.** One of the seven kinds above, with its own typed field(s).
3. **Window context.** Optional `#HotIf` restriction (executable / window class / title substring),
   identical to the hotstring mechanism.

Mouse buttons and wheel are ordinary registry entries (grouped "Mouse" in the picker), so a mouse
hotkey needs no separate model.

## 3. Desktop UI approach

Preserve the existing dual desktop-grid / mobile-list layout. The desktop `MudDataGrid` keeps
server-side load, multi-select + bulk delete, category filter chips, history and recycle bin.
Inline editing is retained **only for the simplest rows** — mirror the hotstring `IsInlineEditable`
predicate (`Validation/HotstringEditModel.cs:58`): inline-edit when `ActionKind ∈ {SendText, Run}`,
no combo, no toggles, no context, **and the `Key` passes current validation**; every other row opens
the fullscreen dialog (single edit button routes by capability, per PR #204). The key clause is what
surfaces un-migratable legacy rows without any new UI — see §8.

Two columns carry the binding and what it does: a **Hotkey** column showing a compact modifier/key
combo label, and an **Action** column showing the action chip (color-coded per kind) + a one-line
payload summary + a window-context indicator. Both are single-sourced through a
`HotkeyActionDisplay` helper so grid and mobile can't drift.

(This section originally specified *one* combined column. Split into two during W1 UI planning,
2026-07-22: a single column mixing binding and payload truncates badly at the width available, and
the binding is the row's identity — it earns its own sortable column. The single-sourcing
requirement is unchanged and is what the helper exists for.)

## 4. Advanced editor flow (dialog)

One fullscreen `HotkeyEditDialog` edits every action. Field flow:

- **Key + modifiers** — modifier checkboxes; a **key picker** backed by the registry (grouped:
  letters/digits, F-keys, named, numpad, media/browser, mouse), plus free-typed `vkNN`/`scNNN`.
- **Combo** — optional prefix-key picker; when set, modifier checkboxes disable (combo forbids
  modifiers in v1) and a prefix-suppression note appears.
- **Toggles** — `*` wildcard, `~` passthrough, `Up` key-up (hidden for Remap/Disable; `Up` disabled
  for wheel keys; `*` hidden when a combo is set — combos are already wildcard by default, see §8.
  `~` and `Up` stay available for combos: `~RButton & C::` and `F1 & e Up::` are both valid AHK).
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

- **SendText, Run** embed free text → run through the shared `EscapeStringLiteral` routine (backtick
  first, then `"`, `\n`, `\r`, `\t`). This is **extracted and shared** with `HotstringEmitter`, not
  cloned — two copies of an escape routine are two places to get the backtick-first ordering wrong.
- **SendKeys, Remap** persist a **validated token** composed by the picker → safe by construction.
  The two tokens use **different grammars** (see §8 Validation); they are not one shared rule.
- **Window** emits from a `WindowOp` enum → no free text.
- **Disable** emits `return` → no free text.
- **Raw** is the **sole verbatim path**: structured (validated) key + modifiers, plus a user-owned
  action `Body`, emitted as `origin::{ <body> }`. Brace-balanced, `#`-directive rejected, warned in
  the UI.

### What this does and does not guarantee

Because the LHS is *always* structured and validated (registry key or `vk`/`sc`), **no action —
including Raw — can reintroduce the #195 hazard on the left side.** That is the guarantee, and it is
what closes #195.

**Raw is not sandboxed.** AHK parses the whole script at load, so a syntax error anywhere aborts the
**entire generated profile**, not just its own binding. A body can also escape its wrapper: the
brace-balance check counts `{`/`}` naively, with no awareness of string literals or comments, so a
body can close the outer block early and have its remainder parsed at top level. This is the same
accepted trade-off as hotstring Raw (decisions D8/D12, recorded in
`docs/development/ahk-v2-syntax.md` → *Known limitations*) — a string- and comment-aware scanner
would drift toward being a script IDE, so it is deliberately **not** built here either. The UI must
say so plainly: *"Raw is unchecked AutoHotkey. A mistake here can stop the whole profile script from
loading."*

### `$` and self-retriggering

Structured **SendKeys** can retrigger the script's own hotkeys. Per AHK, `$` "forces the keyboard
hook to be used to implement this hotkey, which as a side-effect prevents the Send function from
triggering it." `$` is therefore **not** a user-facing v1 toggle (that stays deferred) but is
**emitted automatically for every SendKeys binding on a keyboard key**. Unconditionally, not only on
detected self-collision: `$` has no side effect beyond forcing the hook, and a
same-key-and-modifiers check would still miss A-triggers-B-triggers-A chains. Mouse hotkeys already
use the mouse hook and get no `$`.

The interim `HotkeyRules` denylist relaxes into **per-action validation**: `"` and backtick are no
longer rejected in text fields (they are escaped), while `Key` gains real registry/`vk`/`sc`
validation (closing #195 tasks 2–4).

## 6. UI labels & vocabulary

Honor the glossary: **"Trigger" stays hotstring-only**; the hotkey input is described by its parts
(key, modifiers, combo, toggles). New/updated `CONTEXT.md` terms land **in the wave that introduces
the concept**, not in a trailing documentation wave — a term that ships a wave late is a term the
wave's own PR description had to invent vocabulary for. Wave shown per term:

- **Hotkey** (update, W1) — a key or mouse/combo press, with any of Ctrl/Alt/Shift/Win and optional
  wildcard/passthrough/key-up, that runs one **Action**. Still has no Trigger.
- **Action** (new, W1) — what a Hotkey does: one of SendText, SendKeys, Run, Window, Remap, Disable,
  Raw. _Avoid: type, command._
- **Remap** (new, W1) — a Hotkey Action making one key/button behave as another.
- **Run target** (new, W1) — the application, URL, or folder a Run Hotkey launches.
- **Raw** (extend, W1) — also a Hotkey Action holding a verbatim action body.
- **Combo / custom combination** (new, W2) — a two-key Hotkey (`a & b`); exactly two keys.
- **Passthrough** (`~`) and **Wildcard** (`*`) (new, W2) — hotkey toggles (**not** "trigger" toggles).
- **Window context** (extend, W3) — now applies to Hotkeys too.

## 7. Example hotkey records (golden fixtures)

These drive scope and become emitter goldens + test data.

Emission is the parenthesized call form (§1). `$` is auto-emitted for keyboard SendKeys bindings (§5).

| # | AHK v2 | Action | Hotkey features |
|--|--|--|--|
| 1 | `#n::Run("notepad")` | Run (app) | Win+N |
| 2 | `^!c::Run("calc.exe")` | Run (app) | Ctrl+Alt+C |
| 3 | `*#e::Run("explorer.exe")` | Run (app) | `*` wildcard |
| 4 | `#j::Run("https://github.com")` | Run (URL) | Win+J |
| 5 | `^Space::WinSetAlwaysOnTop(-1, "A")` | Window (always-on-top) | Ctrl+Space |
| 6 | `#Down::WinMinimize("A")` | Window (minimize) | Win+Down |
| 7 | `#Up::WinMaximize("A")` | Window (maximize) | Win+Up |
| 8 | `^!w::WinClose("A")` | Window (close) | Ctrl+Alt+W |
| 9 | ``^!s::SendText("Jane Smith`nAcme")`` | SendText | multiline literal, escaped |
| 10 | ``^+v::{`n`tSendText A_Clipboard`n}`` | Raw | variable send (see §7 note) |
| 11 | `$#p::Send("{Media_Play_Pause}")` | SendKeys | media key |
| 12 | `$^!Up::Send("{Volume_Up}")` | SendKeys | volume key |
| 13 | `CapsLock::Ctrl` | Remap | bare key |
| 14 | `RAlt::RButton` | Remap (→ mouse) | modifier key origin |
| 15 | `F1::return` | Disable | bare key |
| 16 | `#WheelUp::Send("{Volume_Up}")` | SendKeys | mouse wheel (no `$`) |
| 17 | `~MButton::Run("chrome.exe")` | Run (app) | `~` passthrough, mouse |
| 18 | `Numpad0 & Numpad1::Run("notepad")` | Run (app) | combo |
| 19 | `$CapsLock & j::Send("{Down}")` | SendKeys | combo |
| 20 | `#HotIf WinActive("ahk_exe notepad.exe")` + `^s::{ MsgBox "…" }` | Raw | window context |

Note on #10: `SendText A_Clipboard` is an **unquoted expression**, a different emission shape from
`SendText("<escaped literal>")`, and it is *not* paste-as-plain — it types the clipboard's textual
value. Real paste-as-plain needs clipboard save → convert → `^v` → `ClipWait` → restore, which the
hotstring side already solves with `HotstringEmitter.PasteHelperFunction`. So variable sends are
**Raw in v1**; a future safe feature should be a specific *clipboard-text* source reusing that
helper, never arbitrary variable expressions.

Note on #15: `F1::return` is the documented way to disable a key, but it is the one construct where
remap-vs-statement parsing is ambiguous by inspection (`Return` is also a key name). Its golden must
be confirmed against a real AHK v2 load, not just against the emitter.

## 8. Data model & backend design

### Enums (all `int`-backed, EF `HasConversion<int>()`)

- `HotkeyActionKind` — `SendText, SendKeys, Run, Window, Remap, Disable, Raw` (replaces `HotkeyAction`).
- `WindowOp` — `Minimize, Maximize, Restore, Close, ToggleAlwaysOnTop`. (`Center` deferred: it is the
  only op needing a prepended `WinMove` helper, and it is not worth a helper-injection path in v1.)
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
  - **LHS**: `{$}{*}{~}` + (`{^}{!}{+}{#}` mods **xor** `{ComboPrefixKey} & `) + `Key` + (` Up` if
    key-up). `$` is emitter-derived (SendKeys on a keyboard key), not a stored column.
  - **RHS**: per `ActionKind` (table §1); `EscapeStringLiteral` for SendText/Run; validated tokens for
    SendKeys/Remap; `return` for Disable; `{ <body> }` for Raw.
  - Join with `::`.
  - `EscapeStringLiteral` moves to a shared internal helper used by both emitters (§5).
- `AhkScriptGenerator`: delete inline `FormatHotkey`; group hotkeys in the Hotkeys section by
  `(ContextMatchType, ContextValue)` — **context groups first (each wrapped `#HotIf…`/`#HotIf`),
  global group last**.

  The ordering rationale must be stated correctly, because the obvious one is wrong. AHK is **not**
  first-match-wins across the file: "If more than one variant is eligible to fire, only the one
  closest to the top of the script will fire", *and* "the global variant … always has the lowest
  precedence; therefore, it will fire only if no other variant is eligible." So global-last is
  **redundant for correctness** (global already loses) but is kept for readability and to match the
  hotstring section's layout — where it *is* load-bearing, since the global-lowest exception
  explicitly does not apply to hotstrings. Ordering *between* two context variants of the same key
  is what actually decides behavior, so §8's `OrderBy(matchType).ThenBy(value)` is the deterministic
  tie-break and needs a test, not just a comment.

### Validation (`HotkeyRules`, static partial extension methods)

**One registry, five role-specific validators.** The registry is a single source of key facts, but
each *role* a key can play has its own AHK grammar, and one shared token rule cannot express them.
Every role canonicalizes before persisting and before duplicate checks — alias (`Esc`→`Escape`),
case, and `vk`/`sc` digit width.

**Registry scope = curated subset, `vk`/`sc` as the documented escape hatch.** AHK's key list runs
past 100 names and there is nothing to reuse — `MacroTokens` recognizes only Enter and Tab. v1
covers exactly the six picker groups of §4 (letters/digits, F-keys, named/cursor, numpad,
media/browser, mouse + wheel). **Joystick is excluded on purpose, not for effort**: for joystick
"hotkey prefix symbols such as `^` (control) and `+` (shift) are not supported", which contradicts
the modifier-flag model outright, and the axis names (`JoyX`, `JoyY`, `JoyPOV`, …) "cannot be used
as hotkeys" at all. Hand-held remote keys are excluded as unverifiable and vanishingly rare.
Anything omitted stays reachable via `vkNN` / `scNNN`, which is what the escape hatch is for.

Each entry carries **role capability flags** (usable as hotkey key / combo prefix / Send token /
remap source / remap dest) so all five validators read one table instead of maintaining parallel
allow-lists — wheel, for instance, is a legal hotkey key and Send token but not a remap source.

Scan codes are **three** hex digits, not four, and canonicalization pads to that width (`sc1` →
`sc001`); a four-digit value could not canonicalize consistently. Anchors are `\A`/`\z`, not
`^`/`$`: .NET's `$` also matches before a trailing newline, so `vk1\n` would otherwise pass and
split the emitted left-hand side across two script lines. (This row read `{1,4}` with `^`/`$`
while W0 was unlanded; corrected 2026-07-22 to match the shipped `Constants/HotkeyKeys.cs`.)

| Role | Rule |
|--|--|
| Hotkey `Key` | ∈ registry, **or** `\Avk[0-9a-f]{1,2}\z` **or** `\Asc[0-9a-f]{1,3}\z` — combined `vkNNscNNN` is **rejected** (AHK: `vk1Bsc001::` raises an error; combining is supported only by `Send`, `GetKeyName`, `GetKeyVK`, `GetKeySC`, `A_MenuMaskKey`) |
| `ComboPrefixKey` | as Hotkey `Key`, plus `≠ Key`, and modifiers must be empty |
| `SendKeysContent` | optional `^!+#` modifiers (**`*` is not a Send modifier**) + exactly one key; a **named** key must be braced — `^{LButton}`, `{Volume_Up}` — while a single printable character is bare (`^c`) |
| Remap source | as Hotkey `Key`, **minus wheel** (`WheelUp/Down/Left/Right` are not remappable) |
| `RemapDest` | ∈ registry, **minus wheel**, **minus `Pause`** (collides with the built-in function name — use `vk13`), **minus `{}`** |

- Kind-conditional (both-or-neither / must-be-null-unless): each action requires its field(s) and
  forbids the others' (SendText→`Text`; SendKeys→valid `SendKeysContent`; Run→`RunTarget`+`RunTargetKind`;
  Window→`WindowOp`; Remap→valid `RemapDest`; Disable→none; Raw→`Body` brace-balanced, no `#` directive).
- `IsKeyUp` forbidden for wheel keys.
- Combo: `ComboPrefixKey` set ⇒ modifiers empty, prefix valid per its role row, `≠ Key`, **and
  `IsWildcard` false**. `*` is not *illegal* on a combo — AHK says custom combinations "act as
  though they have the wildcard (`*`) modifier by default", so it is redundant. Reject rather than
  silently drop, for the same reason modifiers are rejected: a stored toggle that provably does
  nothing produces a grid label that lies about the row's behavior. `IsPassthrough` and `IsKeyUp`
  **stay legal** with combos (`~RButton & C::`, `F1 & e Up::` are both valid AHK). Exactly two keys —
  AHK does not support three or more.
- Context: both-or-neither; `ContextValue` rejects `"`/backtick/control (embedded raw in `WinActive`).
- **Relax** the interim `"`/backtick rejection on text fields (now escaped at emission).

### Persistence & identity

- EF composite **unique index**
  `(OwnerOid, Ctrl, Alt, Shift, Win, Key, ComboPrefixKey, IsKeyUp, ContextMatchType, ContextValue)`
  with `.HasFilter(null)` (SQL Server treats NULLs as equal → global/no-combo rows still collide).
  `ComboPrefixKey` and `ContextValue` need explicit max lengths so the composite key stays inside
  SQL Server's 900-byte index limit (`ContextValue` at 200 chars is already 400 bytes).
  `*`/`~` are **excluded** from identity. Note this is a **product** decision, not an AHK constraint:
  AHK loads `*a::` and `a::` as distinct hotkeys, so excluding the toggles means a user cannot keep
  both — accepted, because two rows differing only by an invisible toggle read as duplicates in the
  grid. Update the handler dup-check + `Result.Conflict()`.
- Migrations **additive per wave**. The W1 action migration **maps** legacy rows; it does not clear
  them. The "clear, don't map" idea contradicts the very precedent it cited: `RawHotstringKind`
  rewrote every legacy `Script` row in T-SQL, `ScriptToRawComposer` converts legacy snapshots, and
  `RawHotstringKindMigrationTests` pins the two to byte-identical output. Mapping rules:
  - legacy `Run` → `ActionKind.Run`, `RunTarget` = `Parameters`, `RunTargetKind` = **`Application`**,
    except a value beginning `http://` or `https://` → `Url`. No cleverer inference: `Folder`
    detection would need to stat a path on the user's machine, which a server-side migration cannot
    do, and `RunTargetKind` is a **label only** — all three kinds emit the same `Run("<escaped>")`,
    so a wrong guess costs review surface and buys nothing. Users re-label on next edit.
  - legacy `Send` whose `Parameters` is a valid `SendKeysContent` token → `ActionKind.SendKeys`.
  - every other legacy `Send` → `ActionKind.Raw`, `Body` composed to **preserve current emission
    byte-for-byte**. Since W0 that emission is `Send("<escaped Parameters>")` — `HotkeyEmitter`
    routes `Parameters` through `AhkEscaping.EscapeStringLiteral` — so the composed body reproduces
    the **escaped** RHS. (This bullet said "unescaped" while W0 was still unlanded; corrected
    2026-07-22.)
  - rows whose `Key` fails the new registry/`vk`/`sc` validation are **left as-is**, not deleted —
    the key is the LHS and has no safe automatic rewrite. Surfacing them needs **no new UI**: extend
    the `IsInlineEditable` predicate so such a row returns false and routes to the dialog, where the
    existing field-level validation error already appears on open. No grid chip, no one-time notice.
    The row still emits and is still escaped, so this is a data-quality nudge on next edit, not an
    incident; the migration logs a count and stops there. Volume is small by construction — the
    lazy seed is `env.IsDevelopment`-only (`ListHotkeysQuery.cs`), so deployed legacy rows are
    hand-made user data.

### Preview & history

- `GetHotkeyPreviewQuery` — build a transient never-saved `Hotkey` from the dialog draft, run
  `HotkeyEmitter`, wrap `#HotIf`, prepend helpers → snippet byte-identical to download. Clone of
  `GetHotstringPreviewQuery`.
- `HotkeySnapshot` extends per wave with each new field (defaulted trailing members for back-compat).
  **Defaulted trailing members are not enough at W1.** Today's snapshot carries `Action` and
  `Parameters`; W1 replaces them. Old history JSON still holds those keys, and `System.Text.Json`
  silently ignores unknown properties while defaulting the missing new ones — a legacy tombstone
  would restore as `ActionKind = SendText` (value 0) with a null `Text`, i.e. a row that violates its
  own validation. So W1 must:
  - keep `Action` / `Parameters` on `HotkeySnapshot` as **optional legacy members**, and
  - add a `LegacyHotkeySnapshotConverter` (the `ScriptToRawComposer` analogue) applying the same
    mapping rules as the migration, called by **both** `RestoreHotkeyCommand` and
    `RevertHotkeyCommand`, and
  - prove migration ↔ converter agreement with a shared golden fixture set, exactly as
    `ScriptToRawFixtures` / `RawHotstringKindMigrationTests` do today.
  - Enum values for `HotkeyActionKind` must **not** be chosen so that a legacy `Action` int silently
    reads as a valid new kind; the converter keys off the legacy members' presence, not their value.

## 9. Phased implementation plan (each wave = its own PR, independently shippable)

- **W0 — Safety + foundation.** Extract `HotkeyEmitter` (behavior-preserving for current Send/Run,
  but now **escaped** via the shared `EscapeStringLiteral`); add `HotkeyDefinition` record + `Apply`
  refactor; add the canonical key registry (`Constants/HotkeyKeys.cs`) + registry/`vk`/`sc`
  validation and canonicalization in `HotkeyRules`; relax the interim text denylist. No new actions
  or columns. Update the `Generate_Hotkey_EmitsParametersVerbatim_NoEscaping` characterization test
  (`AhkScriptGeneratorTests.cs:425`) to assert escaping, and rename it accordingly.

  **Coverage claim, stated precisely.** Escaping is applied at the **single emission point**, so it
  covers every row regardless of how it was written — including the three paths that bypass
  validators: `RestoreHotkeyCommand.cs:57`, `RevertHotkeyCommand.cs:60`, and the lazy seed at
  `ListHotkeysQuery.cs:217` (plus dev `SeedHotkeysCommand.cs:94`). That is what closes the escaping
  half of **#195**. Key validation is a *boundary* rule, so a pre-validation `Key` in an old snapshot
  can still rehydrate unvalidated — the same by-design trust model already documented for hotstrings
  in `docs/development/ahk-v2-syntax.md`. W0 must **say this**, not imply snapshots are validated;
  the residual is handled by W1's converter, which sees every legacy row. W0 also records the
  current Send-vs-Run semantics in `docs/development/ahk-v2-syntax.md` while they are still true.
- **W1 — Typed actions + preview.** `HotkeyActionKind` + `WindowOp` + `RunTargetKind`; additive action
  columns; **legacy row migration + `LegacyHotkeySnapshotConverter` + shared golden fixtures**
  (§8); update all four `Hotkey.Create`/`Restore` call sites, including the lazy seed's `s_lazySeed`
  table; per-action validation + emitter branches; `HotkeyDefinition`/DTOs/snapshot/mappings
  extended; dialog action panels; `GetHotkeyPreviewQuery` + preview panel; grid Action column with
  `HotkeyActionDisplay` + `HotkeyActionChip` and the inline-row → dialog promotion path — pulled
  forward from W4, because a W1 Action column without them either duplicates display logic or leaves
  simple rows with no way to change their action. `CONTEXT.md` W1 terms + **ADR 0004**.
- **W2 — Hotkey-input expansion.** Combo/toggle/key-up columns; mouse + wheel registry entries +
  picker grouping; combo + toggle UI; self-lockout + prefix-suppression warnings; **unique-index
  rework** (add combo-key + key-up); `CONTEXT.md` W2 terms.
- **W3 — Window context.** Context columns; `#HotIf` grouping in the hotkey section; dialog context
  panel; reuse `AddWindowContextRules`; **index finalize** (add context columns); variant-precedence
  test; `CONTEXT.md` W3 term.
- **W4 — UX polish.** OKLCH chip tints; single edit button routing; glyph legend;
  `docs/development/ahk-v2-syntax.md` full hotkey section rewrite; backlog-034 label sweep for the
  hotkey mirror components.

## 10. Critical files

- **Domain**: `Entities/Hotkey.cs`, new `Entities/HotkeyDefinition.cs`, new
  `Enums/{HotkeyActionKind,WindowOp,RunTargetKind}.cs` (retire `Enums/HotkeyAction.cs`).
- **Application**: new `Services/HotkeyEmitter.cs`, new `Services/LegacyHotkeySnapshotConverter.cs`,
  new `Constants/HotkeyKeys.cs`, `Services/AhkScriptGenerator.cs` (remove `FormatHotkey`, add
  grouping), `Services/HotstringEmitter.cs` (extract shared `EscapeStringLiteral`),
  `Validation/HotkeyRules.cs`, `DTOs/HotkeyDto.cs`, `DTOs/HistorySnapshots.cs`,
  `Mapping/HotkeyMappings.cs`, `Commands/Hotkeys/*`, `Commands/Dev/SeedHotkeysCommand.cs`,
  `Queries/Hotkeys/ListHotkeysQuery.cs` (`s_lazySeed`) + new `Queries/Hotkeys/GetHotkeyPreviewQuery.cs`.
- **Infrastructure**: `Persistence/Configurations/HotkeyConfiguration.cs`, per-wave migrations.
- **API**: `Controllers/HotkeysController.cs` (+ preview endpoint).
- **UI**: `Pages/Hotkeys.razor`, `Components/Hotkeys/HotkeyEditDialog.razor`,
  `Components/Hotkeys/HotkeyMobileList.razor`, `Validation/HotkeyEditModel.cs`, new action panels +
  `HotkeyActionChip.razor` + `Helpers/HotkeyActionDisplay.cs`.
- **Docs**: `CONTEXT.md`, new `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md`,
  `docs/development/ahk-v2-syntax.md`.
- **Tests**: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`, new
  `TestUtilities/Fixtures/LegacyHotkeyFixtures.cs`, `AhkScriptGeneratorTests`,
  `HotkeyRules`/validator tests, new `Infrastructure.Tests/Migrations/*` parity test,
  `History/{Restore,Revert}CommandTests`, `HotkeysEndpointsTests`, bUnit dialog/grid tests,
  `E2E.Tests` hotkey flow.

## 11. Verification

- `dotnet build` + `dotnet test` green each wave. Goldens are **cumulative by wave**, not all
  deferred to the end: W1 proves the action examples (1–2, 4–15, 17–18, 20), W2 adds the
  toggle/combo/mouse ones (3, 16, 18–19), W3 adds context (20), and the full 20-example set is the
  final gate. A wave that ships without its own goldens has nothing to regress against.
- Validator unit tests per **role** (TDD-first, pure functions): the five grammars in §8, including
  the negative cases the design turns on — combined `vkNNscNNN` rejected, `*` rejected as a Send
  modifier, unbraced named Send key rejected, wheel rejected as remap source/dest, `Pause` rejected
  as remap dest. Plus kind-conditional rules, combo/key-up/context edges, relaxed denylist, and
  canonicalization (alias, case, `vk`/`sc` width) before duplicate detection.
- **Legacy migration parity** (Infrastructure Testcontainers, mirroring
  `RawHotstringKindMigrationTests`): every legacy fixture row migrated in T-SQL is byte-identical to
  `LegacyHotkeySnapshotConverter` output, and legacy restore/revert produce the same definition.
  These tests must exist **before** W1's migration is considered done. Seed the fixture set from the
  **existing dev lazy-seed rows** (`ListHotkeysQuery.cs:65`) — they already cover every hard case:
  a Run target carrying arguments (`rundll32.exe user32.dll,LockWorkStation`), a Run target that
  isn't one (`Reload`), a bare scheme (`https://`), clean one-token Sends (`{Up}`, `^v`) that must
  become SendKeys, and a leaked hotstring macro token (`{{date:yyyy-MM-dd}}`) that must fall back to
  Raw. Anything invented would be gentler than the data already in the repo.
- Integration (WebApplicationFactory + Testcontainers): POST each action kind → 201 + correct DB
  state; duplicate identity → 409; malformed → 400 naming the field.
- `#HotIf` variant precedence: two context variants of one key emit in deterministic
  `(matchType, value)` order, and the global variant is emitted last.
- Preview parity: `GetHotkeyPreviewQuery` output == the corresponding line in the profile download.
- bUnit: dialog action-panel switching, warnings, preview debounce; grid inline-edit gating.
- `playwright-cli` smoke of the Hotkeys page (worktree runs no-auth on UI 5603 / API 5602).

## Resolved decisions (grilling, 2026-07-21)

1. Action data = discriminated typed columns (not string/JSON).
2. Safe emission = per-action escaping; Raw the sole verbatim path → #195 closed structurally.
3. Flat `HotkeyDefinition` record + `Apply`; extracted `HotkeyEmitter`.
4. Key validation = canonical registry (single source for validation + picker) + `vk`/`sc` pattern,
   with **role-specific grammars** over one registry (hotkey key, combo prefix, SendKeys token,
   remap source, remap dest) and canonicalization before duplicate checks.
5. Remap and Disable are two dedicated actions → v1 set = 7.
6. Mouse buttons + wheel in v1; soft self-lockout warning.
7. Combo = `ComboPrefixKey`, 2 keys, modifiers forbidden when set, prefix-suppression warning.
8. Toggles = `*`, `~`, ` Up`; defer `$`, left/right modifiers, AltGr.
9. Window context in v1, reuse hotstring `#HotIf` stack, own grouping (context-first/global-last).
10. Binding identity = `(Owner, Ctrl,Alt,Shift,Win, Key, ComboPrefixKey, IsKeyUp, ContextMatchType, ContextValue)`; `*`/`~` excluded.
11. Additive migrations per wave; **map (don't clear)** legacy rows at the action migration, with a
    legacy-snapshot converter and migration/converter parity fixtures.
12. Hotkey preview endpoint = clone of `GetHotstringPreviewQuery`, byte-identical to download.
13. CLI vertical = separate follow-up spec, not this arc.
14. Keep "Trigger" hotstring-only; add Action/Remap/Combo/Passthrough/Wildcard/Run-target terms,
    extend Window-context + Raw; one ADR (0004). Terms land in the wave that introduces them.

## Resolved (spec review, 2026-07-21)

15. **Raw model** = structured, validated, canonicalized key + modifiers, plus a verbatim action
    `Body`. Note this **diverges** from hotstring Raw, which stores the whole verbatim definition
    (`ScriptToRawComposer`, `Helpers/RawDefinition.cs`) — the divergence is deliberate and is what
    keeps #195 closed on the LHS, so "mirrors the hotstring model" must not be claimed for Raw.
    Raw is **not** sandboxed and can break the whole profile script (§5).
16. **Window `Center`** deferred out of v1 — removed from the enum, emitter, examples, and waves.
17. **Variable sends** (`SendText A_Clipboard`) are Raw in v1; example 10 becomes Raw. A future safe
    feature is a *clipboard-text* source reusing `PasteHelperFunction`, not arbitrary expressions.
18. **W0 stays a separate wave** — fastest path to the escaping half of #195, small reviewable PR,
    with its coverage claim scoped honestly to emission (§9 W0).
19. **Token storage** confirmed for `SendKeysContent` / `RemapDest` — single canonical strings
    composed from discrete picker state, each validated by its own grammar (not one shared rule).
20. **`$`** is not a v1 user toggle but is auto-emitted for keyboard SendKeys bindings (§5).
21. **Emission style** standardized on the parenthesized call form (§1).
22. **Combo toggles**: `*` rejected when a combo is set (combos are wildcard by default); `~` and
    `Up` stay legal on combos; exactly two keys.
23. **Legacy `RunTargetKind`**: everything → `Application`, except an `http(s)://` prefix → `Url`.
    No `Folder` inference. `RunTarget` is a **command line**, not a path — no path-shaped validation,
    no separate arguments column in v1.
24. **Legacy invalid keys**: no new UI — extend `IsInlineEditable` to route those rows to the dialog,
    where the existing validation error already shows. Migration logs a count.
25. **Registry scope**: curated six groups + `vk`/`sc` escape hatch; joystick and remote keys
    excluded; entries carry role capability flags feeding all five validators.

## Unresolved questions

None. Ready for `writing-plans`.
