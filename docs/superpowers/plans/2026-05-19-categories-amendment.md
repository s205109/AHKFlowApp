# Categories Plan Amendment — UserPreference Seed Marker + Paginated List

**Companion to:** `docs/superpowers/plans/2026-05-19-categories.md`
**Date:** 2026-05-19

This file supersedes Tasks 4, 5, 12, 13, and 19 in the original plan. The spec `docs/superpowers/specs/2026-05-19-categories-design.md` was tightened after the original plan was drafted. Two changes propagate here:

1. **Seed-state marker.** Track "has this user ever been seeded?" via a new nullable `UserPreference.CategoriesSeededAt: DateTimeOffset?` field — not by row count. Deleting all defaults does **not** trigger re-seed.
2. **Paginated list.** `GET /api/v1/categories` returns `PagedList<CategoryDto>` with `page`/`pageSize`/`search` query parameters (mirroring `ListHotstringsQuery`).

Execute the original plan top-to-bottom **except** when you reach Task 4, 5, 12, 13, or 19, apply the version below.

---

## Task 4 (revised) — DbContext + IAppDbContext + UserPreference Marker

**Files (extends original):**
- All originals **plus**:
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/UserPreference.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/UserPreferenceConfiguration.cs`

- [ ] **Step 1: Add DbSets** — as in the original Task 4.

- [ ] **Step 2: Add the seed marker to `UserPreference`**

```csharp
// src/Backend/AHKFlowApp.Domain/Entities/UserPreference.cs (additions only)
public DateTimeOffset? CategoriesSeededAt { get; private set; }

public void MarkCategoriesSeeded(TimeProvider clock)
{
    if (CategoriesSeededAt is not null) return; // idempotent
    DateTimeOffset now = clock.GetUtcNow();
    CategoriesSeededAt = now;
    UpdatedAt = now;
}
```

- [ ] **Step 3: EF config**

```csharp
// Inside UserPreferenceConfiguration.Configure(builder)
builder.Property(x => x.CategoriesSeededAt).IsRequired(false);
```

- [ ] **Step 4: Build + commit**

```bash
dotnet build --no-restore
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs \
        src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs \
        src/Backend/AHKFlowApp.Domain/Entities/UserPreference.cs \
        src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/UserPreferenceConfiguration.cs
git commit -m "feat: expose Category DbSets and add UserPreference.CategoriesSeededAt marker"
```

---

## Task 5 (revised) — Migration Scope Includes the Column

The generated `<timestamp>_AddCategories` migration adds **all** of the original tables **plus** a nullable `CategoriesSeededAt datetimeoffset NULL` column on `UserPreferences`. Verify both before applying.

Everything else in the original Task 5 is unchanged.

---

## Task 12 (revised) — `ListCategoriesQuery` — Paginated + Marker-Based Lazy Seed

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Categories/ListCategoriesQuery.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryValidatorTests.cs`

Two responsibilities in one query:

1. **First-call seeding** — when the caller's `UserPreference.CategoriesSeededAt` is `null`, insert the eight starter categories AND mark the preference. Subsequent calls skip seeding. **The marker is the source of truth** — deleting all categories does not re-seed.
2. **Paginated read** — returns `PagedList<CategoryDto>` honoring `Page`, `PageSize`, `Search` (LIKE on `Name`, case-insensitive via DB collation).

- [ ] **Step 1: Handler tests first**

