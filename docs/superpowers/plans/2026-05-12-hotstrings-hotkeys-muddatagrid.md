# Hotstrings and Hotkeys MudDataGrid Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Hotstrings and Hotkeys `MudTable` pages with `MudDataGrid` pages that support server-backed paging, sorting, column filtering, and native grid editing without losing existing CRUD, validation, snackbar, and delete-confirmation behavior.

**Architecture:** Keep the API surface as GET endpoints with explicit query parameters, not serialized `GridState<T>`, because MudBlazor filter definitions contain component references. The Blazor pages translate `GridState<T>` into typed frontend request records, the API controllers pass allow-listed sort/filter fields into MediatR queries, and handlers apply explicit EF Core expressions before paging.

**Tech Stack:** .NET 10, Blazor WebAssembly, MudBlazor 9.3.0 `MudDataGrid`, MediatR, EF Core SQL Server, Ardalis.Result, FluentValidation, xUnit, bUnit, FluentAssertions, NSubstitute.

---

## References

- Official MudBlazor DataGrid API reference requested by the user: `https://mudblazor.com/components/datagrid#api`
- Installed package metadata checked locally: `MudBlazor` `9.3.0`, `C:\Users\btase\.nuget\packages\mudblazor\9.3.0\lib\net10.0\MudBlazor.xml`

MudBlazor API facts used by this plan:

- `MudDataGrid<T>.ServerData` accepts `Func<GridState<T>, Task<GridData<T>>>`.
- `GridState<T>.Page` is zero-based, while existing API pages are one-based.
- `GridState<T>` exposes `PageSize`, `SortDefinitions`, and `FilterDefinitions`.
- `GridData<T>` returns `Items` and `TotalItems`.
- `MudDataGrid<T>` exposes `ReloadServerData()`, `SetEditingItemAsync(T)`, and `CancelEditingItemAsync()`.
- `MudDataGridPager<T>` provides `PageSizeOptions`.
- `DataGridFilterMode.ColumnFilterMenu`, `SortMode.Single`, `DataGridEditMode.Cell`, and `DataGridEditTrigger.Manual` are available.

## File Structure

Create:

- `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotstringListRequest.cs` - frontend request record for Hotstrings list query parameters.
- `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotkeyListRequest.cs` - frontend request record for Hotkeys list query parameters.

Modify:

- `src\Backend\AHKFlowApp.Application\Queries\Hotstrings\ListHotstringsQuery.cs` - add allow-listed sort/filter fields and apply them in EF Core.
- `src\Backend\AHKFlowApp.Application\Queries\Hotkeys\ListHotkeysQuery.cs` - add allow-listed sort/filter fields and apply them in EF Core.
- `src\Backend\AHKFlowApp.API\Controllers\HotstringsController.cs` - bind new query parameters and pass them to `ListHotstringsQuery`.
- `src\Backend\AHKFlowApp.API\Controllers\HotkeysController.cs` - bind new query parameters and pass them to `ListHotkeysQuery`.
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotstringsApiClient.cs` - replace list signature with `HotstringListRequest`.
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotstringsApiClient.cs` - build the expanded query string.
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotkeysApiClient.cs` - replace list signature with `HotkeyListRequest`.
- `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotkeysApiClient.cs` - build the expanded query string.
- `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor` - migrate to `MudDataGrid<HotstringEditModel>`.
- `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor` - migrate to `MudDataGrid<HotkeyEditModel>`.
- `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryValidatorTests.cs` - add validation coverage for sort/filter fields.
- `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryHandlerTests.cs` - add server filter/sort coverage.
- `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryValidatorTests.cs` - add validation coverage for sort/filter fields.
- `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryHandlerTests.cs` - add server filter/sort coverage.
- `tests\AHKFlowApp.API.Tests\Hotstrings\HotstringsEndpointsTests.cs` - add endpoint query parameter coverage.
- `tests\AHKFlowApp.API.Tests\Hotkeys\HotkeysEndpointsTests.cs` - add endpoint query parameter coverage.
- `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotstringsApiClientTests.cs` - update list request usage and query string coverage.
- `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotkeysApiClientTests.cs` - update list request usage and query string coverage.
- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotstringsPageTests.cs` - update bUnit selectors and request assertions.
- `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotkeysPageTests.cs` - update bUnit selectors and request assertions.

No package additions are expected. Do not serialize MudBlazor `GridState<T>` or `IFilterDefinition<T>` to the API.

## Implementation Decisions

Use `MudDataGrid<HotstringEditModel>` and `MudDataGrid<HotkeyEditModel>`, not `MudDataGrid<HotstringDto>` or `MudDataGrid<HotkeyDto>`. The existing DTOs are positional records with init-only properties, which are a poor fit for native grid editing. The existing edit models are mutable, already map to create/update DTOs, and preserve current validation behavior.

Use one active edit item per page:

```csharp
private HotstringEditModel? _pendingCreate;
private HotstringEditModel? _editingItem;
private bool _commitAttempted;
```

The Hotkeys page uses the same shape with `HotkeyEditModel`.

Use the API sort field values below. These are the only values accepted by validators and handlers:

Hotstrings:

- `createdAt`
- `updatedAt`
- `trigger`
- `replacement`
- `isEndingCharacterRequired`
- `isTriggerInsideWord`

Hotkeys:

- `createdAt`
- `updatedAt`
- `description`
- `key`
- `ctrl`
- `alt`
- `shift`
- `win`
- `action`
- `parameters`

Use these filter fields:

Hotstrings:

- `triggerFilter`
- `replacementFilter`
- `appliesToAllProfiles`
- `isEndingCharacterRequired`
- `isTriggerInsideWord`

Hotkeys:

- `descriptionFilter`
- `keyFilter`
- `parametersFilter`
- `action`
- `appliesToAllProfiles`
- `ctrl`
- `alt`
- `shift`
- `win`

String filters use SQL `LIKE '%value%'`. Boolean and enum filters use exact equality. Existing `profileId` and `search` behavior stays unchanged and composes with column filters using `AND`.

---

### Task 1: Add Hotstrings Server Sort and Filter Support

**Files:**
- Modify: `src\Backend\AHKFlowApp.Application\Queries\Hotstrings\ListHotstringsQuery.cs`
- Modify: `src\Backend\AHKFlowApp.API\Controllers\HotstringsController.cs`
- Test: `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryValidatorTests.cs`
- Test: `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryHandlerTests.cs`
- Test: `tests\AHKFlowApp.API.Tests\Hotstrings\HotstringsEndpointsTests.cs`

- [ ] **Step 1: Write failing validator tests for new Hotstrings list parameters**

Add these tests to `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryValidatorTests.cs`:

```csharp
[Fact]
public void Validate_WithAllowedSortField_Succeeds()
{
    ValidationResult result = _sut.Validate(new ListHotstringsQuery(SortField: "trigger"));

    result.IsValid.Should().BeTrue();
}

[Fact]
public void Validate_WithUnknownSortField_Fails()
{
    ValidationResult result = _sut.Validate(new ListHotstringsQuery(SortField: "ownerOid"));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "SortField");
}

[Fact]
public void Validate_WithTriggerFilterTooLong_Fails()
{
    string filter = new('x', 201);

    ValidationResult result = _sut.Validate(new ListHotstringsQuery(TriggerFilter: filter));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "TriggerFilter");
}

[Fact]
public void Validate_WithReplacementFilterTooLong_Fails()
{
    string filter = new('x', 201);

    ValidationResult result = _sut.Validate(new ListHotstringsQuery(ReplacementFilter: filter));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "ReplacementFilter");
}
```

- [ ] **Step 2: Run Hotstrings validator tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotstringsQueryValidatorTests" --verbosity normal
```

Expected: FAIL because `ListHotstringsQuery` does not yet define `SortField`, `TriggerFilter`, or `ReplacementFilter`.

- [ ] **Step 3: Write failing Hotstrings handler tests for filter/sort behavior**

Add these tests to `tests\AHKFlowApp.Application.Tests\Hotstrings\ListHotstringsQueryHandlerTests.cs`:

```csharp
[Fact]
public async Task Handle_TriggerFilter_ComposesWithSearch()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "by the way", true, true, true, TimeProvider.System));
        seed.Hotstrings.Add(Hotstring.Create(owner, "btw2", "other text", true, true, true, TimeProvider.System));
        seed.Hotstrings.Add(Hotstring.Create(owner, "fyi", "by the way", true, true, true, TimeProvider.System));
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotstringDto>> result = await handler.Handle(
        new ListHotstringsQuery(Search: "way", TriggerFilter: "btw"), default);

    result.Value.Items.Should().HaveCount(1);
    result.Value.Items[0].Trigger.Should().Be("btw");
}

