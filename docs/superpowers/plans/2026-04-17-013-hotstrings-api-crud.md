# Plan — Backlog 013: Hotstrings API CRUD + OpenAPI

## Context

Backlog 013 asks for five REST endpoints (create / update / delete / get-by-id / list-by-profile) for hotstrings, secured, documented via OpenAPI, with unit + integration tests.

The current repo is a greenfield .NET 10 rebuild — only `TestMessage` entity exists; no Hotstring/Profile code. The domain meaning (field names, AHK behavior flags, validation rules) is derived from the prior AHKFlow implementation. Port the **domain meaning**; do NOT copy its patterns (repository pattern, int Ids, global uniqueness, unprotected endpoints) — those conflict with the new project's AGENTS.md.

**What 013 owns end-to-end** (none of this exists yet in either project in the right shape):
1. Hotstring domain entity + EF config + migration.
2. First real MediatR CQRS pipeline use (handlers returning `Result<T>`).
3. First wiring of `Ardalis.Result.AspNetCore` → `ToActionResult(this)` in a controller.
4. OpenAPI XML docs generation + `IncludeXmlComments` + `Swashbuckle.AspNetCore.Filters` examples.
5. Hotstring test builder.
6. First paginated list query + `PagedResult<T>` envelope (reusable for later list endpoints).
7. Dev-only seeder endpoint (improves on old `TestDataHelper`).

## Resolved design decisions (from clarifying round)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `Guid` Id | Multi-tenant safe, no distributed sequence collisions, public-URL friendly |
| 2 | Two filtered unique indexes on `(OwnerOid, ProfileId, Trigger)` and `(OwnerOid, Trigger) WHERE ProfileId IS NULL` | DB-level, race-proof enforcement for both profile-scoped and profile-less uniqueness (SQL Server otherwise treats NULLs as distinct for uniqueness) |
| 3 | `Trigger` max 50, `Replacement` max 4000 | 50 matches old validator; 4000 fits `nvarchar(4000)` row-page constraints — far beyond realistic replacement length |
| 4 | Cross-tenant returns 404 | Hides row existence from attacker enumerating another user's Ids |
| 5 | PUT returns 200 + full `HotstringDto` | Client gets authoritative server state (UpdatedAt, canonical casing) in one round-trip — cheaper than a follow-up GET |
| 6 | `Swashbuckle.AspNetCore.Filters` in | Request/response examples materially improve Swagger UX; trivial cost |
| 7 | Dev-only seeder endpoint (improved) | Useful for manual demos and Swagger try-it-out without hand-crafting bodies |
| 8 | Pagination on list | `page`/`pageSize` query params; `PagedResult<T>` envelope; default 50, max 200 |

## Domain shape reference

### Domain shape (port as-is for field names + semantics)

Old `Hotstring`:
```csharp
public int      Id { get; set; }
public string   TriggerString { get; set; }                     // required, ≤50 chars
public string   ReplacementString { get; set; }                 // required, no cap
public bool     IsEndingCharacterRequired { get; set; } = true; // AHK option
public bool     IsTriggerInsideWord { get; set; } = true;       // AHK option
public int      ProfileId { get; set; }                         // FK, required
```

**Critical** — `IsEndingCharacterRequired` and `IsTriggerInsideWord` are AutoHotkey-semantic behavior flags. They determine whether a trigger fires after a delimiter (`::` vs `::*:` etc.) and whether it fires inside words (`::?:` option). These belong to 013, not a later item — without them the generated `.ahk` script can't reflect user intent. I had initially missed these. They are in.

### What the old project did poorly (do NOT copy)

| Old pattern | Why reject | What new does instead |
|---|---|---|
| Repository pattern (`IHotstringRepository`) | AGENTS.md forbids — "DbSet is already a repository" | Handlers inject `AppDbContext` directly |
| `int` auto-increment Id | Bad for multi-tenant / distributed creation / public URLs | `Guid` Id |
| Global `TriggerString` uniqueness (`.FirstOrDefault(x.Trigger == ...)`) | Breaks as soon as >1 user exists | Composite uniqueness `(OwnerOid, ProfileId, Trigger)` |
| Entity used directly as API contract | Couples DB shape to wire shape | Separate DTOs (`HotstringDto`, `Create...`, `Update...`) |
| `[Authorize]` commented out | Insecure | `[Authorize]` + `[RequiredScope("access_as_user")]` mandatory |
| Manual try/catch in controller | Leaks details, inconsistent | `GlobalExceptionMiddleware` + `Result<T>` |
| No `OwnerOid` (single-user SQLite) | New is multi-tenant Entra ID | Add `OwnerOid` column, filter every query |
| No `CreatedAt` / `UpdatedAt` | No audit trail | Add both, stamp via `TimeProvider` |
| FluentValidation not pipeline-wired (manual) | Validators authored but bypassed | Auto-runs via `ValidationBehavior` pipeline |

