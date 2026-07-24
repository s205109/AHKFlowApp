# Plan: Fix broken hotkey samples & add Remap / Window / Disable examples

Design: [`docs/superpowers/specs/2026-07-24-hotkey-sample-examples-design.md`](../specs/2026-07-24-hotkey-sample-examples-design.md)

## Context

The W1 hotkey redesign (ADR-0004, plans `2026-07-22-hotkey-redesign-w1-*`) replaced the two-value
`HotkeyAction` with typed action kinds (`SendText`, `SendKeys`, `Run`, `Window`, `Remap`, `Disable`,
`Raw`). The seeded sample data in `DefaultHotkeyCatalog` was **not** migrated — it is still expressed
in the legacy `(Send | Run, Parameters)` shape and run through
`LegacyHotkeyDefinitionConverter.FromLegacy` at seed time. That legacy shape cannot express a function
call or a block body, so several samples emit broken AutoHotkey, and the new kinds (`Window`, `Remap`,
`Disable`) have no sample at all. Outcome: every seeded sample emits correct AHK v2, and one example
exists for each action kind a user can pick.

## Steps

### 1. Restructure `DefaultHotkeyCatalog` to carry typed definitions

`src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs`

- Change `DefaultHotkey` from `(Description, Ctrl, Alt, Shift, Win, Key, Action, Parameters,
  Categories)` to `record DefaultHotkey(HotkeyDefinition Definition, string[] Categories)`.
- Add a static `Legacy(...)` helper wrapping `LegacyHotkeyDefinitionConverter.FromLegacy(...,
  appliesToAllProfiles: true)` — used by every row that keeps its current emitted output (app
  launchers, lock, the 4 snap rows which stay `SendKeys`). Preserves migration parity with
  `LegacyHotkeyFixtures`.
- New / fixed-to-Raw / typed rows construct `HotkeyDefinition` directly (same ctor `FromLegacy`
  returns: `Description, Key, Ctrl, Alt, Shift, Win, ActionKind, AppliesToAllProfiles, Text,
  SendKeysContent, RunTarget, RunTargetKind, WindowOp, RemapDest, Body`).
- Update the class doc-comment: catalog is now mixed legacy + typed; only the legacy subset mirrors
  `LegacyHotkeyFixtures`.

### 2. Point both seed sites at `Definition`

- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs` — replace inline
  `FromLegacy(...)` with `Hotkey.Create(ownerOid, sample.Definition, clock)`; idempotency locals now
  read `sample.Definition.Key/Ctrl/Alt/Shift/Win`.
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` (lazy seed ~line 205) —
  same substitution.

### 3. Catalog contents (17 rows)

**Fixed → `Raw`:** Reload `^!r`→`Reload()` · date `^!d`→`SendText(FormatTime(A_Now, "yyyy-MM-dd"))` ·
paste `^+v`→ block `{ A_Clipboard := A_Clipboard ⏎ Send("^v") }`.

**Fixed → stays `SendKeys` (add `#`):** Maximize `#Up`→`#{Up}` · Minimize `#Down`→`#{Down}` ·
Snap-L `#Left`→`#{Left}` · Snap-R `#Right`→`#{Right}`.

**New:** Disable F1 Help `F1`→`return` · Mute `F10`→Remap `Volume_Mute` · Volume up `F9`→Remap
`Volume_Up` · Keep-on-top `^!a`→Window `WinSetAlwaysOnTop(-1, "A")` · Minimize active `^!m`→Window
`WinMinimize("A")`.

Categories: remaps + F1-disable + reload + lock → App Launcher; snaps + windows → Window Management;
date → DateTime; paste → Code. Bare F-key remap Descriptions note the global-hijack tradeoff. No
trigger collisions.

## Tests to update

- `tests/AHKFlowApp.Application.Tests/Dev/SeedHotkeysCommandHandlerTests.cs` — count 12→17, new typed
  columns.
- `tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysQueryHandlerTests.cs` — lazy-seed count/content.
- `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs` — golden script
  text includes corrected + new lines.
- `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs` — mirrors only the legacy subset;
  new typed rows excluded from parity.

## Verification

1. `dotnet build --configuration Release` (worktree).
2. `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release`.
3. Run API (`Docker SQL (No Auth)` worktree profile) + frontend; download the profile `.ahk` and
   assert the exact lines: `^!r::Reload()`, `^!d::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`,
   `^+v::{ … }`, `$#Up::Send("#{Up}")`, `F1::return`, `F10::Volume_Mute`, `F9::Volume_Up`,
   `^!a::WinSetAlwaysOnTop(-1, "A")`, `^!m::WinMinimize("A")`. Use the `playwright-cli` skill for the
   UI smoke pass.
4. Optional off-app AHK check: the generated script loads with no parse error; date / plain-paste /
   snap / mute bindings behave.
