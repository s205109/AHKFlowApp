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
2. Three of the new kinds — typed `Window`, `Remap`, `Disable` — have no sample at all, so a new
   user never sees them.

## Problems (root cause)

The reported three fail for the same reason: the legacy catalog shape cannot express a function call
or a block body, so each is forced through `Send`/`Run` and emits wrong AHK. A fourth failure — the
native-snap samples — surfaced during planning and shares the root class (wrong `Send` content).

| Sample | Emits today | Why broken |
|---|---|---|
| Reload AHK script | `Run("Reload")` | `Run` tries to **launch a file** named `Reload` → "The system cannot find the file specified" (the reported error). `Reload` is a built-in function, not a program. |
| Insert today's date | `Send("{{date:yyyy-MM-dd}}")` | `{{date:…}}` is an AHKFlow **hotstring macro token**, never expanded for hotkeys. `Send` reads `{…}` as key names → invalid → nothing fires. |
| Paste as plain text | `$^+V::Send("^v")` | Sends Ctrl+V = a normal paste; formatting is preserved. No clipboard stripping happens. |
| Maximize / Minimize / Snap L / Snap R | `$#Up::Send("{Up}")`, … | Bare arrow, **no `#`**. AHK auto-releases a hotkey's own Win modifier before `Send`, so a plain arrow is sent and nothing snaps or maximizes. |

## Goals / Non-goals

**Goals**

- Fix the three reported broken samples so they emit correct AHK v2.
- Fix the four native-snap samples (add the missing `#` to their `Send` content).
- Add one sample for each still-unshown kind: `Remap` (×2), `Window` (×2), `Disable` (×1).
- Restructure `DefaultHotkeyCatalog` so it can carry typed definitions, not only the legacy pair.

**Non-goals**

- No new categories (adding to `DefaultCategories` is out of scope; new samples reuse existing ones).
- No `SendText`-only sample, no runtime execution of `.ahk` (permanently out of scope).

## Design

### 1. Catalog carries typed definitions

`DefaultHotkeyCatalog.All` becomes a list of pre-built `HotkeyDefinition` values (plus each row's
categories), instead of the legacy `(HotkeyAction, string Parameters)` pair.

- **Legacy-shaped rows** (app launchers, native snaps, lock) keep a small `Legacy(...)` helper that
  wraps `LegacyHotkeyDefinitionConverter.FromLegacy`. Their emitted output is unchanged, which
  preserves the migration-parity mirror in `LegacyHotkeyFixtures`.
- **New / fixed rows** construct the typed `HotkeyDefinition` directly (`Raw`, `Window`, `Remap`,
  `Disable`).
- Both seed sites — `SeedHotkeysCommandHandler` and the `ListHotkeysQuery` lazy seed — call
  `Hotkey.Create(ownerOid, definition, clock)` per row. No per-kind branching at the seed site.

The seed path bypasses validation (documented in `ahk-v2-syntax.md` and ADR-0004: the dev lazy seed
and snapshot restore are the two unvalidated paths). The curated typed definitions must therefore be
**correct by construction** — that is exactly what this spec pins.

### 2. Corrected samples (become `Raw`)

Emission forms verified against `docs/development/ahk-v2-syntax.md`.

| Description | Kind | Trigger | Stored `Body` | Emits |
|---|---|---|---|---|
| Reload AHK script | Raw | Ctrl+Alt+R | `Reload()` | `^!r::Reload()` |
| Insert today's date | Raw | Ctrl+Alt+D | `SendText(FormatTime(A_Now, "yyyy-MM-dd"))` | `^!d::SendText(FormatTime(A_Now, "yyyy-MM-dd"))` |
| Paste as plain text | Raw | Ctrl+Shift+V | block below | OTB block after `::` |

Paste-as-plain-text body (minimal, user-chosen):

```ahk
{
    A_Clipboard := A_Clipboard   ; reading returns text-only, stripping formatting
    Send("^v")
}
```

