# AGENTS.md - AHKFlowApp

## Overview

**AutoHotkey Hotstring Manager & CLI.** .NET 10 application for managing AutoHotkey hotstrings and hotkeys on Windows.
Blazor WebAssembly PWA frontend + ASP.NET Core Web API backend + `ahkflow` CLI client — the web UI and CLI are both first-class, shipped interfaces. Hotstring, hotkey, profile, and category management plus per-profile `.ahk` script generation and download are implemented across the API, UI, and CLI.

## Tech Stack

- **.NET 10.0** — all projects target `net10.0`; Microsoft.* packages use 10.x versions
- **EF Core** + SQL Server (LocalDB/Docker Compose/Azure SQL) with `EnableRetryOnFailure()`
- **Blazor WebAssembly** PWA with MudBlazor 9.x and Azure AD (MSAL) authentication
- **Explicit use cases** (`IUseCase`/`IUseCaseHandler`) for CQRS — commands, queries, validation decoration
- **Ardalis.Result** for typed operation outcomes (handlers only)
- **FluentValidation** via `ValidatingUseCase<TRequest,TResult>` decorator (auto-validates before handler)
- `.AddStandardResilienceHandler()` on all HttpClient registrations
- **Serilog** for structured logging (console, file, Application Insights sinks) — keep `CreateBootstrapLogger()` before host build and `Log.CloseAndFlushAsync()` on exit; `UseSerilogRequestLogging` after exception middleware; structured `{Property}` templates over interpolation; never log secrets or tokens
- **MinVer** for automatic semantic versioning from git tags
- **Testing:** xUnit + FluentAssertions + NSubstitute; Testcontainers (SQL Server) for integration tests

## Project Structure

```
src/Backend/
  AHKFlowApp.Domain/              # Entities, value objects — zero external dependencies
  AHKFlowApp.Application/         # DTOs, commands/queries, use case handlers, validators
  AHKFlowApp.Infrastructure/      # EF Core DbContext, repositories, migrations
  AHKFlowApp.API/                 # Controllers, middleware, DI registration

src/Frontend/
  AHKFlowApp.UI.Blazor/           # Blazor WebAssembly PWA (MudBlazor, MSAL auth)

tests/
  AHKFlowApp.API.Tests/           # API integration tests (WebApplicationFactory)
  AHKFlowApp.Application.Tests/   # Validator + handler unit/integration tests
  AHKFlowApp.Domain.Tests/        # Domain logic unit tests
  AHKFlowApp.Infrastructure.Tests/ # EF Core integration tests
  AHKFlowApp.UI.Blazor.Tests/     # Blazor component tests (bUnit)
  AHKFlowApp.E2E.Tests/           # End-to-end browser tests (Playwright)
  AHKFlowApp.TestUtilities/       # Shared builders and DB fixtures
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
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"

# Run Blazor frontend (separate terminal)
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor

# Full stack via Docker Compose (SQL Server + API + Blazor UI)
docker compose up --build

# Local-only stack, no Azure AD: see README "Run locally without Azure"

# EF Core migrations
dotnet ef migrations add <Name> --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
dotnet ef database update --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API

# Format
dotnet format

# GitHub CLI is the primary way to interact with GitHub (PRs, issues, checks)
```

## Architecture Rules

- **Clean Architecture:** API -> Infrastructure -> Application -> Domain (strict inward dependency)
- **Domain** has **no references** to EF Core or infrastructure concerns — zero external dependencies
- **Application** references EF Core by design (it injects `AppDbContext` per the no-repository rule below), including the SQL Server provider for `EF.Functions` translations. It must not reference the API or Infrastructure projects.
- **No repository pattern** — IUseCaseHandler implementations inject AppDbContext directly (DbSet is already a repository)
- **Explicit use cases** for all commands/queries — Controller -> IUseCase<TRequest,TResult>.ExecuteAsync() -> IUseCaseHandler -> DbContext
- **Ardalis.Result** — handlers return Result<T>, controllers map via `result.ToActionResult(this)`
- **FluentValidation** runs through the `ValidatingUseCase<TRequest,TResult>` decorator — handlers never see invalid requests
- **Thin controllers** — accept requests, call the matching IUseCase<TRequest,TResult>, map Result to HTTP response
- **GlobalExceptionMiddleware** returns RFC 9457 ProblemDetails for unhandled errors
- **Explicit mapping** — no mapper libraries (no Mapster, no AutoMapper)
- **Layer folders** — organize by layer (Controllers/, Commands/, Queries/), not by feature
- **Shared projects** contain only contracts (interfaces, DTOs, integration events) — never business logic
- **Error results:** `Result.NotFound()`, `Result.Invalid(errors)`, `Result.Conflict()`, `Result.Error()` for external API failures
- Don't catch bare `Exception` unless at app boundary (middleware); don't catch-and-rethrow without adding context
- Don't defensively validate inside internal/private methods — trust data validated at boundaries

