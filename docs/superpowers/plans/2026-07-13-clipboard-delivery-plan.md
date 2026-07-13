# Clipboard Delivery for Text Hotstrings — Plan

## Context

AutoHotkey delivers hotstring replacements two ways:

- **Typed (SendInput, default):** replacement sent character-by-character. Fast for short snippets, but visibly slow past a few hundred characters and hard-capped at ~5000 chars.
- **Clipboard paste:** an X (execute) hotstring sets `A_Clipboard`, sends `^v`, restores the old clipboard. Instant regardless of length; caveats are Ctrl+V support in the target app, paste timing (needs `ClipWait` + short delay), briefly disturbing clipboard history, and no case-conforming.

AHKFlow only emits typed hotstrings today. This plan adds clipboard delivery for long Text hotstrings, with auto-detection.

## Decisions (confirmed)

1. New enum `HotstringDelivery { Auto = 0, Type = 1, ClipboardPaste = 2 }` on `Hotstring`, orthogonal to `Kind`. Default `Auto`.
2. Auto rule: replacement ≥ **200 chars** (Domain constant) → clipboard; resolved at emit time; preview shows effective delivery.
3. Replacement cap **100 000** chars for clipboard/auto delivery; **4000 stays** for `Delivery=Type`.
4. Built **after the Raw-kind work merges** (assumes `Raw=4`, emitter Raw guard, `nvarchar(max)` Replacement). New branch `feature/wt-clipboard-delivery`.
5. Text kind only; **reject** `Delivery != Auto` for DateTime/Macro/Raw. Out of scope: alternative send modes, import detection, configurable delays.

## Generated-script mechanics

Helper emitted once per script (only when ≥1 hotstring resolves to clipboard), after the header:

```ahk
AhkFlow_PasteReplacement(text, endChar := "") {
    saved := ClipboardAll()
    A_Clipboard := text
    if !ClipWait(1) {
        A_Clipboard := saved
        return
    }
    Send "^v"
    Sleep 150            ; paste-before-restore reliability delay (fixed for now)
    A_Clipboard := saved
    saved := ""
    if (endChar != "")
        SendText endChar
}
```

Emitted line (X hotstring; `X` leads; `* ? C` honored; no `O` — auto-replace-only, replaced by the endChar arg; no `T` — X body is an expression):

```
:X:sig::AhkFlow_PasteReplacement("Kind regards,`nBart...", A_EndChar)   ; end char preserved (default)
:X:sig::AhkFlow_PasteReplacement("Kind regards,`nBart...")              ; OmitEndingCharacter or *
```

Trigger uses `Escape`; replacement uses `EscapeStringLiteral` — multiline stays one physical line via `` `n ``. AHK v2 has no per-line length cap.

Effective-delivery resolver (pure, on `HotstringEmitter`; DB keeps user intent `Auto`):

```csharp
public static HotstringDelivery ResolveEffectiveDelivery(Hotstring hs) =>
    hs.Kind == HotstringKind.Text
        && (hs.Delivery == HotstringDelivery.ClipboardPaste
            || (hs.Delivery == HotstringDelivery.Auto
                && hs.Replacement.Length >= HotstringDeliveryDefaults.AutoClipboardThresholdChars))
        ? HotstringDelivery.ClipboardPaste
        : HotstringDelivery.Type;
```

## Tasks (dependency order)

### P0 — Domain (compile gate)
- New `Domain\Enums\HotstringDelivery.cs`; new `Domain\Constants\HotstringDeliveryDefaults.cs` (`AutoClipboardThresholdChars = 200`).
- `HotstringDefinition.cs`: append `HotstringDelivery Delivery = HotstringDelivery.Auto` (last positional param). `Hotstring.cs`: property + `Apply`.

### P1 — Validators (TDD)
- Tests first (Create/Update/Preview validator tests): invalid enum; non-Text + non-Auto rejected ("Delivery must be Auto unless Kind is Text."); Text+Type at 4001 rejected; Text+Auto at 4001 valid; Text+Clipboard 100 000 valid / 100 001 rejected; Macro at 4001 still rejected.
- `HotstringRules.cs`: `ClipboardReplacementMaxLength = 100_000`; new `AddDeliveryRules(kind, delivery, replacement)`.
- Length-ownership refactor: shared `ValidReplacement()` becomes NotEmpty-only; length moves per-kind (Text → AddDeliveryRules, Macro → AddMacroKindRules, Raw owns its own). Wire into all three validators.

