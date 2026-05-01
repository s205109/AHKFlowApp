# Design Spec — AHKFlow alignment redesign

> Replaces the prior 022-only plan (shipped). This is a new, larger redesign.

## Context

The just-shipped Hotkeys UI (backlog 022) uses a free-form `Trigger`/`Action`/`Description` model. The redesign aligns the Hotkeys page with the AHKFlow reference UI, with columns: **Description, Key, CTRL, ALT, SHIFT, Win, Action (enum dropdown), Profile (multi-select / "Any"), Parameters, Actions**.

This is not a UI tweak. It requires reshaping the Hotkey domain, adding many-to-many profile association, wiring a real Profiles UI/API, and building per-profile script generation + download. Backlog items 024–027 already anticipate most of this; they need updates rather than wholesale rewrite.

## Decisions (locked in by user during brainstorm)

| # | Decision |
|---|---|
| D1 | **Profile association = many-to-many.** Junction tables `HotkeyProfile` and `HotstringProfile`. |
| D2 | **"Any" = global flag.** Hotkey/Hotstring entity gets `AppliesToAllProfiles` bool. When true, junction is empty and the row is included in every profile's generated script (current and future). |
| D3 | **Header + footer templates per profile.** Both stored on `Profile`, editable by the user. Seeded from defaults on profile creation. |
| D4 | **Hotkey `Action` = extensible enum** (start with `Send`, `Run`; add later without schema break). `Parameters` is a separate string column. |
| D5 | **Downloads UX = per-profile rows + bulk zip.** Each profile row has its own Download button; one top-level "Download all" zips every profile's `.ahk`. |
| D6 | **Phase 0 = standalone docs PR.** Backlog rewrite lands by itself before any code phase. |
| D7 | **Dev-only data preservation.** Migrations may drop columns / tables freely; no copy-forward SQL needed. (Revisit if PROD ever holds real user data.) |

## Target domain model

### Profile (new entity)
```
Id (Guid), OwnerOid (Guid), Name (string, ≤100, unique per owner),
IsDefault (bool, exactly one true per owner),
HeaderTemplate (string, ≤8000), FooterTemplate (string, ≤4000),
CreatedAt, UpdatedAt
```
Default `HeaderTemplate` is a standard AHK v2 header (e.g. `#Requires AutoHotkey v2.0`, `#SingleInstance Force`, `SetCapsLockState "AlwaysOff"`, etc.). `FooterTemplate` defaults to empty string.

### Hotkey (rebuild — drop `Trigger`/`Action`/`Description` strings)
```
Id, OwnerOid,
Description (string, ≤200, required, primary identifier),
Key (string, ≤20, required),                 -- single AHK key, e.g. "n", "F5", "Numpad0"
Ctrl, Alt, Shift, Win (bool flags),
Action (enum: Send=0, Run=1; extensible),
Parameters (string, ≤4000),
AppliesToAllProfiles (bool),
CreatedAt, UpdatedAt
```
Junction: `HotkeyProfile (HotkeyId, ProfileId)` — empty when `AppliesToAllProfiles=true`.

Unique index: `(OwnerOid, Key, Ctrl, Alt, Shift, Win)` — one mapping per modifier-combo per user.

### Hotstring (mostly unchanged — schema already aligns)
```
Id, OwnerOid, Trigger, Replacement,
IsEndingCharacterRequired, IsTriggerInsideWord,
AppliesToAllProfiles (NEW),
CreatedAt, UpdatedAt
```
Drop existing nullable `ProfileId` column; replace with junction `HotstringProfile (HotstringId, ProfileId)`.

## Decomposition (six phases)

Each phase = one PR. Items map to existing backlog items where possible.

### Phase 0 — Backlog rewrite (no code) ✅
Update items 022, 024, 025, 026, 027; add items 022b, 024b, 027b. Each item gets its acceptance criteria adjusted to the locked-in decisions.

### Phase 1 — Profile foundation (touches: Domain, Application, Infrastructure, API, UI)
- New `Profile` entity + EF configuration + migration.
- Default-profile seeding on first sign-in (interceptor or login handler).
- API: `ProfilesController` (GET list, GET id, POST, PUT, DELETE) with header/footer fields.
- UI: `Pages/Profiles.razor` — list + inline edit; expand-row textareas for header/footer (large, monospace).
- Maps to backlog **024 + 025** (combined; templates land with the entity).

### Phase 2 — Many-to-many profile association (touches: Domain, Infrastructure, API, UI for Hotstrings only at first)
- Add `AppliesToAllProfiles` to Hotstring; create `HotstringProfile` junction; migration that copies the existing single `ProfileId` into the junction (one row each) and drops the old column.
- API: Hotstring DTOs gain `Guid[] ProfileIds` + `bool AppliesToAllProfiles`.
- Hotstrings UI: replace single-profile picker with multi-select + "Any" checkbox row.
- Existing 014 hotstring tests adapted; new tests for "Any" flag.
- Maps to backlog **024b**.

