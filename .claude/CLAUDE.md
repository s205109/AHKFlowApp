Be concise in all interactions. Optimize for readability when writing documentation. In commit messages, be extremely concise — sacrifice grammar for brevity.

# CLAUDE.md - AHKFlowApp

## Overview

.NET 10 application for managing AutoHotkey hotstrings and hotkeys on Windows.
Blazor WebAssembly PWA frontend + ASP.NET Core Web API backend. Early stage — foundation and CI/CD complete; domain features are future work.

## Tech Stack

- **.NET 10.0** — all projects target `net10.0`; Microsoft.* packages use 10.x versions
- **EF Core** + SQL Server (LocalDB/Docker Compose/Azure SQL) with `EnableRetryOnFailure()`
- **Blazor WebAssembly** PWA with MudBlazor 9.x and Azure AD (MSAL) authentication
- **MediatR** (Jimmy Bogard) for CQRS — commands, queries, pipeline behaviors
- **Ardalis.Result** for typed operation outcomes (handlers only)
- **FluentValidation** via MediatR pipeline behavior (auto-validates before handler)
- `.AddStandardResilienceHandler()` on all HttpClient registrations
- **Serilog** for structured logging (console, file, Application Insights sinks)
- **MinVer** for automatic semantic versioning from git tags
- **Testing:** xUnit + FluentAssertions + NSubstitute; Testcontainers (SQL Server) for integration tests

## Project Structure

```
src/Backend/
  AHKFlowApp.Domain/              # Entities, value objects — zero external dependencies
  AHKFlowApp.Application/         # DTOs, MediatR commands/queries, validators
  AHKFlowApp.Infrastructure/      # EF Core DbContext, repositories, migrations
  AHKFlowApp.API/                 # Controllers, middleware, DI registration

src/Frontend/
  AHKFlowApp.UI.Blazor/           # Blazor WebAssembly PWA (MudBlazor, MSAL auth)

tests/
  AHKFlowApp.API.Tests/           # API integration tests (WebApplicationFactory)
  AHKFlowApp.Application.Tests/   # Validator + service unit tests
  AHKFlowApp.Domain.Tests/        # Domain logic unit tests
  AHKFlowApp.Infrastructure.Test/ # Repository integration tests
  AHKFlowApp.UI.Blazor.Tests/     # Blazor component tests (bUnit)
```

## Commands

```bash
# Build all projects
dotnet restore && dotnet build --configuration Release --no-restore

# Run all tests
dotnet test --configuration Release --no-build --verbosity normal

# Run a single test project
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal

# Run a single test by name
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HealthControllerTests"

# Run API locally (recommended: Docker SQL on port 1433)
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + Docker SQL (Recommended)"

# Run Blazor frontend (separate terminal)
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor

# Full stack via Docker Compose (SQL Server + API)
docker compose up --build

# EF Core migrations
dotnet ef migrations add <Name> --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
dotnet ef database update --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API

# Format
dotnet format

# GitHub CLI is the primary way to interact with GitHub (PRs, issues, checks)
```

## Architecture Rules

- **Clean Architecture:** API -> Infrastructure -> Application -> Domain (strict inward dependency)
- Domain and Application have **no references** to EF Core or infrastructure concerns
- **No repository pattern** — MediatR handlers inject AppDbContext directly (DbSet is already a repository)
- **MediatR** for all commands/queries — Controller -> IMediator.Send() -> Handler -> DbContext
- **Ardalis.Result** — handlers return Result<T>, controllers map via `result.ToActionResult(this)`
- **FluentValidation** runs in MediatR IPipelineBehavior — handlers never see invalid requests
- **Thin controllers** — accept requests, send via MediatR, map Result to HTTP response
- **GlobalExceptionMiddleware** returns RFC 9457 ProblemDetails for unhandled errors
- **Explicit mapping** — no mapper libraries (no Mapster, no AutoMapper)
- **Layer folders** — organize by layer (Controllers/, Commands/, Queries/), not by feature
- **Shared projects** contain only contracts (interfaces, DTOs, integration events) — never business logic
- **Error results:** `Result.NotFound()`, `Result.Invalid(errors)`, `Result.Conflict()`, `Result.Error()` for external API failures
- Don't catch bare `Exception` unless at app boundary (middleware); don't catch-and-rethrow without adding context
- Don't defensively validate inside internal/private methods — trust data validated at boundaries

## Code Conventions

### Naming
- Controllers: plural (`HotstringsController`, `ProfilesController`)
- DTOs: `{Entity}Dto`, `Create{Entity}Dto`, `Update{Entity}Dto` (records)
- Commands: `Create{Entity}Command`, `Update{Entity}Command`
- Queries: `Get{Entity}Query`, `List{Entities}Query`
- Handlers: `{Command/Query}Handler`
- Async methods: `*Async` suffix

