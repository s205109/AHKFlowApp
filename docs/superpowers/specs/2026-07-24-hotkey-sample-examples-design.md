# Fix broken hotkey samples & add Remap / Window / Disable examples

## Context

The W1 hotkey redesign (plans `2026-07-22-hotkey-redesign-w1-*`) replaced the two-value
`HotkeyAction` with typed action kinds — `SendText`, `SendKeys`, `Run`, `Window`, `Remap`,
`Disable`, `Raw` (ADR-0004). The seeded sample data in
`DefaultHotkeyCatalog` was **not** migrated: it is still expressed in the legacy `(Send | Run,
Parameters)` shape and run through `LegacyHotkeyDefinitionConverter.FromLegacy` at seed time.

Two consequences:

1. Three seeded samples are not actually Send-or-Run actions, so the converter mangles them into
   broken AutoHotkey.
2. Three of the new kinds — typed `Window`, `Remap`, `Disable` — have no sample at all, so a fresh
   development owner never sees them.

Both seed paths are **Development-only**; nothing here touches production onboarding.

## Problems (root cause)

The reported three fail for the same reason: the legacy catalog shape cannot express a function call
or a block body, so each is forced through `Send`/`Run` and emits wrong AHK. A fourth failure — the
native window-resize/snap samples — surfaced during planning: driving Aero Snap through `Send` never
snaps reliably (injected Win; §2b).

| Sample | Emits today | Why broken |
|---|---|---|
| Reload AHK script | `Run("Reload")` | `Run` tries to **launch a file** named `Reload` → "The system cannot find the file specified" (the reported error). `Reload` is a built-in function, not a program. |
| Insert today's date | `Send("{{date:yyyy-MM-dd}}")` | `{{date:…}}` is an AHKFlow **hotstring macro token**, never expanded for hotkeys. `Send` reads `{…}` as key names → invalid → nothing fires. |
| Paste as plain text | `$^+V::Send("^v")` | Sends Ctrl+V = a normal paste; formatting is preserved. No clipboard stripping happens. |
| Maximize / Minimize / Snap L / Snap R | `$!#Up::Send("{Up}")`, … | Bare arrow (no `#`) sends a plain `{Up}` — nothing happens. Adding `#` back doesn't fix it either: injected `LWin` (SendInput's `LLKHF_INJECTED` atomic batch) isn't reliably recognized by the shell's Aero-Snap / Win-hotkey handler, so `Send("#{Up}")` still fails to snap. Real fix: abandon `Send`, use native window functions (§2b). |

## Goals / Non-goals

**Goals**

- Fix the three reported broken samples so they emit correct AHK v2.
- Fix the four window resize/snap samples (native window functions on Ctrl+Alt+Arrow, not `Send`).
- Add one sample for each still-unshown kind: `Remap` (×2), `Window` (×2), `Disable` (×1).
- Restructure `DefaultHotkeyCatalog` so it can carry typed definitions, not only the legacy pair.

**Non-goals**

- No new categories (adding to `DefaultCategories` is out of scope; new samples reuse existing ones).
- No `SendText`-only sample. `SendText` stays unrepresented on purpose (the date sample uses
  `SendText(...)` inside a `Raw` body, which is enough to show the pattern) — so this change does **not**
  claim a sample for literally every action kind, only for the three previously-unshown typed kinds.
- No runtime execution of `.ahk` (permanently out of scope).
- **No backfill of existing seeded rows.** Both seed paths are Development-only; the fix lands on
  fresh owners and on `POST /dev/seed?reset=true`. A dev owner already carrying the old broken rows
  keeps them until they reset — acceptable for throwaway dev data (see Decision 6).

## Design

### 1. Catalog carries typed definitions

`DefaultHotkeyCatalog.All` becomes a list of pre-built `HotkeyDefinition` values (plus each row's
categories), instead of the legacy `(HotkeyAction, string Parameters)` pair.

- **Legacy-shaped rows** (app launchers, lock) keep a small `Legacy(...)` helper that
  wraps `LegacyHotkeyDefinitionConverter.FromLegacy`. Their emitted output is unchanged, which
  preserves the migration-parity mirror in `LegacyHotkeyFixtures`.
- **Native-snap rows** keep the `Legacy(...)` helper (they stay `SendKeys`), but their *input* changes
  — `Alt` dropped, `#` added to the payload (§2b) — so their emitted output changes. They are therefore
  **excluded** from the migration-parity mirror.
- **New / fixed rows** construct the typed `HotkeyDefinition` directly (`Raw`, `Window`, `Remap`,
  `Disable`).
- Both seed sites — `SeedHotkeysCommandHandler` and the `ListHotkeysQuery` lazy seed — call
  `Hotkey.Create(ownerOid, definition, clock)` per row. No per-kind branching at the seed site.

The seed path bypasses validation (documented in `ahk-v2-syntax.md` and ADR-0004: the dev lazy seed
and snapshot restore are the two unvalidated paths). The curated typed definitions must therefore be
**correct by construction** — that is exactly what this spec pins.

