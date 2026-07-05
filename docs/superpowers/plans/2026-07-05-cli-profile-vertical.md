# CLI Profile Vertical Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New `ahkflow profile new|list|get|update|delete` command group, extending the existing internal `IProfilesApiClient` (currently list-only) without breaking its consumers. (Spec: [CLI Production Readiness](../specs/2026-07-04-cli-production-readiness-design.md), plan 4.)

**Architecture:** `Commands/Profiles/*` mirroring the hotstring vertical. The existing `IProfilesApiClient.ListAsync → ProfileSummary(Id, Name)` is consumed by hotstring/hotkey/download commands for name resolution — KEEP it unchanged; add full-DTO methods alongside. Addressed by id or (unique per user) name.

**Tech Stack:** .NET 10, System.CommandLine, typed HttpClient (`AddCliApiResilience`), xUnit + FluentAssertions.

## Global Constraints

- Feature branch `feature/cli-profile-vertical`, PR to `main`.
- Verification trio per task: `dotnet build AHKFlowApp.slnx` · `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` · `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Exit codes 0/1/2/3; data → stdout, diagnostics → stderr; `--json` everywhere; no prompts, no color.
- Error handling: `Services/CliErrors.RunAsync` if plan 1 landed; else copy the `ListHotstringCommand.cs:81-120` catch chain (plan 5 consolidates).
- API surface (verified): `GET api/v1/profiles` → `IReadOnlyList<ProfileDto>` (NOT paged), `GET/PUT/DELETE api/v1/profiles/{id}`, `POST api/v1/profiles`. Backend records: `ProfileDto(Id, Name, IsDefault, HeaderTemplate, FooterTemplate, CreatedAt, UpdatedAt)`, `CreateProfileDto(Name, HeaderTemplate?, FooterTemplate?, IsDefault=false)`, `UpdateProfileDto(Name, HeaderTemplate, FooterTemplate, IsDefault)`.
- Existing consumers of `ProfileSummary` must keep compiling untouched.
- No backend changes.

## Resume instructions

`git log --oneline -10` shows landed commits; unchecked boxes remain. Order: T1 → T2 → T3 → T4.

---

### Task 1: Extend IProfilesApiClient

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Services/IProfilesApiClient.cs`, `Services/ProfilesApiClient.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/ProfilesApiClientTests.cs` (new, stub-handler style)

**Interfaces (produces) — added alongside the untouched `ListAsync`/`ProfileSummary`:**

```csharp
Task<IReadOnlyList<ProfileDto>> ListFullAsync(CancellationToken ct);                 // GET api/v1/profiles
Task<ProfileDto> CreateAsync(CreateProfileDto input, CancellationToken ct);         // POST api/v1/profiles
Task<ProfileDto> GetAsync(Guid id, CancellationToken ct);                            // GET api/v1/profiles/{id}
Task<ProfileDto> UpdateAsync(Guid id, UpdateProfileDto input, CancellationToken ct); // PUT api/v1/profiles/{id}
Task DeleteAsync(Guid id, CancellationToken ct);                                     // DELETE api/v1/profiles/{id}

public sealed record ProfileDto(Guid Id, string Name, bool IsDefault,
    string HeaderTemplate, string FooterTemplate, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);
public sealed record CreateProfileDto(string Name, string? HeaderTemplate = null,
    string? FooterTemplate = null, bool IsDefault = false);
public sealed record UpdateProfileDto(string Name, string HeaderTemplate, string FooterTemplate, bool IsDefault);
```

(The existing private `ProfileItem` in `ProfilesApiClient` can be replaced by `ProfileDto` internally as long as `ListAsync`'s `ProfileSummary` return shape is preserved.)

- [ ] **Step 1:** Client tests first (all five methods, error mapping, 204 delete; `ListAsync` still returns summaries). **Step 2:** implement. **Step 3:** verification trio + full CLI test project (proves no consumer broke). **Commit** `feat(cli): full profiles api client`

### Task 2: Formatters + resolver

**Files:**
- Create: `Output/ProfileTableFormatter.cs` (columns: Name, Default (`*` marker), Created, Updated — templates are multi-line, detail-only), `Output/ProfileJsonFormatter.cs`, `Output/ProfileDetailFormatter.cs` (key-value incl. HeaderTemplate/FooterTemplate rendered as indented blocks)
- Create: `Commands/Profiles/ProfileResolver.cs` — `static Task<ProfileDto?> ResolveAsync(IProfilesApiClient client, string target, CancellationToken ct)`: Guid → `GetAsync` (404 → null); else `ListFullAsync` + exact `OrdinalIgnoreCase` name match
- Test: matching `*Tests.cs` for each

- [ ] **Step 1:** Tests first (default marker, template block rendering, resolver id/name/miss). **Step 2:** implement. **Step 3:** verification trio. **Commit** `feat(cli): profile formatters + resolver`

### Task 3: Commands (new/list/get/update/delete) + group wiring

**Files:**
- Create: `Commands/Profiles/ProfileCommand.cs` (group), `NewProfileCommand.cs`, `ListProfileCommand.cs`, `GetProfileCommand.cs`, `UpdateProfileCommand.cs`, `DeleteProfileCommand.cs`
- Modify: `Commands/RootCli.cs` — add `ProfileCommand.Build(services)`
- Test: one `*Tests.cs` per command under `Commands/Profiles/`

**Surfaces:**
- `new --name/-n <name>` (required) `[--header-file <path>] [--footer-file <path>] [--default] [--json]` — template content is read from files (templates are multi-line; inline flags would be unusable). Missing file → stderr + exit 2.
- `list [--json]` — no paging (API list isn't paged).
- `get <id|name> [--json]` — detail formatter; miss → `Profile '<target>' not found.` exit 2.
- `update <id|name> [--name/-n] [--header-file] [--footer-file] [--default true|false]` — ≥1 flag required else `Nothing to update.` exit 2; read-modify-write: resolve → overlay provided flags → `UpdateAsync` with full `UpdateProfileDto`.
- `delete <id|name>` — success `Deleted profile '<name>' (<id>).`; API-side rules (e.g. default/last-profile protection) surface as exit 2 with the API's message.

All bodies wrapped per Global Constraints error-handling rule.

- [ ] **Step 1:** Unit tests per command (asserted request bodies; file-based template read incl. missing-file error; single-field update preserves other fields; not-found → 2; `--json` paths). **Step 2:** implement all five + wiring. **Step 3:** verification trio. **Commit** `feat(cli): profile commands`

### Task 4: Integration tests + smoke

**Files:** create `tests/AHKFlowApp.CLI.Tests/Integration/ProfileCliIntegrationTests.cs`

- [ ] **Step 1:** Flow: new → list shows it → get by name → update rename + `--default true` → get reflects → delete → get exits 2. Plus: duplicate-name create → 2; attempt to delete whatever the API protects (if any) asserts the surfaced message.
- [ ] **Step 2:** Manual smoke against local API; outputs into PR.
- [ ] **Step 3:** Full solution tests + trio. **Commit** `test(cli): profile vertical integration flows`

---

## Final verification

- [ ] `ahkflow profile --help` lists all five; `ahkflow --help` shows the group
- [ ] Existing hotstring/download commands still resolve `--profile` names (their tests green — proves `ProfileSummary` untouched)
- [ ] Verification trio + full solution tests green
