# CLI Hotstring Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the hotstring CLI vertical: `ahkflow hotstring get|update|delete`, `--description` parity on `new`, and a shared command error-handler that plans 2-4 reuse. (Spec: [CLI Production Readiness](../specs/2026-07-04-cli-production-readiness-design.md), plan 1.)

**Architecture:** Extend the existing vertical in place — `Commands/Hotstrings/`, `Services/IHotstringsApiClient`, `Output/Hotstring*Formatter`. New commands address a hotstring by id or (unique) trigger. Updates are read-modify-write: fetch current DTO, overlay provided flags, PUT the full DTO.

**Tech Stack:** .NET 10, System.CommandLine, typed HttpClient (`AddCliApiResilience`), xUnit + FluentAssertions.

## Global Constraints

- Feature branch `feature/cli-hotstring-completion`, PR to `main`.
- Verification trio per task: `dotnet build AHKFlowApp.slnx` · `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` · `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Exit-code contract (existing, keep): 0 success · 1 config/server/transport · 2 user error (validation, not-found, conflict) · 3 auth.
- Data on stdout, diagnostics on stderr. `--json` on every command. No color, no prompts (delete does NOT confirm — scriptable CLI).
- `--category` flags are NOT in this plan (land in plan 5, need the categories client from plan 3).
- No backend changes.

## Resume instructions

`git log --oneline -10` shows landed task commits; unchecked boxes remain. T1 (error handler) must land before T4-T6 (they use it). T2/T3 before T4-T6.

---

### Task 1: Extract shared command error-handler

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/CliErrors.cs`
- Modify: `Commands/Hotstrings/ListHotstringCommand.cs`, `Commands/Hotstrings/NewHotstringCommand.cs` (replace their catch chains)
- Test: `tests/AHKFlowApp.CLI.Tests/Services/CliErrorsTests.cs`

**Interfaces:**
- Produces: `static Task<int> CliErrors.RunAsync(TextWriter stderr, Func<Task<int>> action)` — used by every command in this plan and plans 2-4.

**Context:** `ListHotstringCommand.cs:81-120` and `NewHotstringCommand.cs` carry an identical ~40-line catch chain. Adding 18 commands would multiply it. One deliberate addition: `ApiException` 404 currently falls through to the generic clause (exit 1, "Server error (404)"); for get/update/delete a 404 is a user error → map 404 alongside 400/409 to exit 2.

- [ ] **Step 1: Write tests** for `RunAsync`: action returns 0 → 0; throws `NotAuthenticatedException` → 3 + message on stderr; `AuthConfigurationException` → 1; `ApiException(400/404/409)` → 2 + body; `ApiException(401)` → 3 + `AuthMessages.AuthenticationFailed`; `ApiException(503)` → 1; `HttpRequestException` → 1; `TimeoutRejectedException` → 1 + `ApiMessages.RequestTimedOut`. Run → FAIL (type missing).
- [ ] **Step 2: Implement** — the body is the existing catch chain from `ListHotstringCommand.cs:81-120` verbatim, wrapped, with `404` added to the `400 or 409` clause and the `CliApiFailureDetector.IsStoppedWebAppResponse` clause kept BEFORE the generic `ApiException` clause:

```csharp
public static class CliErrors
{
    public static async Task<int> RunAsync(TextWriter stderr, Func<Task<int>> action)
    {
        try { return await action(); }
        catch (NotAuthenticatedException ex) { await stderr.WriteLineAsync(ex.Message); return 3; }
        catch (AuthConfigurationException ex) { await stderr.WriteLineAsync(ex.Message); return 1; }
        catch (ApiException ex) when (ex.StatusCode is 400 or 404 or 409)
        { await stderr.WriteLineAsync(ex.Body ?? ex.Message); return 2; }
        catch (ApiException ex) when (ex.StatusCode == 401)
        { await stderr.WriteLineAsync(AuthMessages.AuthenticationFailed); return 3; }
        catch (ApiException ex) when (CliApiFailureDetector.IsStoppedWebAppResponse(ex))
        { await stderr.WriteLineAsync(ApiMessages.WebAppUnavailable); return 1; }
        catch (ApiException ex) { await stderr.WriteLineAsync(ex.Body ?? $"Server error ({ex.StatusCode})."); return 1; }
        catch (HttpRequestException ex) { await stderr.WriteLineAsync(ex.Message); return 1; }
        catch (Polly.Timeout.TimeoutRejectedException) { await stderr.WriteLineAsync(ApiMessages.RequestTimedOut); return 1; }
    }
}
```