```csharp
// tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

[Collection("CategoryDb")]
public sealed class ListCategoriesQueryHandlerTests(CategoryDbFixture fx)
{
    private static readonly string[] s_expectedDefaultsAlpha =
    [
        "App Launcher", "Autocorrect", "Code", "Communication",
        "DateTime", "Email", "Symbols", "Window Management",
    ];

    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));

    private ICurrentUser UserFor(Guid oid)
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(oid);
        return u;
    }

    [Fact]
    public async Task First_Call_LazySeeds_Defaults_AndSetsMarker()
    {
        Guid owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, UserFor(owner), _clock);

        Result<PagedList<CategoryDto>> result = await sut.Handle(new ListCategoriesQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Select(c => c.Name).Should().BeEquivalentTo(s_expectedDefaultsAlpha);
        result.Value.TotalCount.Should().Be(8);
        (await ctx.Categories.CountAsync(c => c.OwnerOid == owner)).Should().Be(8);

        UserPreference? pref = await ctx.UserPreferences.AsNoTracking()
            .FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref.Should().NotBeNull();
        pref!.CategoriesSeededAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public async Task Second_Call_DoesNotReseed()
    {
        Guid owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, UserFor(owner), _clock);

        await sut.Handle(new ListCategoriesQuery(), default);
        await sut.Handle(new ListCategoriesQuery(), default);

        (await ctx.Categories.CountAsync(c => c.OwnerOid == owner)).Should().Be(8);
    }

    [Fact]
    public async Task DoesNotReseed_After_User_Deleted_All_Defaults()
    {
        Guid owner = Guid.NewGuid();

        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            var seedSut = new ListCategoriesQueryHandler(seedCtx, UserFor(owner), _clock);
            await seedSut.Handle(new ListCategoriesQuery(), default);
        }

        // Wipe every category the user owns.
        await using (AppDbContext deleteCtx = fx.CreateContext())
        {
            List<Category> all = await deleteCtx.Categories.Where(c => c.OwnerOid == owner).ToListAsync();
            deleteCtx.Categories.RemoveRange(all);
            await deleteCtx.SaveChangesAsync();
        }

        await using AppDbContext readCtx = fx.CreateContext();
        var readSut = new ListCategoriesQueryHandler(readCtx, UserFor(owner), _clock);
        Result<PagedList<CategoryDto>> result = await readSut.Handle(new ListCategoriesQuery(), default);

        result.Value.TotalCount.Should().Be(0);
        result.Value.Items.Should().BeEmpty();
    }

    [Fact]
    public async Task DoesNotShow_OtherUsers_Categories()
    {
        Guid me = Guid.NewGuid();
        Guid other = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();

        ctx.Categories.Add(new CategoryBuilder().WithOwner(other).Named("Private").Build());

        // Pre-mark "me" as seeded so the call below doesn't auto-seed.
        var mePref = UserPreference.CreateDefault(me, _clock);
        mePref.MarkCategoriesSeeded(_clock);
        ctx.UserPreferences.Add(mePref);
        await ctx.SaveChangesAsync();

        var sut = new ListCategoriesQueryHandler(ctx, UserFor(me), _clock);
        Result<PagedList<CategoryDto>> result = await sut.Handle(new ListCategoriesQuery(), default);

        result.Value.Items.Should().NotContain(c => c.Name == "Private");
        result.Value.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task Search_MatchesNameSubstring_CaseInsensitive()
    {
        Guid owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, UserFor(owner), _clock);
        await sut.Handle(new ListCategoriesQuery(), default); // lazy-seed

        Result<PagedList<CategoryDto>> result = await sut.Handle(
            new ListCategoriesQuery(Search: "EMAIL"), default);

        result.Value.Items.Should().ContainSingle(c => c.Name == "Email");
        result.Value.TotalCount.Should().Be(1);
    }

    [Fact]
    public async Task Pagination_Respects_PageAndPageSize()
    {
        Guid owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, UserFor(owner), _clock);
        await sut.Handle(new ListCategoriesQuery(), default); // 8 rows

        Result<PagedList<CategoryDto>> p1 = await sut.Handle(new ListCategoriesQuery(Page: 1, PageSize: 3), default);
        Result<PagedList<CategoryDto>> p2 = await sut.Handle(new ListCategoriesQuery(Page: 2, PageSize: 3), default);
        Result<PagedList<CategoryDto>> p3 = await sut.Handle(new ListCategoriesQuery(Page: 3, PageSize: 3), default);

        p1.Value.Items.Should().HaveCount(3);
        p2.Value.Items.Should().HaveCount(3);
        p3.Value.Items.Should().HaveCount(2);
        p1.Value.TotalCount.Should().Be(8);
        p1.Value.HasNextPage.Should().BeTrue();
        p3.Value.HasNextPage.Should().BeFalse();
    }
}
```

- [ ] **Step 2: Validator tests**

```csharp
// tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryValidatorTests.cs
using AHKFlowApp.Application.Queries.Categories;
using FluentValidation.TestHelper;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

public sealed class ListCategoriesQueryValidatorTests
{
    private readonly ListCategoriesQueryValidator _sut = new();

    [Theory]
    [InlineData(0)]
    [InlineData(10_001)]
    public void Rejects_OutOfRange_Page(int page) =>
        _sut.TestValidate(new ListCategoriesQuery(Page: page))
            .ShouldHaveValidationErrorFor(q => q.Page);

    [Theory]
    [InlineData(0)]
    [InlineData(201)]
    public void Rejects_OutOfRange_PageSize(int pageSize) =>
        _sut.TestValidate(new ListCategoriesQuery(PageSize: pageSize))
            .ShouldHaveValidationErrorFor(q => q.PageSize);

    [Fact]
    public void Rejects_Search_Longer_Than_200() =>
        _sut.TestValidate(new ListCategoriesQuery(Search: new string('x', 201)))
            .ShouldHaveValidationErrorFor(q => q.Search);
}
```

- [ ] **Step 3: Implementation**

