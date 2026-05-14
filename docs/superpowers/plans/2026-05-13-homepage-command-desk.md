# Homepage Command Desk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 homepage at `/` — a basic command desk with welcome hero, CLI quickstart, three stat cards (Hotstrings / Hotkeys / Profiles) with 14-day sparkline, and a recent-activity list derived from existing entity timestamps.

**Architecture:** New `GET /api/v1/dashboard/stats` endpoint (MediatR query + handler + controller) returns all homepage data in a single response. Blazor `Home.razor` composes four small sub-components (`HeroSection`, `StatCard`, `RecentActivityCard`, `CliQuickstartCard`) and fetches data once via a typed API client.

**Tech Stack:** .NET 10, ASP.NET Core, EF Core, MediatR, Ardalis.Result, Microsoft.Identity.Web, Blazor WebAssembly, MudBlazor 9.x, xUnit + FluentAssertions + NSubstitute + Testcontainers (SQL Server) + bUnit, FakeTimeProvider.

**Spec:** `docs/superpowers/specs/2026-05-13-homepage-command-desk-design.md`

**Branch:** `feature/homepage-command-desk` (already created and contains the spec commit).

**Conventions to follow** (cross-cutting; do not relax):
- Controllers: `[ApiController]`, `[Route("api/v1/[controller]")]`, `[Authorize]`, `[RequiredScope("access_as_user")]`, return via `.ToProblemActionResult(this)`.
- Handlers: `internal sealed class`, primary constructor `(IAppDbContext db, ICurrentUser currentUser, TimeProvider clock)`, returns `Ardalis.Result<T>`, early-return `Result.Unauthorized()` when `currentUser.Oid is not Guid ownerOid`.
- Date/time fields are `DateTimeOffset`. Use `clock.GetUtcNow()` — never `DateTime.UtcNow`.
- Tests: AAA pattern with blank-line separation. Builders (`HotstringBuilder`, `HotkeyBuilder`, `ProfileBuilder`) for entity arrangement. `FakeTimeProvider` for time. `[Collection("WebApi")]` for API integration tests using `CustomWebApplicationFactory.WithTestAuth(b => b.WithOid(...))`. bUnit pages inherit `BunitContext` and call `Services.AddMudServices()` + `JSInterop.Mode = JSRuntimeMode.Loose`.
- Commit after every passing test cycle. Conventional commit prefixes: `feat:`, `test:`, `chore:`.

---

## File Structure

**Create**

```
src/Backend/AHKFlowApp.Application/DTOs/DashboardStatsDto.cs
src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQuery.cs
src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs
src/Frontend/AHKFlowApp.UI.Blazor/DTOs/DashboardStatsDto.cs
src/Frontend/AHKFlowApp.UI.Blazor/Services/IDashboardApiClient.cs
src/Frontend/AHKFlowApp.UI.Blazor/Services/DashboardApiClient.cs
src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HomeTimeFormat.cs
src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/HeroSection.razor
src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/StatCard.razor
src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/RecentActivityCard.razor
src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/CliQuickstartCard.razor

tests/AHKFlowApp.Application.Tests/Dashboard/GetDashboardStatsQueryHandlerTests.cs
tests/AHKFlowApp.Application.Tests/Dashboard/DashboardDbFixture.cs
tests/AHKFlowApp.API.Tests/Dashboard/DashboardEndpointsTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Services/DashboardApiClientTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HomeTimeFormatTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/HeroSectionTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/StatCardTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/RecentActivityCardTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/CliQuickstartCardTests.cs
tests/AHKFlowApp.UI.Blazor.Tests/Pages/HomePageTests.cs
```

**Modify**

```
src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor       — replace placeholder content
src/Frontend/AHKFlowApp.UI.Blazor/Program.cs             — register IDashboardApiClient (2 sites)
src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/css/app.css    — append CLI quickstart styles
```

---

## Task 1: Backend DTOs

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/DashboardStatsDto.cs`

No test for plain DTO records (project convention skips DTO unit tests). One commit.

- [ ] **Step 1: Create the DTO file**

```csharp
namespace AHKFlowApp.Application.DTOs;

public sealed record DashboardStatsDto(
    EntityStatsDto Hotstrings,
    EntityStatsDto Hotkeys,
    ProfileStatsDto Profiles,
    IReadOnlyList<RecentActivityItemDto> RecentActivity);

public sealed record EntityStatsDto(
    int Total,
    int CreatedThisWeek,
    IReadOnlyList<int> DailyBuckets);

public sealed record ProfileStatsDto(
    int Total,
    int Active,
    int Default,
    IReadOnlyList<int> DailyBuckets);

public sealed record RecentActivityItemDto(
    string Kind,
    string Action,
    string Label,
    DateTimeOffset OccurredAt);
```

- [ ] **Step 2: Verify it compiles**

Run: `dotnet build src/Backend/AHKFlowApp.Application --configuration Release`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/DTOs/DashboardStatsDto.cs
git commit -m "feat: add dashboard stats DTO records"
```

---

## Task 2: Backend Query + Handler (TDD)

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Dashboard/DashboardDbFixture.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Dashboard/GetDashboardStatsQueryHandlerTests.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQuery.cs`

### Background

- **Recent activity** = the top 5 across Hotstrings, Hotkeys, and Profiles ordered by `MAX(CreatedAt, UpdatedAt)` desc. `Action = "updated"` if `UpdatedAt > CreatedAt`, else `"created"`.
- **Label** per kind: hotstring → `Trigger`; hotkey → `Description`; profile → `Name`. (Key-combo formatting belongs to UI.)
- **CreatedThisWeek** = `CreatedAt >= now.AddDays(-7)`.
- **DailyBuckets** = an `IReadOnlyList<int>` of length 14, oldest→newest. For day-index `i`, bucket counts entities with `CreatedAt.UtcDate == (today - (13 - i)).UtcDate`. "today" = `now.Date` from the injected `TimeProvider`.
- All queries scoped to `currentUser.Oid`.

- [ ] **Step 1: Create the DB fixture (reuse existing pattern)**

Look at `tests/AHKFlowApp.Application.Tests/Profiles/ProfileDbFixture.cs` and mirror it. The dashboard fixture provides a clean `AppDbContext` per test against a shared Testcontainers SQL Server instance from `SqlContainerFixture`.

Create `tests/AHKFlowApp.Application.Tests/Dashboard/DashboardDbFixture.cs`:

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dashboard;

public sealed class DashboardDbFixture(SqlContainerFixture sql) : ICollectionFixture<SqlContainerFixture>
{
    public AppDbContext CreateContext()
    {
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(sql.ConnectionString)
            .Options;
        var ctx = new AppDbContext(options);
        ctx.Database.EnsureCreated();
        return ctx;
    }
}

[CollectionDefinition("DashboardDb")]
public sealed class DashboardDbCollection : ICollectionFixture<DashboardDbFixture>;
```

