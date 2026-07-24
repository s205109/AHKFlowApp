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
exists for each previously-unshown typed kind (`Window`, `Remap`, `Disable`). `SendText` stays
represented only inside the date `Raw` body — no standalone `SendText` sample (design Non-goals).
Both seed paths are Development-only; the fix reaches fresh owners and `reset=true`, not existing
seeded rows.

## Steps

### 1. Restructure `DefaultHotkeyCatalog` to carry typed definitions

`src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs`

- Change `DefaultHotkey` from `(Description, Ctrl, Alt, Shift, Win, Key, Action, Parameters,
  Categories)` to `record DefaultHotkey(HotkeyDefinition Definition, string[] Categories)`.
- Add a static `Legacy(...)` helper wrapping `LegacyHotkeyDefinitionConverter.FromLegacy(...,
  appliesToAllProfiles: true)` — used by app launchers, lock (unchanged output, mirror parity) and by
  the 4 snap rows (stay `SendKeys` but their input changes: `Alt` off + `#` added, so output changes →
  excluded from the parity mirror).
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
paste `^+v`→ save/strip/paste/restore block (design §2, mirrors the app clipboard helper — a bare
`A_Clipboard := A_Clipboard` would permanently strip the clipboard).

**Fixed → stays `SendKeys` (add `#`, keep `Alt`+`Win`):** the live rows are `!#Up` etc.; sole fault
(missing `#`) fixed, trigger kept distinct from target → Maximize `!#Up`→`#{Up}` · Minimize
`!#Down`→`#{Down}` · Snap-L `!#Left`→`#{Left}` · Snap-R `!#Right`→`#{Right}`.

**New:** Disable F1 Help `F1`→`return` · Mute `F10`→Remap `Volume_Mute` · Volume up `F9`→Remap
`Volume_Up` · Keep-on-top `^!a`→Window `WinSetAlwaysOnTop(-1, "A")` · Minimize active `^!m`→Window
`WinMinimize("A")`. All pinned `AppliesToAllProfiles = true`; the F1/F9/F10 Descriptions carry the
global-hijack disclosure (design §3).

Categories: remaps + F1-disable + reload + lock → App Launcher; snaps + windows → Window Management;
date → DateTime; paste → Code. No hotkey collisions.

## Tests / docs to update

- `tests/AHKFlowApp.Application.Tests/Dev/SeedHotkeysCommandHandlerTests.cs` — count 12→17, new typed
  columns.
- `tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysLazySeedTests.cs` — lazy-seed count/content
  (lazy-seed assertions live here, not in `ListHotkeysQueryHandlerTests`).
- `tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs` — combined-seed hotkey count.
- `tests/AHKFlowApp.API.Tests/Dev/DevSeedEndpointTests.cs` — endpoint-level seed count.
- `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeysEndpointsTests.cs` — pagination `TotalCount` 17→**22**
  (`5 created + 17 lazy-seeded`).
- `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs` — inserts two
  **unrelated** hotkeys, so no plain golden swap; add a dedicated catalog-seeded case asserting the
  corrected + new lines.
- `DevController` XML docs + README — any "seeds N sample hotkeys" prose.
- `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs` — new typed rows + edited snap rows
  excluded from parity; the historical `Reload`/`^v`/date-token cases **stay** (guard the transform for
  real legacy data); update only the stale "seeded from lazy-seed rows" doc-comment.

## Verification

1. `dotnet build --configuration Release` (worktree).
2. `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release`.
3. Run API (`Docker SQL (No Auth)` worktree profile) + frontend; download the profile `.ahk` and
   assert the exact lines: `^!r::Reload()`, `^!d::SendText(FormatTime(A_Now, "yyyy-MM-dd"))`,
   `^+v::{ … }`, `$!#Up::Send("#{Up}")`, `F1::return`, `F10::Volume_Mute`, `F9::Volume_Up`,
   `^!a::WinSetAlwaysOnTop(-1, "A")`, `^!m::WinMinimize("A")`. Use the `playwright-cli` skill for the
   UI smoke pass.
4. Optional off-app AHK check: the generated script loads with no parse error; date / plain-paste /
   snap / mute bindings behave.
