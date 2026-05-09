# 018 — Hotstrings CLI support (create/list + JSON) — Design

**Date:** 2026-05-09  
**Epic:** Hotstrings  
**Backlog item:** [018-hotstrings-cli-support.md](../../.claude/backlog/018-hotstrings-cli-support.md)

## Overview

Implement `ahkflow hotstring new` and `ahkflow hotstring list` commands to create and list hotstrings via the CLI, with human-readable table output (default) and `--json` structured output. Commands consume the Hotstrings API (013) and Profiles API (013). Authentication via environment variable (`AHKFLOW_TOKEN`) — MSAL device-code auth deferred to item 029.

## Architecture

### File structure

```
src/Tools/AHKFlowApp.CLI/
├── Program.cs                            (modify: register new clients + commands)
├── CliOptions.cs                         (existing, unchanged)
├── Commands/
│   ├── RootCli.cs                        (modify: add HotstringCommand subcommand)
│   └── Hotstrings/
│       ├── HotstringCommand.cs           (verb-noun group: `hotstring`)
│       ├── NewHotstringCommand.cs        (`ahkflow hotstring new`)
│       └── ListHotstringCommand.cs       (`ahkflow hotstring list`)
├── Services/
│   ├── EnvVarAuthTokenProvider.cs        (new — replaces NullAuthTokenProvider)
│   ├── IHotstringsApiClient.cs           (new interface + local DTOs)
│   ├── HotstringsApiClient.cs            (new — typed HttpClient)
│   ├── ProfilesApiClient.cs              (new — impl of IProfilesApiClient interface)
│   ├── IAuthTokenProvider.cs             (existing — modified registration only)
│   ├── BearerTokenHandler.cs             (existing, unchanged)
│   └── IDownloadsApiClient.cs            (existing, unchanged)
└── Output/
    ├── HotstringTableFormatter.cs        (writes human table to TextWriter)
    └── HotstringJsonFormatter.cs         (writes JSON to TextWriter via System.Text.Json)

tests/AHKFlowApp.CLI.Tests/
├── Commands/Hotstrings/
│   ├── NewHotstringCommandTests.cs       (unit: parsing, flag combos, error cases)
│   └── ListHotstringCommandTests.cs      (unit: query params, filtering, output switches)
├── Output/
│   ├── HotstringTableFormatterTests.cs   (column layout, truncation, profile names)
│   └── HotstringJsonFormatterTests.cs    (camelCase, indented output)
├── Services/
│   └── EnvVarAuthTokenProviderTests.cs   (env var reading, error message)
└── Integration/
    └── HotstringCliIntegrationTests.cs   (end-to-end with CustomWebApplicationFactory + Testcontainers)
```

### Key design decisions

1. **No Application dependency** — CLI stays independent of `AHKFlowApp.Application` (business logic). DTOs duplicated locally as records (matches existing `ProfileSummary`/`DownloadResult` pattern from scaffold). Preserves Clean Architecture inward dependency rule.

2. **DI via command handler** — Commands receive `IServiceProvider` from `RootCli.Build()`, resolve clients at handler execution time (no service-locator anti-pattern; matches 017 scaffold).

3. **Text output via `TextWriter`** — Use `System.CommandLine` 3.0 preview API: `parseResult.Configuration.Output`/`.Error` are `TextWriter` properties. Formatters accept `TextWriter`, tests inject `StringWriter`. No custom `IConsoleOutput` interface.

4. **Profile name resolution** — CLI users pass profile *names* (e.g., `--profile work`), not GUIDs. `ListHotstringCommand` calls `IProfilesApiClient.ListAsync()` once, builds id→name map, looks up in `new` command and displays names in `list` table. Adds one round-trip per `list`; trade-off accepted for friendliness.

5. **Exit codes** — Minimal: `0` success, `1` client/server/logic error, `2` auth error. All errors printed to stderr with RFC 9457 problem details when available.

6. **Auth via environment variable** — `EnvVarAuthTokenProvider` reads `AHKFLOW_TOKEN` env var. Throws `NotAuthenticatedException` with message naming the env var if unset. Replaces `NullAuthTokenProvider` registration. Item 029 will swap in MSAL provider.

## Commands

### `ahkflow hotstring new`

**Purpose:** Create a new hotstring.

**Signature:**
```
ahkflow hotstring new --trigger <text> --replacement <text> [--profile <name>] […options] [--json]
```

**Flags:**

