# AutoHotkey v2 Syntax Reference

The subset of AutoHotkey v2 that AHKFlowApp generates and parses. This is a working reference for
changing the emitters — not a general AHK tutorial. For anything outside this surface, the
authoritative source is [the official v2 docs](https://www.autohotkey.com/docs/v2/)
(the [Hotstrings page](https://www.autohotkey.com/docs/v2/Hotstrings.htm) covers most of what's here).
The site 403s automated fetchers; the same content is fetchable from the
[AutoHotkeyDocs source repo](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v2/docs/Hotstrings.htm).

We generate `.ahk` files; we never run them. Nothing below is validated by executing AutoHotkey, so
the emitters are the only thing standing between a user's input and a broken script on their machine.

**Where this lives in code:**

| Concern | File |
|---|---|
| Script assembly | `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` |
| Hotstring lines, options, escaping | `src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs` |
| Hotkey lines, per-action emission | `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs` |
| Hotkey key registry and roles | `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs` |
| Raw definition parsing | `src/Backend/AHKFlowApp.Application/Services/RawHotstringDefinitionParser.cs` |
| Macro token lexing | `src/Backend/AHKFlowApp.Application/Services/MacroTokenParser.cs` |
| Header/footer tokens | `src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs` |
| Default header | `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs` |
| Input limits | `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs`, `HotkeyRules.cs` |

## Script skeleton

Every generated script opens with the profile's header template. The default
(`DefaultProfileTemplates.Header`) is:

```ahk
; {ProfileName} — AHKFlowApp v{AppVersion}
; {HotstringCount} hotstrings, {HotkeyCount} hotkeys
; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
SendMode "Input"
SetWorkingDir A_ScriptDir
SetTitleMatchMode 2
```

Each directive earns its place:

- `#Requires AutoHotkey v2.0` — refuses to run under v1, whose syntax is incompatible. Without it a
  v1 interpreter fails with confusing errors deep in the file rather than at line 1.
- `#SingleInstance Force` — re-running replaces the running instance instead of prompting.
- `#Warn All, Off` — generated code shouldn't lecture the user about warnings they can't fix.
- `SendMode "Input"` — SendInput is the fastest and most reliable send mode.
- `SetWorkingDir A_ScriptDir` — makes any relative path in a `Run` hotkey resolve predictably.
- `SetTitleMatchMode 2` — "contains" matching. **This one is load-bearing:** `WindowMatchType.TitleContains`
  emits a bare title substring into `WinActive()`, which only means "contains" under mode 2.
  Changing this line silently changes what every title-matched hotstring matches.

Header tokens are substituted by `HeaderTokenRenderer`: `{ProfileName}`, `{AppVersion}`,
`{HotstringCount}`, `{HotkeyCount}`, and `{GeneratedAt}` (accepts a .NET format string after a colon;
defaults to round-trip `o`). Unknown tokens are left verbatim rather than blanked, so a user's
`{Foo}` survives instead of silently vanishing. Literal braces are doubled: `{{` and `}}`.
All formatting uses `InvariantCulture` — generated scripts must not vary by server locale.

Body layout, in order: paste helper (only when some hotstring needs it), `; --- Hotstrings ---`,
window-context groups, global hotstrings, `; --- Hotkeys ---`, hotkeys, footer. Lines are joined
with `\n`.

## Hotstring definitions

The shape is:

```
:options:trigger::replacement
```

The first `::` after the options block delimits the trigger. Everything after it is the replacement,
which may be inline or a brace body.

An `; ` comment line is emitted above each entry from its Description (`DescriptionCommentLines`);
a blank Description emits nothing.

### Option flags we emit

`HotstringEmitter` emits flags in a fixed order — **`X * ? C O T`**. The order is deterministic so
that regenerating an unchanged profile produces byte-identical hotstring lines; diffs then mean
something. (The complete file is *not* byte-identical under the default header — `{GeneratedAt}`
changes every run.) Preserve the order if you add a flag.

| Flag | Meaning | We emit it when |
|---|---|---|
| `X` | Execute: the body is an expression to run, not replacement text | Kind is DateTime, or delivery resolves to ClipboardPaste |
| `*` | No ending character required — fires the moment the trigger completes | `!IsEndingCharacterRequired` |
| `?` | Fires even inside another word | `IsTriggerInsideWord` |
| `C` | Case-sensitive trigger match | `IsCaseSensitive` |
| `O` | Omit the ending character from the output | `OmitEndingCharacter && IsEndingCharacterRequired` |
| `T` | Text mode: send the replacement literally, no `{Enter}`/`^c` translation | Kind is Text |

Two of those conditions look redundant and are not:

- **`O` is gated on `IsEndingCharacterRequired`.** `O` omits the ending character, but `*` means
  there's no ending character to omit — the combination is meaningless, so the gate keeps it out of
  the file.
- **`T` is Text-only.** `T` declares "this is literal replacement text," which is a lie for the
  brace-body kinds (DateTime, Macro, Raw) — they have no auto-replace text at all. `T` and `X` are
  contradictory by construction; never emit both.

`T` on all Text hotstrings is a deliberate literal-characters guarantee: a replacement containing
`{` or `^` is sent as those characters, not reinterpreted as keystrokes. It is *not* full WYSIWYG:
case-insensitive hotstrings still case-conform by default (type the trigger in ALL CAPS and AHK
uppercases the replacement) — suppressing that would take `C1`, which we don't emit.

### Option flags we accept (Raw only)

Raw definitions are authored by the user, so the parser accepts AHK's full documented set rather
than just what we emit (`RawHotstringDefinitionParser.KnownOptions`, case-insensitive):

```
*  *0  ?  ?0  B  B0  C  C0  C1  O  O0  R  R0  S  S0  SI  SP  SE  T  T0  X  Z  Z0
```

plus `Kn` (key delay, `K-1` allowed) and `Pn` (priority) by pattern. Anything else is rejected by
name. Briefly, for the ones we never emit: `B0` disables auto-backspacing of the abbreviation, `C1`
stops case-conforming, `R` sends raw (mutually exclusive with `T`), `Z` resets the recognizer after
each trigger, `SI`/`SP`/`SE` pick the send mode, and a trailing `0` turns most flags back off.

### Bodies by kind

**Text** — the escaped replacement inline, or, when delivery resolves to clipboard, a call to the
paste helper.

```ahk
:T:btw::by the way
```

**DateTime** — `X` plus a `SendText(FormatTime(...))` expression. With an offset configured it wraps
`DateAdd`:

```ahk
:X:ddate::SendText(FormatTime(A_Now, "yyyy-MM-dd"))
:X*:nextweek::SendText(FormatTime(DateAdd(A_Now, 7, "Days"), "dddd d MMMM yyyy"))
```

`DateTimeFormat` is embedded **without escaping** — it's already passed a whitelist regex
(`^(?=.*[yMdHhmst])[yMdHhmst0-9 \-./:,()]+$`) at validation, which is what makes that safe. That
whitelist is the only thing preventing format-string injection into the generated expression; don't
loosen it without re-examining the emitter.

**Macro** — a tab-indented brace body. The user's vocabulary is deliberately tiny: `{{cursor}}`,
`{{key:Enter}}`, `{{key:Tab}}`, and `{{{{...}}}}` for a literal brace run. Consecutive identical keys
collapse into one `Send "{Name N}"`, and a `{{cursor}}` becomes a trailing `Send "{Left N}"` counting
the characters after it.

```ahk
:*:htag::
{
	SendText "<b></b>"
	Send "{Enter 2}"
	Send "{Left 4}"
}
```

(The emission of `<b>{{cursor}}</b>{{key:Enter}}{{key:Enter}}`, pinned in `AhkScriptGeneratorTests`.
`{Left 4}` counts the four text characters after the cursor token — `</b>`. That golden feeds the
emitter directly; API input with keys after `{{cursor}}` is rejected by validation.)

Validation guarantees at most one `{{cursor}}` and no keys after it — that's what lets the emitter
compute a single `{Left N}` at the end instead of tracking caret movement through the token stream.

**Raw** — emitted **verbatim from storage**. `Replacement` already holds the entire
`:opts:trigger::` line plus any body, so the emitter returns it untouched; re-applying the template
would double the definition. But what's stored is not the user's paste: create/update run it through
`RawHotstringDefinitionParser.Prepare` and persist the `NormalizedDefinition`
(`CreateHotstringCommand.cs`), which lifts leading `;` comments into Description, converts
CRLF/lone-CR to LF, trims blank lines and per-line trailing whitespace (except inside continuation
sections, where trailing whitespace is significant under `RTrim0`), and expands an OTB brace
(`:X:t::{`) onto its own line. Three body shapes are accepted: inline replacement, a `{ … }` brace
body, and a `( … )` continuation section kept as verbatim literal text.

**Clipboard delivery** — for long Text replacements, typing is slow and error-prone, so we paste
instead. Delivery resolves to clipboard when Kind is Text and either the user chose `ClipboardPaste`
or delivery is `Auto` and the replacement is ≥ 200 characters
(`HotstringDeliveryDefaults.AutoClipboardThresholdChars`). The helper is emitted once per script,
only if something needs it:

```ahk
AhkFlow_PasteReplacement(text, endChar := "") {
    saved := ClipboardAll()
    A_Clipboard := text
    if !ClipWait(1) {
        A_Clipboard := saved
        return
    }
    Send "^v"
    Sleep 150
    A_Clipboard := saved
    saved := ""
    if (endChar != "")
        SendText endChar
}
```

It saves and restores the user's clipboard around the paste. `A_EndChar` (the character that
triggered the hotstring) is passed through only when an ending character is required and not omitted
— clipboard bodies use `X`, so the ending character isn't handled for us and has to be re-sent by hand.

## Escaping

AHK v2's escape character is the **backtick**, not backslash. Two escape routines exist and the
difference matters:

| | `Escape()` | `EscapeStringLiteral()` |
|---|---|---|
| Used for | triggers, inline replacements | contents of `SendText "..."` / `Send "..."` / `Run("...")` — hotstrings **and** hotkeys, via the shared `AhkEscaping` helper |
| `` ` `` → | ` `` ` | ` `` ` |
| newline → | `` `n `` | `` `n `` |
| CR / tab → | `` `r `` / `` `t `` | `` `r `` / `` `t `` |
| `"` → | *not escaped* | ``  `" `` |
| `;` → | `` `; `` | *not escaped* |

The asymmetry is not an oversight:

- `;` is escaped **only** outside quotes. AHK starts a comment at a `;` preceded by whitespace, which
  would truncate a hotstring line — but inside a quoted string literal that rule doesn't apply.
- `"` is escaped **only** inside quotes, where it would otherwise close the literal early. An inline
  replacement isn't quoted, so a `"` there is just a character.

**In both routines the backtick must be replaced first.** Escaping it after the others would
re-escape the backticks they just introduced, turning `` `n `` into `` ``n ``.

Newlines are escaped rather than emitted so that every hotstring stays on one physical line — which
is what makes the file greppable and the `\n` join safe.

## Window context

Hotstrings with a window context are grouped and wrapped in `#HotIf`. Groups come first (ordered by
match type, then value); the global group is emitted last, unwrapped. Grouping is why the
`GroupBy` in `AhkScriptGenerator` must stay stable — the ordinal trigger sort has to survive it.

```ahk
#HotIf WinActive("ahk_exe notepad.exe")
:T:btw::by the way
#HotIf
```

| `WindowMatchType` | Emits |
|---|---|
| `Executable` | `WinActive("ahk_exe <value>")` |
| `WindowClass` | `WinActive("ahk_class <value>")` |
| `TitleContains` | `WinActive("<value>")` — substring, per `SetTitleMatchMode 2` |

A bare `#HotIf` (no expression) clears context and restores global scope. Every opened group **must**
be closed with one, or the context leaks into every subsequent hotstring in the file. Use
`HotstringEmitter.HotIfClose` rather than a literal, so the generator and the preview handler can't drift.

`ContextValue` is embedded raw into the `WinActive()` expression. That's only safe because
`AddWindowContextRules` rejects double-quotes, backticks, and control characters up front — the
validator is the escaping here.

## Hotkeys

```
[$][modifiers]Key::<action>
```

`HotkeyEmitter` builds the whole line. On the create and update path the left-hand side is assembled
from validated parts only — never free text — which is what keeps a hotkey from breaking the script
it lands in (ADR-0004). Snapshots bypass that path; see the limits below.

| Modifier | Symbol |
|---|---|
| Ctrl | `^` |
| Alt | `!` |
| Shift | `+` |
| Win | `#` |

Modifiers are emitted in the fixed order `^ ! + #` regardless of the order they were set in, for the
same reason the hotstring option flags are ordered: regenerating an unchanged profile must produce
byte-identical lines.

A leading `$` is emitted for `SendKeys` and for **no other action**. `$` forces the keyboard hook,
which as a side effect prevents `Send` from triggering the script's own hotkeys — without it a
`SendKeys` binding can retrigger itself. It is emitted unconditionally rather than only on a detected
self-collision: `$` has no other effect, and a same-key-and-modifiers check would still miss
A-triggers-B-triggers-A chains. It is not a user-facing option.

`Key` is validated against the canonical registry in `HotkeyKeys` (or a `vkNN` / `scNNN` code) at the
create and update boundaries, so an accepted key is a real AHK key name. Two limits are worth stating
plainly:

- **Snapshots bypass validation.** History restore and revert rehydrate a stored snapshot
  without running validators — `LegacyHotkeySnapshotConverter.ToDefinition` passes a W1
  snapshot's typed fields straight through — as does the development lazy seed. Emission-time
  escaping is not a backstop for that: it applies only to the three quoted-literal kinds
  (see below), so a restored `Raw` row reaches `HotkeyEmitter` and is written verbatim with
  neither escaping nor the shape check the create/update path applies. A `Key` or a `Body`
  written before validation landed can return unvalidated until the row is next edited.
  This mirrors the hotstring trust model.
- **VK/SC codes are accepted only in a narrow form.** `vkNN` and `scNNN` are each accepted;
  combined `vkNNscNNN` is not, because AHK raises an error for it in a hotkey definition
  (that form is supported only by `Send`, `GetKeyName`, `GetKeyVK`, `GetKeySC` and
  `A_MenuMaskKey`). `HotkeyKeys` also rejects an all-zero code (`vk0`, `vk00`, `sc000`) —
  it names no key — caps the digits at 2 hex for `vk` and 3 for `sc`, and rejects
  surrounding whitespace rather than trimming it. Accepted codes are canonicalized by
  lower-casing and zero-padding (`vk1` → `vk01`, `sc1` → `sc001`), so one physical key
  cannot survive as two rows.

### Right-hand side per action

Each `HotkeyActionKind` owns its own stored field(s) and exactly one emitted form:

| Action | Stored | Emits |
|---|---|---|
| `SendText` | `Text` | `SendText("<escaped>")` |
| `SendKeys` | `SendKeysContent` | `Send("<escaped>")` — plus the `$` prefix |
| `Run` | `RunTarget`, `RunTargetKind` | `Run("<escaped>")` — `RunTargetKind` is a display label and changes nothing |
| `Window` | `WindowOp` | `WinMinimize("A")`, `WinMaximize("A")`, `WinRestore("A")`, `WinClose("A")`, `WinSetAlwaysOnTop(-1, "A")` |
| `Remap` | `RemapDest` | the destination key name, bare |
| `Disable` | — | `return` |
| `Raw` | `Body` | `Body`, verbatim |

```ahk
#n::Run("notepad")
^!s::SendText("Jane Smith`nAcme")
$#p::Send("{Media_Play_Pause}")
^Space::WinSetAlwaysOnTop(-1, "A")
CapsLock::Ctrl
F1::return
```

Only the three kinds that embed user text in a quoted literal — `SendText`, `SendKeys`, `Run` — pass
through `AhkEscaping.EscapeStringLiteral`. `Remap` emits a bare key name with no literal to escape,
`Disable` emits a fixed word, `Window` emits from an enum, and `Raw` is verbatim by definition.

**Token validation and literal escaping are separate layers.** `"` and `` ` `` are legal
one-character `SendKeys` tokens — `Send` types them — so a token that passed validation still has to
be escaped or it terminates the string literal. A lone backtick emits:

```ahk
$a::Send("``")
```

`RunTarget` is a **command line**, not a path: AHK's `Run` takes arguments and existing rows rely on
it (`rundll32.exe user32.dll,LockWorkStation`), so there is no path-shaped validation.

An action kind the emitter doesn't know throws rather than emitting a broken line, as do `Window`
without a `WindowOp` and `Remap` without a `RemapDest`. The rest degrade instead of throwing: the
three quoted-literal kinds emit an empty literal (`a::Run("")`) when their column is null, and `Raw`
with a null `Body` emits a bare `a::`. Deliberate, and unreachable through the API.

#### `Raw` is unchecked

`Body` is emitted exactly as stored: no wrapper, no braces added, no escaping. A block body carries
its own braces, and because the emitter concatenates it straight after `::` the result is the
one-true-brace form:

```ahk
^+v::{
	SendText A_Clipboard
}
```

Validation checks shape only — non-empty, balanced `{`/`}`, no line starting with a `#` directive, no
stray control characters. It does not check that the body is valid AutoHotkey, and the brace count is
as naive as the hotstring one (see *Known limitations*). AHK parses the whole file at load, so a
mistake here aborts the **entire** generated profile, not just this binding. Verbatim emission is
also what keeps legacy `Send` rows migrated onto `Raw` byte-identical to what the app emitted before
the typed actions landed.

#### Why `SendText` and `SendKeys` are separate

`Send` reads its argument as a key sequence, so AHK re-reads `^ ! + #` as modifiers and `{...}` as
key names. Escaping does not — and must not — prevent this: `AhkEscaping` covers the string-literal
layer only, and by the time `Send` parses the string those characters are ordinary text that `Send`
is entitled to interpret. Prose therefore does not survive `Send`:

```ahk
^a::Send("50% off! a+b {note}")
```

types `50% off` in Notepad++ and `50% ` in Notepad — `!` becomes Alt, so the remainder turns into
Alt+key accelerators that each application resolves differently, `+b` sends Shift+b, and `{note}` is
parsed as a key name. (Backticks and `%` are unaffected: `` he said "hi" 100`% `` round-trips
exactly, because neither is special to `Send`.)

That is why prose belongs to `SendText`, which types its argument literally, while `SendKeys` accepts
only a validated token — optional `^ ! + #` modifiers, each at most once, then exactly one key: a
single printable character bare (`c`), or a registry key braced (`{Volume_Up}`). A named key
unbraced, two keys, or a nested brace are all rejected.

## Input limits

From `HotstringRules`:

| Field | Limit |
|---|---|
| Trigger (structured kinds) | 50 |
| Trigger (Raw) | 40 — AHK's own documented abbreviation cap |
| Replacement (Text, explicit `Type`) | 4,000 |
| Replacement (Text, `Auto` / `ClipboardPaste`) | 100,000 |
| Replacement (Macro) | 4,000 |
| Raw definition | 4,200 — 4,000 body plus option/trigger/brace overhead |
| Description | 200 |
| DateTimeFormat | 50 |
| Date offset amount | ±3,650 |
| ContextValue | 200 |

From `HotkeyRules`:

| Field | Limit |
|---|---|
| Description | 200 |
| Key | 20 |
| `Text`, `RunTarget`, `Body` | 4,000 (`HotkeyRules.PayloadMaxLength`) |

The 4,000 is a validation policy, not a column ceiling: it is the cap the retired `ValidParameters`
rule enforced, carried onto the typed columns so the limit survived the move. Only `RunTarget` is
actually `nvarchar(4000)` — `Text` and `Body` are `nvarchar(max)`.

## Known limitations

Raw brace-balance checking counts `{` and `}` naively, with no awareness of string literals or
comments (decision D12). The heuristic errs in both directions: `SendText "{"` counts the brace
inside the quotes and can be rejected despite being valid AHK, and a comment line ending in `}`
counts toward the balance and can mask a genuinely missing closing brace — an invalid definition
accepted. This is deliberate: a string/comment-aware scanner would drift toward being a script IDE
(D8). If a user hits the false rejection, the workaround is to restructure the definition, not to
loosen the check.