[Fact]
public async Task Handle_BooleanFilters_ReturnMatchingRows()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotstrings.Add(Hotstring.Create(owner, "a", "x", true, true, false, TimeProvider.System));
        seed.Hotstrings.Add(Hotstring.Create(owner, "b", "x", true, false, true, TimeProvider.System));
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotstringDto>> result = await handler.Handle(
        new ListHotstringsQuery(IsEndingCharacterRequired: true, IsTriggerInsideWord: false), default);

    result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
}

[Fact]
public async Task Handle_SortByTriggerAscending_ReturnsStableOrder()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotstrings.Add(Hotstring.Create(owner, "c", "x", true, true, true, TimeProvider.System));
        seed.Hotstrings.Add(Hotstring.Create(owner, "a", "x", true, true, true, TimeProvider.System));
        seed.Hotstrings.Add(Hotstring.Create(owner, "b", "x", true, true, true, TimeProvider.System));
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotstringDto>> result = await handler.Handle(
        new ListHotstringsQuery(SortField: "trigger", SortDescending: false), default);

    result.Value.Items.Select(h => h.Trigger).Should().Equal("a", "b", "c");
}
```

- [ ] **Step 4: Run Hotstrings handler tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotstringsQueryHandlerTests" --verbosity normal
```

Expected: FAIL because the query record and handler do not yet support the new fields.

- [ ] **Step 5: Implement Hotstrings query validation, filtering, and sorting**

Update `src\Backend\AHKFlowApp.Application\Queries\Hotstrings\ListHotstringsQuery.cs` with these changes.

Replace the query record with:

```csharp
public sealed record ListHotstringsQuery(
    Guid? ProfileId = null,
    string? Search = null,
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? TriggerFilter = null,
    string? ReplacementFilter = null,
    bool? AppliesToAllProfiles = null,
    bool? IsEndingCharacterRequired = null,
    bool? IsTriggerInsideWord = null) : IRequest<Result<PagedList<HotstringDto>>>;
```

Replace the validator body with:

```csharp
private static readonly string[] AllowedSortFields =
[
    "createdAt",
    "updatedAt",
    "trigger",
    "replacement",
    "isEndingCharacterRequired",
    "isTriggerInsideWord",
];

public ListHotstringsQueryValidator()
{
    RuleFor(x => x.Search).MaximumLength(200);
    RuleFor(x => x.TriggerFilter).MaximumLength(200);
    RuleFor(x => x.ReplacementFilter).MaximumLength(200);
    RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
    RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    RuleFor(x => x.SortField)
        .Must(field => string.IsNullOrWhiteSpace(field) || AllowedSortFields.Contains(field, StringComparer.OrdinalIgnoreCase))
        .WithMessage($"SortField must be one of: {string.Join(", ", AllowedSortFields)}.");
}
```

In `Handle`, after the existing global search block and before `CountAsync`, add:

```csharp
if (!string.IsNullOrWhiteSpace(request.TriggerFilter))
{
    string pattern = $"%{request.TriggerFilter.Trim()}%";
    query = query.Where(h => EF.Functions.Like(h.Trigger, pattern));
}

if (!string.IsNullOrWhiteSpace(request.ReplacementFilter))
{
    string pattern = $"%{request.ReplacementFilter.Trim()}%";
    query = query.Where(h => EF.Functions.Like(h.Replacement, pattern));
}

if (request.AppliesToAllProfiles is { } appliesToAllProfiles)
    query = query.Where(h => h.AppliesToAllProfiles == appliesToAllProfiles);

if (request.IsEndingCharacterRequired is { } isEndingCharacterRequired)
    query = query.Where(h => h.IsEndingCharacterRequired == isEndingCharacterRequired);

if (request.IsTriggerInsideWord is { } isTriggerInsideWord)
    query = query.Where(h => h.IsTriggerInsideWord == isTriggerInsideWord);
```

Replace the ordering chain before `Skip` with:

```csharp
List<HotstringDto> items = await ApplySorting(query, request.SortField, request.SortDescending)
    .Skip((request.Page - 1) * request.PageSize)
    .Take(request.PageSize)
    .Select(h => new HotstringDto(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Trigger,
        h.Replacement,
        h.IsEndingCharacterRequired,
        h.IsTriggerInsideWord,
        h.CreatedAt,
        h.UpdatedAt))
    .ToListAsync(ct);
```

Add this private method to `ListHotstringsQueryHandler`:

```csharp
private static IOrderedQueryable<Hotstring> ApplySorting(
    IQueryable<Hotstring> query,
    string? sortField,
    bool descending)
{
    string normalized = sortField?.Trim().ToLowerInvariant() ?? "createdat";

    IOrderedQueryable<Hotstring> ordered = normalized switch
    {
        "trigger" => descending ? query.OrderByDescending(h => h.Trigger) : query.OrderBy(h => h.Trigger),
        "replacement" => descending ? query.OrderByDescending(h => h.Replacement) : query.OrderBy(h => h.Replacement),
        "isendingcharacterrequired" => descending ? query.OrderByDescending(h => h.IsEndingCharacterRequired) : query.OrderBy(h => h.IsEndingCharacterRequired),
        "istriggerinsideword" => descending ? query.OrderByDescending(h => h.IsTriggerInsideWord) : query.OrderBy(h => h.IsTriggerInsideWord),
        "updatedat" => descending ? query.OrderByDescending(h => h.UpdatedAt) : query.OrderBy(h => h.UpdatedAt),
        _ => descending ? query.OrderByDescending(h => h.CreatedAt) : query.OrderBy(h => h.CreatedAt),
    };

    return ordered.ThenBy(h => h.Id);
}
```

- [ ] **Step 6: Pass Hotstrings query params through the controller**

Update `src\Backend\AHKFlowApp.API\Controllers\HotstringsController.cs` list action signature:

```csharp
public async Task<ActionResult<PagedList<HotstringDto>>> List(
    [FromQuery] Guid? profileId,
    [FromQuery] string? search = null,
    [FromQuery] int page = 1,
    [FromQuery] int pageSize = 50,
    [FromQuery] string? sortField = null,
    [FromQuery] bool sortDescending = true,
    [FromQuery] string? triggerFilter = null,
    [FromQuery] string? replacementFilter = null,
    [FromQuery] bool? appliesToAllProfiles = null,
    [FromQuery] bool? isEndingCharacterRequired = null,
    [FromQuery] bool? isTriggerInsideWord = null,
    CancellationToken ct = default) =>
    (await mediator.Send(new ListHotstringsQuery(
        profileId,
        search,
        page,
        pageSize,
        sortField,
        sortDescending,
        triggerFilter,
        replacementFilter,
        appliesToAllProfiles,
        isEndingCharacterRequired,
        isTriggerInsideWord), ct)).ToProblemActionResult(this);
```

- [ ] **Step 7: Add Hotstrings API endpoint coverage**

Add these tests to `tests\AHKFlowApp.API.Tests\Hotstrings\HotstringsEndpointsTests.cs`:

```csharp
[Fact]
public async Task List_WithSortAndColumnFilter_ReturnsFilteredSortedRows()
{
    var owner = Guid.NewGuid();
    using HttpClient client = CreateAuthed(owner);

    await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("ccc", "match"));
    await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("aaa", "match"));
    await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("bbb", "skip"));

    HttpResponseMessage response = await client.GetAsync(
        "/api/v1/hotstrings?replacementFilter=match&sortField=trigger&sortDescending=false");

    response.StatusCode.Should().Be(HttpStatusCode.OK);
    PagedList<HotstringDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
    body!.Items.Select(h => h.Trigger).Should().Equal("aaa", "ccc");
}

[Fact]
public async Task List_WithUnknownSortField_Returns400()
{
    using HttpClient client = CreateAuthed();

    HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?sortField=ownerOid");

    response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
}
```

- [ ] **Step 8: Run Hotstrings backend tests and verify pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotstringsQuery" --verbosity normal
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HotstringsEndpointsTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 9: Commit Hotstrings backend support**

