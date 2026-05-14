# Homepage Command Desk — Design

## Context

The current home route (`/`) in the Blazor WebAssembly UI renders a placeholder welcome message and an info alert. With Hotstrings, Hotkeys, and Profiles CRUD fully wired end-to-end, the homepage should become a basic command desk that gives a signed-in user a one-glance view of their workspace and the most common entry points.

This v1 focuses on four sections: a welcome hero with the AHKflow wordmark, a CLI quickstart card with example commands, three stat cards (Hotstrings, Hotkeys, Profiles) showing total count + new-this-week + a 14-day sparkline, and a Recent activity list derived from existing entity timestamps (no audit log exists yet).

The design uses default MudBlazor components without custom theming beyond the existing sage-green palette. The only custom CSS is a small block to style the CLI code listing.

## Scope

In scope:
- New `/api/v1/dashboard/stats` endpoint returning all homepage data in one call.
- New `Home.razor` page composing four sub-components.
- Real data for: counts, weekly delta, 14-day buckets, recent activity (derived from `CreatedAt`/`UpdatedAt`).
- Profile card shows "N active · M default" instead of weekly delta to match the screenshot.

Out of scope:
- Audit/activity-log domain entity. Recent activity is derived from `CreatedAt`/`UpdatedAt` on existing entities; events like "Script generated" or "API cold-started" are not represented.
- Server-driven hero/CLI content. All text is static.
- Theming or wordmark logo work beyond inline italic styling for "AHK*flow*".
- Settings, search, navigation changes.

## Architecture

### Page composition (frontend)

```
Pages/Home.razor
└── MudContainer (existing, from MainLayout)
    └── MudStack Spacing="6"
        ├── Pages/Home/HeroSection.razor
        ├── MudGrid (3 × MudItem xs=12 sm=6 md=4)
        │   ├── StatCard (Hotstrings)
        │   ├── StatCard (Hotkeys)
        │   └── StatCard (Profiles)
        └── MudGrid
            ├── MudItem xs=12 md=8 → RecentActivityCard
            └── MudItem xs=12 md=4 → CliQuickstartCard
```

Each sub-component is small, takes plain DTO parameters, and is independently unit-testable with bUnit. `Home.razor` is the only component that talks to the API client — children are pure presentation.

### Backend — one query, one endpoint

New `GET /api/v1/dashboard/stats` follows the existing pattern: thin controller → `IMediator.Send(query)` → handler → `AppDbContext` → returns `Result<DashboardStatsDto>` → `ToActionResult(this)`.

All queries are scoped to the caller's `OwnerOid` (existing convention).

## Components

### Backend

| File | Purpose |
|---|---|
| `Application/Queries/Dashboard/GetDashboardStatsQuery.cs` | Empty `IRequest<Result<DashboardStatsDto>>` record |
| `Application/Queries/Dashboard/GetDashboardStatsQueryHandler.cs` | Executes 3 count queries, 3 bucket queries, 1 union activity query; assembles DTO |
| `Application/DTOs/Dashboard/DashboardStatsDto.cs` | Composite DTO (record) |
| `Application/DTOs/Dashboard/EntityStatsDto.cs` | `(int Total, int CreatedThisWeek, IReadOnlyList<int> DailyBuckets)` |
| `Application/DTOs/Dashboard/ProfileStatsDto.cs` | `(int Total, int Active, int Default, IReadOnlyList<int> DailyBuckets)` |
| `Application/DTOs/Dashboard/RecentActivityItemDto.cs` | `(string Kind, string Action, string Label, DateTime OccurredAt)` |
| `API/Controllers/DashboardController.cs` | `[ApiController]`, `[Route("api/v1/[controller]")]`, `[Authorize]`, single `GetStats` action |

**Definitions**:
- "This week" = `CreatedAt >= TimeProvider.GetUtcNow().AddDays(-7)`.
- `DailyBuckets` = 14 ints, oldest→newest day, each = count of entities created on that UTC day for the current `OwnerOid`.
- Profile **Active** = `IsDefault == false`. Profile **Default** = `IsDefault == true`.
- Recent activity = top 5 across the 3 entity sets, sorted by `MAX(CreatedAt, UpdatedAt)` desc. `Action = "updated"` if `UpdatedAt > CreatedAt`, else `"created"`. `Label` is the entity's natural identifier: hotstring `Trigger`, hotkey key combo string, profile `Name`.

`TimeProvider` is injected and used for all date math (existing convention).

### Frontend

| File | Purpose |
|---|---|
| `Pages/Home.razor` | Page; calls `IDashboardApiClient.GetStatsAsync`, composes sub-components |
| `Pages/Home/HeroSection.razor` | Pure markup: eyebrow + `MudText Typo="h2"` title with italic "*flow*" + body text with `.ahk` rendered as inline `MudChip` |
| `Pages/Home/StatCard.razor` | Params: `Title`, `Icon`, `Total`, `FooterText`, `DailyBuckets`. Renders MudPaper + MudIcon + MudText (h3) + MudText (caption) + `MudChart ChartType="ChartType.Bar"` height ~40px with axes hidden |
| `Pages/Home/RecentActivityCard.razor` | Param: `IReadOnlyList<RecentActivityItemDto>`. Renders MudList with colored circle icon per kind + label + right-aligned relative timestamp. Empty state when list is empty |
| `Pages/Home/CliQuickstartCard.razor` | Static; MudPaper + 3 command lines + per-line MudIconButton (ContentCopy) → IJSRuntime clipboard + ISnackbar success toast |
| `Services/IDashboardApiClient.cs` + `DashboardApiClient.cs` | Single `GetStatsAsync(CancellationToken)` returning `ApiResult<DashboardStatsDto>` |
| `wwwroot/css/app.css` | Append a small block for the CLI code listing (dark background, monospace font, padding) — the only custom CSS |