If the existing `ProfileDbFixture` has a different shape (e.g., extra cleanup), match that shape. **Read `ProfileDbFixture.cs` first** and adapt to the same constructor signature, cleanup hooks, and `AppDbContext` factory method names. Do not invent your own pattern.

- [ ] **Step 2: Write failing handler tests**

Create `tests/AHKFlowApp.Application.Tests/Dashboard/GetDashboardStatsQueryHandlerTests.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Dashboard;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dashboard;

[Collection("DashboardDb")]
public sealed class GetDashboardStatsQueryHandlerTests(DashboardDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly Guid _otherOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-13T12:00:00Z"));

    private GetDashboardStatsQueryHandler CreateSut(AppDbContext ctx)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return new GetDashboardStatsQueryHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new GetDashboardStatsQueryHandler(ctx, user, _clock);

        Result<DashboardStatsDto> result = await sut.Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Counts_only_current_user_entities()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Hotstrings.AddRange(
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(_clock).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(_clock).Build(),
            new HotstringBuilder().WithOwner(_otherOid).WithClock(_clock).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithClock(_clock).Build());
        ctx.Profiles.AddRange(
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Default").AsDefault(true).WithClock(_clock).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").AsDefault(false).WithClock(_clock).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Hotstrings.Total.Should().Be(2);
        result.Value.Hotkeys.Total.Should().Be(1);
        result.Value.Profiles.Total.Should().Be(2);
        result.Value.Profiles.Default.Should().Be(1);
        result.Value.Profiles.Active.Should().Be(1);
    }

    [Fact]
    public async Task Created_this_week_uses_seven_day_window()
    {
        await using AppDbContext ctx = fx.CreateContext();
        // Inside window: now-3d, now-6d23h. Outside: now-7d1h, now-30d.
        FakeTimeProvider inside1 = new(_clock.GetUtcNow().AddDays(-3));
        FakeTimeProvider inside2 = new(_clock.GetUtcNow().AddDays(-7).AddHours(1));
        FakeTimeProvider outside1 = new(_clock.GetUtcNow().AddDays(-7).AddHours(-1));
        FakeTimeProvider outside2 = new(_clock.GetUtcNow().AddDays(-30));
        ctx.Hotstrings.AddRange(
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(inside1).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(inside2).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(outside1).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithClock(outside2).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.Hotstrings.Total.Should().Be(4);
        result.Value.Hotstrings.CreatedThisWeek.Should().Be(2);
    }

    [Fact]
    public async Task Daily_buckets_length_is_fourteen_oldest_to_newest()
    {
        await using AppDbContext ctx = fx.CreateContext();
        // One entity per day for the last 14 days; verify buckets[0]=1 (oldest), buckets[13]=1 (today).
        for (int i = 0; i < 14; i++)
        {
            FakeTimeProvider c = new(_clock.GetUtcNow().AddDays(-(13 - i)));
            ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithClock(c).Build());
        }
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.Hotkeys.DailyBuckets.Should().HaveCount(14);
        result.Value.Hotkeys.DailyBuckets.Should().AllSatisfy(c => c.Should().Be(1));
    }

    [Fact]
    public async Task Recent_activity_returns_top_five_across_kinds_ordered_by_most_recent()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider t1 = new(_clock.GetUtcNow().AddMinutes(-60));
        FakeTimeProvider t2 = new(_clock.GetUtcNow().AddMinutes(-50));
        FakeTimeProvider t3 = new(_clock.GetUtcNow().AddMinutes(-40));
        FakeTimeProvider t4 = new(_clock.GetUtcNow().AddMinutes(-30));
        FakeTimeProvider t5 = new(_clock.GetUtcNow().AddMinutes(-20));
        FakeTimeProvider t6 = new(_clock.GetUtcNow().AddMinutes(-10));

        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs1").WithClock(t1).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithDescription("hk2").WithClock(t2).Build());
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("p3").AsDefault(false).WithClock(t3).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs4").WithClock(t4).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithDescription("hk5").WithClock(t5).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs6").WithClock(t6).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity.Should().HaveCount(5);
        result.Value.RecentActivity[0].Label.Should().Be("hs6");
        result.Value.RecentActivity[4].Label.Should().Be("hk2");
    }

    [Fact]
    public async Task Recent_activity_marks_updated_when_updated_after_created()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider tCreate = new(_clock.GetUtcNow().AddMinutes(-30));
        var hs = new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("yw").WithClock(tCreate).Build();
        ctx.Hotstrings.Add(hs);
        await ctx.SaveChangesAsync();
        // Simulate an Update by calling the domain Update method with a newer clock.
        FakeTimeProvider tUpdate = new(_clock.GetUtcNow().AddMinutes(-5));
        hs.Update(hs.Trigger, hs.Replacement, hs.AppliesToAllProfiles, hs.IsEndingCharacterRequired, hs.IsTriggerInsideWord, tUpdate);
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity[0].Action.Should().Be("updated");
        result.Value.RecentActivity[0].Kind.Should().Be("hotstring");
    }

    [Fact]
    public async Task Recent_activity_excludes_other_user_entities()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_otherOid).WithTrigger("theirs").WithClock(_clock).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity.Should().BeEmpty();
    }
}
```

- [ ] **Step 3: Run tests — expect failure (query/handler do not exist)**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~GetDashboardStatsQueryHandlerTests" --configuration Release`
Expected: build error — `GetDashboardStatsQuery` / `GetDashboardStatsQueryHandler` not found.

- [ ] **Step 4: Implement the query + handler**