Run:

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs tests/AHKFlowApp.Application.Tests/Hotstrings/ListHotstringsQueryValidatorTests.cs tests/AHKFlowApp.Application.Tests/Hotstrings/ListHotstringsQueryHandlerTests.cs tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs
git commit -m "feat: add hotstring grid query support"
```

---

### Task 2: Add Hotkeys Server Sort and Filter Support

**Files:**
- Modify: `src\Backend\AHKFlowApp.Application\Queries\Hotkeys\ListHotkeysQuery.cs`
- Modify: `src\Backend\AHKFlowApp.API\Controllers\HotkeysController.cs`
- Test: `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryValidatorTests.cs`
- Test: `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryHandlerTests.cs`
- Test: `tests\AHKFlowApp.API.Tests\Hotkeys\HotkeysEndpointsTests.cs`

- [ ] **Step 1: Write failing validator tests for new Hotkeys list parameters**

Add these tests to `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryValidatorTests.cs`:

```csharp
[Fact]
public void Validate_WithAllowedSortField_Succeeds()
{
    ValidationResult result = _sut.Validate(new ListHotkeysQuery(SortField: "description"));

    result.IsValid.Should().BeTrue();
}

[Fact]
public void Validate_WithUnknownSortField_Fails()
{
    ValidationResult result = _sut.Validate(new ListHotkeysQuery(SortField: "ownerOid"));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "SortField");
}

[Fact]
public void Validate_WithDescriptionFilterTooLong_Fails()
{
    string filter = new('x', 201);

    ValidationResult result = _sut.Validate(new ListHotkeysQuery(DescriptionFilter: filter));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "DescriptionFilter");
}

[Fact]
public void Validate_WithKeyFilterTooLong_Fails()
{
    string filter = new('x', 201);

    ValidationResult result = _sut.Validate(new ListHotkeysQuery(KeyFilter: filter));

    result.IsValid.Should().BeFalse();
    result.Errors.Should().Contain(e => e.PropertyName == "KeyFilter");
}
```

- [ ] **Step 2: Run Hotkeys validator tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotkeysQueryValidatorTests" --verbosity normal
```

Expected: FAIL because `ListHotkeysQuery` does not yet define the new fields.

- [ ] **Step 3: Write failing Hotkeys handler tests for filter/sort behavior**

Add these tests to `tests\AHKFlowApp.Application.Tests\Hotkeys\ListHotkeysQueryHandlerTests.cs`:

```csharp
[Fact]
public async Task Handle_DescriptionFilter_ComposesWithSearch()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Open browser").WithKey("b").WithCtrl().WithParameters("firefox").AppliesToAll().Build());
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Open terminal").WithKey("t").WithCtrl().WithParameters("wt").AppliesToAll().Build());
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Lock browser").WithKey("l").WithCtrl().WithParameters("none").AppliesToAll().Build());
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotkeyDto>> result = await handler.Handle(
        new ListHotkeysQuery(Search: "firefox", DescriptionFilter: "browser"), default);

    result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("Open browser");
}

[Fact]
public async Task Handle_BooleanAndActionFilters_ReturnMatchingRows()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Run command").WithKey("r").WithCtrl().WithAction(Domain.Enums.HotkeyAction.Run).AppliesToAll().Build());
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Send text").WithKey("s").WithCtrl().WithAction(Domain.Enums.HotkeyAction.Send).AppliesToAll().Build());
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotkeyDto>> result = await handler.Handle(
        new ListHotkeysQuery(Ctrl: true, Action: Domain.Enums.HotkeyAction.Run), default);

    result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("Run command");
}

[Fact]
public async Task Handle_SortByDescriptionAscending_ReturnsStableOrder()
{
    var owner = Guid.NewGuid();

    await using (AppDbContext seed = fx.CreateContext())
    {
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Zulu").WithKey("z").WithCtrl().AppliesToAll().Build());
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Alpha").WithKey("a").WithCtrl().AppliesToAll().Build());
        seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithDescription("Bravo").WithKey("b").WithCtrl().AppliesToAll().Build());
        await seed.SaveChangesAsync();
    }

    await using AppDbContext db = fx.CreateContext();
    var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

    Result<PagedList<HotkeyDto>> result = await handler.Handle(
        new ListHotkeysQuery(SortField: "description", SortDescending: false), default);

    result.Value.Items.Select(h => h.Description).Should().Equal("Alpha", "Bravo", "Zulu");
}
```

- [ ] **Step 4: Run Hotkeys handler tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotkeysQueryHandlerTests" --verbosity normal
```

Expected: FAIL because the query record and handler do not yet support the new fields.

- [ ] **Step 5: Implement Hotkeys query validation, filtering, and sorting**

Update `src\Backend\AHKFlowApp.Application\Queries\Hotkeys\ListHotkeysQuery.cs`.

Replace the query record with:

```csharp
public sealed record ListHotkeysQuery(
    Guid? ProfileId = null,
    string? Search = null,
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? DescriptionFilter = null,
    string? KeyFilter = null,
    string? ParametersFilter = null,
    HotkeyAction? Action = null,
    bool? AppliesToAllProfiles = null,
    bool? Ctrl = null,
    bool? Alt = null,
    bool? Shift = null,
    bool? Win = null) : IRequest<Result<PagedList<HotkeyDto>>>;
```

Add `using AHKFlowApp.Domain.Enums;` if it is not already present.

Replace the validator body with:

```csharp
private static readonly string[] AllowedSortFields =
[
    "createdAt",
    "updatedAt",
    "description",
    "key",
    "ctrl",
    "alt",
    "shift",
    "win",
    "action",
    "parameters",
];

public ListHotkeysQueryValidator()
{
    RuleFor(x => x.Search).MaximumLength(200);
    RuleFor(x => x.DescriptionFilter).MaximumLength(200);
    RuleFor(x => x.KeyFilter).MaximumLength(200);
    RuleFor(x => x.ParametersFilter).MaximumLength(200);
    RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
    RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    RuleFor(x => x.SortField)
        .Must(field => string.IsNullOrWhiteSpace(field) || AllowedSortFields.Contains(field, StringComparer.OrdinalIgnoreCase))
        .WithMessage($"SortField must be one of: {string.Join(", ", AllowedSortFields)}.");
}
```

In `Handle`, after the existing global search block and before `CountAsync`, add:

```csharp
if (!string.IsNullOrWhiteSpace(request.DescriptionFilter))
{
    string pattern = $"%{request.DescriptionFilter.Trim()}%";
    query = query.Where(h => EF.Functions.Like(h.Description, pattern));
}

if (!string.IsNullOrWhiteSpace(request.KeyFilter))
{
    string pattern = $"%{request.KeyFilter.Trim()}%";
    query = query.Where(h => EF.Functions.Like(h.Key, pattern));
}

if (!string.IsNullOrWhiteSpace(request.ParametersFilter))
{
    string pattern = $"%{request.ParametersFilter.Trim()}%";
    query = query.Where(h => EF.Functions.Like(h.Parameters, pattern));
}

if (request.Action is { } action)
    query = query.Where(h => h.Action == action);

if (request.AppliesToAllProfiles is { } appliesToAllProfiles)
    query = query.Where(h => h.AppliesToAllProfiles == appliesToAllProfiles);

if (request.Ctrl is { } ctrl)
    query = query.Where(h => h.Ctrl == ctrl);

if (request.Alt is { } alt)
    query = query.Where(h => h.Alt == alt);

if (request.Shift is { } shift)
    query = query.Where(h => h.Shift == shift);

if (request.Win is { } win)
    query = query.Where(h => h.Win == win);
```

Replace the ordering chain before `Skip` with:

```csharp
List<HotkeyDto> items = await ApplySorting(query, request.SortField, request.SortDescending)
    .Skip((request.Page - 1) * request.PageSize)
    .Take(request.PageSize)
    .Select(h => new HotkeyDto(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Description,
        h.Key,
        h.Ctrl,
        h.Alt,
        h.Shift,
        h.Win,
        h.Action,
        h.Parameters,
        h.CreatedAt,
        h.UpdatedAt))
    .ToListAsync(ct);