| Name | Short | Type | Required | Default | Notes |
|------|-------|------|----------|---------|-------|
| `--trigger` | `-t` | string | yes | — | Abbreviation to expand. Mapped to API `Trigger`. |
| `--replacement` | `-r` | string | yes | — | Text to insert. Mapped to API `Replacement`. |
| `--profile` | `-p` | string | no | — | Profile name (repeatable). Resolves to Guid(s). Empty list ⇒ `AppliesToAllProfiles=true`. Non-empty ⇒ `false` + `ProfileIds=[…]`. |
| `--no-ending-char` | — | bool | no | false | Sets `IsEndingCharacterRequired=false` (API default is true). |
| `--inside-word` | — | bool | no | false | Sets `IsTriggerInsideWord=true`. |
| `--json` | — | bool | no | false | Emit response as JSON instead of human summary. |

**Behavior:**
- Posts `CreateHotstringDto` to `POST /api/v1/hotstrings`.
- On success (201): prints `Created hotstring <id> ('<trigger>')` to stdout; exits 0. With `--json`, prints full `HotstringDto`.
- On validation error (400): prints RFC 9457 ProblemDetails to stderr; exits 1.
- On duplicate trigger (409): prints conflict error to stderr; exits 1.
- On unknown profile name: prints "Profile '<name>' not found" to stderr; exits 1.
- On auth failure: prints "Not signed in. Set AHKFLOW_TOKEN…" to stderr; exits 2.
- On server/network error: prints problem details to stderr; exits 1.

**Examples:**
```bash
# All profiles, defaults
ahkflow hotstring new -t btw -r "by the way"
# Created hotstring 7f3... ('btw')

# Specific profiles, custom flags
ahkflow hotstring new -t omw -r "on my way" --profile work --profile personal --no-ending-char
# Created hotstring 9a2... ('omw')

# JSON output
ahkflow hotstring new -t ty -r "thank you" --json
# {
#   "id": "3d4f...",
#   "profileIds": [],
#   "appliesToAllProfiles": true,
#   "trigger": "ty",
#   …
# }
```

### `ahkflow hotstring list`

**Purpose:** List hotstrings for the current user, optionally filtered.

**Signature:**
```
ahkflow hotstring list [--profile <name>] [--search <text>] [--page <n>] [--page-size <n>] [--json]
```

**Flags:**

| Name | Short | Type | Required | Default | Notes |
|------|-------|------|----------|---------|-------|
| `--profile` | `-p` | string | no | — | Filter by profile name (single value, resolved to Guid). If omitted, shows all. |
| `--search` | `-s` | string | no | — | LIKE-match on trigger or replacement. |
| `--page` | — | int | no | 1 | Page number (1-indexed). |
| `--page-size` | — | int | no | 50 | Items per page (1–200). |
| `--json` | — | bool | no | false | Emit response as JSON instead of human table. |

**Behavior:**
- GETs `/api/v1/hotstrings?profileId=<guid>&search=<text>&page=<n>&pageSize=<n>`.
- On success (200): prints human table (default) or JSON array.
- Profile names in table column are resolved via a preliminary `GET /api/v1/profiles` call (single round-trip). If a profile ID has no name in the response, falls back to `<id>` literal.
- Pagination footer shown when results span multiple pages.
- On unknown profile name: prints "Profile '<name>' not found" to stderr; exits 1.
- On validation error (400 — invalid page/pageSize): prints error to stderr; exits 1.
- On auth failure: prints "Not signed in. Set AHKFLOW_TOKEN…" to stderr; exits 2.

**Output format (human, default):**

```
TRIGGER  REPLACEMENT          PROFILES                  UPDATED
btw      by the way           all                       2026-05-08 14:23:11
omw      on my way            work                      2026-05-07 09:14:02
sig      Best regards, …      work, personal            2026-05-07 09:13:48
ty       thank you, very …    work, personal, side-proj 2026-05-06 18:02:55
many     covers many profs    work, personal, side-proj +2 more 2026-05-05 10:11:22

Page 1/3 (showing 5 of 127) — use --page 2 for next
```

**Formatting rules:**
- Column widths: `Trigger` ≤20, `Replacement` ≤40, `Profiles` ≤24, `Updated` ≤10 (fixed).
- Truncate long values with `…` (ellipsis).
- `Updated` column: local date/time in `yyyy-MM-dd HH:mm:ss` format (via `DateTimeOffset.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")`).
- `Profiles` column: `all` if `AppliesToAllProfiles=true`; otherwise comma-joined profile names (first 3, then `+N more` if count > 3). If no profile names resolved, show `<n> profiles`.
- Footer line (e.g., `Page 1/3…`) only when `TotalPages > 1`.
- Empty result: print "No hotstrings found." to stdout; exit 0.

**Output format (JSON):**

