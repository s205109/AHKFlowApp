# CLI Hotkey Vertical Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New `ahkflow hotkey new|list|get|update|delete` command group with typed API client, formatters, and full tests. (Spec: [CLI Production Readiness](../specs/2026-07-04-cli-production-readiness-design.md), plan 2.)

**Architecture:** Mirror the hotstring vertical exactly: `Commands/Hotkeys/*` static `Build(IServiceProvider)` commands wired under a `hotkey` group in `RootCli`, a `Services/IHotkeysApiClient` typed client with CLI-local DTO mirrors, `Output/Hotkey*Formatter`. Hotkeys are addressed by **id only** (spec decision #2 — no unique single field).

**Tech Stack:** .NET 10, System.CommandLine, typed HttpClient (`AddCliApiResilience`), xUnit + FluentAssertions.

## Global Constraints

- Feature branch `feature/cli-hotkey-vertical`, PR to `main`.
- Verification trio per task: `dotnet build AHKFlowApp.slnx` · `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` · `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Exit codes: 0 / 1 config-server-transport / 2 user error (incl. 404) / 3 auth. Data → stdout, diagnostics → stderr, `--json` everywhere, no prompts, no color.
- Error handling: use `Services/CliErrors.RunAsync` if plan 1 landed; otherwise copy the catch chain from `Commands/Hotstrings/ListHotstringCommand.cs:81-120` verbatim per command and note it for plan 5 consolidation.
- `--category` flags are NOT in this plan (plan 5, needs plan 3's client).
- **Soft dependency:** cleanup plan A Task 2 fixes the Hotkey ProfileIds `ValidationError` missing its `Identifier`; if not yet landed, the CLI surfaces the raw message — acceptable, note in PR.
- Backend `CreateHotkeyDto` defaults `AppliesToAllProfiles=false` and validation requires ≥1 profile when false — so `hotkey new` REQUIRES `--profile` or `--all-profiles` (opposite of hotstrings; validate client-side for a clean message).
- No backend changes.

## Resume instructions

`git log --oneline -10` shows landed commits; unchecked boxes remain. Order: T1 (client) → T2 (formatters) → T3-T6 (commands) → T7 (integration).

---

### Task 1: IHotkeysApiClient + DTO mirrors

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/IHotkeysApiClient.cs`, `Services/HotkeysApiClient.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs` — register after the hotstrings client (line ~54), same pattern:

```csharp
builder.Services.AddHttpClient<IHotkeysApiClient, HotkeysApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddCliApiResilience("hotkeys");
```

- Test: `tests/AHKFlowApp.CLI.Tests/Services/HotkeysApiClientTests.cs` (stub-handler style like `DownloadsApiClientTests.cs`)

**Interfaces (produces) — CLI-local mirrors of the backend records (`src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs`), enum as string:**

```csharp
public interface IHotkeysApiClient
{
    Task<HotkeyDto> CreateAsync(CreateHotkeyDto input, CancellationToken ct);          // POST api/v1/hotkeys
    Task<PagedList<HotkeyDto>> ListAsync(Guid? profileId, string? search, int page, int pageSize, CancellationToken ct); // GET api/v1/hotkeys
    Task<HotkeyDto> GetAsync(Guid id, CancellationToken ct);                            // GET api/v1/hotkeys/{id}
    Task<HotkeyDto> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct);  // PUT api/v1/hotkeys/{id}
    Task DeleteAsync(Guid id, CancellationToken ct);                                    // DELETE api/v1/hotkeys/{id}
}

public sealed record HotkeyDto(Guid Id, Guid[] ProfileIds, bool AppliesToAllProfiles, string Description,
    string Key, bool Ctrl, bool Alt, bool Shift, bool Win, string Action, string Parameters,
    DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, Guid[] CategoryIds);

public sealed record CreateHotkeyDto(string Description, string Key, bool Ctrl = false, bool Alt = false,
    bool Shift = false, bool Win = false, string Action = "Send", string Parameters = "",
    Guid[]? ProfileIds = null, bool AppliesToAllProfiles = false, Guid[]? CategoryIds = null);

public sealed record UpdateHotkeyDto(string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win,
    string Action, string Parameters, Guid[]? ProfileIds, bool AppliesToAllProfiles, Guid[]? CategoryIds = null);
```

`Action` is a string mirror of backend enum `HotkeyAction { Send, Run }` — verify the API serializes enums as strings (check `JsonSerializerOptions`/`JsonStringEnumConverter` in `src/Backend/AHKFlowApp.API/Program.cs`); if it serializes numbers, use `int` and convert at the formatter instead.

- [ ] **Step 1:** Client tests first (create POST body shape, list query-string incl. `profileId`/`search`/`page`/`pageSize` exactly like `HotstringsApiClient.ListAsync`, get/update/delete status handling, non-success → `ApiException`).
- [ ] **Step 2:** Implement, mirroring `HotstringsApiClient` method-for-method (same `JsonSerializerOptions.Web`, same empty-body `InvalidOperationException` messages with "hotkey" wording). Register in `Program.cs`.
- [ ] **Step 3:** Verification trio. **Commit** `feat(cli): hotkeys api client`

### Task 2: Formatters

**Files:**
- Create: `Output/HotkeyTableFormatter.cs`, `Output/HotkeyJsonFormatter.cs`, `Output/HotkeyDetailFormatter.cs`
- Test: `Output/HotkeyTableFormatterTests.cs`, `Output/HotkeyJsonFormatterTests.cs`, `Output/HotkeyDetailFormatterTests.cs`

**Conventions:** mirror the Hotstring formatters' signatures (`WritePage(TextWriter, PagedList<HotkeyDto>, IReadOnlyDictionary<Guid,string> idToName)` / `Write(...)`) and JSON casing. Key-combo display helper `static string Combo(HotkeyDto h)` → `"Ctrl+Alt+K"` (modifiers in Ctrl, Alt, Shift, Win order, then Key). Table columns: Combo, Description, Action, Profiles. Detail formatter: key-value lines incl. Parameters, timestamps, profile names.

- [ ] **Step 1:** Formatter tests first (combo composition incl. no-modifier case; table renders; JSON round-trips fields). **Step 2:** implement. **Step 3:** verification trio. **Commit** `feat(cli): hotkey formatters`

### Task 3: `ahkflow hotkey new` + group wiring

**Files:**
- Create: `Commands/Hotkeys/HotkeyCommand.cs` (group, mirrors `HotstringCommand.cs`), `Commands/Hotkeys/NewHotkeyCommand.cs`
- Modify: `Commands/RootCli.cs` — add `HotkeyCommand.Build(services)` after `HotstringCommand`
- Test: `Commands/Hotkeys/NewHotkeyCommandTests.cs`

**Flags:** `--description/-d` (required), `--key/-k` (required), `--ctrl`, `--alt`, `--shift`, `--win` (bool switches), `--action` (`Send`|`Run`, default `Send`, validate client-side with a clear message), `--parameters` (default `""`), `--profile/-p` (repeatable, name→id via `IProfilesApiClient` exactly as `NewHotstringCommand` resolves; unknown name → stderr listing available, exit 2), `--all-profiles`, `--json`.
**Rule:** exactly one of `--profile`/`--all-profiles` must be given (backend requires ≥1 profile when not all-profiles) — clear stderr message, exit 2.

- [ ] **Step 1:** Unit tests: happy path (POST body asserted), missing profile rule, bad `--action` value, profile-name resolution failure. **Step 2:** implement (wrapped in `CliErrors.RunAsync` or copied chain per Global Constraints). **Step 3:** verification trio. **Commit** `feat(cli): hotkey new`

### Task 4: `ahkflow hotkey list`

**Files:** create `Commands/Hotkeys/ListHotkeyCommand.cs` (+ wire in group); test `Commands/Hotkeys/ListHotkeyCommandTests.cs`

Mirror `ListHotstringCommand` exactly: `--profile/-p` name filter, `--search/-s/--grep/-g`, `--page` (default 1), `--page-size` (default 50), `--json`; profile-name→id resolution and the lazy id→name map for table rendering.

- [ ] **Step 1:** Unit tests (filter resolution, table vs json paths, unknown profile → 2). **Step 2:** implement. **Step 3:** verification trio. **Commit** `feat(cli): hotkey list`

### Task 5: `ahkflow hotkey get <id>` and Task 6: `update <id>` / `delete <id>`

**Files:**
- Create: `Commands/Hotkeys/GetHotkeyCommand.cs`, `UpdateHotkeyCommand.cs`, `DeleteHotkeyCommand.cs` (+ wire in group)
- Test: matching `*Tests.cs` per command

**Addressing:** id only; non-Guid argument → stderr `Hotkeys are addressed by id. Run 'ahkflow hotkey list' to find it.` exit 2.
**Update flags (all optional, ≥1 required):** `--description/-d`, `--key/-k`, `--ctrl true|false`, `--alt true|false`, `--shift true|false`, `--win true|false` (explicit-value bools so a modifier can be turned OFF), `--action`, `--parameters`, `--profile/-p` repeatable (replaces set), `--all-profiles`. Read-modify-write: `GetAsync` → overlay → `UpdateAsync` full DTO (preserves `CategoryIds`). `--profile`/`--all-profiles` mutually exclusive → 2.
**Delete:** success `Deleted hotkey '<combo>' (<id>).`, no prompt.

- [ ] **Step 1:** Unit tests per command: get by id + `--json`; update single-field preserves the rest (assert PUT body); modifier turn-off (`--ctrl false`); mutual exclusion; non-Guid arg → 2; delete happy + 404 → 2. **Step 2:** implement all three. **Step 3:** verification trio. **Commit** `feat(cli): hotkey get/update/delete`

### Task 7: Integration tests + smoke

**Files:** create `tests/AHKFlowApp.CLI.Tests/Integration/HotkeyCliIntegrationTests.cs` (mirror `HotstringCliIntegrationTests.cs` harness)

- [ ] **Step 1:** Flow: new (with `--profile`) → list shows it → get → update description + turn off a modifier → get reflects both → delete → get exits 2. Assert exit codes + validation-failure path (duplicate combo → 2 with conflict message).
- [ ] **Step 2:** Manual smoke against local API (`Auth:UseTestProvider`); outputs into PR.
- [ ] **Step 3:** Full solution `dotnet test --configuration Release` + trio. **Commit** `test(cli): hotkey vertical integration flows`

---

## Final verification

- [ ] `ahkflow hotkey --help` lists new/list/get/update/delete; `ahkflow --help` shows the group
- [ ] Verification trio + full solution tests green
- [ ] PR notes whether cleanup plan A Task 2 (ValidationError Identifier) was in effect