Create `src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQuery.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Dashboard;

public sealed record GetDashboardStatsQuery : IRequest<Result<DashboardStatsDto>>;

internal sealed class GetDashboardStatsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<GetDashboardStatsQuery, Result<DashboardStatsDto>>
{
    private const int BucketDays = 14;
    private const int RecentActivityCount = 5;

    public async Task<Result<DashboardStatsDto>> Handle(GetDashboardStatsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        DateTimeOffset now = clock.GetUtcNow();
        DateTimeOffset weekAgo = now.AddDays(-7);
        DateTimeOffset bucketStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(-(BucketDays - 1));

        EntityStatsDto hotstrings = await BuildEntityStatsAsync(
            db.Hotstrings.Where(h => h.OwnerOid == ownerOid),
            h => h.CreatedAt, weekAgo, bucketStart, ct);

        EntityStatsDto hotkeys = await BuildEntityStatsAsync(
            db.Hotkeys.Where(h => h.OwnerOid == ownerOid),
            h => h.CreatedAt, weekAgo, bucketStart, ct);

        int profilesTotal = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid, ct);
        int profilesDefault = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid && p.IsDefault, ct);
        IReadOnlyList<int> profileBuckets = await BuildBucketsAsync(
            db.Profiles.Where(p => p.OwnerOid == ownerOid),
            p => p.CreatedAt, bucketStart, ct);
        var profiles = new ProfileStatsDto(profilesTotal, profilesTotal - profilesDefault, profilesDefault, profileBuckets);

        IReadOnlyList<RecentActivityItemDto> recent = await BuildRecentActivityAsync(ownerOid, ct);

        return Result.Success(new DashboardStatsDto(hotstrings, hotkeys, profiles, recent));
    }

    private static async Task<EntityStatsDto> BuildEntityStatsAsync<T>(
        IQueryable<T> query,
        System.Linq.Expressions.Expression<Func<T, DateTimeOffset>> createdAtSelector,
        DateTimeOffset weekAgo,
        DateTimeOffset bucketStart,
        CancellationToken ct)
    {
        int total = await query.CountAsync(ct);
        int createdThisWeek = await query.CountAsync(
            CombineGte(createdAtSelector, weekAgo), ct);
        IReadOnlyList<int> buckets = await BuildBucketsAsync(query, createdAtSelector, bucketStart, ct);
        return new EntityStatsDto(total, createdThisWeek, buckets);
    }

    private static System.Linq.Expressions.Expression<Func<T, bool>> CombineGte<T>(
        System.Linq.Expressions.Expression<Func<T, DateTimeOffset>> selector,
        DateTimeOffset bound)
    {
        var p = selector.Parameters[0];
        var body = System.Linq.Expressions.Expression.GreaterThanOrEqual(
            selector.Body, System.Linq.Expressions.Expression.Constant(bound));
        return System.Linq.Expressions.Expression.Lambda<Func<T, bool>>(body, p);
    }

    private static async Task<IReadOnlyList<int>> BuildBucketsAsync<T>(
        IQueryable<T> query,
        System.Linq.Expressions.Expression<Func<T, DateTimeOffset>> createdAtSelector,
        DateTimeOffset bucketStart,
        CancellationToken ct)
    {
        // Fetch CreatedAt timestamps newer than bucketStart, bucket on the client.
        // Server-side grouping by date across providers is fragile; this is small data (<= total per user).
        List<DateTimeOffset> dates = await query
            .Select(createdAtSelector)
            .Where(d => d >= bucketStart)
            .ToListAsync(ct);

        int[] buckets = new int[BucketDays];
        DateTime startDate = bucketStart.UtcDateTime.Date;
        foreach (DateTimeOffset d in dates)
        {
            int idx = (int)(d.UtcDateTime.Date - startDate).TotalDays;
            if (idx >= 0 && idx < BucketDays)
                buckets[idx]++;
        }
        return buckets;
    }

    private async Task<IReadOnlyList<RecentActivityItemDto>> BuildRecentActivityAsync(Guid ownerOid, CancellationToken ct)
    {
        var hsItems = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid)
            .Select(h => new RecentActivityItemDto(
                "hotstring",
                h.UpdatedAt > h.CreatedAt ? "updated" : "created",
                h.Trigger,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToListAsync(ct);

        var hkItems = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid)
            .Select(h => new RecentActivityItemDto(
                "hotkey",
                h.UpdatedAt > h.CreatedAt ? "updated" : "created",
                h.Description,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToListAsync(ct);

        var pItems = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid)
            .Select(p => new RecentActivityItemDto(
                "profile",
                p.UpdatedAt > p.CreatedAt ? "updated" : "created",
                p.Name,
                p.UpdatedAt > p.CreatedAt ? p.UpdatedAt : p.CreatedAt))
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToListAsync(ct);

        return hsItems.Concat(hkItems).Concat(pItems)
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToList();
    }
}
```

Note on the EF expression helper: `CombineGte` rewrites the `createdAt` selector into a `where` predicate so we can keep the count query on the server. If the EF Core provider complains about the `Expression.Constant(DateTimeOffset)` approach, replace `CreatedThisWeek` with two queries that explicitly cast at the call site (e.g., `db.Hotstrings.CountAsync(h => h.OwnerOid == ownerOid && h.CreatedAt >= weekAgo, ct)`). The handler shape stays the same — only the helper goes away.

- [ ] **Step 5: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~GetDashboardStatsQueryHandlerTests" --configuration Release`
Expected: all 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQuery.cs tests/AHKFlowApp.Application.Tests/Dashboard/
git commit -m "feat: add dashboard stats query and handler"
```

---

## Task 3: Backend Controller (TDD via integration test)

**Files:**
- Create: `tests/AHKFlowApp.API.Tests/Dashboard/DashboardEndpointsTests.cs`
- Create: `src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs`

- [ ] **Step 1: Write failing integration test**

Create `tests/AHKFlowApp.API.Tests/Dashboard/DashboardEndpointsTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Dashboard;

[Collection("WebApi")]
public sealed class DashboardEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task GET_stats_returns_200_with_dto_for_authenticated_user()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        DashboardStatsDto? dto = await response.Content.ReadFromJsonAsync<DashboardStatsDto>();
        dto.Should().NotBeNull();
        dto!.Hotstrings.DailyBuckets.Should().HaveCount(14);
        dto.Hotkeys.DailyBuckets.Should().HaveCount(14);
        dto.Profiles.DailyBuckets.Should().HaveCount(14);
    }

    [Fact]
    public async Task GET_stats_returns_401_for_unauthenticated_request()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 2: Run test — expect failure**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~DashboardEndpointsTests" --configuration Release`
Expected: 404 (route does not exist).

- [ ] **Step 3: Implement controller**

Create `src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs`:

```csharp
using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Dashboard;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
public sealed class DashboardController(IMediator mediator) : ControllerBase
{
    /// <summary>Aggregated counts, weekly delta, 14-day buckets, and recent activity for the home dashboard.</summary>
    [HttpGet("stats")]
    [ProducesResponseType(typeof(DashboardStatsDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<DashboardStatsDto>> GetStats(CancellationToken ct) =>
        (await mediator.Send(new GetDashboardStatsQuery(), ct)).ToProblemActionResult(this);
}
```