## Code Conventions

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
- Domain state: private setters plus factory/domain methods — never public setters on domain entities
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
  -> IUseCase<TRequest,TResult>.ExecuteAsync()
    -> ValidatingUseCase<TRequest,TResult> (FluentValidation)
      -> IUseCaseHandler<TRequest,TResult> (business logic, returns Result<T>)
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
- FluentAssertions over raw `Assert` — better failure messages
- Builder pattern for test data and scenarios — `new HotstringBuilder().WithTrigger("btw").Build()`, not raw construction or many-parameter factories. Builders live in `tests/AHKFlowApp.TestUtilities/Builders/`; add one there for new entities.
- Shared fixtures: `IClassFixture<T>`, `ICollectionFixture<T>` for expensive setup (containers)
- NSubstitute for third-party boundaries only — don't mock what you own
- Test behavior (HTTP response, DB state, Result status), not implementation details
- `FakeTimeProvider` (from `Microsoft.Extensions.TimeProvider.Testing`) for time-dependent tests
- Frameworks: xUnit, FluentAssertions, NSubstitute, Testcontainers (SQL Server)

## Plans

At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

When finalizing a plan or spec (right before presenting the final plan for approval), save it in the repo as `docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md` or `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` — never only in a local plans folder outside the repo.

Only commit plans/specs to `docs/superpowers/` when they relate to project improvements — code, features, infra, deployment, tests, repo tooling that affects contributors. Skip writing (or keep out-of-repo) plans for agent optimization, personal workflow tuning, agent housekeeping, or one-off context/config cleanups.

## Manual Testing Requests

Prefer verifying yourself with browser automation (Playwright preferred; Claude in Chrome as fallback) over asking the user to test manually. Asking is fine when automation can't cover it (e.g. real Azure AD login, visual judgment calls) or when asking is clearly easier or faster.

When asking the user to manually test or verify anything (UI flows, commands, acceptance checks), always provide:

- **Preconditions first** — what must be running, exact URL, login/profile, starting state
- **Numbered steps, one action each** — never combine actions in one step
- **Verbatim input in code blocks** — anything typed or pasted is given literally, never described
- **Expected result per step** — so pass/fail is clear immediately, not only at the end
- **Feedback labeled per step** — state exactly what to paste or screenshot back, mapped to step numbers (e.g. "reply with: step 3 screenshot, step 5 pasted output")

## Rules

### Naming

- Controllers: plural (`HotstringsController`, `ProfilesController`)
- DTOs: `{Entity}Dto`, `Create{Entity}Dto`, `Update{Entity}Dto` (records)
- Commands: `Create{Entity}Command`, `Update{Entity}Command`, `Delete{Entity}Command`
- Queries: `Get{Entity}Query`, `List{Entities}Query`
- Handlers: `{Command/Query}Handler`
- Validators: `{Command/Query}Validator`
- Async methods: `*Async` suffix
- EF configurations: `{Entity}Configuration` implementing `IEntityTypeConfiguration<T>`

### Packages

- Never hardcode package versions from memory — training data contains outdated versions.
- Run `dotnet add package <name>` without `--version` to get latest stable automatically.
- Microsoft.* packages targeting .NET 10 use 10.x versions (EF Core, Extensions, AspNetCore).
- When writing `<PackageReference>`, use `dotnet add package` first to resolve the correct version.
- With `Directory.Packages.props` (CPM), individual .csproj files must NOT specify `Version=`.
- Never downgrade a package unless explicitly asked. Prefer release over preview/RC.
- **Never upgrade `Microsoft.ApplicationInsights.AspNetCore` to 3.x.** Stay on 2.x — v3 caused runtime issues. Only revisit if explicitly asked.

