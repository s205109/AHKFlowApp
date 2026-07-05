# CLI Category Vertical Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New `ahkflow category new|list|get|update|delete` command group with typed API client, formatters, and full tests. (Spec: [CLI Production Readiness](../specs/2026-07-04-cli-production-readiness-design.md), plan 3.)

**Architecture:** Smallest vertical — a category is `(Id, Name, CreatedAt, UpdatedAt)`. Mirror the hotstring vertical: `Commands/Categories/*`, `Services/ICategoriesApiClient`, `Output/Category*Formatter`. Addressed by id or (unique per user) name.

**Tech Stack:** .NET 10, System.CommandLine, typed HttpClient (`AddCliApiResilience`), xUnit + FluentAssertions.

## Global Constraints

- Feature branch `feature/cli-category-vertical`, PR to `main`.
- Verification trio per task: `dotnet build AHKFlowApp.slnx` · `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` · `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Exit codes 0/1/2/3 as per the hotstring vertical; data → stdout, diagnostics → stderr; `--json` everywhere; no prompts, no color.
- Error handling: `Services/CliErrors.RunAsync` if plan 1 landed; else copy the `ListHotstringCommand.cs:81-120` catch chain per command (plan 5 consolidates).
- API surface (verified): `GET api/v1/categories?search=&page=&pageSize=` → `PagedList<CategoryDto>` (lazily seeds defaults on first call), `GET/PUT/DELETE api/v1/categories/{id}`, `POST api/v1/categories`. Create/Update DTOs carry only `Name`.
- No backend changes.

## Resume instructions

`git log --oneline -10` shows landed commits; unchecked boxes remain. Order: T1 → T2 → T3 → T4.

---

### Task 1: ICategoriesApiClient + mirrors + DI

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/ICategoriesApiClient.cs`, `Services/CategoriesApiClient.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs` — register like the others: `.AddCliApiResilience("categories")`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/CategoriesApiClientTests.cs` (stub-handler style)

**Interfaces (produces):**

```csharp
public interface ICategoriesApiClient
{
    Task<CategoryDto> CreateAsync(CreateCategoryDto input, CancellationToken ct);       // POST api/v1/categories
    Task<PagedList<CategoryDto>> ListAsync(string? search, int page, int pageSize, CancellationToken ct);
    Task<CategoryDto> GetAsync(Guid id, CancellationToken ct);
    Task<CategoryDto> UpdateAsync(Guid id, UpdateCategoryDto input, CancellationToken ct);
    Task DeleteAsync(Guid id, CancellationToken ct);
}

public sealed record CategoryDto(Guid Id, string Name, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);
public sealed record CreateCategoryDto(string Name);
public sealed record UpdateCategoryDto(string Name);
```

- [ ] **Step 1:** Client tests first (query-string shape, status/body error mapping, 204 delete). **Step 2:** implement mirroring `HotstringsApiClient` conventions (`JsonSerializerOptions.Web`, `ApiException` on non-success). **Step 3:** verification trio. **Commit** `feat(cli): categories api client`

### Task 2: Formatters + resolver

**Files:**
- Create: `Output/CategoryTableFormatter.cs` (columns: Name, Created, Updated), `Output/CategoryJsonFormatter.cs` (page + single-object writers, casing per Hotstring JSON formatter)
- Create: `Commands/Categories/CategoryResolver.cs` — `static Task<CategoryDto?> ResolveAsync(ICategoriesApiClient client, string target, CancellationToken ct)`: Guid → `GetAsync` (404 → null); else `ListAsync(search: target, page:1, pageSize:200)` + exact `OrdinalIgnoreCase` name match
- Test: `Output/CategoryTableFormatterTests.cs`, `Output/CategoryJsonFormatterTests.cs`, `Commands/Categories/CategoryResolverTests.cs`

- [ ] **Step 1:** Tests first (id path, name path, miss → null). **Step 2:** implement. **Step 3:** verification trio. **Commit** `feat(cli): category formatters + resolver`

### Task 3: Commands (new/list/get/update/delete) + group wiring

**Files:**
- Create: `Commands/Categories/CategoryCommand.cs` (group), `NewCategoryCommand.cs`, `ListCategoryCommand.cs`, `GetCategoryCommand.cs`, `UpdateCategoryCommand.cs`, `DeleteCategoryCommand.cs`
- Modify: `Commands/RootCli.cs` — add `CategoryCommand.Build(services)`
- Test: one `*Tests.cs` per command under `tests/AHKFlowApp.CLI.Tests/Commands/Categories/`

**Surfaces:**
- `new --name/-n <name>` (required) → prints created row / `--json` object.
- `list [--search/-s] [--page] [--page-size] [--json]` — defaults 1/50 like hotstring list.
- `get <id|name> [--json]` — resolver miss → stderr `Category '<target>' not found.` exit 2.
- `update <id|name> --name/-n <newName>` — `--name` required (only editable field), read-modify-write unnecessary (single field): resolve → `UpdateAsync(id, new(newName))`.
- `delete <id|name>` — success `Deleted category '<name>' (<id>).`; duplicates/conflicts surface from API as exit 2.

Every command body wrapped per Global Constraints error-handling rule.

- [ ] **Step 1:** Unit tests per command (happy path with asserted request body, not-found → 2, duplicate-name create → 2 conflict, `--json` paths). **Step 2:** implement all five + wiring. **Step 3:** verification trio. **Commit** `feat(cli): category commands`

### Task 4: Integration tests + smoke

**Files:** create `tests/AHKFlowApp.CLI.Tests/Integration/CategoryCliIntegrationTests.cs` (mirror the hotstring integration harness)

- [ ] **Step 1:** Flow: list (lazy defaults appear) → new → get by name → update (rename) → get by new name → delete → get exits 2; duplicate create → 2.
- [ ] **Step 2:** Manual smoke against local API; outputs into PR.
- [ ] **Step 3:** Full solution tests + trio. **Commit** `test(cli): category vertical integration flows`

---

## Final verification

- [ ] `ahkflow category --help` lists all five; `ahkflow --help` shows the group
- [ ] Verification trio + full solution tests green