```

Add this private method to `ListHotkeysQueryHandler`:

```csharp
private static IOrderedQueryable<Hotkey> ApplySorting(
    IQueryable<Hotkey> query,
    string? sortField,
    bool descending)
{
    string normalized = sortField?.Trim().ToLowerInvariant() ?? "createdat";

    IOrderedQueryable<Hotkey> ordered = normalized switch
    {
        "description" => descending ? query.OrderByDescending(h => h.Description) : query.OrderBy(h => h.Description),
        "key" => descending ? query.OrderByDescending(h => h.Key) : query.OrderBy(h => h.Key),
        "ctrl" => descending ? query.OrderByDescending(h => h.Ctrl) : query.OrderBy(h => h.Ctrl),
        "alt" => descending ? query.OrderByDescending(h => h.Alt) : query.OrderBy(h => h.Alt),
        "shift" => descending ? query.OrderByDescending(h => h.Shift) : query.OrderBy(h => h.Shift),
        "win" => descending ? query.OrderByDescending(h => h.Win) : query.OrderBy(h => h.Win),
        "action" => descending ? query.OrderByDescending(h => h.Action) : query.OrderBy(h => h.Action),
        "parameters" => descending ? query.OrderByDescending(h => h.Parameters) : query.OrderBy(h => h.Parameters),
        "updatedat" => descending ? query.OrderByDescending(h => h.UpdatedAt) : query.OrderBy(h => h.UpdatedAt),
        _ => descending ? query.OrderByDescending(h => h.CreatedAt) : query.OrderBy(h => h.CreatedAt),
    };

    return ordered.ThenBy(h => h.Id);
}
```

- [ ] **Step 6: Pass Hotkeys query params through the controller**

Update `src\Backend\AHKFlowApp.API\Controllers\HotkeysController.cs` list action signature:

```csharp
public async Task<ActionResult<PagedList<HotkeyDto>>> List(
    [FromQuery] Guid? profileId,
    [FromQuery] string? search = null,
    [FromQuery] int page = 1,
    [FromQuery] int pageSize = 50,
    [FromQuery] string? sortField = null,
    [FromQuery] bool sortDescending = true,
    [FromQuery] string? descriptionFilter = null,
    [FromQuery] string? keyFilter = null,
    [FromQuery] string? parametersFilter = null,
    [FromQuery] HotkeyAction? action = null,
    [FromQuery] bool? appliesToAllProfiles = null,
    [FromQuery] bool? ctrl = null,
    [FromQuery] bool? alt = null,
    [FromQuery] bool? shift = null,
    [FromQuery] bool? win = null,
    CancellationToken ct = default) =>
    (await mediator.Send(new ListHotkeysQuery(
        profileId,
        search,
        page,
        pageSize,
        sortField,
        sortDescending,
        descriptionFilter,
        keyFilter,
        parametersFilter,
        action,
        appliesToAllProfiles,
        ctrl,
        alt,
        shift,
        win), ct)).ToProblemActionResult(this);
```

Add `using AHKFlowApp.Domain.Enums;` to the controller.

- [ ] **Step 7: Add Hotkeys API endpoint coverage**

Add these tests to `tests\AHKFlowApp.API.Tests\Hotkeys\HotkeysEndpointsTests.cs`:

```csharp
[Fact]
public async Task List_WithSortAndColumnFilter_ReturnsFilteredSortedRows()
{
    var owner = Guid.NewGuid();
    using HttpClient client = CreateAuthed(owner);

    await client.PostAsJsonAsync("/api/v1/hotkeys",
        new CreateHotkeyDto("Zulu", "z", Ctrl: true, Action: HotkeyAction.Run, AppliesToAllProfiles: true));
    await client.PostAsJsonAsync("/api/v1/hotkeys",
        new CreateHotkeyDto("Alpha", "a", Ctrl: true, Action: HotkeyAction.Run, AppliesToAllProfiles: true));
    await client.PostAsJsonAsync("/api/v1/hotkeys",
        new CreateHotkeyDto("Skip", "s", Ctrl: true, Action: HotkeyAction.Send, AppliesToAllProfiles: true));

    HttpResponseMessage response = await client.GetAsync(
        "/api/v1/hotkeys?action=Run&sortField=description&sortDescending=false");

    response.StatusCode.Should().Be(HttpStatusCode.OK);
    PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
    body!.Items.Select(h => h.Description).Should().Equal("Alpha", "Zulu");
}

[Fact]
public async Task List_WithUnknownSortField_Returns400()
{
    using HttpClient client = CreateAuthed();

    HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?sortField=ownerOid");

    response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
}
```

- [ ] **Step 8: Run Hotkeys backend tests and verify pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotkeysQuery" --verbosity normal
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HotkeysEndpointsTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 9: Commit Hotkeys backend support**

Run:

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysQueryValidatorTests.cs tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysQueryHandlerTests.cs tests/AHKFlowApp.API.Tests/Hotkeys/HotkeysEndpointsTests.cs
git commit -m "feat: add hotkey grid query support"
```

---

### Task 3: Add Frontend List Request Contracts and Query String Support

**Files:**
- Create: `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotstringListRequest.cs`
- Create: `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotkeyListRequest.cs`
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotstringsApiClient.cs`
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotstringsApiClient.cs`
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotkeysApiClient.cs`
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotkeysApiClient.cs`
- Test: `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotstringsApiClientTests.cs`
- Test: `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotkeysApiClientTests.cs`

- [ ] **Step 1: Write failing Hotstrings API client query-string test**

Update `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotstringsApiClientTests.cs`.

Change `ListAsync` calls to pass `new HotstringListRequest(...)`. Add:

```csharp
[Fact]
public async Task ListAsync_WithGridParameters_AppendsEncodedQueryString()
{
    var paged = new PagedList<HotstringDto>([], 1, 50, 0, 0, false, false);
    var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

    await ClientWith(handler).ListAsync(new HotstringListRequest(
        ProfileId: Guid.Parse("11111111-1111-1111-1111-111111111111"),
        Page: 2,
        PageSize: 25,
        Search: "by way",
        SortField: "trigger",
        SortDescending: false,
        TriggerFilter: "bt",
        ReplacementFilter: "way",
        AppliesToAllProfiles: true,
        IsEndingCharacterRequired: false,
        IsTriggerInsideWord: true));

    handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be(
        "/api/v1/hotstrings?page=2&pageSize=25&profileId=11111111-1111-1111-1111-111111111111&search=by%20way&sortField=trigger&sortDescending=False&triggerFilter=bt&replacementFilter=way&appliesToAllProfiles=True&isEndingCharacterRequired=False&isTriggerInsideWord=True");
}
```

- [ ] **Step 2: Write failing Hotkeys API client query-string test**

Update `tests\AHKFlowApp.UI.Blazor.Tests\Services\HotkeysApiClientTests.cs`.

Change `ListAsync` calls to pass `new HotkeyListRequest(...)`. Add:

```csharp
[Fact]
public async Task ListAsync_WithGridParameters_AppendsEncodedQueryString()
{
    var paged = new PagedList<HotkeyDto>([], 1, 50, 0, 0, false, false);
    var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

    await ClientWith(handler).ListAsync(new HotkeyListRequest(
        ProfileId: Guid.Parse("11111111-1111-1111-1111-111111111111"),
        Page: 2,
        PageSize: 25,
        Search: "open terminal",
        SortField: "description",
        SortDescending: false,
        DescriptionFilter: "open",
        KeyFilter: "t",
        ParametersFilter: "wt",
        Action: HotkeyAction.Run,
        AppliesToAllProfiles: true,
        Ctrl: true,
        Alt: false,
        Shift: true,
        Win: false));

    handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be(
        "/api/v1/hotkeys?page=2&pageSize=25&profileId=11111111-1111-1111-1111-111111111111&search=open%20terminal&sortField=description&sortDescending=False&descriptionFilter=open&keyFilter=t&parametersFilter=wt&action=Run&appliesToAllProfiles=True&ctrl=True&alt=False&shift=True&win=False");
}
```

- [ ] **Step 3: Run API client tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsApiClientTests|FullyQualifiedName~HotkeysApiClientTests" --verbosity normal
```

Expected: FAIL because `HotstringListRequest` and `HotkeyListRequest` do not exist and interfaces still use the old signature.

- [ ] **Step 4: Add frontend list request records**

Create `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotstringListRequest.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotstringListRequest(
    Guid? ProfileId = null,
    int Page = 1,
    int PageSize = 50,
    string? Search = null,
    string? SortField = null,
    bool SortDescending = true,
    string? TriggerFilter = null,
    string? ReplacementFilter = null,
    bool? AppliesToAllProfiles = null,
    bool? IsEndingCharacterRequired = null,
    bool? IsTriggerInsideWord = null);
```

Create `src\Frontend\AHKFlowApp.UI.Blazor\DTOs\HotkeyListRequest.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotkeyListRequest(
    Guid? ProfileId = null,
    int Page = 1,
    int PageSize = 50,
    string? Search = null,
    string? SortField = null,
    bool SortDescending = true,
    string? DescriptionFilter = null,
    string? KeyFilter = null,
    string? ParametersFilter = null,
    HotkeyAction? Action = null,
    bool? AppliesToAllProfiles = null,
    bool? Ctrl = null,
    bool? Alt = null,
    bool? Shift = null,
    bool? Win = null);
