# Entity Version History — Design (v1)

**Status:** Draft for review
**Date:** 2026-07-01
**Scope:** v1 — Hotstrings & Hotkeys

## Context

AHKFlowApp stores personal, hand-crafted content: carefully worded hotstring
replacements and tuned hotkeys. Today every update overwrites state in place and
every delete is a hard delete with cascade — there is **no** history, soft-delete,
audit, or `RowVersion`. The delete dialog literally warns *"This cannot be undone."*

The costly failure mode for single-owner data is **accidental loss**: a fat-finger
delete or a botched edit destroys work with no recovery. This feature adds a
lightweight safety net so a user can go back in time to **see or revert** their own
changes. It is intentionally basic and built to extend later (more entities, CLI,
time-based purge, point-in-time script generation).

Not in scope: multi-user audit ("who changed what") — data is single-owner, so it
has weak value. No compliance logging.

## Decisions (locked)

| Question | Decision |
|---|---|
| Primary goal | Undo accidental loss (safety net) |
| Recovery scope | Deletes **and** edits |
| Capture approach | App-level snapshot table (JSON before-images) |
| Entities in v1 | **Hotstring, Hotkey** (table generic; Profile/Category later) |
| UI surface | Per-item History dialog **+** Recycle Bin page |
| Retention | Last **50** versions per item; deletes kept until restored/purged |

## Model: before-image snapshots

Current state remains the single source of truth in the existing tables. The history
table holds only **superseded** states — the way an item looked before a change.

- **On Update:** snapshot the current (soon-to-be-old) aggregate → `EntityHistory`
  (`ChangeType = Edit`), then apply the new state to the main table.
- **On Delete / BulkDelete:** snapshot the current aggregate → `EntityHistory`
  (`ChangeType = Delete`), then hard-delete from the main table (unchanged behavior).
- **Create:** writes nothing (current state is the item itself).

A single item's timeline for the UI = `[EntityHistory rows ordered by Version]`
followed by the live main-table state (or, for a deleted item, ending at the
`Delete` tombstone).

Why not soft-delete columns or SQL temporal tables: the entities have per-owner
**unique indexes** (e.g. `(OwnerOid, Trigger)`) and no global query filters. Hard-delete
+ tombstone avoids index conflicts, avoids adding `HasQueryFilter` to every existing
query, and keeps the many-to-many links (which are replaced wholesale on edit) captured
as one aggregate. It also keeps the existing tables untouched — the migration is purely
additive.

## Data model

New: `EntityHistory` (entity + `IEntityTypeConfiguration` + migration).

| Column | Type | Notes |
|---|---|---|
| `Id` | `Guid` | PK |
| `OwnerOid` | `Guid` | Per-user scope + authorization |
| `EntityType` | `int` (enum) | `Hotstring`, `Hotkey` (extensible: `Profile`, `Category`) |
| `EntityId` | `Guid` | The tracked entity's Id |
| `Version` | `int` | Monotonic per `(EntityType, EntityId)`, 1-based |
| `ChangeType` | `int` (enum) | `Edit`, `Delete` |
| `SchemaVersion` | `int` | Snapshot-JSON schema tag for forward-compat |
| `CapturedAt` | `DateTimeOffset` | When the change occurred (`TimeProvider`) |
| `SnapshotJson` | `nvarchar(max)` | Serialized aggregate (see below) |

Index: **unique** on `(OwnerOid, EntityType, EntityId, Version)` — guarantees
`history/{version}` is unambiguous even under concurrent writes (see version
allocation below).

**Snapshot DTOs** (System.Text.Json, one record per entity type, versioned by
`SchemaVersion`):

- **Hotstring:** `Trigger`, `Replacement`, `Description`, `AppliesToAllProfiles`,
  `IsEndingCharacterRequired`, `IsTriggerInsideWord`, `ProfileIds[]`, `CategoryIds[]`,
  `CreatedAt`, `UpdatedAt`.
- **Hotkey:** `Description`, `Key`, `Ctrl`, `Alt`, `Shift`, `Win`, `Action`,
  `Parameters`, `AppliesToAllProfiles`, `ProfileIds[]`, `CategoryIds[]`, `CreatedAt`,
  `UpdatedAt`.