```csharp
// src/Backend/AHKFlowApp.Application/Queries/Categories/ListCategoriesQuery.cs
using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Categories;

public sealed record ListCategoriesQuery(
    int Page = 1,
    int PageSize = 50,
    string? Search = null) : IRequest<Result<PagedList<CategoryDto>>>;

public sealed class ListCategoriesQueryValidator : AbstractValidator<ListCategoriesQuery>
{
    public ListCategoriesQueryValidator()
    {
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
        RuleFor(x => x.Search).MaximumLength(200);
    }
}

internal sealed class ListCategoriesQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<ListCategoriesQuery, Result<PagedList<CategoryDto>>>
{
    private static readonly string[] s_defaults =
    [
        "Autocorrect", "Communication", "DateTime", "Email",
        "Code", "Symbols", "Window Management", "App Launcher",
    ];

    public async Task<Result<PagedList<CategoryDto>>> Handle(ListCategoriesQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        await EnsureLazySeededAsync(ownerOid, ct);

        IQueryable<Category> query = db.Categories.AsNoTracking()
            .Where(c => c.OwnerOid == ownerOid);

        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(c => EF.Functions.Like(c.Name, pattern));
        }

        int totalCount = await query.CountAsync(ct);

        List<CategoryDto> items = await query
            .OrderBy(c => c.Name)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(c => new CategoryDto(c.Id, c.Name, c.CreatedAt, c.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<CategoryDto>(items, request.Page, request.PageSize, totalCount));
    }

    private async Task EnsureLazySeededAsync(Guid ownerOid, CancellationToken ct)
    {
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

        if (pref?.CategoriesSeededAt is not null)
            return;

        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            db.UserPreferences.Add(pref);
        }

        foreach (string name in s_defaults)
            db.Categories.Add(Category.Create(ownerOid, name, clock));

        pref.MarkCategoriesSeeded(clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            db.Entry(pref).State = EntityState.Detached;
        }
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

- [ ] **Step 4: Run tests — all pass**

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Queries/Categories/ListCategoriesQuery.cs \
        tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryHandlerTests.cs \
        tests/AHKFlowApp.Application.Tests/Categories/ListCategoriesQueryValidatorTests.cs
git commit -m "feat: paginated ListCategoriesQuery with marker-based lazy seed"
```

---

## Task 13 (revised) — Controller with query params + paginated response

Replace the `List` action with:

```csharp
/// <summary>Paginated list of the current user's categories. Lazily seeds eight defaults on first call.</summary>
[HttpGet]
[ProducesResponseType(typeof(PagedList<CategoryDto>), StatusCodes.Status200OK)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<ActionResult<PagedList<CategoryDto>>> List(
    [FromQuery] int page = 1,
    [FromQuery] int pageSize = 50,
    [FromQuery] string? search = null,
    CancellationToken ct = default) =>
    (await mediator.Send(new ListCategoriesQuery(page, pageSize, search), ct))
        .ToProblemActionResult(this);
```

Integration test additions:

- First call returns `PagedList` with `TotalCount = 8` and seeded names.
- Re-call after deleting all categories → `TotalCount = 0`, no re-seed, no 500.
- `?search=Email` → `TotalCount = 1`.
- `?page=2&pageSize=3` → returns the 4th–6th categories alphabetically.

---

## Task 19 (revised) — Frontend client returns `PagedList<CategoryDto>`

Add a frontend `PagedList<T>` type (or reuse if hotstrings/hotkeys already have one). Update the client signature:

```csharp
public interface ICategoriesApiClient
{
    Task<PagedList<CategoryDto>> ListAsync(int page = 1, int pageSize = 50, string? search = null, CancellationToken ct = default);
    Task<CategoryDto> GetAsync(Guid id, CancellationToken ct = default);
    Task<CategoryDto> CreateAsync(CreateCategoryDto dto, CancellationToken ct = default);
    Task<CategoryDto> UpdateAsync(Guid id, UpdateCategoryDto dto, CancellationToken ct = default);
    Task DeleteAsync(Guid id, CancellationToken ct = default);
}
```

Implementation builds the query string from the optional parameters and `GetFromJsonAsync<PagedList<CategoryDto>>(...)`.

`Categories.razor` page: the `MudDataGrid<CategoryDto>.ServerData` callback reads `state.Page` (0-based) + `state.PageSize`, calls `_client.ListAsync(state.Page + 1, state.PageSize, _searchText)`, and constructs `GridData<CategoryDto> { Items = paged.Items, TotalItems = paged.TotalCount }`.

For chip-filter usage on `Hotstrings.razor` / `Hotkeys.razor` (needs all categories at once): `await _client.ListAsync(page: 1, pageSize: 200)` on page load. The realistic per-user category count is well below 200; if a user ever exceeds it, the chip set truncates silently — acceptable trade-off documented in the spec.

---

## Cross-Task Impact

- Task 4 commit now also includes `UserPreference.cs` + `UserPreferenceConfiguration.cs` changes.
- Task 5 migration scope grows by one column (`UserPreferences.CategoriesSeededAt`).
- Task 12 lazy-seed must set the marker in the same `SaveChangesAsync` call. Concurrent first-call races resolve via the `(OwnerOid, Name)` unique index on Category — the loser detaches its pending `UserPreference` insert and re-reads.
- The seed expansion plan's `SeedCategoriesCommand` and `SeedAllCommand` must also `MarkCategoriesSeeded(clock)` to suppress lazy-seed on a future `GET /categories` call. (Covered in the seed-expansion plan when written.)

## Self-Review Additions

- [ ] Marker is set on first call.
- [ ] Deleted-then-listed returns empty without re-seed.
- [ ] List endpoint returns `PagedList<CategoryDto>` with correct `TotalCount`.
- [ ] Chip filter uses `pageSize = 200` to fetch all categories for the chip set.