Reading `A_Clipboard` returns plain text; assigning it back sets the clipboard to that plain text
(synchronous), so the subsequent `Send("^v")` pastes unformatted. The date form mirrors the existing
DateTime **hotstring** emission (`SendText(FormatTime(A_Now, "yyyy-MM-dd"))`), keeping one pattern
across the app. Brace balance holds (one `{`, one `}`); Raw shape validation would pass even though
the seed skips it.

These three stay their existing categories (Reload → App Launcher, date → DateTime, paste → Code).

### 2b. Corrected native-snap samples (stay `SendKeys`)

The four snap rows keep their kind and the `Legacy(...)` helper — only the `Send` content gains the
missing `#`. `#{Up}` is a valid SendKeys token (`#` modifier + `{Up}`), so this is a one-token edit
per row. The `$` prefix already blocks the sent `#{Up}` from re-triggering the hotkey, so Windows
receives the real Win+Arrow and snaps.

| Description | Trigger | `Parameters` before → after | Emits |
|---|---|---|---|
| Maximize window | `#Up` | `{Up}` → `#{Up}` | `$#Up::Send("#{Up}")` |
| Minimize window | `#Down` | `{Down}` → `#{Down}` | `$#Down::Send("#{Down}")` |
| Snap window left | `#Left` | `{Left}` → `#{Left}` | `$#Left::Send("#{Left}")` |
| Snap window right | `#Right` | `{Right}` → `#{Right}` | `$#Right::Send("#{Right}")` |

### 3. New samples

| Description | Kind | Trigger | Stored | Emits | Category |
|---|---|---|---|---|---|
| Disable F1 Help | Disable | F1 | — | `F1::return` | App Launcher |
| Mute volume | Remap | F10 | `RemapDest = Volume_Mute` | `F10::Volume_Mute` | App Launcher |
| Volume up | Remap | F9 | `RemapDest = Volume_Up` | `F9::Volume_Up` | App Launcher |
| Keep window on top | Window | Ctrl+Alt+A | `WindowOp = ToggleAlwaysOnTop` | `^!a::WinSetAlwaysOnTop(-1, "A")` | Window Management |
| Minimize active window | Window | Ctrl+Alt+M | `WindowOp = Minimize` | `^!m::WinMinimize("A")` | Window Management |

Registry checks: `F1`/`F9`/`F10` are valid function keys; `Volume_Mute`/`Volume_Up` carry the
`RemapDest` role; `Disable` and `Window` take their fields from an enum. `Remap` emits a bare
destination with no literal — nothing to escape.

## Tests to update

- `SeedHotkeysCommandHandlerTests` — seed count (12 → 17) and the new rows' typed columns.
- `ListHotkeysQueryHandlerTests` — lazy-seed count/content.
- `AhkScriptGeneratorIntegrationTests` — golden generated-script text now includes the corrected +
  new lines.
- `LegacyHotkeyFixtures` / migration parity — the new typed rows never existed as legacy data, so
  they are **excluded** from the legacy-parity fixture; only the still-legacy subset mirrors it.
- `DefaultHotkeyCatalog` doc-comment — update to describe the mixed legacy + typed shape.

## Risks

- **Bare F-key remaps hijack globally.** `F10` also activates the menu bar in many apps; `F1::return`
  removes the Help key everywhere. Intended: these are teaching samples the user curates before
  running their own script (nothing runs automatically).
- **Seed skips validation** — mitigated by pinning every typed definition here and by the golden
  integration test.
- **Migration parity** — kept intact by leaving legacy rows on the `Legacy(...)` helper and excluding
  new typed rows from the parity fixture.

## Decisions (resolved with the user)

1. **F-key remaps stay bare** (`F9`/`F10`, not `^F9`/`^F10`) — real media-key UX is a bare tap; the
   global-hijack tradeoff (F10 menu bar) is spelled out in each Description.
2. **Second remap is `F9::Volume_Up`** — pairs with F10 mute as one volume cluster.
3. **Categories:** the media remaps + F1-disable go to **App Launcher**, following the seed's existing
   precedent (Lock workstation and Reload already live there as non-launcher system utilities).
4. **Native-snap samples are in scope** — fixed by adding `#` to their `Send` content (§2b).
5. **Catalog shape:** one unified typed list; `Legacy(...)` helper for legacy/SendKeys rows.