- [ ] **Step 3: Refactor** `list` and `new` hotstring commands: `cmd.SetAction((parse, ct) => CliErrors.RunAsync(stderr, async () => { …existing body… }))` — inner logic unchanged. Note `stderr` comes from `parse.InvocationConfiguration.Error` inside the action.
- [ ] **Step 4: Run** all existing CLI tests → PASS (behavior preserved; the only intended delta is 404 → exit 2, which no existing test asserts — verify by grepping tests for `404`).
- [ ] **Step 5: Commit** `refactor(cli): shared CliErrors.RunAsync error handler`

### Task 2: Extend CLI DTO mirrors with Description + CategoryIds

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs` (the records live here)
- Modify: `Output/HotstringTableFormatter.cs`, `Output/HotstringJsonFormatter.cs` and their tests
- Test: `tests/AHKFlowApp.CLI.Tests/Output/*FormatterTests.cs`, `Commands/Hotstrings/NewHotstringCommandTests.cs`

**Context:** The CLI's `HotstringDto` mirror (IHotstringsApiClient.cs:15-24) omits `Description` and `CategoryIds` that the backend DTO carries; `CreateHotstringDto` mirror omits `Description`/`CategoryIds`. JSON deserialization currently drops them silently.

- [ ] **Step 1:** Add `string? Description` and `Guid[] CategoryIds` to the CLI `HotstringDto` record (positions matching backend: Description after Replacement, CategoryIds last; make it `Guid[]? CategoryIds = null` and normalize with `?? []` at use sites, or add it as required positional and fix construction sites). Add `string? Description = null` and `Guid[]? CategoryIds = null` to the CLI `CreateHotstringDto` (CategoryIds stays unused until plan 5 adds `--category`, but the mirror must already match the backend so plan 5 touches no client code).
- [ ] **Step 2:** Add `--description` (`-d`) option to `NewHotstringCommand`, passed through to the DTO. Table formatter: add a Description column only if it stays readable (existing column style decides); JSON formatter emits the new fields as-is.
- [ ] **Step 3:** Update/extend formatter + command tests: JSON output contains `description`; `new --description "note"` sends it (assert via the existing stub-handler harness in `Infrastructure/`).
- [ ] **Step 4:** Verification trio. **Commit** `feat(cli): hotstring description + category ids in DTO mirrors`

### Task 3: Client Get/Update/Delete

**Files:**
- Modify: `Services/IHotstringsApiClient.cs` + `Services/HotstringsApiClient.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/HotstringsApiClientTests.cs` (new — mirror `DownloadsApiClientTests.cs` stub-handler style)

**Interfaces (produces):**

```csharp
Task<HotstringDto> GetAsync(Guid id, CancellationToken ct);              // GET  api/v1/hotstrings/{id}
Task<HotstringDto> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct); // PUT api/v1/hotstrings/{id}
Task DeleteAsync(Guid id, CancellationToken ct);                          // DELETE api/v1/hotstrings/{id} (204)
```

plus a CLI mirror `UpdateHotstringDto(string Trigger, string Replacement, Guid[]? ProfileIds, bool AppliesToAllProfiles, bool IsEndingCharacterRequired, bool IsTriggerInsideWord, string? Description, Guid[]? CategoryIds)` matching the backend record.

- [ ] **Step 1:** Tests first (success deserialization, non-success → `ApiException` with status/body, delete tolerates 204 empty body). **Step 2:** implement following `HotstringsApiClient.CreateAsync`'s exact error pattern. **Step 3:** verification trio. **Step 4: Commit** `feat(cli): hotstrings client get/update/delete`

### Task 4: `ahkflow hotstring get <id|trigger>`

**Files:**
- Create: `Commands/Hotstrings/GetHotstringCommand.cs`; wire into `Commands/Hotstrings/HotstringCommand.cs`
- Create: `Output/HotstringDetailFormatter.cs` (key-value lines: Id, Trigger, Replacement, Description, Profiles (names), Options, Created, Updated) — JSON path reuses `HotstringJsonFormatter` conventions for a single object
- Test: `Commands/Hotstrings/GetHotstringCommandTests.cs`, `Output/HotstringDetailFormatterTests.cs`

**Resolution rule (spec decision #2, reuse in T5/T6):** argument `target`; if `Guid.TryParse(target, out var id)` → `GetAsync(id)`. Else resolve by trigger, **paging until found or exhausted** — the API caps `pageSize` at 200 and `search` is a substring match applied before paging, so the exact trigger can sit beyond page 1: loop `ListAsync(profileId: null, search: target, page: n, pageSize: 200)` for n = 1, 2, … while no exact `OrdinalIgnoreCase` match on `Trigger` and `result.HasNextPage`. No match after the last page → stderr `Hotstring '<target>' not found.` exit 2. Extract this as `private static` helper `ResolveAsync` in a new `Commands/Hotstrings/HotstringResolver.cs` so update/delete share it.

- [ ] **Step 1:** Unit tests: id path, trigger path, **trigger match on page 2** (stub returns a full 200-item page 1 without the target, then page 2 containing it), not-found → 2, `--json` emits single-object JSON. **Step 2:** implement (body wrapped in `CliErrors.RunAsync`). **Step 3:** verification trio. **Step 4: Commit** `feat(cli): hotstring get`

### Task 5: `ahkflow hotstring update <id|trigger>`

**Files:**
- Create: `Commands/Hotstrings/UpdateHotstringCommand.cs`; wire into `HotstringCommand.cs`
- Test: `Commands/Hotstrings/UpdateHotstringCommandTests.cs`

**Flags (all optional; at least one required or stderr `Nothing to update.` exit 2):** `--trigger/-t`, `--replacement/-r`, `--description/-d`, `--profile/-p` (repeatable, replaces the set, name-resolved like `new`), `--all-profiles`, `--ending-char true|false`, `--inside-word true|false`.

**Semantics (spec risk table):** resolve target → `GetAsync` current → overlay only provided flags → `UpdateAsync` with the FULL `UpdateHotstringDto` (unprovided fields keep current values, including `CategoryIds`). `--all-profiles` and `--profile` are mutually exclusive (stderr + exit 2).

- [ ] **Step 1:** Unit tests: single-field update preserves others (assert PUT body via stub handler); mutual-exclusion error; not-found → 2. **Step 2:** implement with `HotstringResolver` + `CliErrors.RunAsync`. **Step 3:** verification trio. **Step 4: Commit** `feat(cli): hotstring update`

### Task 6: `ahkflow hotstring delete <id|trigger>`

**Files:**
- Create: `Commands/Hotstrings/DeleteHotstringCommand.cs`; wire into `HotstringCommand.cs`
- Test: `Commands/Hotstrings/DeleteHotstringCommandTests.cs`

Success prints `Deleted hotstring '<trigger>' (<id>).` to stdout, exit 0. No confirmation prompt (scriptable; recycle bin exists server-side).

- [ ] **Step 1:** Unit tests: id path, trigger path, not-found → 2. **Step 2:** implement. **Step 3:** verification trio. **Step 4: Commit** `feat(cli): hotstring delete`

### Task 7: Integration tests + smoke

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/Integration/HotstringCliIntegrationTests.cs` (follow its existing harness exactly)

- [ ] **Step 1:** Add integration flows: create → get (by trigger) → update replacement → get shows new value → delete → get exits 2. Assert exit codes and stdout/stderr routing.
- [ ] **Step 2:** Manual smoke against local API (`Auth:UseTestProvider` path per README): run each new command once; paste outputs into the PR description.
- [ ] **Step 3:** Full verification trio + `dotnet test --configuration Release` (whole solution). **Commit** `test(cli): hotstring get/update/delete integration flows`

---

## Final verification

- [ ] `ahkflow hotstring --help` lists new/list/get/update/delete
- [ ] Verification trio green; full solution test run green
- [ ] PR: single concern, includes smoke outputs