## Application layer

**`EntityHistoryRecorder`** (Application service; abstraction in
`Abstractions/`, used by handlers):
- Computes next `Version` = current max for `(type, id)` + 1. The unique index makes
  a concurrent duplicate a hard failure, not silent corruption: on a duplicate-key
  `DbUpdateException` against the history index (reuse `IsDuplicateKeyViolation()`),
  the handler retries the whole operation **once** (re-read max, re-save); if it
  still collides, return `Result.Conflict`. Single-owner data makes contention
  near-zero; one retry is enough.
- Serializes the snapshot DTO, adds an `EntityHistory` row with
  `CapturedAt = clock.GetUtcNow()`.
- Prunes: if an item exceeds 50 rows, remove the **oldest** (the newest — a `Delete`
  tombstone or latest edit — is always retained).
- Only **adds** to the tracked `IAppDbContext`; the calling handler owns
  `SaveChangesAsync`, so capture + mutation commit in one transaction.

**Wire capture into existing handlers:**
`UpdateHotstringCommand`, `DeleteHotstringCommand`, `BulkDeleteHotstringsCommand`,
`UpdateHotkeyCommand`, `DeleteHotkeyCommand`, `BulkDeleteHotkeysCommand`.

The update handlers already load `Profiles`/`Categories` via `Include` and can reuse
the aggregate. The delete and bulk-delete handlers currently load **only the root
entity** — they must add `.Include(x => x.Profiles).Include(x => x.Categories)`
(both entities) so tombstone snapshots capture the junction links. Covered by an
integration test asserting a delete tombstone contains the item's
`ProfileIds`/`CategoryIds`.