### Performance

- Always propagate `CancellationToken` through the entire call chain.
- Async all the way — no `.Result` or `.Wait()`. Only exception: `Program.cs` top-level statements.
- `TimeProvider` over `DateTime.Now` / `DateTime.UtcNow` — injectable and testable.
- `IHttpClientFactory` over `new HttpClient()` — prevents socket exhaustion.
- Disable retries for unsafe HTTP methods (`options.Retry.DisableForUnsafeHttpMethods()`) when a client makes non-idempotent calls.
- Cross-cutting HTTP concerns (auth, correlation IDs, logging) belong in `DelegatingHandler`s, not call sites.
- `ArrayPool<T>` / `MemoryPool<T>` for buffer-heavy operations.
- Compiled queries (`EF.CompileAsyncQuery`) for hot-path EF Core queries.
- `ValueTask<T>` over `Task<T>` for high-throughput paths that often complete synchronously.

### Security

- Never hardcode secrets. Use `dotnet user-secrets` locally and Azure App Service Configuration in deployed environments.
- Never commit `.env` files, `appsettings.Development.json` with real credentials, or `credentials.json`.
- Blazor WASM `wwwroot/appsettings*.json` is public (downloadable by any user) — never treat it as secret.
- Options classes bind via `.BindConfiguration().ValidateDataAnnotations().ValidateOnStart()` — fail fast at startup.
- Validate all external input at system boundaries (FluentValidation / validation attributes).
- Parameterized queries only — never string concatenation for SQL. EF Core `$""` interpolation is safe; `ExecuteSqlRaw` with concatenation is not.
- Always add `[Authorize]` or `[AllowAnonymous]` explicitly on every controller/endpoint.
- HTTPS everywhere — enforce via HSTS, redirect HTTP to HTTPS.
- Data Protection API for encrypting user data at rest — never roll your own encryption.
- CORS: explicit origins only, never `AllowAnyOrigin()` in production.

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `ci.yml` — PR gate: build, test, format check, Bicep lint
- `deploy-api.yml` — build, test, publish/package the API, migrate DB, deploy to Azure App Service (TEST on push to main, PROD on manual trigger)
- `deploy-frontend.yml` — build and deploy Blazor to Azure Static Web Apps (TEST on push to main, PROD on manual trigger)
- `migrate-db.yml` — manual database migration workflow with environment selection
- `provision.yml` — manual Bicep-only provisioning (advanced path; initial setup always requires `deploy.ps1`)
- `release-cli.yml` — on `v*` tags: build, test, package `ahkflow-win-x64.zip`, and publish it as a GitHub Release asset (CLI releases / winget source)

**Environments:**
- **DEV:** Local development environment (`ASPNETCORE_ENVIRONMENT=Development`)
  - LocalDB or Docker SQL Server
  - No Azure resources required
  - Run locally with `dotnet run`
- **TEST:** Azure pre-production environment (`ASPNETCORE_ENVIRONMENT=Test`)
  - Auto-deploys on push to `main` branch
  - Azure App Service, Azure SQL Database, Static Web Apps
  - Resource suffix: `-test`
- **PROD:** Azure production environment (`ASPNETCORE_ENVIRONMENT=Production`)
  - Manual deployment via workflow_dispatch trigger
  - Azure App Service, Azure SQL Database, Static Web Apps
  - Resource suffix: `-prod`

Configuration: Frontend `appsettings.json` is committed (public, no secrets). Backend secrets are managed via Azure App Service Configuration. Environment-specific settings in `appsettings.{Environment}.json` files.

Azure resources are provisioned per-environment using `.\scripts\deploy.ps1`. Each environment gets its own isolated resource group, SQL database, App Service, and Static Web App. See `docs/deployment/getting-started.md` for full instructions.

## Environment URLs

### DEV (Local)
- API: `http://localhost:5600` (single port for all backend scenarios: VS, docker-compose, Docker-only)
- Frontend: `http://localhost:5601`

These are the **main checkout** ports. Agent git worktrees are assigned their own offset ports so a
worktree can run alongside the main checkout — read the worktree's own `launchSettings.json` rather
than assuming (e.g. API 5602 / frontend 5603 / SQL 14330, with a per-worktree `COMPOSE_PROJECT_NAME`).