### P2 — Emitter (TDD, golden lines) — ⚠ after Open Q1 verified
- Golden tests in `AhkScriptGeneratorTests`: default → `..., A_EndChar)`; `OmitEndingCharacter`/`*` → no endChar arg; `*?C` order, no T; escaping golden; Auto boundary 199→typed / 200→clipboard; non-Text kinds unaffected.
- `HotstringEmitter.cs`: `ResolveEffectiveDelivery`, `PasteHelperName`/`PasteHelperFunction` consts, clipboard branch in `Emit` after Raw guard, `BuildClipboardOptions` (extract shared `*?C` helper), `BuildClipboardBody`.

### P3 — Generator helper emission (TDD)
- `AhkScriptGenerator.Generate`: emit helper block between header and hotstrings when any hotstring resolves to clipboard. Tests: exactly once across #HotIf groups; absent when unused.

### P4 — Backend DTOs / handlers / preview
- DTO records (`HotstringDto`, `Create…`, `Update…`, `HotstringPreviewRequestDto`): append `Delivery = Auto`. `HotstringPreviewDto` gains `EffectiveDelivery` (never Auto in responses).
- Mappings, Create/Update handlers, preview handler returns `ResolveEffectiveDelivery`. Handler + preview tests.

### P5 — EF config + migration
- `HotstringConfiguration.cs`: `Property(x => x.Delivery).IsRequired().HasConversion<int>()`.
- `dotnet ef migrations add AddHotstringDelivery` — additive int, `defaultValue: 0`.

### P6 — History snapshots
- `HotstringSnapshot`: append `Delivery = Auto` (legacy JSON degrades to Auto). Recorder + Restore/Revert pass-through. Round-trip + legacy-JSON tests.

### P7 — OpenAPI
- `HotstringExamples.cs`: preview example gains `EffectiveDelivery = Type`; show `Delivery: Auto` on create example.

### P8 — Blazor UI
- Enum copy in `UI.Blazor\DTOs\`; mirror DTO changes.
- `HotstringEditModel.cs`: `Delivery` through FromDto/Clone/ToCreate/ToUpdate; replace `[MaxLength(4000)]` with conditional validation (4000 when Text+Type, 100k otherwise).
- `HotstringEditDialog.razor`: delivery selector (Auto/Typed/Clipboard) for Text only, reset on kind switch; hint "Auto types short replacements and pastes 200+ characters via the clipboard"; preview carries Delivery; effective-delivery chip (`data-test="preview-delivery"`).
- Lists: minimal "Clipboard" chip for Text rows with explicit delivery. bUnit tests.

### P9 — CLI
- Enum copy + `Delivery` on DTOs in `IHotstringsApiClient.cs`. `NewHotstringCommand.cs`: `--delivery auto|type|clipboard` (case-insensitive; invalid → stderr + exit 2). Tests.

### P10 — Docs, E2E, verify
- `docs\cli\hotstrings.md`: `--delivery` + clipboard-delivery paragraph.
- E2E: 250-char Text hotstring → downloaded script contains helper exactly once + `AhkFlow_PasteReplacement(`.
- `dotnet build`, full `dotnet test`, `dotnet format`, dck-verify.

## Verification
- TDD gates: P1 validator, P2/P3 golden tests red→green.
- Manual: profile with 1 short + 1 long Text hotstring; inspect .ahk (helper once, typed short line, clipboard long line with `A_EndChar`).
- E2E download assertion; full suite green before PR.

## Out of scope
Menu-based multi-replacement output, SendPlay/SendEvent modes, import recognition of the helper call (re-import classifies as unsupported — follow-up), configurable Sleep/ClipWait, case-conforming for pasted text (documented in hint).

## Unresolved questions
1. End-char behavior for X hotstrings — verify empirically (5-line .ahk, manual) that AHK consumes the ending char before finalizing P2; if it survives, drop the `A_EndChar` arg.
2. Preview: delivery chip + hint only, or include helper block in preview snippet? (Plan: chip + hint.)
3. UI hint threshold (200) hardcoded vs served by API? (Plan: duplicated constant, like existing limits.)
