# Import Existing `.ahk` Hotstrings — Design

**Date:** 2026-07-05
**Status:** Approved for planning
**Parent:** [First-Release Feature Shortlist](2026-07-04-first-release-feature-shortlist.md) — item #2

## Purpose

Convert existing AutoHotkey users in minutes: paste or upload their AHK v2 script, preview which
hotstring lines were recognized, and bulk-create them into their account. Strongest onboarding
lever on the first-release shortlist.

## Decisions (user-approved 2026-07-05)

| Decision | Choice |
|---|---|
| Surfaces | **UI first**; CLI command is a later thin follow-up reusing the same endpoints |
| Unsupported option flags | **Import with warning** — `*` and `?` map faithfully; other flags are dropped, row marked Warning in preview, still imports |
| Duplicate triggers | **Skip and report** — never overwrite; in-file repeats keep first occurrence |
| Profile target | **One target for the whole batch**, chosen in the dialog (all profiles, or specific ones) |
| Input method | **Paste box + file upload** (.ahk / .txt), both feed the same parser |
| Batch cap | **1000 parsed hotstring rows** per import; reject above with clear message |

## Architecture

The parser is the single source of truth and runs **server-side only** for both preview and
commit. The client sends raw script text + profile target; it never sends parsed rows back.

```
Paste/upload script ─► POST /import/preview ─► parse + mark collisions (read-only) ─► preview table
                       POST /import          ─► re-parse + filter + bulk insert     ─► summary
```

Re-parsing on commit means preview and import can never disagree, and the commit endpoint is
safe to call without a prior preview (the future CLI can use it directly).

## Components

### Application layer

**`Services/AhkHotstringParser`** — pure function, no dependencies. The exact inverse of
`AhkScriptGenerator.FormatHotstring` (`:{options}:{trigger}::{replacement}`). Input: raw script
text. Output: list of parsed rows. Per line:

- Matches single-line `:options:trigger::replacement` (also plain `::trigger::replacement`).
- `*` → `IsEndingCharacterRequired = false`; `?` → `IsTriggerInsideWord = true`.
- Any other option letter (C, B0, O, R, T, SI, K*n*, P*n*, X, Z, …) → collected into
  `IgnoredFlags`, row status **Warning**, still importable.
- Comment lines (`;`), blank lines, hotkeys, directives, plain code → silently ignored
  (not hotstrings; not reported).
- Leading/trailing whitespace on the parsed **trigger** is trimmed before validation — a stray
  space shouldn't turn an otherwise-valid line Invalid (import is a lenient bulk path, unlike the
  interactive create form where `ValidTrigger` rejects padded triggers). The **replacement** is
  kept verbatim (whitespace can be significant in AHK).
- Trigger/replacement then checked against `HotstringRules` constants (trigger ≤ 50 chars, no
  linebreaks/tabs; replacement non-empty, ≤ 4000) → failures become **Invalid** rows with reason.
- Multi-line continuation sections (`(` … `)`) → **Invalid**, "multi-line replacements not
  supported". The continuation block's inner lines are consumed so they don't misparse.

**Row status:** `Ready` | `Warning` (both import) · `Duplicate` | `Invalid` (both skipped). The
parser only ever emits `Ready` / `Warning` / `Invalid` — it is **syntax-only** and has no
knowledge of duplicates. The `Duplicate` status is assigned exclusively by the preview/import
handlers, which own both existing-trigger and in-file-repeat detection.

**`Commands/Hotstrings/PreviewHotstringImportCommand(string Script)`**
→ `Result<HotstringImportPreviewDto>`. Read-only. Parses, then marks rows **Duplicate** when the
trigger already exists for the owner (one DB query) or repeats earlier in the file (first
occurrence wins). Duplicate detection is case-insensitive, matching the default SQL Server
collation behind `IX_Hotstring_Owner_Trigger`.

**`Commands/Hotstrings/ImportHotstringsCommand(ImportHotstringsRequestDto)`**
→ `Result<HotstringImportResultDto>`. Re-parses, drops Invalid + Duplicate rows, bulk-inserts
Ready + Warning rows in one `SaveChanges`, attaching the batch profile target
(`AppliesToAllProfiles` or `HotstringProfile` junction rows, validated with the existing
`OwnedIdsValidation` + `AddProfileAssociationRules` patterns). Handles the race where a trigger
was created between preview and import: catch duplicate-key `DbUpdateException`, then **detach the
pending entities** (`db.Hotstrings.Local` + `db.HotstringProfiles.Local`, following the detach
pattern in `ListHotstringsQuery` around line 229), re-query the owner's existing triggers, rebuild
the batch without the now-colliding rows, and `SaveChanges` once more so the remaining rows still
import. A failed `SaveChanges` leaves the whole attempted batch tracked, so the detach is required
before the retry — a bare retry would re-submit the conflicting insert. Returns per-row final
statuses (below).

**Validation (FluentValidation, via existing decorator):**
- Script non-empty, max length 1 MB (sanity bound on payload).
- More than 1000 parsed hotstring rows → `Result.Invalid` with message.
- Profile association rules identical to `CreateHotstringCommand`.