**New commands/queries** (per entity, matching the codebase's explicit style).
Hotstring and Hotkey get the **full symmetric set** — for every command/query below,
a `…Hotkey…` twin exists with identical semantics:
- `GetHotstringHistoryQuery` / `GetHotkeyHistoryQuery` — list version metadata
  (owner-scoped; another user's item → `NotFound`).
- `GetHotstringHistoryVersionQuery` / `GetHotkeyHistoryVersionQuery` — full snapshot
  for preview.
- `RevertHotstringCommand(id, version)` / `RevertHotkeyCommand(id, version)` —
  snapshot current as an `Edit`, then re-apply the target snapshot via the entity's
  domain `Update` + rebuild junctions.
- `ListDeletedHotstringsQuery` / `ListDeletedHotkeysQuery` — Recycle Bin source:
  latest `Delete` tombstone per `EntityId` where no live entity with that Id exists.
- `RestoreHotstringCommand(id)` / `RestoreHotkeyCommand(id)` — re-create from the
  tombstone with the **original Id** and links; `Result.Conflict` if a unique index
  (e.g. trigger) now collides.
- `PurgeDeletedHotstringCommand(id)` / `PurgeDeletedHotkeyCommand(id)` — Recycle Bin
  "Delete forever": removes **all** `EntityHistory` rows for `(type, id)`.
  `NotFound` if no tombstone exists or a live entity with that Id still exists
  (purge is only valid from the deleted state in v1).

**Missing Profiles/Categories on restore & revert.** Junction FKs cascade, so a
snapshot may reference Profile/Category Ids that no longer exist. Restore/revert
must never fail because of them (safety-net first): filter the snapshot's
`ProfileIds`/`CategoryIds` against the owner's live rows and **silently drop missing
links**. Edge case: if `AppliesToAllProfiles = false` and *all* snapshot profiles
are gone, restore/revert still succeeds with zero profile links — the item is inert
(appears in no generated script) until the user edits it. This intentionally
bypasses the command validator's "≥1 profile" rule; that rule guards user input, not
recovery. Both behaviors get integration tests.

**Domain additions:** `Hotstring.Restore(...)` / `Hotkey.Restore(...)` factories that
accept the original `Id` and `CreatedAt` (current `Create` generates a new Guid). Set
`UpdatedAt = clock.GetUtcNow()`.

## API surface (per-entity controllers, `[Authorize]` + existing scope)

On `HotstringsController` and `HotkeysController`:

```
GET  api/v1/hotstrings/{id}/history                 -> version list (metadata)
GET  api/v1/hotstrings/{id}/history/{version}       -> full snapshot (preview)
POST api/v1/hotstrings/{id}/history/{version}/revert -> revert; returns updated DTO
GET  api/v1/hotstrings/deleted                      -> Recycle Bin list
POST api/v1/hotstrings/{id}/restore                 -> restore; returns restored DTO
DELETE api/v1/hotstrings/deleted/{id}               -> purge ("Delete forever"); 204
```

Same six routes on `api/v1/hotkeys`.

Thin actions: `mediator.Send(...)` → `ToProblemActionResult(this)`, as elsewhere.

## UI (Blazor, MudBlazor)

- **History dialog** on `Hotstrings.razor` / `Hotkeys.razor`: a row action opens a
  `MudDialog` listing versions (timestamp, change type). Selecting one shows a
  read-only preview + **"Revert to this version"** (confirm).
- **Recycle Bin page** (`RecycleBin.razor`, new nav entry): combined list of deleted
  hotstrings and hotkeys with a type column; each row has **Restore** and
  **Delete forever** (calls the purge endpoint after a confirm dialog). Restore
  surfaces conflict messages.
- **Soften delete copy:** replace *"This cannot be undone."* in the delete-confirm
  dialogs with *"You can restore this from the Recycle Bin."*
- New API-client methods on the existing typed clients.

## Testing

- **Domain:** `Restore` factories set `Id`/`CreatedAt` correctly.
- **Application/integration (Testcontainers):** update writes a correct before-image;
  revert restores prior fields **and** junction links and writes a new before-image;
  delete/bulk-delete write tombstones that **include `ProfileIds`/`CategoryIds`** and
  remove the rows; restore re-inserts with original Id + links; duplicate trigger →
  `Conflict`; restore/revert with deleted Profile/Category Ids drops the missing
  links (incl. the all-profiles-gone → zero-links case); purge removes all history
  rows and returns `NotFound` for live or unknown items; pruning caps at 50; unique
  version index rejects duplicate `(type, id, version)`.
- **API (WebApplicationFactory):** history/revert/restore/purge endpoints; owner
  scoping (another user's history → `NotFound`); auth.
- **bUnit:** history dialog renders versions and calls revert; Recycle Bin renders and
  calls restore + purge (with confirm).

## Migration

`dotnet ef migrations add AddEntityHistory` — adds one table; **no** changes to existing
tables (no soft-delete columns, no query-filter changes). Low-risk, additive.

## Verification (end-to-end)

1. `dotnet build` + `dotnet test` green.
2. Run API (Docker SQL) + Blazor. Create a hotstring, edit it twice, open **History**,
   revert to v1 → fields + profile/category links match the original.
3. Delete a hotstring → appears in **Recycle Bin** → **Restore** → reappears in the list
   with the same content; delete dialog now points to the Recycle Bin.
4. Repeat for a hotkey (modifiers + action preserved through revert/restore).
5. Restore into a colliding trigger → clear conflict message.
6. Delete a hotstring, **Delete forever** in Recycle Bin → gone from the bin and no
   history rows remain.

## Extensibility (explicitly deferred)

- **Profile/Category history:** add enum values + snapshot DTOs + handler wiring — no
  schema change.
- **CLI verbs** (`ahkflow hotstring history/restore`): API already supports it.
- **Time-based purge** (e.g. 90-day auto-clean): add a scheduled job.
- **Point-in-time script generation:** have `ProfileScriptLoader` read from history.
- **Version diff view** in the History dialog.

## Open questions

- CLI history/restore verbs in v1, or defer? (Recommend: defer.)
- Restore always uses the latest pre-delete state; older-version revert is live-items
  only — OK? (Recommend: yes.)
- Silently dropping missing Profile/Category links on restore/revert — OK, or should
  the restore response/UI mention how many links were dropped? (Recommend: silent in
  v1; snackbar note is a cheap follow-up.)