Icon-color mapping for activity items: hotstring → `Color.Success`, hotkey → `Color.Warning`, profile → `Color.Secondary`. Updates dim to `Color.Default`.

Relative timestamp formatter is a small static helper (`HomeTimeFormat.Relative(DateTime utcNow, DateTime occurredAt)`) returning "2 min ago", "1 h ago", "Yesterday", or `yyyy-MM-dd`.

## Data flow

```
Home.razor.OnInitializedAsync
  → IDashboardApiClient.GetStatsAsync(ct)
    → GET /api/v1/dashboard/stats
      → DashboardController
        → IMediator.Send(new GetDashboardStatsQuery())
          → Handler:
              counts        : 3 × CountAsync (scoped by OwnerOid)
              weekly delta  : 3 × CountAsync (CreatedAt >= now-7d, OwnerOid)
              buckets       : 3 × GroupBy day → 14-day array
              profile split : CountAsync (IsDefault==true) + total
              activity      : 3 small Select() projections, UnionAll, OrderByDescending(MAX(Created,Updated)), Take 5
          → assemble DashboardStatsDto
          → Result.Success(dto)
      → result.ToActionResult(this) → 200 + DTO
  ← ApiResult<DashboardStatsDto>
  → set state, render
```

## Error handling

- Loading: `_loading = true`; stat cards and activity card render `MudSkeleton`. Hero and CLI quickstart render immediately (no data dependency).
- API failure (`ApiResult.IsSuccess == false`): page renders the hero, the CLI quickstart, and a `MudAlert Severity="Warning"` at the top with the error message. Stat cards and activity card render their empty states.
- Empty data: stat cards show `0` and an empty 14-bucket sparkline; activity card shows "No activity yet — add your first hotstring to get started.".
- The page does not handle 401 explicitly; the existing MSAL/auth setup in `MainLayout` is responsible.

## Testing

| Layer | Project | Tests |
|---|---|---|
| Handler | `AHKFlowApp.Application.Tests` (or `Infrastructure.Tests` if Testcontainers fixture lives there — follow existing handler-test placement) | Seed entities across two `OwnerOid`s; assert: filtering by current OwnerOid, weekly-delta math at the 7-day boundary, bucket array length = 14 and ordering oldest→newest, recent-activity ordering and "updated" vs "created" classification, profile Active/Default split |
| Controller | `AHKFlowApp.API.Tests` | `WebApplicationFactory` happy path returns 200 + serialized DTO; unauthenticated returns 401 |
| Component | `AHKFlowApp.UI.Blazor.Tests` | `StatCard` renders count + footer + chart; `RecentActivityCard` renders populated list and empty state; `HomePageTests` covers skeleton-during-load, success render, error render (MudAlert visible) |

No new Testcontainers fixture or test infrastructure is needed; reuse the existing SQL Server container fixture used by Hotstrings/Hotkeys/Profiles tests.

## Files to create / modify

**Create**:
- `src/Backend/AHKFlowApp.Application/DTOs/Dashboard/DashboardStatsDto.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/Dashboard/EntityStatsDto.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/Dashboard/ProfileStatsDto.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/Dashboard/RecentActivityItemDto.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQuery.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Dashboard/GetDashboardStatsQueryHandler.cs`
- `src/Backend/AHKFlowApp.API/Controllers/DashboardController.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/IDashboardApiClient.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/DashboardApiClient.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/HeroSection.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/StatCard.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/RecentActivityCard.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home/CliQuickstartCard.razor`
- `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HomeTimeFormat.cs`
- Test files matching the table in the Testing section

**Modify**:
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Home.razor` — replace placeholder with the composition above
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` — register `IDashboardApiClient` (follow existing client registration pattern with `.AddStandardResilienceHandler()`)
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/css/app.css` — append CLI code-block styles

## Verification

1. `dotnet build` succeeds.
2. `dotnet test` — new handler, controller, and bUnit tests pass.
3. Run locally:
   ```
   dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
   dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
   ```
4. Sign in, navigate to `/`. Verify:
   - Hero renders with italic "*flow*" and `.ahk` chip.
   - 3 stat cards render with real counts, "+X this week" (or "N active · M default" for profiles), and a 14-day sparkline.
   - Recent activity shows up to 5 most recent items with correct icon color and relative timestamps.
   - CLI quickstart copy buttons place the command on the clipboard and show a "Copied" snackbar.
   - With an empty database (new user): cards show 0, sparkline is flat, activity shows the empty state.
5. Force an API error (stop the API while frontend is open and reload): the `MudAlert` is visible and the page still renders hero + CLI quickstart.

## Open questions

- "Active" profile semantics: spec assumes `!IsDefault`. confirm vs. "currently selected"
- 14 days for sparkline buckets — keep or change (e.g., 7 / 30)?
- CLI command text in quickstart — keep aspirational examples or wait until CLI actually has those subcommands?
