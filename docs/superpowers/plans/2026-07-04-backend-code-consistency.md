# Backend Code Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the Hotstring↔Hotkey vertical drift, remove dead `TestMessage` scaffolding, and thin the one fat controller — the concrete findings of the 2026-07-04 backend audit (see the [roadmap](../specs/2026-07-04-first-release-cleanup-roadmap-design.md)).

**Architecture:** No new patterns. Align existing pairs of handlers on the better of their two implementations, extract one shared helper, add one use case, delete one entity + migration.

**Tech Stack:** .NET 10, EF Core + SQL Server (Testcontainers in tests), Ardalis.Result, FluentValidation, xUnit + FluentAssertions.

## Global Constraints

- Work on a feature branch (`feature/backend-code-consistency`), PR to `main`. Never commit to main.
- Verification trio after every task: `dotnet build AHKFlowApp.slnx`, `scripts/test-fast.ps1` (or `dotnet test --configuration Release`), `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Handlers return `Result<T>`; validation errors carry `Identifier` bindable to a request field.
- Test naming `MethodName_Scenario_ExpectedResult`; Testcontainers, never `UseInMemoryDatabase`.
- Do NOT touch: CLI project, frontend, worktree/local-dev scripts.
- Audit says these are already clean — do not "improve" them: naming conventions, controller auth attributes, TimeProvider usage, CancellationToken propagation.

## Resume instructions

If resuming mid-plan: `git log --oneline -10` shows which task commits landed; unchecked boxes below are remaining work. Each task is independent except T5 (helper) which T1/T4 code paths call — if T5 landed first, use the helper in later tasks.

---

### Task 1: Align create-handler post-save collection loading

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs:106-113`
- Inspect first: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs:108-110` (the target pattern), `Mapping/*.cs` `ToDto()` for Hotstring
- Test: `tests/AHKFlowApp.Application.Tests/` (create-hotstring handler tests; follow existing fixture usage there)

**Context:** After `SaveChangesAsync`, the Hotkey handler loads both collections explicitly:

```csharp
await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
await db.Entry(entity).Collection(h => h.Categories).LoadAsync(ct);
```

The Hotstring handler instead manually queries `HotstringProfiles` into `entity.Profiles` and never loads `Categories` — `ToDto()` relies on EF change-tracker fixup for CategoryIds. That may work today by accident; it is fragile and inconsistent.

- [ ] **Step 1: Write/extend a failing-or-green characterization test** asserting the create-hotstring handler's returned DTO contains BOTH the requested `ProfileIds` and `CategoryIds` (create with 2 profiles + 2 categories; assert `result.Value.ProfileIds` and `result.Value.CategoryIds` match). If it's already green, keep it — it pins behavior for Step 2.
- [ ] **Step 2: Replace the manual reload block** (lines 106-111, including the `// Reload profiles…` comment) with the Hotkey pattern:

```csharp
await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
await db.Entry(entity).Collection(h => h.Categories).LoadAsync(ct);
```

(If `IAppDbContext` doesn't expose `Entry`, mirror however the Hotkey handler accesses it — same abstraction, so it does.)
- [ ] **Step 3: Run** `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~CreateHotstring"` → PASS, then the verification trio.
- [ ] **Step 4: Commit** `fix: align hotstring create post-save loads with hotkey pattern`

### Task 2: Add missing ValidationError Identifier in CreateHotkey

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs:59`
- Inspect first: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs` (check whether its ProfileIds error has the same gap — fix it in this task too if so)
- Test: existing CreateHotkey handler tests in `tests/AHKFlowApp.Application.Tests/`

**Context:** Hotkey returns `Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."))` — no `Identifier`, so clients can't bind the error to the field. Hotstring sets `Identifier = "Input.ProfileIds"`.

- [ ] **Step 1: Write failing test**: create hotkey with a nonexistent ProfileId; assert `result.ValidationErrors.Single().Identifier == "Input.ProfileIds"`. Run → FAIL (Identifier empty).
- [ ] **Step 2: Change to the Hotstring shape:**

```csharp
return Result.Invalid(new ValidationError
{
    Identifier = "Input.ProfileIds",
    ErrorMessage = "One or more ProfileIds do not exist for this user.",
});
```

- [ ] **Step 3: Run** the test → PASS; verification trio.
- [ ] **Step 4: Commit** `fix: add Input.ProfileIds identifier to hotkey validation error`

### Task 3: Unify profile-association validator helper naming

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs:34` (`ValidProfileAssociation<T>` → `AddProfileAssociationRules<T>`)
- Modify: call sites — `Commands/Hotkeys/CreateHotkeyCommand.cs:23`, `Commands/Hotkeys/UpdateHotkeyCommand.cs` (find with `grep -r "ValidProfileAssociation" src tests`)
- Inspect first: `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs:31` (the kept name) — confirm both helpers' rule sets are semantically identical; if one has a rule the other lacks, align the rules too and note it in the commit body.

- [ ] **Step 1: Rename** method + update all call sites (mechanical; csharp-lsp rename or find/replace).
- [ ] **Step 2: Run** verification trio (behavior unchanged → full test suite green).
- [ ] **Step 3: Commit** `refactor: unify profile-association validator helper name`

### Task 4: Fix update-handler category-junction asymmetry (both verticals)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs:96-110`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs:91-105`
- Test: update-handler tests in `tests/AHKFlowApp.Application.Tests/`

**Context (from audit — verify by reading both files first):** after `RemoveRange`+`Clear`, new profile junctions are added to both the DbSet and `entity.Profiles`, but new category junctions go only to the DbSet; the returned DTO's CategoryIds depend on EF fixup.

- [ ] **Step 1: Write characterization tests** (both verticals): update an entity replacing its categories (e.g. from [A] to [B,C]); assert returned DTO `CategoryIds == [B,C]` and DB state matches. Run — note green/red.
- [ ] **Step 2: Make the handling symmetric** — either add category junctions to `entity.Categories` exactly as profiles do, or (preferred if Task 1 landed) drop the manual collection mutations and use post-save `LoadAsync` for both collections in both update handlers. Pick ONE approach and apply it to both files identically.
- [ ] **Step 3: Run** update-handler tests → PASS; verification trio.
- [ ] **Step 4: Commit** `fix: symmetric profile/category junction handling in update handlers`

### Task 5: Extract shared owned-ids existence check

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Common/OwnedIdsValidation.cs` (or fold into an existing helper class in `Common/` if one fits — inspect folder first)
- Modify: the 4 handlers — `Commands/Hotstrings/{Create,Update}HotstringCommand.cs`, `Commands/Hotkeys/{Create,Update}HotkeyCommand.cs`

**Interfaces:**
- Produces (example shape — adjust to what the 4 call sites actually need after reading them):

```csharp
internal static class OwnedIdsValidation
{
    /// <returns>null when all ids exist for the owner; otherwise an Invalid result carrying the field identifier.</returns>
    public static async Task<ValidationError?> CheckOwnedIdsAsync<TEntity>(
        IQueryable<TEntity> set, Guid ownerOid, Guid[] distinctIds,
        string identifier, string entityDisplayName, CancellationToken ct) ...
}
```

**Context:** The `CountAsync`-against-distinct-ids block for ProfileIds and CategoryIds is copy-pasted 8× across 4 handlers (Task 2 showed one copy already drifted). Note: `Profile`/`Category` need a common way to filter `OwnerOid` + `Id` — if no shared interface exists, pass an `Expression<Func<TEntity,bool>>` predicate or two lambdas; keep it as simple as the call sites allow. This must stay in handlers (needs DB), not the FluentValidation decorator.

- [ ] **Step 1: Write tests for the helper** (valid ids → null; one missing id → error with the right `Identifier` and message).
- [ ] **Step 2: Implement the helper; replace all 8 blocks.** Messages/identifiers must stay byte-identical to today's Hotstring versions (`"Input.ProfileIds"` / `"Input.CategoryIds"`, "One or more ProfileIds/CategoryIds do not exist for this user.").
- [ ] **Step 3: Run** full Application test project → PASS; verification trio.
- [ ] **Step 4: Commit** `refactor: shared owned-ids existence check for handlers`

### Task 6: Move zip assembly out of DownloadsController

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsZipQuery.cs` (query + handler returning `Result<ProfileScriptZip>` where `ProfileScriptZip(byte[] Content, string FileName)` is a new record in `Application/DTOs/`)
- Modify: `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs:56-83` — `GetAllZip` becomes: execute use case, `return File(result.Value.Content, ZipContentType, result.Value.FileName)`
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` — register via the existing `AddUseCase<TReq,TRes,THandler>` helper
- Inspect first: `Queries/Downloads/GenerateAllProfileScriptsQuery.cs` — the new handler composes it (inject `IUseCase<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>>`) or reuses its underlying generation service; match whichever composition style the folder already uses.

**Context:** `GetAllZip` builds a `ZipArchive` inline — the only non-thin action across 11 controllers. Move the `MemoryStream`/`ZipArchive` block verbatim into the new handler (it's correct; `CompressionLevel.Optimal`, BOM-less UTF-8 writer).

- [ ] **Step 1: Confirm existing integration test** for `GET /api/v1/downloads/zip` in `tests/AHKFlowApp.API.Tests/` (find with `grep -ri "downloads/zip" tests`). If none, write one first: seed 2 profiles, GET, assert 200 + `application/zip` + archive contains one `.ahk` entry per profile.
- [ ] **Step 2: Implement** query/handler/DTO + DI registration; thin the controller.
- [ ] **Step 3: Run** `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~Downloads"` → PASS (unchanged behavior); verification trio.
- [ ] **Step 4: Commit** `refactor: move zip assembly into GenerateAllProfileScriptsZip use case`

### Task 7: Remove TestMessage scaffolding

**Files:**
- Delete: `src/Backend/AHKFlowApp.Domain/Entities/TestMessage.cs`
- Delete: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/TestMessageConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs:10` (drop DbSet) + `IAppDbContext` if it exposes the set
- Create: migration `RemoveTestMessage`
- Inspect first: `grep -ri "TestMessage" src tests docs` — remove every reference (tests seeding it, health checks querying it, seed compositions).

- [ ] **Step 1: Remove all code references** found by the grep; build must succeed before the migration step.
- [ ] **Step 2: Add migration:**

```bash
dotnet ef migrations add RemoveTestMessage --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Review the generated migration: it must contain only `DropTable` for the TestMessage table (name per snapshot) — nothing else.
- [ ] **Step 3: Apply locally** (`dotnet ef database update …` same projects) against Docker SQL; run full test suite (Testcontainers apply migrations from scratch — proves the chain) → PASS; verification trio.
- [ ] **Step 4: Commit** `chore: remove TestMessage entity + DropTable migration`

### Task 8 (OPTIONAL — open question #4 in roadmap; skip unless user approved): Rename Behaviors/ → Decorators/

- [ ] Move `src/Backend/AHKFlowApp.Application/Behaviors/ValidatingUseCase.cs` to `Decorators/`, update namespace + usings (`grep -r "Application.Behaviors" src tests`). Verification trio. Commit `refactor: rename Behaviors folder to Decorators`.

---

## Final verification

- [ ] `dotnet build AHKFlowApp.slnx` — 0 warnings introduced
- [ ] `dotnet test --configuration Release` (full suite, incl. Testcontainers) — green
- [ ] `dotnet format AHKFlowApp.slnx --verify-no-changes` — clean
- [ ] `grep -ri "TestMessage" src tests` — no hits
- [ ] PR to main, single concern: "backend code consistency"
