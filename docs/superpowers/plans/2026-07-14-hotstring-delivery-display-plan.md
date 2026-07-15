# Hotstring delivery — always-visible Type column

## Context

Clipboard delivery works, but the Hotstrings list doesn't make delivery legible:

- A **long `Auto` row** (e.g. `200b`, `10000c`) that will paste via clipboard shows **no** delivery indicator — the list reads the raw stored `Delivery` (`Auto`), which never renders a chip. Users can't tell a typed row from a clipboard row.
- An **explicit `ClipboardPaste` row** shows **two** chips in the Type column: `Text` + `Clipboard`. The double chip is undesirable.

Goal: every Text row shows **one** chip in the Type column reflecting its **effective** delivery — `Hotstring` (typed) or `Clipboard` — with `Auto` resolved for display. Non-Text kinds keep their kind chip. No stored-value or script-generation behavior changes.

## Decisions (confirmed with user)

1. **Keep `Auto` stored; resolve only for display.** `Delivery=Auto` stays dynamic in the DB and in script generation — no migration, no emitter change. The list just displays the resolved delivery.
2. **Delivery chip replaces the `Text` kind chip.** Text rows show a single chip: `Hotstring` (typed) or `Clipboard`. DateTime / Macro / Raw rows keep their existing kind chip unchanged.
3. **Wording:** typed = `Hotstring`, clipboard = `Clipboard` (a "clipboard hotstring"). Tooltip may spell out "Clipboard hotstring".
4. **Align edit-dialog preview chip** to the same wording (`Typed` → `Hotstring`).
5. **Selector wording follows the chip** (revised 2026-07-15, supersedes the original "selector stays unchanged"): the Delivery selector reads **Auto / Hotstring / Clipboard**. The original split — selector `Typed` (user intent) vs chip `Hotstring` (resolved type) — made the same mode read under two names in one dialog. One name everywhere wins over the intent/result distinction. The CLI's `--delivery auto|type|clipboard` values are unchanged (see Out of scope).

## Approach

Compute effective delivery **server-side** and surface it as a new `EffectiveDelivery` field on `HotstringDto` (never `Auto`), mirroring the existing `HotstringPreviewDto.EffectiveDelivery`. The list chip then reads one authoritative field — no client-side threshold duplication, no coupling to the list-truncation length.

### Backend

- **`HotstringDto` (Application, `DTOs/HotstringDto.cs`)** — append `HotstringDelivery EffectiveDelivery = HotstringDelivery.Type` (last positional param, defaulted). XML doc: "Resolved delivery for display; never `Auto`."
- **Shared mapper `HotstringMappings.ToDto` (`Mapping/HotstringMappings.cs:8`)** — set `EffectiveDelivery = HotstringEmitter.ResolveEffectiveDelivery(h)`. Covers GET-by-id, create, update, restore, revert responses.
- **List projection (`Queries/Hotstrings/ListHotstringsQuery.cs:202`)** — `ResolveEffectiveDelivery` can't translate to SQL, so inline the equivalent expression. Use `EF.Functions.DataLength(...) / 2` rather than `h.Replacement.Length`: the latter translates to SQL Server `LEN()`, which strips trailing spaces and would undercount them against the resolver's .NET `Length`. The list-truncation predicate must use the same char count so the two derived columns agree:
  ```csharp
  EffectiveDelivery = h.Kind == HotstringKind.Text
      && (h.Delivery == HotstringDelivery.ClipboardPaste
          || (h.Delivery == HotstringDelivery.Auto
              && (EF.Functions.DataLength(h.Replacement) ?? 0) / 2 >= HotstringDeliveryDefaults.AutoClipboardThresholdChars))
      ? HotstringDelivery.ClipboardPaste
      : HotstringDelivery.Type
  ```
  Add a code comment: keep in sync with `HotstringEmitter.ResolveEffectiveDelivery`.

### Frontend (Blazor)

- **`UI.Blazor/DTOs/HotstringDto.cs`** — mirror the new `EffectiveDelivery` field.
- **Shared helper** — add a small static helper (in `UI.Blazor/Helpers`) returning the delivery chip label (`Hotstring`/`Clipboard`) and whether it's clipboard, reused by both render sites (KindLabel is already duplicated across them; this keeps the new logic single-sourced).
- **Desktop Type column (`Pages/Hotstrings.razor:152-172`)** — for `Kind == Text`, render **one** chip from `EffectiveDelivery`: `Clipboard` (Color.Info, `clipboard-delivery` class) or `Hotstring` (default color). Non-Text rows render the existing kind chip (Raw warning styling preserved). Keep option glyphs + context icon. `data-test` = `clipboard-delivery` / `hotstring-delivery`.
- **Mobile list (`Components/Hotstrings/HotstringMobileList.razor:54-55`)** — same single-chip logic via the shared helper.
- **Tooltip/aria parts (`Hotstrings.razor:966`)** — for Text rows, use the delivery label instead of `KindLabel` so screen-reader text matches the chip.
- **Edit dialog preview chip (`HotstringEditDialog.razor:197`)** — align wording `Typed` → `Hotstring` (Decision #4).
- **Edit dialog Delivery selector (`HotstringEditDialog.razor:66`)** — option label `Typed` → `Hotstring` so selector and chip name the mode identically (Decision #5). Enum value (`HotstringDelivery.Type`) unchanged.

### Tests

- **Backend:** `ListHotstringsQuery` — `EffectiveDelivery` is `ClipboardPaste` for Auto@200 and explicit Clipboard, `Type` for Auto@199 and Macro. `HotstringMappings.ToDto` — sets `EffectiveDelivery` from the resolver.
- **bUnit:** desktop + mobile lists render exactly one Type chip: `Hotstring` for short Text, `Clipboard` for long-Auto and explicit-Clipboard Text; kind label for DateTime/Macro/Raw. Update existing tests that assert the old `Text`+`Clipboard` double chip or `clipboard-delivery` presence/absence. Preview-chip test wording `Typed` → `Hotstring`.

## Out of scope

- Storing the resolved value / migrations (explicitly rejected — `Auto` stays dynamic).
- Filtering or sorting the list by delivery (Type column keeps sorting by `Kind`).
- CLI table formatter delivery column.

## Verification

1. `dotnet build` + `dotnet test` (Application + UI.Blazor test projects) green.
2. `dotnet format`.
3. Run the app (no-auth worktree profile) and open Hotstrings: confirm `200b`/`10000c`/`199a` show a single Type chip — `Clipboard` for the two ≥200 rows, `Hotstring` for `199a` and `aaa`; the explicit-Clipboard row shows one `Clipboard` chip (no `Text` chip). Verify with the `playwright-cli` skill / screenshot.
4. Toggle a Text row's Delivery to Hotstring/Clipboard/Auto in the edit dialog and confirm the list chip updates on save.
