# Skill Template Drift (Issue #220) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the five template-heavy skill files under `.agents/` (`dck-security-scan`, `dck-ef-core`, `dck-blazor-mudblazor`, `dck-scaffolding`, `dck-openapi`) so every code block that copies a project-specific pattern is replaced by a pointer to the real, compiled/tested file that already shows that pattern — per issue [#220](https://github.com/s205109/AHKFlowApp/issues/220).

**Architecture:** No app code changes. Each task edits one `SKILL.md` file. A "pointer" is one or two sentences naming the exact file (and line range where useful) that demonstrates the pattern, replacing an inlined code block that copied it. Where research below found **no live example** of a taught pattern anywhere in the repo, the block is kept but re-labeled so a reader knows it is a framework-API reference, not a description of this app's behavior — inventing a citation for something that does not exist would be exactly the kind of fabrication the issue is about.

**Tech Stack:** Markdown only. No build, no tests to run — this falls under AGENTS.md's "Docs, skills, or plan files only" verification exemption. Verification per task is: (1) grep the cited `file:line` after editing to confirm it still contains what's claimed, (2) read the rewritten section back for accuracy.

## Global Constraints

- Every citation in the rewritten skills must be a real `file:line` that was read during this plan's research (listed per task) — no invented paths.
- Where research found a pattern the skill teaches has **no live implementation**, keep the block but mark it clearly (see the standard note text in each task) — do not point it at a file that doesn't demonstrate it.
- Don't touch the other seven active skills (`dck-build-fix`, `dck-de-sloppify`, `dck-ef-core` migration workflow companion `dck-migration-workflow`, `dck-openapi` companion docs, `dck-verify`, `dck-workflow-mastery`, `dck-scaffolding`'s sibling `dck-security-scan`... i.e. anything not in the five named above) — the issue explicitly scopes risk to these five.
- Don't fix unrelated staleness discovered during research (e.g. `AGENTS.md`'s own `result.ToActionResult(this)` reference, which the real code has replaced with `ToProblemActionResult`) — out of scope for this issue; flag it to the user instead of expanding scope.
- Preserve each skill's frontmatter (`name`, `description`) and overall section order unless a task says otherwise.

---

## Research Findings (evidence backing every task below)

Read during this plan's research, with what was found:

| Claim | Proof |
|---|---|
| `IAppDbContext` interface exists and is injected into handlers (contradicts dck-ef-core's stated "No `IAppDbContext` interface" principle) | `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs:7-27`; injected in `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs:28-31` and `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs:12-14` |
| DbContext registration differs from template (adds `IAppDbContext` scoped registration) | `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs:16-21` |
| Real query handlers use `AsNoTracking()` + `Include()` + an explicit `.ToDto()` mapping extension, not `.Select()` DTO projection as the skill's "Query Projections" section teaches | `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs:22-29` |
| `HotstringConfiguration` is far richer than the skill's toy version (unique index with `HasFilter(null)`, enum-as-int conversions, `nvarchar(max)` column) | `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs:1-74` |
| `ExecuteUpdateAsync`/`ExecuteDeleteAsync`, `SaveChangesInterceptor`, `EF.CompileAsyncQuery`, strongly-typed-ID value converters, `HasQueryFilter`, and `AsSplitQuery` are **not used anywhere** in the codebase | `grep -rl` for each across `src/Backend` returned no matches (session transcript) |
| Soft-delete/recycle-bin is implemented via an `EntityHistory` snapshot table plus explicit Restore/Purge commands, not an `IsDeleted` flag + global query filter | no `IsDeleted`/`DeletedAt` property anywhere in `src/Backend/AHKFlowApp.Domain`; `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{RestoreHotkeyCommand,PurgeDeletedHotkeyCommand}.cs`, `.../Hotstrings/PurgeDeletedHotstringCommand.cs` reference `EntityHistories` directly |
| Testcontainers usage is a shared fixture, not a per-class `MsSqlContainer` | `tests/AHKFlowApp.TestUtilities/Fixtures/SqlContainerFixture.cs`, `tests/AHKFlowApp.TestUtilities/Fixtures/ApiTestFixture.cs:1-28`; consumed via `[Collection("WebApi")]` per issue #220's own body, citing `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15` |
| Handler naming in dck-scaffolding/dck-ef-core templates (`CreateHotstringHandler`, `GetHotstringHandler`) doesn't match the real `{Command/Query}Handler` convention (`CreateHotstringCommandHandler`, `GetHotstringQueryHandler`) | `src/Backend/AHKFlowApp.Application/DependencyInjection.cs:39` (`CreateHotstringCommandHandler`); `GetHotstringQueryHandler` class name in `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs:12` |
| Controllers map `Result` via a custom `ToProblemActionResult` extension, not the bare `Ardalis.Result.AspNetCore.ToActionResult` the scaffolding/openapi templates show | `src/Backend/AHKFlowApp.API/Extensions/ProblemDetailsResultExtensions.cs:6-10` (doc comment explicitly says it replaces `ToActionResult`), method defined at lines 22-30; usage at `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs:71,78,91` |
| Real controllers also carry `[RequiredScope("access_as_user")]` and class-level `[ProducesResponseType]` for 401/403, absent from every scaffolding/openapi template | `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs:16-19` |
| Swagger setup lives behind `AddSwaggerDocs()`/`UseSwaggerDocs()` extensions, not the inline `AddSwaggerGen` block the openapi skill teaches; uses the newer `OpenApiSecuritySchemeReference` API, not `OpenApiReference` | `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:50-101`; called from `src/Backend/AHKFlowApp.API/Program.cs:102,196` |
| XML doc generation is on for both API and Application projects | `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj:4-5`, `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj:3` |
| Real CORS policy uses `SetIsOriginAllowed` reading live config (not the static `WithOrigins(...)` the security-scan "GOOD" example shows) | `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:10-24` |
| Real auth setup delegates JWT validation to `AddMicrosoftIdentityWebApi` (Microsoft.Identity.Web) rather than hand-building `TokenValidationParameters` as the security-scan "BAD/GOOD JWT configuration" example assumes | `src/Backend/AHKFlowApp.API/Program.cs:130-135` |
| Blazor's own `CLAUDE.md` already documents the real, more nuanced pattern set (MudDataGrid inline edit for complex lists, MudTable inline edit for simple ones, full-screen MudDialog only on the mobile branch) that the skill's single MudTable+MudDialog template doesn't reflect | `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` ("Conventions" section); confirmed in code at `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:70-78` (`MudDataGrid` inline edit), `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Categories.razor:32` (`MudTable` inline edit), `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor:10` (`MudDialog`, mobile-only per the CLAUDE.md) |
| No `FluentValidationExtensions.ValidateValue` adapter exists anywhere — real Blazor forms validate with plain `Func<string,string?>` delegates on `EditModel` classes | `grep -rl ValidateValue src/Frontend` returned nothing; real pattern in `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs` and used at `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor:90` (`Validation="@(new Func<string, string?>(Item.ValidateReplacement))"`) |

---

## Task 1: `dck-ef-core/SKILL.md`

**Files:**
- Modify: `.agents/dck-ef-core/SKILL.md` (364 lines)

- [ ] **Step 1: Fix Core Principle #2 (stale "no IAppDbContext" claim)**

Replace (current lines 11):
```
2. **DbContext injected directly into handlers** — No repository pattern. No IAppDbContext interface. EF Core's DbSet already implements repository and unit-of-work. Adding another layer adds indirection without value.
```
with:
```
2. **`IAppDbContext` injected into handlers** — This project wraps `AppDbContext` behind `IAppDbContext` (`src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`) purely so handler unit tests can substitute it — the interface still exposes `DbSet<T>` properties directly, no per-entity CRUD methods, so it is not a repository. Never add a repository interface on top of it.
```

- [ ] **Step 2: Replace "DbContext Registration (SQL Server)" with a pointer**

Replace the code block under that heading (lines 20-29) with:
```
See `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs:16-21` for the live registration — `AddDbContext<AppDbContext>` with `EnableRetryOnFailure()`, plus a scoped `IAppDbContext` registration that resolves to the same `AppDbContext` instance.
```

- [ ] **Step 3: Replace "DbContext Configuration" with a pointer**

Replace both code blocks under that heading (lines 33-60) with:
```
`AppDbContext` lives at `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`; entity configs live one level down in `Configurations/`, one file per entity, each implementing `IEntityTypeConfiguration<T>`. `Configurations/HotstringConfiguration.cs` is the fullest example — required/max-length properties, an enum-as-int conversion, and a filtered unique index (`HasIndex(...).HasFilter(null)`) for the "one global row per owner+trigger" rule. Follow its shape rather than a simplified one.
```

- [ ] **Step 4: Fix "Handler Injects DbContext Directly" — wrong type, wrong naming, wrong projection style**

Replace the heading and code block (lines 62-78) with:
```
### Handler Injects IAppDbContext Directly

`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs` is the live shape: the handler class is named `{Query}Handler` off the full query name (`GetHotstringQueryHandler`, not `GetHotstringHandler`), it takes `IAppDbContext` (not `AppDbContext`) and `ICurrentUser` in its primary constructor, and it loads the entity with `AsNoTracking()` + `Include()` rather than a `.Select()` projection, then maps with an explicit `.ToDto()` extension (`Application/Mapping/`). Follow that shape, not a `.Select()` projection — see Step 5.
```

- [ ] **Step 5: Fix "Query Projections (Avoid Over-Fetching)" — contradicts real handlers**

Replace the heading, prose, and code block (lines 80-88) with:
```
### Loading and Mapping (not `.Select()` projection)

Core Principle #4 above ("Queries should be projections") describes the *intent* — avoid over-fetching — but the actual pattern in this codebase is `AsNoTracking()` + `Include()` on the entity, then an explicit `.ToDto()` extension method in `Application/Mapping/`, not an inline `.Select(x => new Dto(...))`. See `GetHotstringQuery.cs` (Step 4) for the live shape. Reach for `.Select()` projection only if a query needs to avoid loading a large related collection that `.ToDto()` would otherwise touch.
```

- [ ] **Step 6: Mark "ExecuteUpdateAsync / ExecuteDeleteAsync" as framework reference, not live pattern**

Insert this line immediately under the heading (before its existing code block, which stays as-is):
```
_No live example in this codebase yet — nothing here bulk-updates/deletes today. Framework API reference for when that need arises; convert to a pointer at that time instead of trusting this snippet to still be current._
```

- [ ] **Step 7: Mark "Interceptors" the same way, and correct the audit-trail claim**

Replace the prose line under the heading ("Use interceptors for cross-cutting concerns like audit trails.") with:
```
_No `SaveChangesInterceptor` exists in this codebase. This app's audit trail (`EntityHistory`) is written explicitly inside command handlers, not via an interceptor — see `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RestoreHotkeyCommand.cs` for the shape. Keep this section as a framework-API reference only; don't imply the project uses interceptors._
```
Keep the existing code block below it — it is illustrative, not a claim about this app.

- [ ] **Step 8: Mark "Compiled Queries" as framework reference**

Insert under the heading, before the existing code block:
```
_No live example in this codebase — no compiled query exists today. Framework API reference only._
```

- [ ] **Step 9: Fix "Value Converters" — cite the real enum conversion, mark strongly-typed IDs as unused**

Replace the code block (lines 169-180) with:
```csharp
// Real example: enum stored as int — src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs:35-37
builder.Property(x => x.Kind)
    .IsRequired()
    .HasConversion<int>();
```
followed by:
```
_Strongly-typed ID value converters (e.g. a `HotstringId` wrapper) are not used anywhere in this codebase — every ID is a plain `Guid`. Framework API reference only if that changes._
```

- [ ] **Step 10: Fix "Global Query Filters" — this app doesn't soft-delete this way**

Replace the heading, prose, and code block (lines 202-210) with:
```
### Soft Delete / Recycle Bin (this app does NOT use a global query filter)

This app has no `IsDeleted` flag and no `HasQueryFilter`. Delete/restore is modeled through an `EntityHistory` snapshot table plus explicit commands — see `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{RestoreHotkeyCommand,PurgeDeletedHotkeyCommand}.cs`. If a future entity needs true soft-delete via a boolean flag, `HasQueryFilter` is still the right EF Core mechanism — but don't describe it as what this app already does.
```

- [ ] **Step 11: Fix "Testcontainers (SQL Server)" — per-class container is the exact pattern issue #220 already retired once**

Replace the code block (lines 217-225) with:
```
The shared fixture lives in `tests/AHKFlowApp.TestUtilities/Fixtures/`: `SqlContainerFixture.cs` owns the `MsSqlContainer`, `ApiTestFixture.cs` wraps it with a `CustomWebApplicationFactory`. Tests share one container per collection via `[Collection("WebApi")]` — see `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15` for the live shape. Never spin up a per-test-class `MsSqlContainer` — that is the exact pattern this project already retired once (see issue #220).
```

- [ ] **Step 12: Mark "Split Queries (avoid cartesian explosion)" as framework reference**

Insert under the heading, before its existing code block:
```
_No live example in this codebase — no query combines multiple/large `Include`s today. Framework API reference only._
```

- [ ] **Step 13: Fix the "Don't Wrap DbContext in a Repository" anti-pattern GOOD example**

Replace the GOOD line (line 302):
```csharp
// GOOD — use AppDbContext directly in handlers
internal sealed class GetHotstringHandler(AppDbContext db) { }
```
with:
```csharp
// GOOD — use IAppDbContext directly in handlers (see GetHotstringQueryHandler)
internal sealed class GetHotstringQueryHandler(IAppDbContext db, ICurrentUser currentUser) { }
```

- [ ] **Step 14: Re-check word count and commit**

Run: `wc -l .agents/dck-ef-core/SKILL.md` — expect a drop from 364 lines (large code blocks became one-paragraph pointers).

```bash
git add .agents/dck-ef-core/SKILL.md
git commit -m "docs: point dck-ef-core at live code instead of stale templates"
```

---

## Task 2: `dck-blazor-mudblazor/SKILL.md`

**Files:**
- Modify: `.agents/dck-blazor-mudblazor/SKILL.md` (330 lines)

- [ ] **Step 1: Replace "Page Layout (List View)" with pointers to the two real shapes**

Replace the code block (lines 21-77) with:
```
This app uses two shapes depending on list complexity (documented in `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`, "Conventions"):
- **Simple list, ≤6 short fields, inline edit** — `MudTable` with inline row editing. See `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Categories.razor`.
- **Larger list needing sort/filter/bulk-select** — `MudDataGrid` with `ServerData`, inline row editing, and a bulk-select toolbar. See `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:70-78` (the `MudDataGrid` declaration) and `Pages/Hotkeys.razor` for a second example.

Pages needing mobile support render both a `.desktop-branch` and `.mobile-branch`, gated by scoped CSS at 959.95px — see `Components/Hotstrings/` and `Components/Hotkeys/` for the mobile-branch components.
```

- [ ] **Step 2: Replace "MudDialog for Create/Edit" with a pointer, correcting when dialogs are actually used**

Replace the code block (lines 81-133) with:
```
Full-screen `MudDialog` for create/edit is the **mobile-branch** pattern in this app, not the default — desktop list pages edit inline in the table/grid (Step 1). See `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor` for the live shape: a `MudDialog` with a `TitleContent` back-button + save button, an `EditModel` (`Validation/HotstringEditModel.cs`) bound via `@bind-Value`, and per-field `Func<string,string?>` validators (see Task's Step 4 below — no FluentValidation adapter is involved).
```

- [ ] **Step 3: Replace "Opening Dialogs from Pages" and "Delete Confirmation" with pointers**

Replace both code blocks (lines 137-183) with:
```
### Opening Dialogs / Delete Confirmation

See `HotstringEditDialog.razor`'s caller in `Pages/Hotstrings.razor` for `IDialogService.ShowAsync<T>` and result handling, and any page's delete action for `IDialogService.ShowMessageBox(...)` — the shape (title, message, yesText/cancelText, `== true` check) matches the original template; no drift found here.
```

- [ ] **Step 4: Fix "MudForm Validation with FluentValidation" — this adapter does not exist**

Replace the heading, prose, and code block (lines 185-206) with:
```
### Form Validation (per-field delegates, not a FluentValidation adapter)

There is no `FluentValidationExtensions.ValidateValue` adapter in this codebase — real forms validate with a plain `Func<string, string?>` delegate per field, defined as a method on an `EditModel` class in `Validation/` (e.g. `Validation/HotstringEditModel.cs`), wired up as `Validation="@(new Func<string, string?>(Item.ValidateReplacement))"` (see `Components/Hotstrings/HotstringEditDialog.razor:90`). Don't introduce a FluentValidation-to-MudForm adapter — follow the `EditModel` pattern instead.
```

- [ ] **Step 5: Replace "Server-Side Table (Pagination/Search)" with a pointer**

Replace the code block (lines 210-256) with:
```
`Pages/Categories.razor` (`MudTable`) and `Pages/Hotstrings.razor` / `Pages/Hotkeys.razor` (`MudDataGrid`) all use `ServerData` — see Step 1 for which shape applies to a new page.
```

- [ ] **Step 6: Leave the "Anti-patterns" and "Decision Guide" sections as-is**

These are short generic MudBlazor do/don't rules (raw HTML, missing `For`, skipping loading states, `StateHasChanged()` misuse, nested dialogs) that don't copy a specific project template and were not found to contradict live code — no change needed. Update the Decision Guide's "Create/Edit form" row only, from `MudDialog + MudForm + FluentValidation` to `Inline edit (MudTable/MudDataGrid) by default; MudDialog + EditModel only for the mobile branch`.

- [ ] **Step 7: Re-check word count and commit**

Run: `wc -l .agents/dck-blazor-mudblazor/SKILL.md`

```bash
git add .agents/dck-blazor-mudblazor/SKILL.md
git commit -m "docs: point dck-blazor-mudblazor at live pages instead of stale templates"
```

---

## Task 3: `dck-scaffolding/SKILL.md`

**Files:**
- Modify: `.agents/dck-scaffolding/SKILL.md` (231 lines)

- [ ] **Step 1: Replace "Command and Handler" with a pointer, fixing the naming and `IAppDbContext` gaps**

Replace both code blocks (lines 50-78) plus the "Register the use case" block (lines 80-84) with:
```
`src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs` is a live example: command record + validator + handler share one file, the handler class is `{CommandName}Handler` (e.g. `CreateHotkeyCommandHandler`, not `CreateHotkeyHandler`), it injects `IAppDbContext` (not `AppDbContext`) plus `ICurrentUser` and `TimeProvider`, and DI registration is a chained `.AddUseCase<TCommand, TResult, THandler>()` call in `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` (see lines 33-40 for the chain shape).
```

- [ ] **Step 2: Replace "Validator" with a pointer**

Replace the code block (lines 88-98) with:
```
Validators are usually a nested class in the same file as the command they validate (see `CreateHotkeyCommandValidator` in `CreateHotkeyCommand.cs`, Step 1) — not a separate file, despite the Layer Structure diagram above implying otherwise for large validators. Follow the co-located shape unless a validator grows large enough to warrant its own file.
```

- [ ] **Step 3: Replace "Query and Handler" with a pointer, fixing naming**

Replace both code blocks (lines 103-125) with:
```
`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs` is the live shape — handler class `GetHotstringQueryHandler` (not `GetHotstringHandler`), `IAppDbContext` + `ICurrentUser` injected, `AsNoTracking()` + `Include()` + `.ToDto()` rather than a `.Select()` projection. See `.agents/dck-ef-core/SKILL.md` for the EF Core side of this pattern.
```

- [ ] **Step 4: Replace "Controller" with a pointer, fixing `ToActionResult`**

Replace the code block (lines 129-158) with:
```
`src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` is the live shape. Note three things the simplified template above misses: results map via `result.ToProblemActionResult(this)` (an in-repo RFC 9457 extension, `src/Backend/AHKFlowApp.API/Extensions/ProblemDetailsResultExtensions.cs`), not the bare `Ardalis.Result.AspNetCore.ToActionResult`; class-level attributes add `[RequiredScope("access_as_user")]` and `[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]` / `...Status403Forbidden`; and action methods return `ActionResult<T>`, not `IActionResult`.
```

- [ ] **Step 5: Replace "Entity and EF Configuration" with a pointer**

Replace both code blocks (lines 164-206) with:
```
`src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (entity: private setters, `Create` factory) and `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs` (EF config: required/max-length properties, enum-as-int conversions, a filtered unique index) are the live, much richer versions of the toy example above — read them before scaffolding a new entity, don't copy the simplified shape here.
```

- [ ] **Step 6: Leave "Integration Test Shape" — already a pointer-style paragraph, just fix the fixture name**

Replace (line 210):
```
Use `WebApplicationFactory` and SQL Server Testcontainers. Replace `DbContextOptions<AppDbContext>` with `services.RemoveAll<DbContextOptions<AppDbContext>>()`, run migrations, and assert behavior through HTTP or handler results.
```
with:
```
Use the shared `ApiTestFixture` (`tests/AHKFlowApp.TestUtilities/Fixtures/ApiTestFixture.cs`) via `[Collection("WebApi")]` — see `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15`. Don't stand up a new `WebApplicationFactory`/`MsSqlContainer` per test class.
```

- [ ] **Step 7: Leave "Mandatory Checklist", "Layer Structure", "Anti-Patterns", "Decision Guide" as-is**

These are short bullet/table content, not inlined code templates — no drift found; no change needed.

- [ ] **Step 8: Re-check word count and commit**

Run: `wc -l .agents/dck-scaffolding/SKILL.md`

```bash
git add .agents/dck-scaffolding/SKILL.md
git commit -m "docs: point dck-scaffolding at live code instead of stale templates"
```

---

## Task 4: `dck-openapi/SKILL.md`

**Files:**
- Modify: `.agents/dck-openapi/SKILL.md` (212 lines)

- [ ] **Step 1: Replace "Basic Setup (Program.cs)" with a pointer**

Replace the code block (lines 19-47) with:
```
Swagger setup is behind two extension methods, not inlined in `Program.cs`: `AddSwaggerDocs()` and `UseSwaggerDocs()` in `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:50-101`, called conditionally in Development from `src/Backend/AHKFlowApp.API/Program.cs:102,196`. Read the extension methods rather than copying the inline shape above — they also register `AddSwaggerExamplesFromAssemblies` and read XML comments from both `AHKFlowApp.API` and `AHKFlowApp.Application` assemblies.
```

- [ ] **Step 2: Replace "ProducesResponseType on Controller Actions" with a pointer**

Replace the code block (lines 53-100) with:
```
`src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` is the live, much larger example — 15 actions, each with XML `<summary>`/`<response>` comments and `[ProducesResponseType]` per possible status. It also carries class-level `[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]` / `...Status403Forbidden` that this simplified template omits — those apply to every action via `[Authorize]` + `[RequiredScope]` and don't need repeating per action.
```

- [ ] **Step 3: Leave "Enable XML Documentation" but cite the real csproj lines**

Replace the code block (lines 106-111) with:
```csharp
<!-- src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj:4-5 (also set in AHKFlowApp.Application.csproj:3) -->
<GenerateDocumentationFile>true</GenerateDocumentationFile>
<NoWarn>$(NoWarn);CS1591</NoWarn>
```

- [ ] **Step 4: Fix "Bearer Token Security Scheme" — API shape has moved on**

Replace the code block (lines 117-145) with:
```
The real registration is in `AddSwaggerDocs()` (`ApiExtensions.cs:61-74`) and uses the newer `Microsoft.OpenApi` shape — `OpenApiSecuritySchemeReference("Bearer", doc)` inside `AddSecurityRequirement(doc => ...)`, not the older `OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }` this template shows. Copy the live extension method rather than this block; the two are not interchangeable across `Microsoft.OpenApi` versions.
```

- [ ] **Step 5: Leave "ProblemDetails Schema" but note the real registration also adds a trace ID**

Replace the code block (line 152) with:
```csharp
// src/Backend/AHKFlowApp.API/Program.cs:75-77 — also stamps a traceId extension on every problem response
builder.Services.AddProblemDetails(options =>
    options.CustomizeProblemDetails = ctx =>
        ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);
```

- [ ] **Step 6: Leave "Anti-patterns" and "Decision Guide" as-is**

Generic dos/don'ts (missing `ProducesResponseType`, Minimal API metadata on controllers, exposing Swagger in prod) — no drift found; no change needed.

- [ ] **Step 7: Re-check word count and commit**

Run: `wc -l .agents/dck-openapi/SKILL.md`

```bash
git add .agents/dck-openapi/SKILL.md
git commit -m "docs: point dck-openapi at live code instead of stale templates"
```

---

## Task 5: `dck-security-scan/SKILL.md`

**Files:**
- Modify: `.agents/dck-security-scan/SKILL.md` (374 lines)

**Note on scope for this file specifically:** unlike the other four, most of this skill's BAD/GOOD examples (Layers 1, 2, 3, 6) are generic OWASP teaching content using placeholder names (`OrderController`, `SearchOrders`) — they were never copied from this project's real code, so there's no live file to point them at and no drift to fix. Only Layers 4 and 5 assume a configuration shape this app doesn't use. Leave everything else as-is.

- [ ] **Step 1: Fix Layer 4 (Auth Configuration) — this app doesn't hand-configure JWT validation**

Replace the "BAD/GOOD JWT configuration" code block (lines 149-179) with:
```
This app doesn't hand-build `TokenValidationParameters` — it delegates JWT validation to `Microsoft.Identity.Web`'s `AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"))` (`src/Backend/AHKFlowApp.API/Program.cs:130-135`), which reads issuer/audience/signing-key config from the `AzureAd` section and validates all four checklist items above automatically. A test-only bypass exists for local dev (`TestAuthenticationHandler`, gated to `Development` + `Auth:UseTestProvider=true`, `Program.cs:114-129`) — flag it as a finding only if it can be reached outside Development. Scanning this project's auth means checking the `AzureAd` config is populated and that `useTestAuth` can't go true outside Development, not reviewing hand-rolled `TokenValidationParameters` (keep the BAD/GOOD block below only as a reference for other .NET apps that do configure JWT bearer manually).
```
Keep the existing BAD/GOOD code block below this new paragraph — don't delete it, since other projects using this skill may hand-roll JWT bearer.

- [ ] **Step 2: Fix Layer 5 (CORS Configuration) — point the GOOD example at the real policy**

Insert this paragraph immediately before the existing "GOOD — explicit origins" code block (before line 204):
```
This app's real CORS policy (`src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:10-24`) doesn't use a static `WithOrigins(...)` array like the block below — it uses `SetIsOriginAllowed` reading `Cors:AllowedOrigins` from live configuration on every request, so an edited `appsettings.Development.json` takes effect without an API restart. Check for that dynamic-origin pattern here specifically; the static-array block below is the general-case illustration.
```

- [ ] **Step 3: Leave Layers 1, 2, 3, 6, "Full Scan Report", "Anti-patterns", and "Decision Guide" as-is**

No drift found — these don't copy project-specific code.

- [ ] **Step 4: Re-check word count and commit**

Run: `wc -l .agents/dck-security-scan/SKILL.md`

```bash
git add .agents/dck-security-scan/SKILL.md
git commit -m "docs: point dck-security-scan auth/CORS layers at live code"
```

---

## Task 6: Close the loop

- [ ] **Step 1: Re-read all five rewritten files end to end**

Confirm no leftover contradiction (e.g. a "Decision Guide" row that still says `AppDbContext` where the body now says `IAppDbContext`).

- [ ] **Step 2: Report total line-count change**

Run: `wc -l .agents/dck-security-scan/SKILL.md .agents/dck-ef-core/SKILL.md .agents/dck-blazor-mudblazor/SKILL.md .agents/dck-scaffolding/SKILL.md .agents/dck-openapi/SKILL.md`

- [ ] **Step 3: Push and open the PR referencing #220**

```bash
git push -u origin fix/wt-skill-template-drift
gh pr create --title "docs: convert template-heavy skills to pointer style" --body "Closes #220"
```