```json
{
  "items": [
    {
      "id": "7f3f...",
      "profileIds": [],
      "appliesToAllProfiles": true,
      "trigger": "btw",
      "replacement": "by the way",
      "isEndingCharacterRequired": true,
      "isTriggerInsideWord": true,
      "createdAt": "2026-05-08T14:23:11Z",
      "updatedAt": "2026-05-08T14:23:11Z"
    },
    …
  ],
  "page": 1,
  "pageSize": 50,
  "totalCount": 127
}
```

- Camel-case via `System.Text.Json` default (`JsonSerializerOptions.Web`).
- Pretty-printed (`WriteIndented = true`).
- Full `PagedList<HotstringDto>` shape serialized.

**Examples:**
```bash
# List all
ahkflow hotstring list
# (table output)

# Filter by profile
ahkflow hotstring list --profile work
# (table showing only work-profile hotstrings)

# Search
ahkflow hotstring list --search "say"
# (table showing triggers/replacements matching "say")

# Pagination
ahkflow hotstring list --page 2 --page-size 10

# JSON
ahkflow hotstring list --json | jq '.items[].trigger'
```

## DTOs (CLI-local)

All DTOs are records defined in `Services/` alongside their client interface.

```csharp
// IHotstringsApiClient
public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);

public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}

// IProfilesApiClient (reused from 017)
public sealed record ProfileSummary(Guid Id, string Name);
```

## Testing strategy

### Unit tests

**`EnvVarAuthTokenProviderTests`**
- Token returned when `AHKFLOW_TOKEN` env var is set (non-empty).
- `NotAuthenticatedException` thrown when env var is unset, with message: "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token."
- Exception message tests ensure message quality.

**`HotstringTableFormatterTests`**
- Column truncation: long trigger/replacement/profile names.
- Profile name resolution: `id → name` map built from `List<ProfileSummary>`, applied to `ProfileIds[]` and `AppliesToAllProfiles` flag.
- `+N more` suffix when profiles > 3.
- Local time formatting: `DateTimeOffset` converted to `yyyy-MM-dd HH:mm:ss`.
- Footer rendering: shown when `TotalPages > 1`, hidden when `TotalPages <= 1`.
- Empty result: prints "No hotstrings found."
- Use `StringWriter` to capture output for assertions.

**`HotstringJsonFormatterTests`**
- Full `PagedList<HotstringDto>` serialized to valid JSON.
- Camel-case keys (`appliesToAllProfiles`, not `AppliesToAllProfiles`).
- Indented output.
- Dates in ISO-8601 format (from API JSON, unchanged).

**`NewHotstringCommandTests`**
- Required flags `-t` and `-r` enforced by System.CommandLine (framework responsibility; no explicit test needed, but document in test comments).
- `--profile` omitted ⇒ `AppliesToAllProfiles=true`, `ProfileIds=[]` sent to API.
- `--profile work --profile personal` ⇒ resolved to Guids, `AppliesToAllProfiles=false`, `ProfileIds=[guid1, guid2]` sent.
- Unknown profile name ⇒ `ProfileNotFoundException` caught, stderr message "Profile 'nope' not found", exit 1.
- `--no-ending-char` ⇒ `IsEndingCharacterRequired=false` sent.
- `--inside-word` ⇒ `IsTriggerInsideWord=true` sent.
- `--json` flag ⇒ JSON formatter used instead of human summary.
- API validation error (400, ProblemDetails) ⇒ stderr, exit 1.
- API conflict (409, duplicate trigger) ⇒ stderr, exit 1.
- Auth error ⇒ stderr "Not signed in…", exit 2.
- Success ⇒ stdout "Created hotstring <id> ('<trigger>')", exit 0.
- Use `NSubstitute` for `IHotstringsApiClient`, `IProfilesApiClient`.
- Use `StringWriter` for `parseResult.Configuration.Output/Error` to capture output.

**`ListHotstringCommandTests`**
- Query parameters plumbed: `profileId`, `search`, `page`, `pageSize`.
- `--profile work` ⇒ profiles API queried, name resolved to Guid, passed as `profileId` query param.
- `--search btw` ⇒ `search=btw` query param.
- `--page 2 --page-size 25` ⇒ `page=2&pageSize=25` query params.
- `--json` ⇒ JSON formatter; default ⇒ table formatter.
- Unknown profile name ⇒ stderr, exit 1.
- Validation error (bad page/pageSize) ⇒ stderr, exit 1.
- Empty result (0 items) ⇒ "No hotstrings found." to stdout.
- Auth error ⇒ exit 2.
- Success ⇒ formatted output (table or JSON) to stdout, exit 0.