### Phase 3 — Hotkey rebuild (touches: Domain, Application, Infrastructure, API, UI)
- Rebuild `Hotkey` to the target schema. Migration drops `Trigger`/`Action`/`Description` columns and the nullable `ProfileId`; adds `Description` (required), `Key`, `Ctrl/Alt/Shift/Win`, `Action` enum (int), `Parameters`, `AppliesToAllProfiles`. Junction `HotkeyProfile`.
- API: rebuild DTOs/validators/handlers/controller. Backward-incompatible. Existing 021 + 022 tests are largely thrown out and rewritten.
- UI: rebuild `Pages/Hotkeys.razor` — Description, Key (single text input), Ctrl/Alt/Shift/Win (MudCheckBox), Action (MudSelect bound to enum), Profile (MudSelect multi-select with "Any" toggle), Parameters (MudTextField), Actions.
- Maps to **022 (replace)** + **022b**.

### Phase 4 — Script generation
- New `AhkScriptGenerator` service in Application layer. Per-profile output:
  ```
  {profile.HeaderTemplate}
  ; --- Hotstrings ---
  ...generated lines using IsEndingCharacterRequired + IsTriggerInsideWord...
  ; --- Hotkeys ---
  ...modifiers + key + Action(Send|Run) + Parameters...
  {profile.FooterTemplate}
  ```
- Includes hotkeys/hotstrings where the row is in `{Profile}Profile` junction OR `AppliesToAllProfiles=true`.
- Deterministic ordering: hotstrings by `Trigger` ASC, hotkeys by `Description` ASC.
- AHK v2 syntax: `^!+#` modifier prefix order = Ctrl, Alt, Shift, Win; hotstring format `:options:trigger::replacement`; option `*` = no ending character required, `?` = trigger inside word.
- Pure unit tests on the generator + integration test against seeded data.
- Maps to **026**.

### Phase 5 — Downloads page + endpoints
- API: `GET /api/v1/downloads/{profileId}` returns one `.ahk`; `GET /api/v1/downloads/zip` returns a zip of every profile's `.ahk`.
- UI: `Pages/Downloads.razor` — list profiles with per-row Download button, plus a top-level "Download all (zip)" button.
- Maps to **027** + **027b**.

## Files (representative, not exhaustive)

- `src/Backend/AHKFlowApp.Domain/Entities/Profile.cs` (new)
- `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` (rebuild)
- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (add `AppliesToAllProfiles`)
- `src/Backend/AHKFlowApp.Domain/Entities/HotkeyProfile.cs`, `HotstringProfile.cs` (new junctions)
- `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs` (new enum)
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/{Profile,Hotkey,Hotstring,HotkeyProfile,HotstringProfile}Configuration.cs`
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/...` (one per phase)
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` (new)
- `src/Backend/AHKFlowApp.API/Controllers/{Profiles,Downloads}Controller.cs` (new); rebuild `HotkeysController.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/{Profiles,Hotkeys,Hotstrings,Downloads}.razor`
- `.claude/backlog/{022,022b,024,024b,025,026,027,027b}.md`

## Files NOT touched

- `tests/AHKFlowApp.E2E.Tests` (no E2E in this stream)
- CI/CD workflows
- MSAL / auth wiring
- AppInsights / Serilog config
- Dockerfile / docker-compose

## Verification (per phase)

1. `dotnet test --configuration Release --no-build` passes.
2. `dotnet format` clean.
3. Manual smoke after Phase 3: create two profiles, add a hotkey with "Any" + a hotkey with one specific profile + a hotstring; download both profiles; inspect `.ahk` for correct header, modifier prefixes, hotstring options, footer.
4. Phase 5 final smoke: bulk zip downloads correct number of files, each named `ahkflow_{profile_name}.ahk`.

## Out of scope (for THIS spec)

- Search/filter UI (backlog 023 for hotkeys; 019 for hotstrings — separate work).
- CLI changes (017/018/028/029).
- Profile import/export.
- Template versioning.
- Key-capture widget for the Key field — plain text input only (`MudTextField`); user types `n`, `F5`, `Numpad0`. Capture widget can come later.
- Runtime execution of AHK scripts.

## Decisions log

- Profile assoc model → many-to-many (D1)
- "Any" semantics → global flag (D2)
- Templates editable → per-profile, editable (D3)
- Action field → extensible enum (D4)
- Download UX → per-profile + zip (D5)
- Phase 0 packaging → standalone docs PR first (D6)
- Data preservation → dev-only, destructive migrations OK (D7)