### Things 013 needs to add or defer

| Item | 013 action |
|---|---|
| `<GenerateDocumentationFile>true</GenerateDocumentationFile>` | **ADD** in `AHKFlowApp.API.csproj` |
| `Swashbuckle.AspNetCore.Filters` (request/response examples) | **ADD** package + examples — richer OpenAPI |
| AutoHotkey behavior flags on entity | **ADD** `IsEndingCharacterRequired`, `IsTriggerInsideWord` |
| `Profile` entity | **DEFER** — item 024. Use nullable `ProfileId` for now. |
| Typed HTTP client | **DEFER** — item 014 (Blazor UI CRUD) |
| MudBlazor hotstrings page | **DEFER** — item 014 |
| Search/filter | **DEFER** — item 019 |
| Seed data | **ADD** — improved dev-only seeder endpoint, richer sample set + flag variations |

Other infra the new project **already has** and the old project lacked: `ICurrentUser` + Entra claim extraction, `ValidationBehavior` pipeline, `Testcontainers` SQL Server fixture, `TestAuthHandler` + `TestUserBuilder`, `TimeProvider` as singleton, Serilog, `ProblemDetails` with traceId, `Ardalis.Result.AspNetCore` package referenced. The new project is strictly ahead on platform; 013 just uses those pieces for the first time.

## Design

### 1. Domain — `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs`

```csharp
public sealed class Hotstring
{
    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }         // from ICurrentUser.Oid — tenant isolation
    public Guid? ProfileId { get; private set; }       // nullable until item 024
    public string Trigger { get; private set; }        // was TriggerString — glossary prefers 'Trigger'
    public string Replacement { get; private set; }    // was ReplacementString
    public bool IsEndingCharacterRequired { get; private set; }
    public bool IsTriggerInsideWord { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    private Hotstring() { } // EF

    public static Hotstring Create(
        Guid ownerOid, string trigger, string replacement, Guid? profileId,
        bool isEndingCharacterRequired, bool isTriggerInsideWord, TimeProvider clock);

    public void Update(
        string trigger, string replacement, Guid? profileId,
        bool isEndingCharacterRequired, bool isTriggerInsideWord, TimeProvider clock);
}
```

No domain-layer business rules beyond timestamp stamping. Structural invariants enforced by FluentValidation + EF.

### 2. Infrastructure

**`Persistence/Configurations/HotstringConfiguration.cs`** (new — use `TestMessageConfiguration` as template):
- PK `Id`
- `OwnerOid`: required, indexed
- `ProfileId`: nullable, indexed
- `Trigger`: `nvarchar(50)`, required (matches old validator cap)
- `Replacement`: `nvarchar(4000)`, required (old had no cap; 4000 is reasonable)
- `IsEndingCharacterRequired`, `IsTriggerInsideWord`: `bit`, required
- `CreatedAt`, `UpdatedAt`: `datetimeoffset`, required
- **Two filtered unique indexes** (SQL Server treats `NULL`s as distinct for uniqueness, so a single composite index is insufficient):
  - `IX_Hotstring_Owner_Profile_Trigger` — `HasIndex(x => new { x.OwnerOid, x.ProfileId, x.Trigger }).IsUnique().HasFilter("[ProfileId] IS NOT NULL")`
  - `IX_Hotstring_Owner_Trigger_NoProfile` — `HasIndex(x => new { x.OwnerOid, x.Trigger }).IsUnique().HasFilter("[ProfileId] IS NULL")`
  - Together: uniqueness is enforced *within each profile*, and *among profile-less hotstrings per user*. Race-proof at DB level. Verify both via Testcontainers.

**`AppDbContext`**: add `public DbSet<Hotstring> Hotstrings => Set<Hotstring>();`

**Migration**: `dotnet ef migrations add AddHotstrings`

### 3. Application

**DTOs** (`src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`):
```csharp
public sealed record HotstringDto(
    Guid Id, Guid? ProfileId, string Trigger, string Replacement,
    bool IsEndingCharacterRequired, bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

public sealed record CreateHotstringDto(
    string Trigger, string Replacement, Guid? ProfileId,
    bool IsEndingCharacterRequired = true, bool IsTriggerInsideWord = true);

public sealed record UpdateHotstringDto(
    string Trigger, string Replacement, Guid? ProfileId,
    bool IsEndingCharacterRequired, bool IsTriggerInsideWord);
```