- [ ] **Step 4: Run test — expect pass**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~DashboardEndpointsTests" --configuration Release`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs tests/AHKFlowApp.API.Tests/Dashboard/
git commit -m "feat: add dashboard stats endpoint"
```

---

## Task 4: Frontend DTOs

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/DashboardStatsDto.cs`

Frontend DTOs mirror the backend DTOs by shape so `ReadFromJsonAsync<DashboardStatsDto>` deserializes correctly. Keep them as `public sealed record` for consistency.

- [ ] **Step 1: Create the DTO file**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record DashboardStatsDto(
    EntityStatsDto Hotstrings,
    EntityStatsDto Hotkeys,
    ProfileStatsDto Profiles,
    IReadOnlyList<RecentActivityItemDto> RecentActivity);

public sealed record EntityStatsDto(
    int Total,
    int CreatedThisWeek,
    IReadOnlyList<int> DailyBuckets);

public sealed record ProfileStatsDto(
    int Total,
    int Active,
    int Default,
    IReadOnlyList<int> DailyBuckets);

public sealed record RecentActivityItemDto(
    string Kind,
    string Action,
    string Label,
    DateTimeOffset OccurredAt);
```

- [ ] **Step 2: Verify build**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/DashboardStatsDto.cs
git commit -m "feat: add frontend dashboard stats DTO"
```

---

## Task 5: Frontend API Client (TDD)

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/DashboardApiClientTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IDashboardApiClient.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/DashboardApiClient.cs`

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Services/DashboardApiClientTests.cs`:

```csharp
using System.Net;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class DashboardApiClientTests
{
    private static DashboardApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetStatsAsync_OnSuccess_DeserializesDto()
    {
        var dto = new DashboardStatsDto(
            new EntityStatsDto(15, 3, Enumerable.Repeat(1, 14).ToArray()),
            new EntityStatsDto(6, 1, Enumerable.Repeat(0, 14).ToArray()),
            new ProfileStatsDto(5, 2, 1, Enumerable.Repeat(0, 14).ToArray()),
            Array.Empty<RecentActivityItemDto>());
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<DashboardStatsDto> result = await ClientWith(handler).GetStatsAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.Hotstrings.Total.Should().Be(15);
        result.Value.Profiles.Default.Should().Be(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/dashboard/stats");
        handler.LastRequest.Method.Should().Be(HttpMethod.Get);
    }

    [Fact]
    public async Task GetStatsAsync_On500_ReturnsFailure()
    {
        var handler = StubHttpMessageHandler.Status(HttpStatusCode.InternalServerError);

        ApiResult<DashboardStatsDto> result = await ClientWith(handler).GetStatsAsync();

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.ServerError);
    }
}
```

If `StubHttpMessageHandler.Status(...)` doesn't exist in the helper class, replace the second test's setup with `StubHttpMessageHandler.JsonResponse(HttpStatusCode.InternalServerError, new { })` — copy whichever helper the existing `ProfilesApiClientTests` uses for failure paths.

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~DashboardApiClientTests" --configuration Release`
Expected: build error — `DashboardApiClient` / `IDashboardApiClient` not found.