### 2. Corrected samples (become `Raw`)

Emission forms verified against `docs/development/ahk-v2-syntax.md`.

| Description | Kind | Hotkey | Stored `Body` | Emits |
|---|---|---|---|---|
| Reload AHK script | Raw | Ctrl+Alt+R | `Reload()` | `^!r::Reload()` |
| Insert today's date | Raw | Ctrl+Alt+D | `SendText(FormatTime(A_Now, "yyyy-MM-dd"))` | `^!d::SendText(FormatTime(A_Now, "yyyy-MM-dd"))` |
| Paste as plain text | Raw | Ctrl+Shift+V | block below | OTB block after `::` |

Paste-as-plain-text body — mirrors the app's clipboard helper (`ahk-v2-syntax.md`
"Clipboard delivery"): save the rich clipboard, strip to text, paste, restore. `A_Clipboard :=
A_Clipboard` alone would leave the clipboard **permanently** converted to plain text, so the save /
restore is mandatory, not optional:

```ahk
{
    saved := ClipboardAll()      ; preserve the original rich clipboard
    A_Clipboard := A_Clipboard   ; reading returns text-only, stripping formatting
    Send("^v")
    Sleep(150)                   ; let the paste consume the clipboard first
    A_Clipboard := saved         ; restore the original formatting
    saved := ""
}
```

Reading `A_Clipboard` returns plain text; assigning it back sets the clipboard to that plain text
(synchronous), so the `Send("^v")` pastes unformatted, then `A_Clipboard := saved` puts the rich
content back. The date form mirrors the existing DateTime **hotstring** emission
(`SendText(FormatTime(A_Now, "yyyy-MM-dd"))`), keeping one pattern across the app. Brace balance holds
(one `{`, one `}`); Raw shape validation would pass even though the seed skips it.

These three stay their existing categories (Reload → App Launcher, date → DateTime, paste → Code).

### 2b. Window resize/snap samples (native functions, not `Send`)

**Why not `Send("#{Left}")`.** `#` is `LWin`; `Send` injects `{LWin down}{Left}{LWin up}` via
SendInput. Injected input carries the `LLKHF_INJECTED` flag and arrives as one atomic batch, which the
shell's Aero-Snap / Win-hotkey handler does not reliably recognize as a genuine Win+Arrow gesture — so
the window fails to snap (confirmed in use; community consensus is to position with `WinMove`, not to
drive Aero Snap through `Send`). Changing the trigger does not help: the broken part is the **sent**
Win, not the trigger. So these four drop `SendKeys` entirely and use deterministic native calls on a
**Ctrl+Alt+Arrow** trigger (no Win anywhere).

Max/Min are the typed `Window` kind. Snap L/R need a half-work-area move that no `WindowOp` expresses,
so they are `Raw` block bodies: `WinRestore("A")` (so a maximized window can move) →
`MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)` → `WinMove` to the left/right half. Primary
monitor keeps the sample readable; a real multi-monitor snap would resolve the window's own monitor.

| Description | Kind | Hotkey | Emits |
|---|---|---|---|
| Maximize window | Window | Ctrl+Alt+Up | `^!Up::WinMaximize("A")` |
| Minimize window | Window | Ctrl+Alt+Down | `^!Down::WinMinimize("A")` |
| Snap window left | Raw | Ctrl+Alt+Left | `^!Left::{ WinRestore… WinMove(l, t, (r-l)//2, b-t, "A") }` |
| Snap window right | Raw | Ctrl+Alt+Right | `^!Right::{ WinRestore… WinMove(l+(r-l)//2, t, (r-l)//2, b-t, "A") }` |

### 3. New samples

| Description | Kind | Hotkey | Stored | Emits | Category |
|---|---|---|---|---|---|
| Disable F1 Help (removes the Help key everywhere) | Disable | F1 | — | `F1::return` | App Launcher |
| Mute volume (also steals F10, the menu-bar key) | Remap | F10 | `RemapDest = Volume_Mute` | `F10::Volume_Mute` | App Launcher |
| Volume up (F9 no longer types normally) | Remap | F9 | `RemapDest = Volume_Up` | `F9::Volume_Up` | App Launcher |
| Keep window on top | Window | Ctrl+Alt+A | `WindowOp = ToggleAlwaysOnTop` | `^!a::WinSetAlwaysOnTop(-1, "A")` | Window Management |
| Restore active window | Window | Ctrl+Alt+M | `WindowOp = Restore` | `^!m::WinRestore("A")` | Window Management |

### 3. New samples

| Description | Kind | Hotkey | Stored | Emits | Category |
|---|---|---|---|---|---|
| Disable F1 Help (removes the Help key everywhere) | Disable | F1 | — | `F1::return` | App Launcher |
| Mute volume (also steals F10, the menu-bar key) | Remap | F10 | `RemapDest = Volume_Mute` | `F10::Volume_Mute` | App Launcher |
| Volume up (F9 no longer types normally) | Remap | F9 | `RemapDest = Volume_Up` | `F9::Volume_Up` | App Launcher |
| Keep window on top | Window | Ctrl+Alt+A | `WindowOp = ToggleAlwaysOnTop` | `^!a::WinSetAlwaysOnTop(-1, "A")` | Window Management |
| Minimize active window | Window | Ctrl+Alt+M | `WindowOp = Minimize` | `^!m::WinMinimize("A")` | Window Management |