Defaults on `CreateHotstringDto` mirror old project (`= true` both flags).

**Pagination envelope** (`src/Backend/AHKFlowApp.Application/DTOs/PagedResult.cs` — new, reusable):
```csharp
public sealed record PagedResult<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}
```

**Commands** (`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/`):
- `CreateHotstringCommand(CreateHotstringDto Input) : IRequest<Result<HotstringDto>>` + `Handler` + `Validator`
- `UpdateHotstringCommand(Guid Id, UpdateHotstringDto Input) : IRequest<Result<HotstringDto>>` + `Handler` + `Validator`
- `DeleteHotstringCommand(Guid Id) : IRequest<Result>` + `Handler`

**Queries** (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/`):
- `GetHotstringQuery(Guid Id) : IRequest<Result<HotstringDto>>` + `Handler`
- `ListHotstringsQuery(Guid? ProfileId, int Page = 1, int PageSize = 50) : IRequest<Result<PagedResult<HotstringDto>>>` + `Handler` + `Validator`
  - Validator: `Page >= 1`, `PageSize` between `1` and `200`
  - Handler: orders by `CreatedAt DESC` for stable pagination, computes `TotalCount` + page slice in a single `IQueryable` pipeline

**Handler rules** (apply to all):
- Inject `AppDbContext`, `ICurrentUser`, `TimeProvider`
- Short-circuit `Result.Unauthorized()` if `currentUser.Oid is null`
- Scope every DB query by `OwnerOid == currentUser.Oid` — cross-tenant row → `Result.NotFound()` (hides existence)
- On Create/Update, catch `DbUpdateException` with SQL unique-violation → `Result.Conflict("Duplicate trigger within profile")`
- Explicit mapping Hotstring → HotstringDto (no Mapster/AutoMapper per AGENTS.md)

**Validators** (013 scope — structural, port from old `HotstringValidator`):
- `Trigger`: `NotEmpty`, `MaximumLength(50)` (matches old)
- `Replacement`: `NotEmpty`, `MaximumLength(4000)` (old had none; cap here)
- `IsEndingCharacterRequired`, `IsTriggerInsideWord`: no validator (bool always valid)
- Rich AHK-specific rules (reserved chars, etc.) defer to item 015

### 4. API — `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`

```csharp
[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
public sealed class HotstringsController(IMediator mediator) : ControllerBase
{
    /// <summary>List hotstrings for the current user, optionally filtered by profile. Paginated.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<HotstringDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> List(
        [FromQuery] Guid? profileId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        (await mediator.Send(new ListHotstringsQuery(profileId, page, pageSize), ct)).ToActionResult(this);

    /// <summary>Get a hotstring by id.</summary>
    [HttpGet("{id:guid}", Name = "GetHotstring")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetHotstringQuery(id), ct)).ToActionResult(this);

    /// <summary>Create a new hotstring for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Create([FromBody] CreateHotstringDto dto, CancellationToken ct)
    {
        var result = await mediator.Send(new CreateHotstringCommand(dto), ct);
        if (result.IsSuccess)
            return CreatedAtRoute("GetHotstring", new { id = result.Value.Id }, result.Value);
        return result.ToActionResult(this);
    }

    /// <summary>Update an existing hotstring.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateHotstringDto dto, CancellationToken ct) =>
        (await mediator.Send(new UpdateHotstringCommand(id, dto), ct)).ToActionResult(this);

    /// <summary>Delete a hotstring.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct) =>
        (await mediator.Send(new DeleteHotstringCommand(id), ct)).ToActionResult(this);
}
```

Shared 401 / 403 responses inherited from class-level `[Authorize]` + `[RequiredScope]` — document via a `ConfigureDefaultResponses` operation filter (or simply add `[ProducesResponseType(401)]` / `[ProducesResponseType(403)]` to each method — decide during implementation).

### 5. OpenAPI wiring

**`src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj`**:
```xml
<PropertyGroup>
  <GenerateDocumentationFile>true</GenerateDocumentationFile>
  <NoWarn>$(NoWarn);CS1591</NoWarn>
</PropertyGroup>
```

**`src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs`** — inside `AddSwaggerGen`:
```csharp
var xmlPath = Path.Combine(AppContext.BaseDirectory, "AHKFlowApp.API.xml");
if (File.Exists(xmlPath)) options.IncludeXmlComments(xmlPath, includeControllerXmlComments: true);
options.ExampleFilters();
```

Add package `Swashbuckle.AspNetCore.Filters` (old project had it; new doesn't). Add `CreateHotstringDtoExample`, `HotstringDtoExample`, `PagedHotstringDtoExample` under `src/Backend/AHKFlowApp.API/OpenApi/Examples/` — this is a small net-new addition borrowed from the old project. Examples give the Swagger UI concrete sample payloads — strong win for 013's OpenAPI AC.

### 6. Dev-only seeder

**`src/Backend/AHKFlowApp.API/Controllers/DevController.cs`** — mapped only when `app.Environment.IsDevelopment()` (guarded at DI/routing level; returns 404 otherwise).

```csharp
[ApiController]
[Route("api/v1/dev")]
[Authorize]
[RequiredScope("access_as_user")]
public sealed class DevController(IMediator mediator) : ControllerBase
{
    /// <summary>Seeds a curated set of sample hotstrings for the authenticated user. Development only.</summary>
    [HttpPost("hotstrings/seed")]
    [ProducesResponseType(typeof(PagedResult<HotstringDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> SeedHotstrings([FromQuery] bool reset = false, CancellationToken ct = default) =>
        (await mediator.Send(new SeedHotstringsCommand(reset), ct)).ToActionResult(this);
}
```

`SeedHotstringsCommand` handler (in `Application/Commands/Dev/`):
- Guarded by `IHostEnvironment.IsDevelopment()` inside handler too (defense in depth).
- If `reset=true`, deletes all hotstrings for the current user first.
- Inserts a curated set — improves on old `btw/fyi/f2f` with richer variety + flag combinations:

| Trigger | Replacement | `IsEndingCharacterRequired` | `IsTriggerInsideWord` |
|---------|-------------|-----------------------------|------------------------|
| `btw` | `by the way` | true | true |
| `fyi` | `for your information` | true | true |
| `omw` | `on my way` | true | true |
| `ty` | `thank you` | true | true |
| `afaik` | `as far as I know` | true | true |
| `idk` | `I don't know` | true | true |
| `brb` | `be right back` | true | true |
| `asap` | `as soon as possible` | true | true |
| `sig` | `— Bart Segers\nSenior Developer` | true | true |
| `@@em` | `hientruongsegers@outlook.com` | false | true |
| `ssn` | `SELECT * FROM ` | false | false |
| `:date:` | dynamic → current date (ISO 8601) | false | false |

Last three exercise the two boolean flags in non-default combinations, which also makes the Swagger responses more instructive.

> Note: this is scaffolding, not a permanent feature. Marked `[Obsolete]` is overkill; rely on the `IsDevelopment()` gate and a `// Dev-only` comment on the command class.

### 7. Tests

**Unit tests** (`tests/AHKFlowApp.Application.Tests/Hotstrings/`):
- `CreateHotstringValidatorTests` — empty/too-long trigger, empty replacement
- `UpdateHotstringValidatorTests` — same rules
- `CreateHotstringHandlerTests` — happy path, unauthorized when no `Oid`, conflict on duplicate `(Owner,Profile,Trigger)`
- `UpdateHotstringHandlerTests` — happy path, not-found (wrong owner), not-found (missing id), conflict on duplicate
- `DeleteHotstringHandlerTests` — 204, 404 when wrong owner
- `GetHotstringHandlerTests` — 200, 404 when wrong owner
- `ListHotstringsHandlerTests` — empty, scoped to owner, filtered by profileId, null profileId returns all, page/pageSize honored, `TotalCount` correct across multi-page scenarios, PageSize=200 boundary
- `ListHotstringsValidatorTests` — page<1 → invalid, pageSize<1 → invalid, pageSize>200 → invalid

Handler tests use real `AppDbContext` against `SqlContainerFixture` (no `UseInMemoryDatabase` — AGENTS.md). NSubstitute only on `ICurrentUser`. `TimeProvider` via a fake fixed clock for deterministic timestamps.

**Integration tests** (`tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`, `[Collection("WebApi")]`):
- POST → 201 + `Location` header → GET 200
- POST with invalid body → 400 Problem Details with `errors` dictionary (ValidationBehavior path)
- POST duplicate trigger in same profile → 409
- PUT unknown id → 404
- PUT another user's row → 404 (tenant isolation, uses `WithTestAuth(builder => builder.WithOid(otherGuid))`)
- DELETE 204 → GET 404
- GET `?profileId=...` returns filtered list
- GET `?page=2&pageSize=2` returns correct slice with matching `TotalCount`
- GET `?pageSize=500` → 400 (validator cap)
- GET without bearer → 401
- GET with bearer but no `access_as_user` scope → 403 (`.WithoutScope()`)
- PUT success → 200 with updated DTO body (not 204), `UpdatedAt > CreatedAt`
- `POST /api/v1/dev/hotstrings/seed` in Development → 200, user now has ≥12 hotstrings; `reset=true` prunes prior rows first
- `POST /api/v1/dev/hotstrings/seed` in non-Development → 404 (routing not mapped)

**Test builder** (`tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs`):
- Fluent builder matching style of `HealthResponseBuilder` / `TestUserBuilder`
- Defaults: random `Id`, random `OwnerOid`, null `ProfileId`, `"btw"` / `"by the way"`, both flags `true`, now-ish timestamps
- `WithOwner`, `InProfile`, `WithTrigger`, `WithReplacement`, `WithEndingCharacterRequired`, `WithTriggerInsideWord`, `Build()`

## Files to create / modify

**Create:**
- `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs`
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Migrations/<ts>_AddHotstrings.cs` (ef-generated)
- `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/PagedResult.cs`
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/{Create,Update,Delete}HotstringCommand{,Handler,Validator}.cs`
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand{,Handler}.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/{Get,List}HotstringsQuery{,Handler}.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQueryValidator.cs`
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`
- `src/Backend/AHKFlowApp.API/Controllers/DevController.cs` (dev-only routing)
- `src/Backend/AHKFlowApp.API/OpenApi/Examples/HotstringExamples.cs`
- `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs`
- `tests/AHKFlowApp.Application.Tests/Hotstrings/*Tests.cs`
- `tests/AHKFlowApp.Application.Tests/Dev/SeedHotstringsHandlerTests.cs`
- `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`
- `tests/AHKFlowApp.API.Tests/Dev/DevSeederEndpointTests.cs`

**Modify:**
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` — add `DbSet<Hotstring>`
- `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj` — `<GenerateDocumentationFile>true</GenerateDocumentationFile>` + `<PackageReference Include="Swashbuckle.AspNetCore.Filters" />`
- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs` — `IncludeXmlComments`, `ExampleFilters`, register `AssemblyMarker` for examples
- `src/Backend/AHKFlowApp.API/Program.cs` — conditional `MapControllers` guard so `DevController` only binds when `env.IsDevelopment()` (or use `[Conditional]`-style feature gate via endpoint convention)
- `Directory.Packages.props` — add `Swashbuckle.AspNetCore.Filters`

## Reused infrastructure (do not rebuild)

- `ICurrentUser` → `src/Backend/AHKFlowApp.Application/Abstractions/ICurrentUser.cs`
- `ValidationBehavior<,>` → `src/Backend/AHKFlowApp.Application/Behaviors/ValidationBehavior.cs`
- `GlobalExceptionMiddleware` → `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs`
- `CustomWebApplicationFactory` + `SqlContainerFixture` + `TestAuthHandler` + `TestUserBuilder` → `tests/AHKFlowApp.TestUtilities/`
- `TimeProvider` (registered in `Program.cs`)
- `Ardalis.Result.AspNetCore` — package already referenced

## Verification

1. `dotnet build --configuration Release` — clean
2. `dotnet ef database update --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API` — migration applies; check indexes created via `sp_helpindex Hotstrings` (expect PK + 2 filtered unique indexes + any extra single-column indexes)
3. `dotnet test --configuration Release` — all green (incl. Testcontainers integration, pagination assertions, seeder dev-only gating)
4. `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + Docker SQL (Recommended)"` → open `/swagger`:
   - 5 Hotstrings endpoints + 1 Dev endpoint listed (Dev endpoint absent in non-Dev builds)
   - Each shows XML `<summary>` text, schemas, `200/201/400/404/409` responses, padlock (Bearer)
   - List endpoint shows `page`, `pageSize`, `profileId` query params
   - Request/response examples appear (from Swashbuckle.AspNetCore.Filters)
   - Try-it-out works with a pasted bearer token
   - Hit `POST /api/v1/dev/hotstrings/seed` with `reset=true` → then GET list shows 12 seeded rows
5. `dotnet format --verify-no-changes` — clean

## Branch + commits

- Branch: `feature/013-hotstrings-api-crud`
- Atomic commits:
  1. domain + EF config + migration (Hotstring + filtered unique indexes)
  2. `PagedResult<T>` + DTOs + hotstring commands/queries/handlers/validators
  3. `HotstringsController` + OpenAPI wiring (XML docs + Swashbuckle examples)
  4. Dev-only seeder (`DevController` + `SeedHotstringsCommand` + dev routing gate)
  5. tests (unit + integration + `HotstringBuilder`)
