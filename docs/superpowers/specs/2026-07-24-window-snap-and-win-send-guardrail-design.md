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

**Two enums, not one.** `WindowOp` is duplicated: the domain enum
(`AHKFlowApp.Domain/Enums/WindowOp.cs`) and its numeric wire-contract mirror in the frontend
(`AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs`). Both gain `SnapLeft = 5` / `SnapRight = 6` with
matching numeric values — the dropdown enumerates the *frontend* type via `Enum.GetValues`, so a
domain-only change would leave 5/6 absent from the UI and the new label cases would not compile.

The emitter's `WindowCall` returns a block body for them:

```ahk
{
    WinRestore("A")
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    WinMove(l, t, (r - l) // 2, b - t, "A")          ; SnapLeft
}
```

SnapRight differs only in the `WinMove` X/Width. Its X is the left window's right edge, and its
width spans from there to `r` so an odd work-area width leaves no uncovered strip:
`WinMove(l + (r - l) // 2, t, r - (l + (r - l) // 2), b - t, "A")`.

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
| SnapRight | `{ WinRestore("A") … WinMove(l+(r-l)//2, t, r-(l+(r-l)//2), b-t, "A") }` |

## 2. Catalog: snap samples become `Window` kind

The two snap samples (currently `Raw` bodies from the sibling spec) become
`Typed(… WindowOp.SnapLeft / SnapRight)` on Ctrl+Alt+Left / Ctrl+Alt+Right. The Raw
`SnapLeftBody` / `SnapRightBody` string constants are removed — the WinMove AHK now lives
once, in the emitter. Emitted output is byte-identical, so the golden integration-test
assertions do not change. The snap conversion is in-place, so it alone keeps the count at 17;
§5 then adds two SendKeys rows, taking the catalog to **19**.

## 3. Labels

`HotkeyActionDisplay.WindowOpLabel` gains **"Snap left"** and **"Snap right"** — these `case`
arms reference the frontend `WindowOp.SnapLeft` / `SnapRight` members added in §1, so that enum
change lands first. The Window-op dropdown (`HotkeyEditDialog`) and the read-only action chips
are enum-driven, so they pick up the new entries with no further change.

## 4. SendKeys warning (non-blocking)

In the SendKeys panel of `HotkeyEditDialog`, when the Win modifier checkbox (`_sendWin`) is
checked **and an arrow key is the sent key**, render a `MudAlert` (`Severity.Warning`,
`Dense`), mirroring the existing Raw-panel warning:

> ⚠ Sending Win + Arrow won't snap the window — Windows ignores injected Win for Aero Snap.
> To snap the active window, use a **Window** action (Snap left / Snap right). For other Win
> shortcuts, use **Raw**.

- **Non-blocking**: Save is unaffected; the token still validates and persists.
- **Trigger**: Win + arrow only — that is the sole gesture documented to fail (Aero Snap;
  companion spec §2b). Injected Win *does* fire some OS shortcuts (`Send "#e"` = Win+E per the
  AHK v2 Send docs), so a blanket "all Win+key" warning would be wrong.
- The message string and its `data-test` id are constants beside `RawWarningText` in
  `HotkeyActionDisplay`, so markup and tests share one source.

## 5. SendKeys samples

The catalog demonstrates every action kind **except `SendKeys`**: the sibling spec left
`SendText` unrepresented on purpose and moved the old snap rows off `SendKeys` onto Window/Raw
(§2b there), so no seeded sample now shows the `SendKeys` kind at all. That is also the kind the
§4 warning teaches about — with no working sample, the only `SendKeys` a new owner meets is the
broken Win+Arrow one. Add two working, **no-Win** samples so the kind has a positive example.

Both go through the existing `Legacy(… HotkeyAction.Send, "<token>")` helper: a valid SendKeys
token converts to `HotkeyActionKind.SendKeys` and emits `$key::Send("<token>")` (per
`LegacyHotkeyDefinitionConverter`). No new helper, no new category.

| Description | Hotkey | Token | Emits | Category |
|---|---|---|---|---|
| Play / pause media | Ctrl+Alt+P | `{Media_Play_Pause}` | `$^!p::Send("{Media_Play_Pause}")` | App Launcher |
| Select current line | Ctrl+Alt+K | `{Home}+{End}` | `$^!k::Send("{Home}+{End}")` | Code |

- These pick a virtual media key and a modified key sequence — the two things `SendKeys` does
  that `SendText`/`Run` cannot — so one working sample earns its place.
- Keys `P` / `K` are free of existing Ctrl+Alt bindings (`T N E B L r d a m` + arrows are taken).
- Like the other new rows, both are **excluded** from the `LegacyHotkeyFixtures` migration-parity
  mirror (they never existed as real legacy data); they stay pinned `AppliesToAllProfiles = true`.

## Testing

- **Emitter** (`HotkeyEmitterTests`): a case per snap op asserting the exact WinMove block.
- **Catalog SendKeys** (`AhkScriptGeneratorIntegrationTests`): the two new rows emit
  `$^!p::Send("{Media_Play_Pause}")` / `$^!k::Send("{Home}+{End}")` and report `SendKeys` kind.
- **Validator** (`HotkeyKindConditionalRulesTests`): `Window` accepts `SnapLeft` / `SnapRight`
  (guards `Enum.IsDefined`).
- **UI** (`HotkeyEditDialog` bUnit): the warning renders when the Send Win checkbox is checked
  **and an arrow key is chosen**, is absent for Win + a non-arrow key and for arrow-without-Win,
  and Save is not blocked while it shows. The op dropdown lists the two new frontend `WindowOp`
  values.
- **Catalog** (`AhkScriptGeneratorIntegrationTests`): existing snap-line assertions stand
  (same emit); the two samples now report `Window` kind.
- **Seed counts**: the two SendKeys rows move the catalog 17 → **19**. Update every count
  assertion the sibling spec inventoried — `SeedHotkeysCommandHandlerTests`,
  `ListHotkeysLazySeedTests`, `SeedAllCommandHandlerTests`, `DevSeedEndpointTests`,
  `HotkeysEndpointsTests` pagination (`5 created + 19` = **24**), and any "seeds N samples" prose.
- **Display** (`HotkeyActionDisplayTests`): labels for the two new ops.

## Files touched

- `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs` — two enum values (`SnapLeft=5`, `SnapRight=6`).
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs` — same two values in the frontend mirror
  (the dropdown enumerates this type).
- `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs` — `WindowCall` snap cases.
- `src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs` — snap rows → Window;
  drop the two Raw body consts; add two `Legacy(… Send …)` SendKeys rows (§5).
- `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs` — snap labels + warning
  constant.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor` — SendKeys
  warning alert.
- `docs/development/ahk-v2-syntax.md` — extend the `Window` emit row with the two block-bodied
  snap ops and their primary-monitor `MonitorGetWorkArea` behavior.
- Tests as listed above.

## Open questions

None.