Registry checks: `F1`/`F9`/`F10` are valid function keys; `Volume_Mute`/`Volume_Up` carry the
`RemapDest` role; `Disable` and `Window` take their fields from an enum. `Remap` emits a bare
destination with no literal — nothing to escape.

**Activation policy.** Every seeded sample — including these risky ones — is pinned
`AppliesToAllProfiles = true`, matching the existing seed and the `Legacy(...)` helper. They are
therefore live in every generated `.ahk` the moment the owner downloads one; the "user curates before
running" story means the owner **deletes or edits** the global-hijack samples first, not that they
start unassigned. The hijack is disclosed in each `Description` (above) so it is visible in the list,
not only in this spec. Note `Volume_Mute` is a *toggle*: a remap holds and auto-repeats its
destination, so holding F10 flaps mute on/off — acceptable for a teaching sample tapped once, and
`Volume_Up` (repeat-friendly) is the better-behaved half of the pair.

## Tests / docs to update

Full inventory — every surface that asserts a seed count or the sample set:

- `SeedHotkeysCommandHandlerTests` — seed count (12 → 17) and the new rows' typed columns.
- `ListHotkeysLazySeedTests` — lazy-seed count/content (the lazy-seed assertions live here, **not** in
  `ListHotkeysQueryHandlerTests`).
- `SeedAllCommandHandlerTests` (`Application.Tests/Dev`) — asserts the combined seed; hotkey count moves.
- `DevSeedEndpointTests` (`API.Tests/Dev`) — endpoint-level seed count.
- `HotkeysEndpointsTests` pagination — `TotalCount` assertion `5 created + 12` → `5 created + 17` = **22**.
- `AhkScriptGeneratorIntegrationTests` — this test manually inserts **two unrelated** hotkeys, so it
  cannot take a simple golden-text swap; add a dedicated case (or a new golden) that seeds from
  `DefaultHotkeyCatalog` and asserts the corrected + new lines, rather than editing its existing golden.
- `DevController` XML doc comments + README seed counts — any "seeds N sample hotkeys" prose.

Migration-parity fixtures (`LegacyHotkeyFixtures`):

- The new typed rows never existed as legacy data, so they are **excluded** from the parity fixture.
- The historical converter/migration cases — `run-not-a-path` (`"Reload"`), `send-ctrl-v` (`"^v"`),
  `send-macro-leak` (the `{{date:…}}` token) — **stay**. Real databases and snapshots still contain
  those legacy inputs, so they guard the transform regardless of whether the catalog still emits them.
  Only the fixture's doc-comment claim that it is "seeded from the dev lazy-seed rows" needs updating:
  the catalog no longer feeds those three rows, but the fixture keeps them as historical cases.

- `DefaultHotkeyCatalog` doc-comment — update to describe the mixed legacy + typed shape.

## Risks

- **Bare F-key remaps hijack globally.** `F10` also activates the menu bar in many apps; `F1::return`
  removes the Help key everywhere. Intended: these are teaching samples the user curates before
  running their own script (nothing runs automatically).
- **Seed skips validation** — mitigated by pinning every typed definition here and by the golden
  integration test.
- **Migration parity** — kept intact by leaving unchanged legacy rows on the `Legacy(...)` helper;
  the new typed rows **and** the edited native-snap rows are excluded from the parity fixture, which
  retains its historical converter cases (see Tests / docs).

## Decisions (resolved with the user)

1. **F-key remaps stay bare** (`F9`/`F10`, not `^F9`/`^F10`) — real media-key UX is a bare tap; the
   global-hijack tradeoff (F10 menu bar) is spelled out in each Description.
2. **Second remap is `F9::Volume_Up`** — pairs with F10 mute as one volume cluster.
3. **Categories:** the media remaps + F1-disable go to **App Launcher**, following the seed's existing
   precedent (Lock workstation and Reload already live there as non-launcher system utilities).
4. **Window resize/snap samples are in scope** — dropped `Send` for native window functions on
   Ctrl+Alt+Arrow; injected Win never reliably snaps (§2b). The old §3 Ctrl+Alt+M minimize became
   `Restore` since Ctrl+Alt+Down now minimizes.
5. **Catalog shape:** one unified typed list; `Legacy(...)` helper for legacy/SendKeys rows.
6. **Existing rows: reset-only, no backfill.** Dev-only data; owners refresh via `reset=true`. No
   exact-old-sample backfill query is added (keeps the change minimal; avoids touching real-looking
   custom rows).
7. **Risky samples stay all-profiles + disclosed**, not opt-in/unassigned (§3 Activation policy). Keeps
   the golden `.ahk` verification (plan step 3) meaningful — an unassigned sample would emit nothing.
