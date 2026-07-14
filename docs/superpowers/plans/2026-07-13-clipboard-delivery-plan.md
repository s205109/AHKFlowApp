# Clipboard Delivery for Text Hotstrings — Plan

**Status:** Implemented 2026-07-14 on `feature/wt-clipboard-delivery`. Build, full automated tests, formatting, browser E2E, and AutoHotkey v2 static validation are green; the real-application clipboard acceptance checklist remains a pre-merge manual step.

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

### P2 — Emitter (TDD, golden lines) — ⚠ after Verification checklist item 1 (end-char behavior) is confirmed
- Golden tests in `AhkScriptGeneratorTests`: default → `..., A_EndChar)`; `OmitEndingCharacter`/`*` → no endChar arg; `*?C` order, no T; escaping golden; Auto boundary 199→typed / 200→clipboard; non-Text kinds unaffected.
- `HotstringEmitter.cs`: `ResolveEffectiveDelivery`, `PasteHelperName`/`PasteHelperFunction` consts, clipboard branch in `Emit` after Raw guard, `BuildClipboardOptions` (extract shared `*?C` helper), `BuildClipboardBody`.

### P3 — Generator helper emission (TDD)
- `AhkScriptGenerator.Generate`: emit helper block between header and hotstrings when any hotstring resolves to clipboard. Tests: exactly once across #HotIf groups; absent when unused.

### P4 — Backend DTOs / handlers / preview
- DTO records (`HotstringDto`, `Create…`, `Update…`, `HotstringPreviewRequestDto`): append `Delivery = Auto`. `HotstringPreviewDto` gains `EffectiveDelivery` (never Auto in responses).
- Mappings, Create/Update handlers, preview handler returns `ResolveEffectiveDelivery` and, when that is `ClipboardPaste`, prepends the `AhkFlow_PasteReplacement` helper block to the snippet so the copyable "Generated AutoHotkey code" preview is self-contained. Handler + preview tests (incl. clipboard preview contains the helper; typed preview unchanged).

