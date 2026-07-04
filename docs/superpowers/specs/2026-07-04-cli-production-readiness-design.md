# CLI Production Readiness — Design

**Date:** 2026-07-04
**Status:** Approved (decomposition confirmed by user)
**Related:** [First-Release Cleanup Roadmap](2026-07-04-first-release-cleanup-roadmap-design.md) (decision #1), [CLI Foundation Design](2026-05-08-cli-foundation-design.md) (historical)

## Goal

Make the `ahkflow` CLI a production-ready, well-documented first-class interface: full command parity with the API for the four core data verticals (Hotstring, Hotkey, Category, Profile), a consistent UX across every command, full test coverage, and complete external documentation.

## Current state

The CLI (`src/Tools/AHKFlowApp.CLI`, System.CommandLine + typed API clients with resilience handlers, tested in `tests/AHKFlowApp.CLI.Tests`) covers:

- `ahkflow login` / `ahkflow logout` (MSAL device code)
- `ahkflow hotstring new` / `ahkflow hotstring list` (with `--json`, `--profile` name resolution)
- `ahkflow download ahk` / `ahkflow download zip`

The API additionally supports, per vertical: Get, Update, Delete for all four; paged List for hotstrings/hotkeys/categories; bulk-delete, history/revert, and recycle-bin (list-deleted/restore/purge) for hotstrings/hotkeys. `IProfilesApiClient` exists internally but is list-only; there are no Hotkey or Category clients.

## Scope

**Command surface (CRUD parity):**

| Vertical | Commands |
|---|---|
| `hotstring` | `new` ✔, `list` ✔, `get`, `update`, `delete` |
| `hotkey` | `new`, `list`, `get`, `update`, `delete` |
| `category` | `new`, `list`, `get`, `update`, `delete` |
| `profile` | `new`, `list`, `get`, `update`, `delete` |

(✔ = exists today.) Each command maps to the corresponding API endpoint; flags mirror the API DTO fields the way `hotstring new` already does.

**Quality bar (user-confirmed):**
1. **Consistent UX + help text** — every command has clear `--help`; flag names are uniform across verticals (`--profile` semantics identical everywhere; `--json` on every read/write command; same table/JSON formatter conventions); errors map API validation failures (incl. field identifiers) to readable messages; non-zero exit codes on failure, consistent codes for the same failure classes.
2. **Full test coverage** — per new command: unit tests for parsing and output formatting; integration tests against a test API, matching the bar backlog 018 set for the hotstring vertical.
3. **External docs** — `docs/cli/` gains a full command reference; README and `docs/architecture/product-vision.md` §8.3 updated to the complete surface.

## Non-goals

- CLI commands for Preferences, Dashboard, Health, Version, WhoAmI (introspection/UI-shaped, not power-user scripting targets).
- Bulk-delete, history/revert, and recycle-bin commands — API supports them, but v1 CLI parity is CRUD only (revisit by demand; see open questions).
- Packaging/winget changes beyond keeping existing packaging correct (no release planned — roadmap decision #2).
- New backend endpoints; the CLI consumes what exists. (If a vertical's API turns out to lack something a command needs, that's a finding to surface, not scope to add silently.)
- Interactive/TUI modes, shell completion, config files beyond the existing `AHKFLOW_*`/appsettings mechanism.

## Architecture

Follow the established vertical pattern exactly — no new abstractions:

- **Commands:** `Commands/{Vertical}/{Verb}{Vertical}Command.cs`, static `Build(IServiceProvider)` returning a `Command`, wired in `RootCli.cs` under a `{vertical}` group command (as `HotstringCommand.cs` does today).
- **Clients:** `Services/I{Vertical}sApiClient.cs` + `Services/{Vertical}sApiClient.cs` (typed `HttpClient`, registered via the existing `CliHttpClientBuilderExtensions` with resilience + bearer handler). Extend `IProfilesApiClient` rather than replacing it.
- **Output:** `Output/{Vertical}TableFormatter.cs` / `{Vertical}JsonFormatter.cs` mirroring the hotstring formatters; shared conventions (column sets, JSON casing) unified in plan 5.
- **Errors:** existing `ApiException`/`CliApiFailureDetector`/exit-code paths; plan 5 makes messages and codes uniform.
- **Name resolution:** commands accept human-friendly names (`--profile <name>`, `--category <name>`) and resolve to ids via list endpoints, exactly like `hotstring new` resolves profiles today; `get/update/delete` accept an id or (where unambiguous) a name — decided per vertical in its plan, consistently across verticals by plan 5.

## Plan index (user-approved decomposition)

| # | Plan | Scope | Depends on | Size |
|---|---|---|---|---|
| 1 | Hotstring CLI completion | `get`/`update`/`delete` on the existing vertical | — | one (S-M) |
| 2 | Hotkey CLI vertical | `IHotkeysApiClient` + 5 commands + formatters | soft: cleanup plan A Task 2 (Hotkey `ValidationError.Identifier` fix the CLI will surface) | one (M) |
| 3 | Category CLI vertical | client + 5 commands + formatters | — | one (M) |
| 4 | Profile CLI vertical | extend `IProfilesApiClient` + 5 commands + formatters | — | one (M) |
| 5 | Cross-cutting UX consistency pass | normalize flags, `--json` shape, errors, exit codes, `--help` copy across ALL commands (old + new) | 1-4 | one (M) |
| 6 | CLI docs | `docs/cli/` command reference; README + product-vision §8.3 update | 5 | one (S) |

Plans 1-4 are independent of each other (parallelizable); each lands as its own PR with its vertical fully tested. Plan 5 runs once over the complete surface; plan 6 documents the final state.

## Testing

- Unit: argument parsing, name-resolution logic, table/JSON formatting per command (`tests/AHKFlowApp.CLI.Tests/Commands`, `Output` — follow existing structure).
- Integration: each command against a test API (existing `Integration/` harness in the CLI test project), covering success, validation failure (asserting the surfaced field identifier), not-found, and unauthenticated paths.
- Verification per plan: `dotnet build AHKFlowApp.slnx`, `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release`, `dotnet format AHKFlowApp.slnx --verify-no-changes`, plus a manual smoke of the new commands against a locally running API (`Auth:UseTestProvider` path).

## Success criteria

- All four verticals expose `new/list/get/update/delete`; every command supports `--json` and returns non-zero on failure.
- A user can discover the full surface from `ahkflow --help` alone; `docs/cli/` reference matches actual behavior.
- CLI test project covers every command at the backlog-018 bar; CI green.
- product-vision §8.3 and README describe the complete CLI truthfully.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Verticals drift in UX while built in separate sessions | Plan 5 is a mandatory single-session consistency pass over everything; plans 1-4 note divergence candidates rather than bikeshedding mid-vertical |
| Hotkey validation errors unreadable in CLI | Sequence plan 2 after cleanup plan A (Task 2 adds the missing `Identifier`); if not landed, surface raw message and note it |
| Update commands need read-modify-write semantics (API `PUT` takes full DTO) | Each update command fetches current state, applies only provided flags, sends full DTO — decided here, uniform everywhere |
| Scope creep into history/recycle-bin | Explicit non-goal; listed as open question for a later decision |

## Open questions

1. History/recycle-bin/bulk-delete CLI commands: wanted later? (out of v1 parity)
2. `get/update/delete` addressing: id-only, or name-with-ambiguity-error too? (proposed: both where names are unique; per-vertical plans confirm)
3. Should plan 5 introduce a global `--quiet`/`--no-color` convention while normalizing output? (only if trivial)