**Local auth:** the main checkout runs real MSAL (Azure AD) by default. Agent git worktrees run
**no-auth** (test provider, always signed in as "Test User") automatically — `setup-worktree-local-dev.ps1`
writes both `appsettings.Development.json` files with `Auth:UseTestProvider=true`, so Playwright/E2E get
full CRUD with no login. Humans in the main checkout opt into no-auth via the `http (No Auth)` frontend
and `Docker SQL (No Auth)` backend launch profiles.

App Service and SQL Server names include a short deterministic suffix (e.g. `ahkflowapp-api-test-ab12cd`)
to avoid Azure's global-name collisions. Exact names/URLs are saved to `scripts/.env.<env>` after
running `deploy.ps1`.

### TEST (Azure)
- API: `https://<APP_SERVICE_NAME_TEST>.azurewebsites.net` — read from `scripts/.env.test`
- API health: append `/health` to the URL above
- Frontend (SWA): `az staticwebapp show --name ahkflowapp-swa-test --query defaultHostname -o tsv`

### PROD (Azure)
- API: `https://<APP_SERVICE_NAME_PROD>.azurewebsites.net` — read from `scripts/.env.prod`
- API health: append `/health` to the URL above
- Frontend (SWA): `az staticwebapp show --name ahkflowapp-swa-prod --query defaultHostname -o tsv`

## Git Workflow

GitHub Flow — feature branches from `main`, PR required for all merges.
Branch naming: `feature/NNN-short-description`, `fix/short-description`, `hotfix/issueid-short-description`
Branches created in agent git worktrees insert `wt-` after the type prefix: `fix/wt-<topic>`, `feature/wt-NNN-<topic>` — marks worktree-born branches for grepping/cleanup.
Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:` — body explains "why", not "what".
Atomic commits: one logical change per commit; feature + its tests = one commit. Don't bundle unrelated changes.
Never force-push to main/master. Run `dotnet build` + `dotnet test` before creating a PR.
Keep PRs focused on a single concern; split large changes into stacked PRs.

The AHKFlowApp main checkout is human-owned for Git mutations. Agents may inspect, edit, build,
test, and format there, but must branch, add, commit, merge, rebase, and push for this repository
only from a managed linked worktree. Use `scripts/new-worktree.ps1` or the `WorktreeCreate` tool.
`AHKFLOW_ALLOW_MAIN=1` is an explicit location override; destructive-command protections still
apply. See `docs/agents/cross-agent-git-guardrails.md`.

## GitHub

Primary way to interact with GitHub is the `gh` CLI.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `s205109/AHKFlowApp`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — [`CONTEXT.md`](CONTEXT.md) (domain-term glossary; use its vocabulary) + [`docs/adr/`](docs/adr/) at the repo root. See `docs/agents/domain.md`.

The AHK v2 syntax we emit — option flags, escaping, `#HotIf`, bodies per kind — is documented in [`docs/development/ahk-v2-syntax.md`](docs/development/ahk-v2-syntax.md); read it before changing an emitter.

## Prerequisites

- **Windows Developer Mode** must be enabled (required for symlinks without admin privileges)
- **`git config core.symlinks true`** must be set per-repo (default is `false` on Windows)
- **Roslyn Navigator MCP** (`CWM.RoslynNavigator`) powers the code-navigation calls in the `dck-verify`, `dck-build-fix`, and `dck-de-sloppify` skills — install with `dotnet tool install -g CWM.RoslynNavigator` (registered in the repo's `.mcp.json`). Without it, those skills fall back to Grep/Roslyn LSP instead of the richer diagnostics.

Run `scripts/agents/setup-copilot-symlinks.ps1` after cloning to configure symlinks for GitHub Copilot CLI skill discovery.

`scripts/agents/setup-cross-agent-skills.ps1` (re-run automatically by the `post-merge` hook when skills change) also bumps the Codex plugin version in `plugins/ahkflowapp/.codex-plugin/plugin.json` from a content hash and refreshes the installed Codex plugin cache via `codex plugin add ahkflowapp@ahkflowapp-local`. Codex captures available skills at session start — start a new Codex session after skill changes.
