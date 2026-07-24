# Window snap operations + Win-in-Send guardrail — design

**Date:** 2026-07-24
**Status:** approved (brainstorm)

## Problem

A user who wants to snap a window to the left/right half of the screen has no first-class
way to do it. The `Window` action kind exposes only Minimize / Maximize / Restore / Close /
ToggleAlwaysOnTop, so the natural attempt is a **SendKeys** hotkey that sends `#{Left}`
(Win+Left) to invoke Aero Snap. That is accepted by validation — `IsValidSendKeysContent`
treats `#` as a normal modifier — but it never reliably snaps: injected `LWin` (SendInput's
`LLKHF_INJECTED` atomic batch) is not recognised by the shell's Aero-Snap / Win-hotkey
handler (see the sibling `2026-07-24-hotkey-sample-examples-design.md` §2b). The window does
nothing and the user has no idea why.

Two gaps compound: there is **no working non-Raw route** to snap, and **nothing warns**
the user that the Send route is a dead end. This design closes both.

## Goals

- Add `SnapLeft` / `SnapRight` as `Window` operations so snapping is a first-class, working
  dropdown choice — no Raw body required.
- Warn (non-blocking) in the SendKeys editor when the Win modifier is used, steering the user
  to the Window action.

## Non-goals

- **Blocking** `#` in SendKeys content. Chosen non-blocking: a hard reject would forbid the
  rare legitimate Win+key send and is a stricter behaviour change than warranted.
- **Trigger-side Win.** Using Win as an *activating* modifier (e.g. Win+Left as the hotkey
  trigger) is a valid, common hotkey and is left unwarned.
- **CLI warning.** The UI is the authoring surface. A shared advisory the CLI can print is a
  clean follow-up, not part of this change.
- **Multi-monitor-aware snap.** v1 snaps against the primary monitor's work area; resolving
  the window's own monitor is a later refinement.

## 1. Snap operations (`WindowOp.SnapLeft` / `SnapRight`)

`WindowOp` gains two values. The emitter's `WindowCall` returns a block body for them:

```ahk
{
    WinRestore("A")
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    WinMove(l, t, (r - l) // 2, b - t, "A")          ; SnapLeft
}
```

SnapRight differs only in the `WinMove` X/Width:
`WinMove(l + (r - l) // 2, t, (r - l) // 2, b - t, "A")`.

`WinRestore("A")` first so a maximized window can be moved. `//` is AHK integer division.
`MonitorGetPrimary()` keeps the emit readable; a real multi-monitor snap would resolve the
window's own monitor first (non-goal).

**No DB migration.** `WindowOp` persists as `int`. New enum values add no schema change,
leave existing rows untouched, and validation's `Enum.IsDefined(op)` accepts them
automatically. The `WindowCall` switch gains two cases (its `default` still throws for an
undefined value the validator would already have rejected).

| WindowOp | Emits (rhs after `key::`) |
|---|---|
| SnapLeft | `{ WinRestore("A") … WinMove(l, t, (r-l)//2, b-t, "A") }` |
| SnapRight | `{ WinRestore("A") … WinMove(l+(r-l)//2, t, (r-l)//2, b-t, "A") }` |

## 2. Catalog: snap samples become `Window` kind

The two snap samples (currently `Raw` bodies from the sibling spec) become
`Typed(… WindowOp.SnapLeft / SnapRight)` on Ctrl+Alt+Left / Ctrl+Alt+Right. The Raw
`SnapLeftBody` / `SnapRightBody` string constants are removed — the WinMove AHK now lives
once, in the emitter. Emitted output is byte-identical, so the golden integration-test
assertions do not change. Sample count stays 17.

## 3. Labels

`HotkeyActionDisplay.WindowOpLabel` gains **"Snap left"** and **"Snap right"**. The Window-op
dropdown (`HotkeyEditDialog`) and the read-only action chips are enum-driven, so they pick up
the new entries with no further change.

## 4. SendKeys warning (non-blocking)

In the SendKeys panel of `HotkeyEditDialog`, when the Win modifier checkbox (`_sendWin`) is
checked, render a `MudAlert` (`Severity.Warning`, `Dense`), mirroring the existing Raw-panel
warning:

> ⚠ Sending Win + a key rarely triggers Windows shortcuts like Aero Snap or Win+D — Windows
> ignores injected Win. To snap or resize the window, use a **Window** action. For anything
> else, use **Raw**.

- **Non-blocking**: Save is unaffected; the token still validates and persists.
- **Trigger**: any Win+key, not only arrows — injected Win is unreliable for every OS gesture.
- The message string and its `data-test` id are constants beside `RawWarningText` in
  `HotkeyActionDisplay`, so markup and tests share one source.

## Testing

- **Emitter** (`HotkeyEmitterTests`): a case per snap op asserting the exact WinMove block.
- **Validator** (`HotkeyKindConditionalRulesTests`): `Window` accepts `SnapLeft` / `SnapRight`
  (guards `Enum.IsDefined`).
- **UI** (`HotkeyEditDialog` bUnit): the warning renders when the Send Win checkbox is checked
  and is absent otherwise; Save is not blocked while it shows.
- **Catalog** (`AhkScriptGeneratorIntegrationTests`): existing snap-line assertions stand
  (same emit); the two samples now report `Window` kind.
- **Display** (`HotkeyActionDisplayTests`): labels for the two new ops.

## Files touched

- `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs` — two enum values.
- `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs` — `WindowCall` snap cases.
- `src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs` — snap rows → Window;
  drop the two Raw body consts.
- `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs` — snap labels + warning
  constant.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor` — SendKeys
  warning alert.
- Tests as listed above.

## Open questions

None.