**DTOs (records):**
- `HotstringImportRowDto(int LineNumber, string Trigger, string Replacement, bool IsEndingCharacterRequired, bool IsTriggerInsideWord, string[] IgnoredFlags, HotstringImportRowStatus Status, string? Reason)`
- `HotstringImportPreviewDto(HotstringImportRowDto[] Rows, int ReadyCount, int WarningCount, int DuplicateCount, int InvalidCount)`
- `ImportHotstringsRequestDto(string Script, bool AppliesToAllProfiles, Guid[]? ProfileIds)`
- `HotstringImportResultDto(int ImportedCount, int WarningCount, HotstringImportRowDto[] Rows)`
  — `Rows` carries **every** processed line with its final status (Ready/Warning = imported,
  Duplicate/Invalid = skipped), so a caller that imports without a prior preview (future CLI, or
  a direct API client) still receives the warning rows and sees which unsupported flags were
  dropped. Skipped rows are the `Duplicate`/`Invalid` subset; no separate list needed.

### API

Two endpoints on the existing `HotstringsController` (same auth/scope attributes):

- `POST api/v1/hotstrings/import/preview` → 200 `HotstringImportPreviewDto`, 400 on validation.
- `POST api/v1/hotstrings/import` → 200 `HotstringImportResultDto`, 400 on validation.

A fully-duplicate file is a **200 with `ImportedCount = 0`** and the per-row results — not an error.
Per-line problems never fail the request; they surface as row statuses.

### Frontend (Blazor)

**Import entry points** on `Pages/Hotstrings.razor` — the page has separate `.desktop-branch`
and `.mobile-branch` containers gated in `Hotstrings.razor.css` at 959.95px. Add **both**: an
Import `MudButton` in the desktop toolbar (next to Add) and an Import affordance in the mobile
branch (a secondary `MudFab`, or a menu item on the existing FAB, consistent with how mobile Add
is surfaced). Both open the same `Components/Hotstrings/HotstringImportDialog.razor`
(convention: sibling of `HotstringEditDialog.razor`), shown full-screen on mobile per the
project's mobile-dialog convention. A single dialog with conditional content (not a MudStepper) —
the input stays editable while the preview shows below, so the user can tweak and re-preview
without losing state. Dialog flow:

1. **Input step:** paste textarea + `MudFileUpload` (.ahk/.txt, read as text) + profile target
   (all-profiles switch / `EntityMultiSelect` for specific profiles, mirroring the edit dialog).
2. **Preview step:** on Preview click, call preview endpoint; show `MudTable` of rows with
   status chips (Ready / Warning + ignored flags / Duplicate / Invalid + reason) and a summary
   line: *N ready, N with warnings, N duplicates skipped, N invalid*.
3. **Confirm:** "Import N hotstrings" button (disabled when N = 0) calls the import endpoint;
   snackbar with imported/skipped counts; refresh the hotstrings list; close.

Extends UI `IHotstringsApiClient`/`HotstringsApiClient` with `PreviewImportAsync` /
`ImportAsync`; mirror the four DTOs in the UI project (explicit mapping convention — no shared
project change needed).

## Error handling

- Request-level failures (empty script, bad profile ids, > 1000 rows) → `Result.Invalid` →
  RFC 9457 ProblemDetails via existing pipeline.
- Line-level failures → row status, never an HTTP error.
- Import is best-effort but atomic for accepted rows: one transaction; either all Ready+Warning
  rows insert or none do.

## Testing

- **Parser unit tests (TDD, the core):** plain hotstring, `*`, `?`, `*?`, unknown flag →
  Warning + IgnoredFlags, comment/blank/hotkey/directive ignored, trigger too long,
  empty replacement, tab/linebreak in trigger, multi-line continuation rejected + inner lines
  consumed, `::` inside replacement text, leading/trailing trigger whitespace trimmed. No
  duplicate cases here — the parser never classifies duplicates.
- **Handler integration (Testcontainers):** preview marks existing-trigger collisions
  (case-insensitive) **and in-file repeats** (first occurrence wins); import skips both duplicate
  kinds and inserts the rest; profile target applied (all-profiles and specific); imported result
  reports warning rows; 1000-row cap; empty script invalid; concurrent-create race detaches,
  re-filters, and still imports the non-colliding rows.
- **API integration (WebApplicationFactory):** both endpoints wired, `[Authorize]` enforced,
  400 ProblemDetails on invalid payload.
- **bUnit:** dialog input → preview → confirm flow, disabled confirm at N = 0; both desktop and
  mobile entry points open the dialog.

## Out of scope

- CLI `ahkflow hotstring import` command (follow-up; endpoints designed for it).
- Multi-line continuation replacements.
- Fidelity for option flags other than `*` and `?`.
- Hotkey import.
- Overwrite/merge on trigger collision.
- AHK v1 syntax (v1 `::btw::by the way` lines parse identically anyway; no v1-specific handling).