### P5 — EF config + migration
- `HotstringConfiguration.cs`: `Property(x => x.Delivery).IsRequired().HasConversion<int>()`.
- `dotnet ef migrations add AddHotstringDelivery` — additive int, `defaultValue: 0`.
- **Behavior change (intentional, per Decision #2):** every existing row defaults to `Auto=0`, so existing Text replacements ≥200 chars flip from typed to clipboard delivery on next script generation — including loss of auto-replace case-conforming. Keep `Auto` as the default (do not backfill to `Type`), but: (a) add a migration/emit regression test asserting a pre-existing 200+ char Text row resolves to clipboard, and (b) surface a one-time release note + UI hint that long existing hotstrings now paste. Alternative if the silent flip is unacceptable: backfill existing rows to `Type` and keep `Auto` only for newly created rows — revisit with product.

### P6 — History snapshots
- `HotstringSnapshot`: append `Delivery = Auto` (legacy JSON degrades to Auto). Recorder + Restore/Revert pass-through. Round-trip + legacy-JSON tests.

### P7 — OpenAPI
- `HotstringExamples.cs`: preview example gains `EffectiveDelivery = Type`; show `Delivery: Auto` on create example.

### P8 — Blazor UI
- Enum copy in `UI.Blazor\DTOs\`; mirror DTO changes.
- `HotstringEditModel.cs`: `Delivery` through FromDto/Clone/ToCreate/ToUpdate; replace `[MaxLength(4000)]` with conditional validation mirroring the **full server matrix**: Text+Type 4000; Text+Auto/Clipboard 100 000; Macro 4000; Raw 4200; DateTime empty. (Not "4000 when Text+Type, 100k otherwise" — that would wrongly allow Macro/Raw/DateTime up to 100k on the client.)
- **All three client length gates** must move off the hardcoded 4000, not just the model: `HotstringEditDialog.razor` `MaxLength="4000"` (line 62), the desktop inline editor's `MaxLength="4000"` input (Hotstrings.razor:105), and its separate `ValidateReplacement` commit guard (Hotstrings.razor:481). Drive all three from the same per-kind/delivery limit. bUnit tests: enter and save a 4001-char Text+Auto/Clipboard value through both the dialog and the inline editor.
- **List payload/render guard:** a 200-row page (`PageSize` max, ListHotstringsQuery.cs:52) of 100 000-char rows is ~20 MB, rendered in full (Hotstrings.razor:122). Truncate Text-replacement list rendering to a preview length; preferably ship a truncated replacement from `ListHotstringsQuery` (a summary/list DTO) and fetch full content only when editing.
- `HotstringEditDialog.razor`: delivery selector (Auto/Typed/Clipboard) for Text only, reset on kind switch; hint "Auto types short replacements and pastes 200+ characters via the clipboard. Pasted text is not case-conforming (typed replacements adapt to how you capitalized the trigger; pasted ones don't)."; preview carries Delivery; effective-delivery chip (`data-test="preview-delivery"`).
- Lists: minimal "Clipboard" chip for Text rows with explicit delivery. bUnit tests.

### P9 — CLI
- Enum copy + `Delivery` on DTOs in `IHotstringsApiClient.cs`. `NewHotstringCommand.cs`: `--delivery auto|type|clipboard` (case-insensitive; invalid → stderr + exit 2). Tests.
- **`--replacement-file <path>`:** `--replacement` is a process argument, capped well below the 100 000-char clipboard limit by the OS command-line length (~32 767 chars, ~8 191 under `cmd.exe`; [Microsoft docs](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/command-line-string-limitation)). Add `--replacement-file` reading UTF-8 file content as the replacement body; mutually exclusive with `--replacement` (both → stderr + exit 2), exactly one of the two required alongside `--trigger` (same rule as today). Tests: file path resolves content correctly; both/neither supplied → exit 2.

### P10 — Docs, E2E, verify
- `docs\cli\hotstrings.md`: `--delivery` + clipboard-delivery paragraph.
- Release/changelog note: existing Text hotstrings ≥200 chars now paste via clipboard after this migration (see P5).
- E2E: 250-char Text hotstring → downloaded script contains helper exactly once + `AhkFlow_PasteReplacement(`.
- `dotnet build`, full `dotnet test`, `dotnet format`, dck-verify.

## Verification
- TDD gates: P1 validator, P2/P3 golden tests red→green.
- Static: `AutoHotkey.exe /Validate` (or `/ErrorStdOut`) against the full generated script for a profile mixing short/typed and long/clipboard hotstrings — catches syntax errors the golden tests can't (this is static parse validation, not running the script; still within the project's no-runtime-execution rule).
- Manual acceptance checklist (real AHK v2 install, one pass before merge — no automated AHK execution, per project scope):
  1. **End-char behavior (was Q1):** trigger a 5-line X hotstring manually; confirm whether AHK consumes the ending char before the paste fires or whether it survives into the target app. Drop the `A_EndChar` arg from `AhkFlow_PasteReplacement` calls if it survives (finalize before P2 golden tests lock the signature).
  2. 199-char and 200-char Text replacements — confirm the boundary: 199 types, 200 pastes.
  3. `O` (OmitEndingCharacter) and `*` (no ending char) variants — confirm no stray ending-char paste.
  4. Ending character is preserved/consumed consistently with step 1's finding, across both variants.
  5. 100 000-char replacement — paste completes and target app receives full text.
  6. Clipboard is restored to its pre-paste contents after each paste.
- E2E download assertion; full suite green before PR.

## Out of scope
Menu-based multi-replacement output, SendPlay/SendEvent modes, import recognition of the helper call (re-import classifies as unsupported — follow-up), configurable Sleep/ClipWait, case-conforming for pasted text (documented in hint).

## Unresolved questions
1. **Resolved:** clipboard previews must be copy-safe. The "Generated AutoHotkey code" block is copyable, so a bare `:X:sig::AhkFlow_PasteReplacement(...)` line would reference an undefined helper. The preview handler prepends the `AhkFlow_PasteReplacement` helper block when effective delivery is clipboard (see P4), so a copied snippet is self-contained. Chip + hint stay; typed previews unchanged.
2. UI hint threshold (200) hardcoded vs served by API? (Plan: duplicated constant, like existing limits.)

(End-char behavior for X hotstrings — formerly Q1 — moved to the Verification section as acceptance-checklist item 1; it's a manual empirical check gating P2, not an open design question.)