- [ ] **Step 3: Implement interface + client**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/IDashboardApiClient.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IDashboardApiClient
{
    Task<ApiResult<DashboardStatsDto>> GetStatsAsync(CancellationToken ct = default);
}
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/DashboardApiClient.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class DashboardApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IDashboardApiClient
{
    private const string Path = "api/v1/dashboard/stats";

    public Task<ApiResult<DashboardStatsDto>> GetStatsAsync(CancellationToken ct = default) =>
        SendAsync<DashboardStatsDto>(HttpMethod.Get, Path, content: null, ct);
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~DashboardApiClientTests" --configuration Release`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/IDashboardApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/DashboardApiClient.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/DashboardApiClientTests.cs
git commit -m "feat: add dashboard API client"
```

---

## Task 6: Register API client in Program.cs

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

Two registration sites exist in this file — one for the no-auth bootstrap path (`useAuth: false`) and one for the authed path (`useAuth: true`). Add `IDashboardApiClient` to both, alongside the existing `IProfilesApiClient` line.

- [ ] **Step 1: Add registration line to the no-auth section**

After the existing line:
```csharp
AddApiClient<IProfilesApiClient, ProfilesApiClient>(
    baseAddress, TimeSpan.FromSeconds(30), useAuth: false);
```

Insert:
```csharp
AddApiClient<IDashboardApiClient, DashboardApiClient>(
    baseAddress, TimeSpan.FromSeconds(15), useAuth: false);
```

- [ ] **Step 2: Add registration line to the authed section**

After the existing line:
```csharp
AddApiClient<IProfilesApiClient, ProfilesApiClient>(
    baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
```

Insert:
```csharp
AddApiClient<IDashboardApiClient, DashboardApiClient>(
    baseAddress, TimeSpan.FromSeconds(15), useAuth: true);
```

- [ ] **Step 3: Verify build**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Program.cs
git commit -m "feat: register dashboard API client in DI"
```

---

## Task 7: Relative time-format helper (TDD)

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HomeTimeFormatTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HomeTimeFormat.cs`

Rules for `Relative(DateTimeOffset utcNow, DateTimeOffset occurredAt)`:
- delta < 60 s → `"just now"`
- delta < 60 min → `"{m} min ago"` (1 min, 2 min, ...)
- delta < 24 h → `"{h} h ago"`
- same calendar date as `utcNow.AddDays(-1)` → `"Yesterday"`
- otherwise → `occurredAt.ToString("yyyy-MM-dd")`

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HomeTimeFormatTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class HomeTimeFormatTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-05-13T12:00:00Z");

    [Theory]
    [InlineData(-30, "just now")]
    [InlineData(-59, "just now")]
    public void Relative_under_one_minute_returns_just_now(int seconds, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddSeconds(seconds)).Should().Be(expected);

    [Theory]
    [InlineData(-2, "2 min ago")]
    [InlineData(-14, "14 min ago")]
    [InlineData(-59, "59 min ago")]
    public void Relative_under_one_hour_returns_minutes(int minutes, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddMinutes(minutes)).Should().Be(expected);

    [Theory]
    [InlineData(-1, "1 h ago")]
    [InlineData(-23, "23 h ago")]
    public void Relative_under_one_day_returns_hours(int hours, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddHours(hours)).Should().Be(expected);

    [Fact]
    public void Relative_yesterday_returns_yesterday() =>
        HomeTimeFormat.Relative(Now, Now.AddDays(-1)).Should().Be("Yesterday");

    [Fact]
    public void Relative_older_than_yesterday_returns_iso_date() =>
        HomeTimeFormat.Relative(Now, DateTimeOffset.Parse("2026-05-01T08:00:00Z"))
            .Should().Be("2026-05-01");
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HomeTimeFormatTests" --configuration Release`
Expected: build error — `HomeTimeFormat` not found.

- [ ] **Step 3: Implement**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HomeTimeFormat.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.Helpers;

public static class HomeTimeFormat
{
    public static string Relative(DateTimeOffset utcNow, DateTimeOffset occurredAt)
    {
        TimeSpan delta = utcNow - occurredAt;
        if (delta < TimeSpan.FromMinutes(1)) return "just now";
        if (delta < TimeSpan.FromHours(1)) return $"{(int)delta.TotalMinutes} min ago";
        if (delta < TimeSpan.FromDays(1)) return $"{(int)delta.TotalHours} h ago";
        if (occurredAt.UtcDateTime.Date == utcNow.UtcDateTime.AddDays(-1).Date) return "Yesterday";
        return occurredAt.ToString("yyyy-MM-dd");
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HomeTimeFormatTests" --configuration Release`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HomeTimeFormat.cs tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HomeTimeFormatTests.cs
git commit -m "feat: add HomeTimeFormat relative-time helper"
```

---

## Task 8: HeroSection component

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/HeroSectionTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/HeroSection.razor`

- [ ] **Step 1: Write failing test**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/HeroSectionTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Pages.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class HeroSectionTests : BunitContext
{
    public HeroSectionTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void Renders_eyebrow_title_and_subtitle()
    {
        IRenderedComponent<HeroSection> cut = Render<HeroSection>();

        cut.Markup.Should().Contain("AUTOHOTKEY HOTSTRING MANAGER & CLI");
        cut.Markup.Should().Contain("Welcome to AHK");
        cut.Markup.Should().Contain("<em>flow</em>");
        cut.Markup.Should().Contain("Manage your AutoHotkey hotstrings and hotkeys");
        cut.Markup.Should().Contain(".ahk");
    }
}
```

- [ ] **Step 2: Run test — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HeroSectionTests" --configuration Release`
Expected: build error — `HeroSection` not found.

- [ ] **Step 3: Implement**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/HeroSection.razor`:

```razor
<MudStack Spacing="2" Class="mb-2">
    <MudText Typo="Typo.overline" Color="Color.Primary">AUTOHOTKEY HOTSTRING MANAGER &amp; CLI</MudText>
    <MudText Typo="Typo.h2">Welcome to AHK<em>flow</em></MudText>
    <MudText Typo="Typo.body1">
        Manage your AutoHotkey hotstrings and hotkeys in one place.
        Define them once, organize them by profile, and download a valid
        <MudChip T="string" Size="Size.Small" Variant="Variant.Text" Class="mx-1">.ahk</MudChip>
        script — from the web or the CLI.
    </MudText>
</MudStack>
```

- [ ] **Step 4: Run test — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HeroSectionTests" --configuration Release`
Expected: test passes.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/HeroSection.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/HeroSectionTests.cs
git commit -m "feat: add HeroSection component"
```

---

## Task 9: StatCard component

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/StatCardTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/StatCard.razor`

`StatCard` parameters: `Title` (string), `Icon` (string — Material icon path), `Total` (int), `FooterText` (string), `DailyBuckets` (`IReadOnlyList<int>`).

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/StatCardTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Pages.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class StatCardTests : BunitContext
{
    public StatCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void Renders_title_total_and_footer()
    {
        IRenderedComponent<StatCard> cut = Render<StatCard>(ps => ps
            .Add(p => p.Title, "HOTSTRINGS")
            .Add(p => p.Icon, Icons.Material.Outlined.Abc)
            .Add(p => p.Total, 15)
            .Add(p => p.FooterText, "+3 this week")
            .Add(p => p.DailyBuckets, new[] { 0, 1, 0, 2, 1, 0, 3, 1, 2, 0, 1, 1, 2, 1 }));

        cut.Markup.Should().Contain("HOTSTRINGS");
        cut.Markup.Should().Contain("15");
        cut.Markup.Should().Contain("+3 this week");
    }

    [Fact]
    public void Renders_with_empty_buckets()
    {
        IRenderedComponent<StatCard> cut = Render<StatCard>(ps => ps
            .Add(p => p.Title, "HOTKEYS")
            .Add(p => p.Icon, Icons.Material.Outlined.Keyboard)
            .Add(p => p.Total, 0)
            .Add(p => p.FooterText, "+0 this week")
            .Add(p => p.DailyBuckets, new int[14]));

        cut.Markup.Should().Contain("0");
        cut.Markup.Should().Contain("+0 this week");
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~StatCardTests" --configuration Release`
Expected: `StatCard` not found.

- [ ] **Step 3: Implement**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/StatCard.razor`:

```razor
<MudPaper Class="pa-4" Elevation="1">
    <MudStack Spacing="2">
        <MudStack Row Spacing="2" AlignItems="AlignItems.Center">
            <MudIcon Icon="@Icon" Size="Size.Small" Color="Color.Default" />
            <MudText Typo="Typo.overline">@Title</MudText>
        </MudStack>
        <MudText Typo="Typo.h3">@Total</MudText>
        <MudText Typo="Typo.caption" Color="Color.Default">@FooterText</MudText>
        <MudChart ChartType="ChartType.Bar"
                  ChartSeries="@_series"
                  XAxisLabels="@_emptyLabels"
                  Width="100%"
                  Height="40px"
                  ChartOptions="@_chartOptions" />
    </MudStack>
</MudPaper>

@code {
    [Parameter, EditorRequired] public string Title { get; set; } = string.Empty;
    [Parameter, EditorRequired] public string Icon { get; set; } = string.Empty;
    [Parameter, EditorRequired] public int Total { get; set; }
    [Parameter, EditorRequired] public string FooterText { get; set; } = string.Empty;
    [Parameter, EditorRequired] public IReadOnlyList<int> DailyBuckets { get; set; } = [];

    private List<ChartSeries> _series = [];
    private string[] _emptyLabels = [];
    private ChartOptions _chartOptions = new()
    {
        DisableLegend = true,
        ShowLabels = false,
        ShowToolTips = false,
        YAxisTicks = 0,
        ChartPalette = ["#6AA84F"],
    };

    protected override void OnParametersSet()
    {
        _series =
        [
            new ChartSeries { Name = Title, Data = DailyBuckets.Select(i => (double)i).ToArray() }
        ];
        _emptyLabels = Enumerable.Repeat(string.Empty, DailyBuckets.Count).ToArray();
    }
}
```

If MudBlazor 9.x `ChartOptions` does not have all the named properties above, drop the ones it doesn't recognize — the build error will name them. The minimal must-have is hiding legend, labels, tooltips, and Y-axis ticks; everything else is decoration.

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~StatCardTests" --configuration Release`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/StatCard.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/StatCardTests.cs
git commit -m "feat: add StatCard component"
```

---

## Task 10: RecentActivityCard component

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/RecentActivityCardTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/RecentActivityCard.razor`

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/RecentActivityCardTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class RecentActivityCardTests : BunitContext
{
    public RecentActivityCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void Renders_each_item_with_label_and_action()
    {
        DateTimeOffset now = DateTimeOffset.Parse("2026-05-13T12:00:00Z");
        var items = new[]
        {
            new RecentActivityItemDto("hotstring", "created", "yw", now.AddMinutes(-2)),
            new RecentActivityItemDto("hotkey", "created", "Run Notepad", now.AddHours(-1)),
            new RecentActivityItemDto("profile", "updated", "Personal", now.AddDays(-1)),
        };

        IRenderedComponent<RecentActivityCard> cut = Render<RecentActivityCard>(ps => ps
            .Add(p => p.Items, items)
            .Add(p => p.UtcNow, now));

        cut.Markup.Should().Contain("Recent activity");
        cut.Markup.Should().Contain("yw");
        cut.Markup.Should().Contain("Run Notepad");
        cut.Markup.Should().Contain("Personal");
        cut.Markup.Should().Contain("2 min ago");
        cut.Markup.Should().Contain("1 h ago");
        cut.Markup.Should().Contain("Yesterday");
    }

    [Fact]
    public void Renders_empty_state_when_no_items()
    {
        IRenderedComponent<RecentActivityCard> cut = Render<RecentActivityCard>(ps => ps
            .Add(p => p.Items, Array.Empty<RecentActivityItemDto>())
            .Add(p => p.UtcNow, DateTimeOffset.UtcNow));

        cut.Markup.Should().Contain("No activity yet");
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~RecentActivityCardTests" --configuration Release`
Expected: not found.

- [ ] **Step 3: Implement**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/RecentActivityCard.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Helpers

<MudPaper Class="pa-4" Elevation="1">
    <MudText Typo="Typo.h6" Class="mb-2">Recent activity</MudText>
    @if (Items.Count == 0)
    {
        <MudText Typo="Typo.body2" Color="Color.Default">
            No activity yet — add your first hotstring to get started.
        </MudText>
    }
    else
    {
        <MudList T="RecentActivityItemDto" Dense Gutters="false">
            @foreach (RecentActivityItemDto item in Items)
            {
                <MudListItem T="RecentActivityItemDto">
                    <MudStack Row AlignItems="AlignItems.Center" Spacing="3">
                        <MudIcon Icon="@MudBlazor.Icons.Material.Filled.Circle"
                                 Size="Size.Small"
                                 Color="@IconColorFor(item)" />
                        <MudText Typo="Typo.body2" Class="flex-grow-1">@DescribeItem(item)</MudText>
                        <MudText Typo="Typo.caption" Color="Color.Default">
                            @HomeTimeFormat.Relative(UtcNow, item.OccurredAt)
                        </MudText>
                    </MudStack>
                </MudListItem>
            }
        </MudList>
    }
</MudPaper>

@code {
    [Parameter, EditorRequired] public IReadOnlyList<RecentActivityItemDto> Items { get; set; } = [];
    [Parameter] public DateTimeOffset UtcNow { get; set; } = DateTimeOffset.UtcNow;

    private static Color IconColorFor(RecentActivityItemDto item)
    {
        if (item.Action == "updated") return Color.Default;
        return item.Kind switch
        {
            "hotstring" => Color.Success,
            "hotkey" => Color.Warning,
            "profile" => Color.Secondary,
            _ => Color.Default,
        };
    }

    private static string DescribeItem(RecentActivityItemDto item) => (item.Kind, item.Action) switch
    {
        ("hotstring", "created") => $"Added hotstring {item.Label}",
        ("hotstring", "updated") => $"Updated hotstring {item.Label}",
        ("hotkey", "created")    => $"New hotkey saved — {item.Label}",
        ("hotkey", "updated")    => $"Updated hotkey — {item.Label}",
        ("profile", "created")   => $"Profile {item.Label} created",
        ("profile", "updated")   => $"Profile {item.Label} updated",
        _                        => $"{item.Kind} {item.Action} — {item.Label}",
    };
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~RecentActivityCardTests" --configuration Release`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/RecentActivityCard.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/RecentActivityCardTests.cs
git commit -m "feat: add RecentActivityCard component"
```

---

## Task 11: CliQuickstartCard component + CSS

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/CliQuickstartCardTests.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/CliQuickstartCard.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/css/app.css`

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/CliQuickstartCardTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Pages.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class CliQuickstartCardTests : BunitContext
{
    public CliQuickstartCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void Renders_title_and_three_commands()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();

        cut.Markup.Should().Contain("CLI quickstart");
        cut.Markup.Should().Contain("ahkflow new");
        cut.Markup.Should().Contain("ahkflow list");
        cut.Markup.Should().Contain("ahkflow download");
    }

    [Fact]
    public void Copy_button_invokes_clipboard_writeText()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();

        cut.FindAll("button.cli-copy-btn").First().Click();

        JSInterop.VerifyInvoke("navigator.clipboard.writeText");
    }
}
```

If `BunitContext.JSInterop.VerifyInvoke(string)` returns no overload matching navigator.clipboard, the implementation may use `IJSRuntime.InvokeVoidAsync("navigator.clipboard.writeText", text)` directly — adjust the verify call to whichever identifier the implementation invokes.

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~CliQuickstartCardTests" --configuration Release`
Expected: not found.

- [ ] **Step 3: Implement the component**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/CliQuickstartCard.razor`:

```razor
@inject IJSRuntime JS
@inject ISnackbar Snackbar

<MudPaper Class="pa-4" Elevation="1">
    <MudStack Row Spacing="2" AlignItems="AlignItems.Center" Class="mb-2">
        <MudIcon Icon="@MudBlazor.Icons.Material.Filled.Terminal" />
        <MudText Typo="Typo.h6">CLI quickstart</MudText>
    </MudStack>
    <div class="cli-block">
        @foreach (string cmd in _commands)
        {
            <div class="cli-line">
                <span class="cli-prompt">$</span>
                <span class="cli-text">@cmd</span>
                <MudIconButton Icon="@MudBlazor.Icons.Material.Filled.ContentCopy"
                               Size="Size.Small"
                               Color="Color.Inherit"
                               Class="cli-copy-btn"
                               aria-label="Copy command"
                               OnClick="@(() => CopyAsync(cmd))" />
            </div>
        }
    </div>
</MudPaper>

@code {
    private static readonly string[] _commands =
    [
        "ahkflow new \"yw\" \"you're welcome\" --profile work",
        "ahkflow list --profile work --grep \"typo\"",
        "ahkflow download ahk --profile work",
    ];

    private async Task CopyAsync(string text)
    {
        await JS.InvokeVoidAsync("navigator.clipboard.writeText", text);
        Snackbar.Add("Copied", Severity.Success);
    }
}
```

- [ ] **Step 4: Append CSS to app.css**

Open `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/css/app.css` and append:

```css
/* Home page — CLI quickstart code block */
.cli-block {
    background: #1e1e1e;
    color: #f5f5f5;
    border-radius: 6px;
    padding: 12px 16px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 0.875rem;
    line-height: 1.6;
}
.cli-line {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 2px 0;
}
.cli-line + .cli-line {
    margin-top: 2px;
}
.cli-prompt {
    color: #6AA84F;
    user-select: none;
}
.cli-text {
    flex: 1;
    white-space: pre-wrap;
    word-break: break-all;
}
.cli-copy-btn {
    color: #cccccc !important;
}
```

- [ ] **Step 5: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~CliQuickstartCardTests" --configuration Release`
Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/CliQuickstartCard.razor src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/css/app.css tests/AHKFlowApp.UI.Blazor.Tests/Pages/Home/CliQuickstartCardTests.cs
git commit -m "feat: add CliQuickstartCard component"
```

---

## Task 12: Home.razor page composition (TDD)

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HomePageTests.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor`

- [ ] **Step 1: Write failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HomePageTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HomePageTests : BunitContext
{
    private readonly IDashboardApiClient _api = Substitute.For<IDashboardApiClient>();

    public HomePageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private static DashboardStatsDto SampleStats() => new(
        new EntityStatsDto(15, 3, new int[14]),
        new EntityStatsDto(6, 1, new int[14]),
        new ProfileStatsDto(5, 2, 1, new int[14]),
        [
            new RecentActivityItemDto("hotstring", "created", "yw", DateTimeOffset.UtcNow.AddMinutes(-2)),
        ]);

    [Fact]
    public void OnLoad_Renders_skeleton_until_data_arrives()
    {
        TaskCompletionSource<ApiResult<DashboardStatsDto>> tcs = new();
        _api.GetStatsAsync(Arg.Any<CancellationToken>()).Returns(tcs.Task);

        IRenderedComponent<Home> cut = Render<Home>();

        cut.Markup.Should().Contain("mud-skeleton");
    }

    [Fact]
    public void OnSuccess_Renders_all_four_sections()
    {
        _api.GetStatsAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<DashboardStatsDto>.Ok(SampleStats())));

        IRenderedComponent<Home> cut = Render<Home>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("Welcome to AHK");        // hero
        cut.Markup.Should().Contain("HOTSTRINGS");            // stat card
        cut.Markup.Should().Contain("15");                    // total
        cut.Markup.Should().Contain("+3 this week");          // weekly delta
        cut.Markup.Should().Contain("2 active");              // profile subtitle
        cut.Markup.Should().Contain("Recent activity");       // activity card
        cut.Markup.Should().Contain("CLI quickstart");        // CLI card
    }

    [Fact]
    public void OnFailure_Renders_alert_plus_hero_and_cli()
    {
        _api.GetStatsAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<DashboardStatsDto>.Failure(ApiResultStatus.ServerError, null)));

        IRenderedComponent<Home> cut = Render<Home>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("mud-alert");
        cut.Markup.Should().Contain("Welcome to AHK");
        cut.Markup.Should().Contain("CLI quickstart");
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HomePageTests" --configuration Release`
Expected: build error / failures (page is still the old placeholder, `IDashboardApiClient` not injected).

- [ ] **Step 3: Replace Home.razor with the new page**

Replace the **entire** contents of `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor` with:

```razor
@page "/"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Pages.Home
@using AHKFlowApp.UI.Blazor.Services
@inject IDashboardApiClient DashboardApi

<PageTitle>AHKFlow</PageTitle>

<MudStack Spacing="6">

    <HeroSection />

    @if (_errorMessage is not null)
    {
        <MudAlert Severity="Severity.Warning">@_errorMessage</MudAlert>
    }

    <MudGrid>
        <MudItem xs="12" sm="6" md="4">
            @if (_loading)
            {
                <MudPaper Class="pa-4"><MudSkeleton SkeletonType="SkeletonType.Rectangle" Height="120px" /></MudPaper>
            }
            else
            {
                <StatCard Title="HOTSTRINGS"
                          Icon="@MudBlazor.Icons.Material.Outlined.Abc"
                          Total="@(_stats?.Hotstrings.Total ?? 0)"
                          FooterText="@($"+{_stats?.Hotstrings.CreatedThisWeek ?? 0} this week")"
                          DailyBuckets="@(_stats?.Hotstrings.DailyBuckets ?? new int[14])" />
            }
        </MudItem>
        <MudItem xs="12" sm="6" md="4">
            @if (_loading)
            {
                <MudPaper Class="pa-4"><MudSkeleton SkeletonType="SkeletonType.Rectangle" Height="120px" /></MudPaper>
            }
            else
            {
                <StatCard Title="HOTKEYS"
                          Icon="@MudBlazor.Icons.Material.Outlined.Keyboard"
                          Total="@(_stats?.Hotkeys.Total ?? 0)"
                          FooterText="@($"+{_stats?.Hotkeys.CreatedThisWeek ?? 0} this week")"
                          DailyBuckets="@(_stats?.Hotkeys.DailyBuckets ?? new int[14])" />
            }
        </MudItem>
        <MudItem xs="12" sm="6" md="4">
            @if (_loading)
            {
                <MudPaper Class="pa-4"><MudSkeleton SkeletonType="SkeletonType.Rectangle" Height="120px" /></MudPaper>
            }
            else
            {
                <StatCard Title="PROFILES"
                          Icon="@MudBlazor.Icons.Material.Outlined.Person"
                          Total="@(_stats?.Profiles.Total ?? 0)"
                          FooterText="@($"{_stats?.Profiles.Active ?? 0} active · {_stats?.Profiles.Default ?? 0} default")"
                          DailyBuckets="@(_stats?.Profiles.DailyBuckets ?? new int[14])" />
            }
        </MudItem>
    </MudGrid>

    <MudGrid>
        <MudItem xs="12" md="8">
            @if (_loading)
            {
                <MudPaper Class="pa-4"><MudSkeleton SkeletonType="SkeletonType.Rectangle" Height="200px" /></MudPaper>
            }
            else
            {
                <RecentActivityCard Items="@(_stats?.RecentActivity ?? Array.Empty<RecentActivityItemDto>())"
                                    UtcNow="@DateTimeOffset.UtcNow" />
            }
        </MudItem>
        <MudItem xs="12" md="4">
            <CliQuickstartCard />
        </MudItem>
    </MudGrid>

</MudStack>

@code {
    private DashboardStatsDto? _stats;
    private bool _loading = true;
    private string? _errorMessage;

    protected override async Task OnInitializedAsync()
    {
        ApiResult<DashboardStatsDto> result = await DashboardApi.GetStatsAsync();
        if (result.IsSuccess)
        {
            _stats = result.Value;
        }
        else
        {
            _errorMessage = "We couldn't load your dashboard data. Please try again later.";
        }
        _loading = false;
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HomePageTests" --configuration Release`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HomePageTests.cs
git commit -m "feat: replace home placeholder with command desk page"
```

---

## Task 13: Full-stack verification

**No new files.** Run the whole test suite, then exercise the page in a browser.

- [ ] **Step 1: Build all**

Run: `dotnet build --configuration Release`
Expected: success.

- [ ] **Step 2: Run all tests**

Run: `dotnet test --configuration Release --no-build`
Expected: all green.

- [ ] **Step 3: Format check**

Run: `dotnet format --verify-no-changes`
Expected: no changes required. If it reports diffs, run `dotnet format`, review, then commit them as `chore: dotnet format`.

- [ ] **Step 4: Start API and frontend locally**

Terminal A: `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"`
Terminal B: `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor`

Sign in. Open `http://localhost:5601/`.

- [ ] **Step 5: Manual verification checklist**

Visually verify:
- Hero renders with italic "*flow*" and the `.ahk` chip inline.
- Three stat cards show real counts, "+X this week" subtitle (or "N active · M default" for the profile card), and a 14-day bar sparkline.
- Recent activity lists up to 5 most-recent items with the correct icon color (green/amber/blue), label, and relative timestamp ("just now", "2 min ago", "1 h ago", "Yesterday", or `yyyy-MM-dd`).
- CLI quickstart card shows 3 example commands; clicking the copy icon puts the command text on the clipboard (paste into another app to confirm) and shows a "Copied" snackbar.

Empty-state verification:
- With no entities (fresh user or DB cleared): each stat card shows `0`, sparkline is flat (all zero bars), and Recent activity shows "No activity yet — add your first hotstring to get started.".

Error verification:
- Stop the API process. Refresh the page. The hero and CLI quickstart still render; a `MudAlert` Warning appears between them ("We couldn't load your dashboard data…"); stat cards and activity card show their empty/zero state.

- [ ] **Step 6: Push and open PR**

```bash
git push -u origin feature/homepage-command-desk
gh pr create --title "feat: homepage command desk v1" --body "$(cat <<'EOF'
## Summary
- New `/api/v1/dashboard/stats` endpoint aggregating Hotstring/Hotkey/Profile counts, weekly delta, 14-day bar buckets, and top-5 recent activity derived from CreatedAt/UpdatedAt.
- `Home.razor` replaced with a basic command-desk layout: hero, three stat cards with sparkline, recent activity list, CLI quickstart card.
- All sub-components built with default MudBlazor controls; one small CSS block for the CLI code listing.

## Test plan
- [ ] Backend handler unit tests cover authz, counts, weekly delta, 14-day bucket length, recent-activity ordering and "updated" classification, OwnerOid isolation.
- [ ] API integration test verifies 200 + DTO shape and 401 for unauthenticated request.
- [ ] Frontend bUnit tests cover the API client, time-format helper, and each sub-component.
- [ ] Home page tests cover skeleton, success, and error states.
- [ ] Manual verification in a browser against a real backend with empty, populated, and offline-API states.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**1. Spec coverage**
- Welcome hero → Task 8.
- CLI quickstart → Task 11.
- Three stat cards with count, weekly delta, 14-day sparkline → Tasks 9, 12; backend Tasks 1–3.
- Recent activity derived from CreatedAt/UpdatedAt → Tasks 2, 10.
- New `GET /api/v1/dashboard/stats` endpoint → Tasks 1–3.
- Single-call frontend fetch via typed API client → Tasks 4–6.
- Default MudBlazor components, minimal CSS → all frontend tasks; one CSS block in Task 11.
- Error handling: alert above hero/CLI, empty states in stat & activity → Tasks 10, 12.
- Skeleton on load → Task 12.
- Testing: handler tests, API tests, component tests, page tests → Tasks 2, 3, 5, 7, 8, 9, 10, 11, 12.

**2. Placeholder scan**
No `TBD`, `TODO`, or "appropriate error handling" stubs. Each test step lists actual asserts; each implementation step contains full code.

**3. Type / signature consistency**
- `DashboardStatsDto`, `EntityStatsDto`, `ProfileStatsDto`, `RecentActivityItemDto` are defined identically (record shape) on backend (Task 1) and frontend (Task 4) for JSON deserialization.
- Handler uses `DateTimeOffset` end-to-end matching `Hotstring`, `Hotkey`, `Profile` entity fields.
- Controller uses `.ToProblemActionResult(this)` matching the existing pattern in `ProfilesController`.
- `IDashboardApiClient.GetStatsAsync(CancellationToken)` returns `ApiResult<DashboardStatsDto>`; consumed identically in `Home.razor` and `DashboardApiClientTests`.
- `HomeTimeFormat.Relative(DateTimeOffset utcNow, DateTimeOffset occurredAt)` signature is consistent across helper, tests, and `RecentActivityCard`.

---

## Open from the spec (unanswered)

- "Active" profile = `!IsDefault`. Implemented as such — confirm vs. "currently selected".
- 14-day sparkline window. Implemented as 14 — confirm vs. 7 / 30.
- CLI quickstart commands aspirational (no matching CLI subcommands yet).