### Patterns We Use
- Primary constructors for DI (no `_field = field` ceremony)
- Records for DTOs, commands, queries, and value objects
- File-scoped namespaces, Allman brace style — enforced by `.editorconfig`
- Controller-based APIs: `[ApiController]` + `[Route("api/v1/[controller]")]`
- `var` when type is apparent, null-coalescing (`??`) over verbose null checks
- `sealed` on classes not designed for inheritance
- `internal` by default, `public` only when needed
- Collection expressions (`[1, 2, 3]`) over constructor calls (`new List<int> { 1, 2, 3 }`)
- Pattern matching / switch expressions over if-else chains
- Member ordering: constants, fields, constructors, properties, public methods, private methods
- English for all code comments and documentation
- PowerShell for script files, bash for manual scripts in .md files

### Patterns We DON'T Use (Never Suggest)
- **Traditional constructors** with `_field` ceremony — use primary constructors
- **Repository pattern** — use EF Core DbContext directly in handlers
- **Mapster / AutoMapper** — write explicit mappings
- **Minimal APIs** — controller-based only, no `IEndpointGroup` or endpoint routing
- **Feature folders** — use layer folders (Controllers/, Commands/, Queries/)
- **Exceptions for flow control** — use Ardalis.Result
- **Stored procedures** — EF Core only
- **.NET Foundation license header** — this project is not part of the .NET Foundation

## Request Flow

```
HTTP Request -> Controller (thin, maps Result to HTTP)
  -> IMediator.Send(Command/Query)
    -> IPipelineBehavior (FluentValidation)
      -> Handler (business logic, returns Result<T>)
        -> AppDbContext (EF Core, direct injection)
```

## Testing

- **TDD first:** FluentValidation validators (pure functions), domain business rules
- **Test alongside:** Controllers + handlers — write impl + integration test together
- **Skip:** DTOs (records, no logic), DI registration, simple Blazor pages
- **Integration tests first** — WebApplicationFactory + Testcontainers catches serialization, middleware, DI, and query bugs
- **No `UseInMemoryDatabase`** — different behavior from real providers; always use Testcontainers
- Test naming: `MethodName_Scenario_ExpectedResult`
- AAA pattern (Arrange/Act/Assert) with blank line separation; one assertion concept per test
- Assert on `Result.IsSuccess` / `Result.Status` in handler unit tests
- Shared fixtures: `IClassFixture<T>`, `ICollectionFixture<T>` for expensive setup (containers)
- NSubstitute for third-party boundaries only — don't mock what you own
- Test behavior (HTTP response, DB state, Result status), not implementation details
- Frameworks: xUnit, FluentAssertions, NSubstitute, Testcontainers (SQL Server)

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `ahkflowapp-deploy-api.yml` — build, test, publish, migrate DB, deploy to Azure App Service
- `ahkflowapp-deploy-frontend.yml` — build and deploy Blazor to Azure Static Web Apps
- `ahkflowapp-migrate-db.yml` — manual database migration workflow
- `ahkflowapp-configure-production.yml` — Azure infrastructure configuration (Key Vault, CORS, env vars)

Configuration: Frontend `appsettings.json` is committed (public, no secrets). Backend secrets managed via Azure App Service Configuration + Key Vault.

## Git Workflow

GitHub Flow — feature branches from `main`, PR required for all merges.
Branch naming: `feature/NNN-short-description`, `fix/short-description`, `hotfix/issueid-short-description`
Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:` — body explains "why", not "what".
Atomic commits: one logical change per commit; feature + its tests = one commit. Don't bundle unrelated changes.
Never force-push to main/master. Run `dotnet build` + `dotnet test` before creating a PR.
Keep PRs focused on a single concern; split large changes into stacked PRs.

## GitHub

Primary way to interact with GitHub is the `gh` CLI.

## Plans

At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

## Local URLs

- API: `https://localhost:7600` (HTTPS), `http://localhost:5600` (HTTP)
- Frontend: `https://localhost:7601`, `http://localhost:5601`
- Docker Compose API: `http://localhost:5602`

## Domain Terms

- **Hotstring** — text replacement trigger: type an abbreviation (e.g., `btw`), auto-expands to full text (`by the way`). Core domain entity.
- **Hotkey** — keyboard shortcut binding: key combination triggers an action. Future feature.
- **Profile** — named grouping of hotstrings and hotkeys (e.g., "Work", "Personal"). Future feature.
- **Script** — generated `.ahk` file per profile, combining all definitions into executable AutoHotkey syntax. Future feature.
- **Trigger** — the abbreviation or key combination that activates a hotstring or hotkey.
- **Replacement** — the expanded text that replaces a hotstring trigger.

## Workflow Preferences

- When asked to store instructions or rules, put them in CLAUDE.md (not memory files) unless explicitly told otherwise.

## Out of Scope

Do not implement these — they are planned for future phases or intentionally excluded:
- CLI application (`src/Tools/AHKFlowApp.CLI`) — planned, directory not yet created
- Hotstring/Hotkey/Profile CRUD features — see `.claude/backlog/` items 013-026
- Script generation and download
- Runtime execution of AutoHotkey scripts — intentionally excluded
- Authentication implementation details — see backlog item 012

## Project Configuration

- Rules (always loaded): `.claude/rules/claude-code-kit/`
- Skills (on demand): `.claude/skills/claude-code-kit/`
- Backlog: `.claude/backlog/` — ordered work items (implement in backlog order)
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored — Azure defaults, private CLI commands)
- Documentation: `docs/` — architecture, azure, development guides