### Integration tests

**Setup:** `[Collection("WebApi")]` shared with API tests, reusing `SqlContainerFixture` and `CustomWebApplicationFactory.WithTestAuth()`.

**Test helper:** Custom `DelegatingHandler` to inject `X-Test-Oid`/`X-Test-Email` headers (bypasses MSAL, allows test auth to succeed).

**Test fixture:**
```csharp
var factory = new CustomWebApplicationFactory(sqlFixture)
    .WithTestAuth(u => u
        .WithOid(testUserId)
        .WithEmail("test@example.com"));

// Replace CLI's DI container to inject factory.CreateClient()
// Replace IAuthTokenProvider with stub returning "test-token"
```

**Test cases:**

1. **Happy path — create:**
   - `hotstring new -t btw -r "by the way"` → 201, hotstring in DB, stdout has `Created …`.

2. **Happy path — list:**
   - Seed 3 hotstrings, run `hotstring list` → table output with 3 rows.

3. **Create with profile:**
   - Seed profile "work", run `hotstring new -t omw -r x --profile work` → hotstring linked to profile.

4. **List filtered by profile:**
   - Seed hotstrings in "work" and "personal" profiles, run `hotstring list --profile work` → only work hotstrings.

5. **Duplicate trigger:**
   - Create hotstring, create again with same trigger → exit 1, 409 problem details to stderr.

6. **Unknown profile:**
   - Run `hotstring new -t x -r y --profile nope` → exit 1, "Profile 'nope' not found" to stderr.

7. **Validation error:**
   - Run `hotstring new -t "" -r ""` → exit 1, validation error from API to stderr.

8. **JSON output:**
   - `hotstring list --json` → valid JSON, parseable to PagedList<HotstringDto>.
   - `hotstring new -t x -r y --json` → valid JSON HotstringDto.

9. **Pagination:**
   - Seed 150 hotstrings, run `hotstring list --page-size 50 --page 2` → second page items shown.

10. **Search:**
    - Seed hotstrings with varied triggers/replacements, run `hotstring list --search "bye"` → filtered.

11. **Auth failure:**
    - Clear `AHKFLOW_TOKEN` env var, run any command → exit 2, "Not signed in…" to stderr.

## Scope: additions from backlog 028

Item 017 deferred `IProfilesApiClient` registration and HttpClient wiring to 028. We move forward into 018 because profile-name resolution is critical for UX:

- **New in 018:** `ProfilesApiClient` implementation, `AddHttpClient<IProfilesApiClient, ProfilesApiClient>` registration in `Program.cs`.
- **Update 028:** Remove "wire ProfilesApiClient" from acceptance criteria; scope remains: `download ahk` command, `--profile` argument specific to that command, bulk zip download (027).

## Scope: intentional exclusions

- No `update`, `delete`, `get-by-id` CLI commands (backlog 018 specifies only create/list).
- No `login`/`logout` — item 029.
- No token caching or refresh — item 029.
- No `--token` CLI flag — env var only.
- No localization of error messages.
- No bulk hotstring import / file input.

## Risk mitigations

| Risk | Mitigation |
|------|-----------|
| Env var token leaks into shell history | Document in README: use `$env:AHKFLOW_TOKEN = "…"` (PowerShell, ephemeral) or dotenv file; show how to obtain token. |
| Profile renamed/deleted between resolve and create | Acceptable — API enforces; error surfaced to user. No client-side cache. |
| Table width on small terminals | Don't detect `Console.WindowWidth` (breaks on pipes). Fixed column caps + truncation handle small widths. |
| JSON shape coupling to API | CLI defines local DTOs (mirrors API). Integration tests deserialize real API responses into CLI types; catches drift early. |
| Profile name resolution adds latency | One round-trip per `list` / `new` command. Acceptable trade-off for friendliness. |

## Dependencies

- **Existing:** `System.CommandLine` 3.0 preview, Serilog, Microsoft.Extensions.Http.Resilience, System.Text.Json.
- **New:** None (all .NET BCL).
- **On 012 (auth):** API endpoints require `[Authorize]` + `access_as_user` scope; token validation happens server-side.
- **On 013 (Hotstrings API):** REST endpoints `GET/POST/PUT/DELETE /api/v1/hotstrings`, `GET /api/v1/profiles`.
- **On 015 (validation):** API enforces FluentValidation; CLI surfaces errors.

## Backlog updates required

After merge:
- Update **017** notes: `IAuthTokenProvider` registration replaced with `EnvVarAuthTokenProvider`; auth flow no longer stubbed.
- Update **028** notes: Profiles client impl moved to 018; only download command remains in 028 scope.