```

- [ ] **Step 5: Update frontend API client interfaces**

Update `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotstringsApiClient.cs`:

```csharp
Task<ApiResult<PagedList<HotstringDto>>> ListAsync(HotstringListRequest request, CancellationToken ct = default);
```

Update `src\Frontend\AHKFlowApp.UI.Blazor\Services\IHotkeysApiClient.cs`:

```csharp
Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(HotkeyListRequest request, CancellationToken ct = default);
```

- [ ] **Step 6: Update Hotstrings API client query builder**

Replace `ListAsync` in `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotstringsApiClient.cs` with:

```csharp
public Task<ApiResult<PagedList<HotstringDto>>> ListAsync(HotstringListRequest request, CancellationToken ct = default)
{
    List<string> query =
    [
        $"page={request.Page}",
        $"pageSize={request.PageSize}",
    ];

    Add(query, "profileId", request.ProfileId?.ToString());
    Add(query, "search", request.Search);
    Add(query, "sortField", request.SortField);
    query.Add($"sortDescending={request.SortDescending}");
    Add(query, "triggerFilter", request.TriggerFilter);
    Add(query, "replacementFilter", request.ReplacementFilter);
    Add(query, "appliesToAllProfiles", request.AppliesToAllProfiles?.ToString());
    Add(query, "isEndingCharacterRequired", request.IsEndingCharacterRequired?.ToString());
    Add(query, "isTriggerInsideWord", request.IsTriggerInsideWord?.ToString());

    return SendAsync<PagedList<HotstringDto>>(HttpMethod.Get, $"{BasePath}?{string.Join("&", query)}", content: null, ct);
}

private static void Add(List<string> query, string name, string? value)
{
    if (!string.IsNullOrWhiteSpace(value))
        query.Add($"{Uri.EscapeDataString(name)}={Uri.EscapeDataString(value)}");
}
```

- [ ] **Step 7: Update Hotkeys API client query builder**

Replace `ListAsync` in `src\Frontend\AHKFlowApp.UI.Blazor\Services\HotkeysApiClient.cs` with:

```csharp
public Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(HotkeyListRequest request, CancellationToken ct = default)
{
    List<string> query =
    [
        $"page={request.Page}",
        $"pageSize={request.PageSize}",
    ];

    Add(query, "profileId", request.ProfileId?.ToString());
    Add(query, "search", request.Search);
    Add(query, "sortField", request.SortField);
    query.Add($"sortDescending={request.SortDescending}");
    Add(query, "descriptionFilter", request.DescriptionFilter);
    Add(query, "keyFilter", request.KeyFilter);
    Add(query, "parametersFilter", request.ParametersFilter);
    Add(query, "action", request.Action?.ToString());
    Add(query, "appliesToAllProfiles", request.AppliesToAllProfiles?.ToString());
    Add(query, "ctrl", request.Ctrl?.ToString());
    Add(query, "alt", request.Alt?.ToString());
    Add(query, "shift", request.Shift?.ToString());
    Add(query, "win", request.Win?.ToString());

    return SendAsync<PagedList<HotkeyDto>>(HttpMethod.Get, $"{BasePath}?{string.Join("&", query)}", content: null, ct);
}

private static void Add(List<string> query, string name, string? value)
{
    if (!string.IsNullOrWhiteSpace(value))
        query.Add($"{Uri.EscapeDataString(name)}={Uri.EscapeDataString(value)}");
}
```

- [ ] **Step 8: Run API client tests and verify pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsApiClientTests|FullyQualifiedName~HotkeysApiClientTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 9: Commit frontend client support**

Run:

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringListRequest.cs src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyListRequest.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeysApiClient.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs
git commit -m "feat: add grid list clients"
```

---

### Task 4: Migrate Hotstrings Page to MudDataGrid

**Files:**
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor`
- Test: `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotstringsPageTests.cs`

- [ ] **Step 1: Update Hotstrings page tests for list request and grid edit behavior**

In `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotstringsPageTests.cs`, replace the stubs:

```csharp
private void StubList(PagedList<HotstringDto> page) =>
    _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(page));

private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
    _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Failure(status, problem));
```

Replace `Page_AddButton_InsertsDraftRow` with:

```csharp
[Fact]
public void Page_AddButton_StartsDraftGridEdit()
{
    StubList(Page());

    IRenderedComponent<Hotstrings> cut = RenderPage();
    cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));

    cut.Find("button.add-hotstring").Click();

    cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]").Should().NotBeNull());
}
```

Add:

```csharp
[Fact]
public void Page_OnLoad_UsesGridListRequest()
{
    StubList(Page());

    RenderPage();

    _api.Received().ListAsync(
        Arg.Is<HotstringListRequest>(request =>
            request.Page == 1 &&
            request.PageSize == UserPreferences.Default.RowsPerPage),
        Arg.Any<CancellationToken>());
}
```

Keep the existing create/update/validation/conflict tests, but change API substitute signatures from the old `ListAsync(Guid?, int, int, string?, CancellationToken)` to `ListAsync(HotstringListRequest, CancellationToken)`.

- [ ] **Step 2: Run Hotstrings page tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsPageTests" --verbosity normal
```

Expected: FAIL because the page still uses `MudTable<HotstringDto>` and the old API client signature.

- [ ] **Step 3: Replace Hotstrings MudTable with MudDataGrid**

In `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotstrings.razor`, replace the `<MudTable>` block with:

```razor
<MudDataGrid @ref="_grid" T="HotstringEditModel" ServerData="LoadServerData"
             Dense="true" Hover="true" RowsPerPage="_rowsPerPage"
             Filterable="true" FilterMode="DataGridFilterMode.ColumnFilterMenu"
             SortMode="SortMode.Single" ReadOnly="false"
             EditMode="DataGridEditMode.Cell" EditTrigger="DataGridEditTrigger.Manual">
    <Columns>
        <PropertyColumn Identifier="trigger" Property="x => x.Trigger" Title="Trigger">
            <EditTemplate>
                <MudTextField @bind-Value="context.Item.Trigger"
                              Validation="@(new Func<string, string?>(ValidateTrigger))"
                              Error="@(_commitAttempted && ValidateTrigger(context.Item.Trigger) is not null)"
                              ErrorText="@(_commitAttempted ? ValidateTrigger(context.Item.Trigger) : null)"
                              Immediate="true" MaxLength="50"
                              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "trigger-input" })" />
            </EditTemplate>
        </PropertyColumn>
        <PropertyColumn Identifier="replacement" Property="x => x.Replacement" Title="Replacement">
            <EditTemplate>
                <MudTextField @bind-Value="context.Item.Replacement"
                              Validation="@(new Func<string, string?>(ValidateReplacement))"
                              Error="@(_commitAttempted && ValidateReplacement(context.Item.Replacement) is not null)"
                              ErrorText="@(_commitAttempted ? ValidateReplacement(context.Item.Replacement) : null)"
                              Immediate="true" MaxLength="4000"
                              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "replacement-input" })" />
            </EditTemplate>
        </PropertyColumn>
        <TemplateColumn Title="Profiles" Sortable="false" Filterable="false">
            <CellTemplate>@RenderProfiles(context.Item.AppliesToAllProfiles, context.Item.ProfileIds)</CellTemplate>
            <EditTemplate>@RenderProfileEditor(context.Item)</EditTemplate>
        </TemplateColumn>
        <PropertyColumn Identifier="isEndingCharacterRequired" Property="x => x.IsEndingCharacterRequired" Title="Ending char required">
            <EditTemplate>
                <MudCheckBox T="bool" @bind-Value="context.Item.IsEndingCharacterRequired" />
            </EditTemplate>
        </PropertyColumn>
        <PropertyColumn Identifier="isTriggerInsideWord" Property="x => x.IsTriggerInsideWord" Title="Trigger inside word">
            <EditTemplate>
                <MudCheckBox T="bool" @bind-Value="context.Item.IsTriggerInsideWord" />
            </EditTemplate>
        </PropertyColumn>
        <TemplateColumn Title="Actions" Sortable="false" Filterable="false" HeaderStyle="width:160px">
            <CellTemplate>
                @if (ReferenceEquals(_editingItem, context.Item))
                {
                    <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                   Color="Color.Success" OnClick="() => CommitEditAsync(context.Item)" />
                    <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                   Color="Color.Default" OnClick="CancelEditAsync" />
                }
                else
                {
                    <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                   OnClick="() => DeleteAsync(context.Item)" />
                    <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                   OnClick="() => StartEditAsync(context.Item)" />
                }
            </CellTemplate>
        </TemplateColumn>
    </Columns>
    <NoRecordsContent><MudText>No hotstrings yet.</MudText></NoRecordsContent>
    <PagerContent>
        <MudDataGridPager T="HotstringEditModel" PageSizeOptions="UserPreferences.AllowedRowsPerPage" />
    </PagerContent>
</MudDataGrid>
```

This snippet introduces `RenderProfiles` and `RenderProfileEditor`. Add them as private render fragments:

```csharp
private RenderFragment RenderProfiles(bool appliesToAllProfiles, IReadOnlyCollection<Guid> profileIds) => builder =>
{
    if (appliesToAllProfiles)
    {
        builder.OpenComponent<MudChip<string>>(0);
        builder.AddAttribute(1, "Size", Size.Small);
        builder.AddAttribute(2, "Color", Color.Info);
        builder.AddAttribute(3, "ChildContent", (RenderFragment)(chipBuilder => chipBuilder.AddContent(0, "Any")));
        builder.CloseComponent();
        return;
    }

    int sequence = 10;
    foreach (Guid pid in profileIds)
    {
        string name = _profiles.FirstOrDefault(p => p.Id == pid)?.Name ?? pid.ToString()[..8];
        builder.OpenComponent<MudChip<string>>(sequence++);
        builder.AddAttribute(sequence++, "Size", Size.Small);
        builder.AddAttribute(sequence++, "ChildContent", (RenderFragment)(chipBuilder => chipBuilder.AddContent(0, name)));
        builder.CloseComponent();
    }
};

private RenderFragment RenderProfileEditor(HotstringEditModel edit) => builder =>
{
    builder.OpenComponent<MudStack>(0);
    builder.AddAttribute(1, "Row", true);
    builder.AddAttribute(2, "AlignItems", AlignItems.Center);
    builder.AddAttribute(3, "Spacing", 1);
    builder.AddAttribute(4, "ChildContent", (RenderFragment)(stackBuilder =>
    {
        stackBuilder.OpenComponent<MudCheckBox<bool>>(0);
        stackBuilder.AddAttribute(1, "Value", edit.AppliesToAllProfiles);
        stackBuilder.AddAttribute(2, "ValueChanged", EventCallback.Factory.Create<bool>(this, value => edit.AppliesToAllProfiles = value));
        stackBuilder.AddAttribute(3, "Label", "Any");
        stackBuilder.AddAttribute(4, "UserAttributes", new Dictionary<string, object?> { ["data-test"] = "applies-to-all-checkbox" });
        stackBuilder.CloseComponent();

        if (!edit.AppliesToAllProfiles)
        {
            stackBuilder.OpenComponent<MudSelect<Guid>>(10);
            stackBuilder.AddAttribute(11, "MultiSelection", true);
            stackBuilder.AddAttribute(12, "SelectedValues", edit.ProfileIds);
            stackBuilder.AddAttribute(13, "SelectedValuesChanged", EventCallback.Factory.Create<IEnumerable<Guid>>(this, ids => edit.ProfileIds = [.. ids]));
            stackBuilder.AddAttribute(14, "ToStringFunc", (Func<Guid, string>)(id => _profiles.FirstOrDefault(p => p.Id == id)?.Name ?? id.ToString()));
            stackBuilder.AddAttribute(15, "Dense", true);
            stackBuilder.AddAttribute(16, "Placeholder", "Select profiles");
            stackBuilder.AddAttribute(17, "UserAttributes", new Dictionary<string, object?> { ["data-test"] = "profile-select" });
            stackBuilder.AddAttribute(18, "ChildContent", (RenderFragment)(selectBuilder =>
            {
                int profileSequence = 0;
                foreach (ProfileDto profile in _profiles)
                {
                    selectBuilder.OpenComponent<MudSelectItem<Guid>>(profileSequence++);
                    selectBuilder.AddAttribute(profileSequence++, "Value", profile.Id);
                    selectBuilder.AddAttribute(profileSequence++, "ChildContent", (RenderFragment)(itemBuilder => itemBuilder.AddContent(0, profile.Name)));
                    selectBuilder.CloseComponent();
                }
            }));
            stackBuilder.CloseComponent();
        }
    }));
    builder.CloseComponent();
};
```

If render-fragment builders make the file hard to read during implementation, replace them with local Razor fragments inside the same page. Preserve the exact `data-test` attributes above.

- [ ] **Step 4: Replace Hotstrings page fields and server loader**

Replace:

```csharp
private MudTable<HotstringDto>? _table;
private readonly Dictionary<Guid, HotstringEditModel> _editing = new();
private readonly HashSet<Guid> _commitAttempted = [];
private static readonly HotstringDto _draftPlaceholder = new(
    Guid.Empty, [], true, "", "", true, true, DateTimeOffset.MinValue, DateTimeOffset.MinValue);
```

with:

```csharp
private MudDataGrid<HotstringEditModel>? _grid;
private HotstringEditModel? _pendingCreate;
private HotstringEditModel? _editingItem;
private bool _commitAttempted;
```

Replace `LoadServerData` with:

```csharp
private async Task<GridData<HotstringEditModel>> LoadServerData(GridState<HotstringEditModel> state)
{
    _loading = true;
    _loadError = null;

    (string? sortField, bool sortDescending) = GetSort(state);

    ApiResult<PagedList<HotstringDto>> result = await Api.ListAsync(
        new HotstringListRequest(
            Page: state.Page + 1,
            PageSize: state.PageSize,
            Search: string.IsNullOrWhiteSpace(_search) ? null : _search,
            SortField: sortField,
            SortDescending: sortDescending,
            TriggerFilter: StringFilter(state, "trigger"),
            ReplacementFilter: StringFilter(state, "replacement"),
            IsEndingCharacterRequired: BoolFilter(state, "isEndingCharacterRequired"),
            IsTriggerInsideWord: BoolFilter(state, "isTriggerInsideWord")),
        _cts.Token);

    _loading = false;

    if (!result.IsSuccess)
    {
        _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        await InvokeAsync(StateHasChanged);
        return new GridData<HotstringEditModel> { Items = [], TotalItems = 0 };
    }

    List<HotstringEditModel> items = [.. result.Value!.Items.Select(HotstringEditModel.FromDto)];
    if (state.Page == 0 && _pendingCreate is not null)
        items.Insert(0, _pendingCreate);

    int totalItems = result.Value.TotalCount + (_pendingCreate is not null ? 1 : 0);
    return new GridData<HotstringEditModel> { Items = items, TotalItems = totalItems };
}
```

Add these helpers:

```csharp
private static (string? SortField, bool SortDescending) GetSort(GridState<HotstringEditModel> state)
{
    SortDefinition<HotstringEditModel>? sort = state.SortDefinitions.OrderBy(s => s.Index).FirstOrDefault();
    if (sort is null)
        return (null, true);

    string? sortField = sort.SortBy switch
    {
        "trigger" or nameof(HotstringEditModel.Trigger) => "trigger",
        "replacement" or nameof(HotstringEditModel.Replacement) => "replacement",
        "isEndingCharacterRequired" or nameof(HotstringEditModel.IsEndingCharacterRequired) => "isEndingCharacterRequired",
        "isTriggerInsideWord" or nameof(HotstringEditModel.IsTriggerInsideWord) => "isTriggerInsideWord",
        _ => null,
    };

    return (sortField, sort.Descending);
}

private static string? StringFilter(GridState<HotstringEditModel> state, string identifier) =>
    state.FilterDefinitions
        .FirstOrDefault(filter => ColumnKey(filter) == identifier)?
        .Value?
        .ToString();

private static bool? BoolFilter(GridState<HotstringEditModel> state, string identifier)
{
    object? value = state.FilterDefinitions
        .FirstOrDefault(filter => ColumnKey(filter) == identifier)?
        .Value;

    return value switch
    {
        bool typed => typed,
        string text when bool.TryParse(text, out bool parsed) => parsed,
        _ => null,
    };
}

private static string? ColumnKey(IFilterDefinition<HotstringEditModel> filter) =>
    filter.Column?.Identifier ?? filter.Column?.PropertyName;
```

- [ ] **Step 5: Replace Hotstrings edit, add, reload, search, commit, and delete methods**

Replace `ReloadAsync`, `OnSearchChangedAsync`, `StartAddAsync`, `StartEdit`, `CancelEditAsync`, `CommitEditAsync`, and `DeleteAsync` with:

```csharp
private async Task ReloadAsync()
{
    if (_grid is not null) await _grid.ReloadServerData();
}

private async Task OnSearchChangedAsync()
{
    if (_grid is not null) await _grid.ReloadServerData();
}

private async Task StartAddAsync()
{
    _pendingCreate = new HotstringEditModel();
    _editingItem = _pendingCreate;
    _commitAttempted = false;
    if (_grid is not null)
    {
        await _grid.ReloadServerData();
        await _grid.SetEditingItemAsync(_pendingCreate);
    }
}

private async Task StartEditAsync(HotstringEditModel item)
{
    _editingItem = item;
    _commitAttempted = false;
    if (_grid is not null)
        await _grid.SetEditingItemAsync(item);
}

private async Task CancelEditAsync()
{
    if (ReferenceEquals(_editingItem, _pendingCreate))
        _pendingCreate = null;

    _editingItem = null;
    _commitAttempted = false;

    if (_grid is not null)
    {
        await _grid.CancelEditingItemAsync();
        await _grid.ReloadServerData();
    }
}

private async Task CommitEditAsync(HotstringEditModel item)
{
    _commitAttempted = true;
    if (ValidateTrigger(item.Trigger) is not null || ValidateReplacement(item.Replacement) is not null)
        return;

    _commitAttempted = false;

    if (item.Id is null)
    {
        ApiResult<HotstringDto> result = await Api.CreateAsync(item.ToCreateDto(), _cts.Token);
        if (result.IsSuccess)
        {
            _pendingCreate = null;
            _editingItem = null;
            Snackbar.Add("Hotstring created.", Severity.Success);
            if (_grid is not null) await _grid.ReloadServerData();
        }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }
    else
    {
        ApiResult<HotstringDto> result = await Api.UpdateAsync(item.Id.Value, item.ToUpdateDto(), _cts.Token);
        if (result.IsSuccess)
        {
            _editingItem = null;
            Snackbar.Add("Hotstring updated.", Severity.Success);
            if (_grid is not null) await _grid.ReloadServerData();
        }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }
}

private async Task DeleteAsync(HotstringEditModel item)
{
    if (item.Id is not { } id)
        return;

    bool? confirm = await DialogService.ShowMessageBoxAsync(
        title: "Delete hotstring?",
        message: $"Delete \"{item.Trigger}\"? This cannot be undone.",
        yesText: "Delete", cancelText: "Cancel");
    if (confirm != true) return;

    ApiResult result = await Api.DeleteAsync(id, _cts.Token);
    if (result.IsSuccess)
    {
        Snackbar.Add("Hotstring deleted.", Severity.Success);
        if (_grid is not null) await _grid.ReloadServerData();
    }
    else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
}
```

Update the Add button disabled expression to:

```razor
Disabled="@(!_isAuthenticated || _pendingCreate is not null || _editingItem is not null)"
```

- [ ] **Step 6: Run Hotstrings page tests and verify pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsPageTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 7: Commit Hotstrings DataGrid migration**

Run:

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs
git commit -m "feat: migrate hotstrings to MudDataGrid"
```

---

### Task 5: Migrate Hotkeys Page to MudDataGrid

**Files:**
- Modify: `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor`
- Test: `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotkeysPageTests.cs`

- [ ] **Step 1: Update Hotkeys page tests for list request and grid edit behavior**

In `tests\AHKFlowApp.UI.Blazor.Tests\Pages\HotkeysPageTests.cs`, replace the stubs:

```csharp
private void StubList(PagedList<HotkeyDto> page) =>
    _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotkeyDto>>.Ok(page));

private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
    _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotkeyDto>>.Failure(status, problem));
```

Replace `Page_AddButton_InsertsDraftRow` with:

```csharp
[Fact]
public void Page_AddButton_StartsDraftGridEdit()
{
    StubList(Page());

    IRenderedComponent<Hotkeys> cut = RenderPage();
    cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));

    cut.Find("button.add-hotkey").Click();

    cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]").Should().NotBeNull());
}
```

Add:

```csharp
[Fact]
public void Page_OnLoad_UsesGridListRequest()
{
    StubList(Page());

    RenderPage();

    _api.Received().ListAsync(
        Arg.Is<HotkeyListRequest>(request =>
            request.Page == 1 &&
            request.PageSize == UserPreferences.Default.RowsPerPage),
        Arg.Any<CancellationToken>());
}
```

Keep the existing create/update/validation/delete/conflict tests, but change API substitute signatures from the old `ListAsync(Guid?, int, int, string?, CancellationToken)` to `ListAsync(HotkeyListRequest, CancellationToken)`.

- [ ] **Step 2: Run Hotkeys page tests and confirm failure**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotkeysPageTests" --verbosity normal
```

Expected: FAIL because the page still uses `MudTable<HotkeyDto>` and the old API client signature.

- [ ] **Step 3: Replace Hotkeys MudTable with MudDataGrid**

In `src\Frontend\AHKFlowApp.UI.Blazor\Pages\Hotkeys.razor`, replace the `<MudTable>` block with a `MudDataGrid<HotkeyEditModel>` using these columns:

```razor
<MudDataGrid @ref="_grid" T="HotkeyEditModel" ServerData="LoadServerData"
             Dense="true" Hover="true" RowsPerPage="_rowsPerPage"
             Filterable="true" FilterMode="DataGridFilterMode.ColumnFilterMenu"
             SortMode="SortMode.Single" ReadOnly="false"
             EditMode="DataGridEditMode.Cell" EditTrigger="DataGridEditTrigger.Manual">
    <Columns>
        <PropertyColumn Identifier="description" Property="x => x.Description" Title="Description">
            <EditTemplate>
                <MudTextField @bind-Value="context.Item.Description"
                              Validation="@(new Func<string, string?>(ValidateDescription))"
                              Error="@(_commitAttempted && ValidateDescription(context.Item.Description) is not null)"
                              ErrorText="@(_commitAttempted ? ValidateDescription(context.Item.Description) : null)"
                              Immediate="true" MaxLength="200"
                              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "description-input" })" />
            </EditTemplate>
        </PropertyColumn>
        <PropertyColumn Identifier="key" Property="x => x.Key" Title="Key">
            <EditTemplate>
                <MudTextField @bind-Value="context.Item.Key"
                              Validation="@(new Func<string, string?>(ValidateKey))"
                              Error="@(_commitAttempted && ValidateKey(context.Item.Key) is not null)"
                              ErrorText="@(_commitAttempted ? ValidateKey(context.Item.Key) : null)"
                              Immediate="true" MaxLength="20" Style="max-width: 80px;"
                              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "key-input" })" />
            </EditTemplate>
        </PropertyColumn>
        <PropertyColumn Identifier="ctrl" Property="x => x.Ctrl" Title="Ctrl" />
        <PropertyColumn Identifier="alt" Property="x => x.Alt" Title="Alt" />
        <PropertyColumn Identifier="shift" Property="x => x.Shift" Title="Shift" />
        <PropertyColumn Identifier="win" Property="x => x.Win" Title="Win" />
        <PropertyColumn Identifier="action" Property="x => x.Action" Title="Action">
            <EditTemplate>
                <MudSelect T="HotkeyAction" @bind-Value="context.Item.Action" Dense="true"
                           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-select" })">
                    <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Send">Send</MudSelectItem>
                    <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Run">Run</MudSelectItem>
                </MudSelect>
            </EditTemplate>
        </PropertyColumn>
        <TemplateColumn Title="Profiles" Sortable="false" Filterable="false">
            <CellTemplate>@RenderProfiles(context.Item.AppliesToAllProfiles, context.Item.ProfileIds)</CellTemplate>
            <EditTemplate>@RenderProfileEditor(context.Item)</EditTemplate>
        </TemplateColumn>
        <PropertyColumn Identifier="parameters" Property="x => x.Parameters" Title="Parameters">
            <EditTemplate>
                <MudTextField @bind-Value="context.Item.Parameters" Immediate="true" MaxLength="4000"
                              UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "parameters-input" })" />
            </EditTemplate>
        </PropertyColumn>
        <TemplateColumn Title="Actions" Sortable="false" Filterable="false" HeaderStyle="width:160px">
            <CellTemplate>
                @if (ReferenceEquals(_editingItem, context.Item))
                {
                    <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                   Color="Color.Success" OnClick="() => CommitEditAsync(context.Item)" />
                    <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                   Color="Color.Default" OnClick="CancelEditAsync" />
                }
                else
                {
                    <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                   OnClick="() => DeleteAsync(context.Item)" />
                    <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                   OnClick="() => StartEditAsync(context.Item)" />
                }
            </CellTemplate>
        </TemplateColumn>
    </Columns>
    <NoRecordsContent><MudText>No hotkeys yet.</MudText></NoRecordsContent>
    <PagerContent>
        <MudDataGridPager T="HotkeyEditModel" PageSizeOptions="UserPreferences.AllowedRowsPerPage" />
    </PagerContent>
</MudDataGrid>
```

Add `RenderProfiles` and `RenderProfileEditor` equivalents for `HotkeyEditModel`. Use the same implementation as Task 4, replacing `HotstringEditModel` with `HotkeyEditModel`.

- [ ] **Step 4: Replace Hotkeys page fields and server loader**

Replace:

```csharp
private MudTable<HotkeyDto>? _table;
private readonly Dictionary<Guid, HotkeyEditModel> _editing = new();
private readonly HashSet<Guid> _commitAttempted = [];
private static readonly HotkeyDto _draftPlaceholder = new(
    Guid.Empty, [], true, "", "", false, false, false, false,
    HotkeyAction.Send, "", DateTimeOffset.MinValue, DateTimeOffset.MinValue);
```

with:

```csharp
private MudDataGrid<HotkeyEditModel>? _grid;
private HotkeyEditModel? _pendingCreate;
private HotkeyEditModel? _editingItem;
private bool _commitAttempted;
```

Replace `LoadServerData` with:

```csharp
private async Task<GridData<HotkeyEditModel>> LoadServerData(GridState<HotkeyEditModel> state)
{
    _loading = true;
    _loadError = null;

    (string? sortField, bool sortDescending) = GetSort(state);

    ApiResult<PagedList<HotkeyDto>> result = await Api.ListAsync(
        new HotkeyListRequest(
            Page: state.Page + 1,
            PageSize: state.PageSize,
            Search: string.IsNullOrWhiteSpace(_search) ? null : _search,
            SortField: sortField,
            SortDescending: sortDescending,
            DescriptionFilter: StringFilter(state, "description"),
            KeyFilter: StringFilter(state, "key"),
            ParametersFilter: StringFilter(state, "parameters"),
            Action: ActionFilter(state, "action"),
            Ctrl: BoolFilter(state, "ctrl"),
            Alt: BoolFilter(state, "alt"),
            Shift: BoolFilter(state, "shift"),
            Win: BoolFilter(state, "win")),
        _cts.Token);

    _loading = false;

    if (!result.IsSuccess)
    {
        _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        await InvokeAsync(StateHasChanged);
        return new GridData<HotkeyEditModel> { Items = [], TotalItems = 0 };
    }

    List<HotkeyEditModel> items = [.. result.Value!.Items.Select(HotkeyEditModel.FromDto)];
    if (state.Page == 0 && _pendingCreate is not null)
        items.Insert(0, _pendingCreate);

    int totalItems = result.Value.TotalCount + (_pendingCreate is not null ? 1 : 0);
    return new GridData<HotkeyEditModel> { Items = items, TotalItems = totalItems };
}
```

Add these helpers:

```csharp
private static (string? SortField, bool SortDescending) GetSort(GridState<HotkeyEditModel> state)
{
    SortDefinition<HotkeyEditModel>? sort = state.SortDefinitions.OrderBy(s => s.Index).FirstOrDefault();
    if (sort is null)
        return (null, true);

    string? sortField = sort.SortBy switch
    {
        "description" or nameof(HotkeyEditModel.Description) => "description",
        "key" or nameof(HotkeyEditModel.Key) => "key",
        "ctrl" or nameof(HotkeyEditModel.Ctrl) => "ctrl",
        "alt" or nameof(HotkeyEditModel.Alt) => "alt",
        "shift" or nameof(HotkeyEditModel.Shift) => "shift",
        "win" or nameof(HotkeyEditModel.Win) => "win",
        "action" or nameof(HotkeyEditModel.Action) => "action",
        "parameters" or nameof(HotkeyEditModel.Parameters) => "parameters",
        _ => null,
    };

    return (sortField, sort.Descending);
}

private static string? StringFilter(GridState<HotkeyEditModel> state, string identifier) =>
    state.FilterDefinitions
        .FirstOrDefault(filter => ColumnKey(filter) == identifier)?
        .Value?
        .ToString();

private static bool? BoolFilter(GridState<HotkeyEditModel> state, string identifier)
{
    object? value = state.FilterDefinitions
        .FirstOrDefault(filter => ColumnKey(filter) == identifier)?
        .Value;

    return value switch
    {
        bool typed => typed,
        string text when bool.TryParse(text, out bool parsed) => parsed,
        _ => null,
    };
}

private static HotkeyAction? ActionFilter(GridState<HotkeyEditModel> state, string identifier)
{
    object? value = state.FilterDefinitions
        .FirstOrDefault(filter => ColumnKey(filter) == identifier)?
        .Value;

    return value switch
    {
        HotkeyAction typed => typed,
        string text when Enum.TryParse(text, ignoreCase: true, out HotkeyAction parsed) => parsed,
        _ => null,
    };
}

private static string? ColumnKey(IFilterDefinition<HotkeyEditModel> filter) =>
    filter.Column?.Identifier ?? filter.Column?.PropertyName;
```

- [ ] **Step 5: Replace Hotkeys edit, add, reload, search, commit, and delete methods**

Use the same method shape from Task 4, replacing `HotstringEditModel`, `HotstringDto`, `CreateHotstringDto`, and `UpdateHotstringDto` with the Hotkeys equivalents. Preserve current messages exactly:

```csharp
Snackbar.Add("Hotkey created.", Severity.Success);
Snackbar.Add("Hotkey updated.", Severity.Success);
Snackbar.Add("Hotkey deleted.", Severity.Success);
```

The validation block in `CommitEditAsync` must be:

```csharp
_commitAttempted = true;
if (ValidateDescription(item.Description) is not null || ValidateKey(item.Key) is not null)
    return;
```

The delete confirmation must remain:

```csharp
bool? confirm = await DialogService.ShowMessageBoxAsync(
    title: "Delete hotkey?",
    message: $"Delete \"{item.Description}\"? This cannot be undone.",
    yesText: "Delete", cancelText: "Cancel");
```

Update the Add button disabled expression to:

```razor
Disabled="@(!_isAuthenticated || _pendingCreate is not null || _editingItem is not null)"
```

- [ ] **Step 6: Run Hotkeys page tests and verify pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotkeysPageTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 7: Commit Hotkeys DataGrid migration**

Run:

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs
git commit -m "feat: migrate hotkeys to MudDataGrid"
```

---

### Task 6: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run focused backend and frontend tests**

Run:

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~ListHotstringsQuery|FullyQualifiedName~ListHotkeysQuery" --verbosity normal
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HotstringsEndpointsTests|FullyQualifiedName~HotkeysEndpointsTests" --verbosity normal
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsPageTests|FullyQualifiedName~HotkeysPageTests|FullyQualifiedName~HotstringsApiClientTests|FullyQualifiedName~HotkeysApiClientTests" --verbosity normal
```

Expected: PASS.

- [ ] **Step 2: Run full build**

Run:

```powershell
dotnet build --configuration Release
```

Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run:

```powershell
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: PASS.

- [ ] **Step 4: Run formatting check**

Run:

```powershell
dotnet format --verify-no-changes
```

Expected: PASS with no formatting changes required.

- [ ] **Step 5: Manual UI smoke test**

Run the frontend and API according to the repo's local instructions:

```powershell
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
```

Manual checks:

- Open `http://localhost:5601/hotstrings`.
- Confirm rows render in `MudDataGrid`.
- Confirm toolbar search reloads data.
- Confirm Trigger and Replacement header filtering reloads server data.
- Confirm Trigger sorting changes server order.
- Confirm Add creates a hotstring after entering Trigger and Replacement.
- Confirm blank Replacement shows `Replacement is required`.
- Confirm Edit updates an existing hotstring.
- Confirm Delete still opens the confirmation dialog.
- Open `http://localhost:5601/hotkeys`.
- Confirm rows render in `MudDataGrid`.
- Confirm toolbar search reloads data.
- Confirm Description and Key header filtering reloads server data.
- Confirm Description sorting changes server order.
- Confirm Add creates a hotkey after entering Description and Key.
- Confirm blank Key shows `Key is required`.
- Confirm Edit updates an existing hotkey.
- Confirm Delete still opens the confirmation dialog.

- [ ] **Step 6: Commit final verification adjustments**

If verification required fixes, commit them:

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs src/Frontend/AHKFlowApp.UI.Blazor tests/AHKFlowApp.UI.Blazor.Tests tests/AHKFlowApp.Application.Tests tests/AHKFlowApp.API.Tests
git commit -m "fix: stabilize MudDataGrid migration"
```

If verification passed without fixes, do not create an empty commit.

## Done Criteria

- Hotstrings page uses `MudDataGrid` and no longer uses `MudTable`.
- Hotkeys page uses `MudDataGrid` and no longer uses `MudTable`.
- Toolbar search still works on both pages.
- Column filters translate to explicit server query parameters.
- Column sorting translates to explicit server query parameters.
- Backend validators reject unknown sort fields.
- Backend handlers apply profile filter, global search, column filters, sorting, total count, and paging in the correct order.
- Create/update validation blocks invalid commits on both pages.
- Existing snackbar success/error paths still run.
- Delete confirmation behavior is unchanged.
- Focused tests, full build, full test suite, and format check pass.
