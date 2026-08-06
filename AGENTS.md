# AGENTS.md - AHKFlowApp

## Overview

**AutoHotkey Hotstring Manager & CLI.** .NET 10 application for managing AutoHotkey hotstrings and hotkeys on Windows.
Blazor WebAssembly PWA frontend + ASP.NET Core Web API backend + `ahkflow` CLI client — the web UI and CLI are both first-class, shipped interfaces. Hotstring, hotkey, profile, and category management plus per-profile `.ahk` script generation and download are implemented across the API, UI, and CLI.

## Tech Stack

- **.NET 10.0** — all projects target `net10.0`; Microsoft.* packages use 10.x versions
- **EF Core** + SQL Server (LocalDB/Docker Compose/Azure SQL) with `EnableRetryOnFailure()`
- **Blazor WebAssembly** PWA with MudBlazor 9.x and Azure AD (MSAL) authentication
- **MinVer** for versioning from git tags; `.AddStandardResilienceHandler()` on all HttpClient registrations
- **Serilog** for structured logging (console, file, Application Insights sinks) — keep `CreateBootstrapLogger()` before host build and `Log.CloseAndFlushAsync()` on exit; `UseSerilogRequestLogging` after exception middleware; structured `{Property}` templates over interpolation; never log secrets or tokens

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
- Controller-based APIs: `[ApiController]` + `[Route("api/v1/[controller]")]`
- `sealed` on classes not designed for inheritance; `internal` by default, `public` only when needed
- Domain state: private setters plus factory/domain methods — never public setters on domain entities
- Style (file-scoped namespaces, Allman braces, `var`, collection expressions, pattern matching) — enforced by `.editorconfig`; run `dotnet format`
- English for all code comments and documentation — follow **Plain English** below
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

## Plain English

Applies to repo documentation (`docs/`, `AGENTS.md`, `CLAUDE.md`, specs, plans, skill files, README) and to app-facing text (Blazor UI labels, error messages, validation messages, CLI help and output).

The reader may not be a native English speaker. Write so they never have to re-read a sentence.

- Easy to read matters more than short. When the two conflict, use more words.
- One idea per sentence. Keep sentences under about 20 words.
- Use common words. "use" not "leverage". "cannot be undone" not "irreversible". "start" not "initiate". "text" not "prose".
- No idioms, no metaphors, no culture references. Cut "blow past it", "moving the needle", "escape hatch".
- Active voice. "The handler saves the record", not "the record is saved by the handler".
- Keep identifiers exact. Never simplify `IUseCaseHandler` or `Result.NotFound()`. Explain the term once instead.
- When you quote an existing error string, keep it exact. When you write a new error message, apply the rules above.
- Do not stack clauses. Split a long sentence into two.

Commit messages and PR titles are the exception — those stay extremely short, grammar optional.

## Testing

Frameworks: xUnit, FluentAssertions (over raw `Assert`), NSubstitute, Testcontainers (SQL Server). AAA pattern; naming `MethodName_Scenario_ExpectedResult`.

- **TDD first:** FluentValidation validators (pure functions), domain business rules
- **Test alongside:** Controllers + handlers — write impl + integration test together
- **Skip:** DTOs (records, no logic), DI registration, simple Blazor pages
- **Integration tests first** — WebApplicationFactory + Testcontainers catches serialization, middleware, DI, and query bugs
- **No `UseInMemoryDatabase`** — different behavior from real providers; always use Testcontainers
- Assert on `Result.IsSuccess` / `Result.Status` in handler unit tests
- Builder pattern for test data and scenarios — `new HotstringBuilder().WithTrigger("btw").Build()`, not raw construction or many-parameter factories. Builders live in `tests/AHKFlowApp.TestUtilities/Builders/`; add one there for new entities.
- NSubstitute for third-party boundaries only — don't mock what you own
- Test behavior (HTTP response, DB state, Result status), not implementation details
- `FakeTimeProvider` (from `Microsoft.Extensions.TimeProvider.Testing`) for time-dependent tests
- Derive expected seed keys and row counts from the seed source — never hard-code them, or a catalog change breaks unrelated suites
- Rebuild in Release **and restart the API/UI** before any live smoke test; a stale Debug build has served old seed data and produced a false failure

## Debugging

- State the root cause with `file:line` evidence before editing. Can't point to it — say so and keep investigating instead of shipping a plausible guess.
- If a fix fails ("it still does not work"), stop patching. Go back to instrumentation or docs research rather than guessing again at the same shape.

## Plans

At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

### Verify the draft before you present it

Run this on your own draft, right before you present a plan or spec for approval. It is not optional, and it is not something I have to ask for.

Every plan names things it claims already exist. Each one is either proven or made up. Prove them:

- **Identifiers defined in this repository** — a type, method, property, or option the plan says to call or extend. Paste the `file:line` that defines it.
- **Identifiers from .NET or a NuGet package** — `TimeProvider`, `HttpClient`, an `Ardalis.Result` member, an EF Core method. These have no `file:line` here, so that form of proof does not apply. Cite the official documentation instead, for the version this repository uses. Read that version from `Directory.Packages.props`. Never cite an external API from memory.
- **Component parameters** — any MudBlazor or other component parameter you pass. Prove it against the component API for the version in `Directory.Packages.props`. Guessed parameter names have reached plans before.
- **Selectors and test hooks** — every CSS selector and `data-test` value a test step depends on. Paste the `file:line` in the `.razor` file that renders it.
- **Emitted AHK syntax** — every option flag or construct the plan says to emit. Cite [`docs/development/ahk-v2-syntax.md`](docs/development/ahk-v2-syntax.md) or the official AHK v2 docs.
- **Branch and file state** — every claim about what is merged, what a sibling branch contains, or which files exist. Prove each with a `git` or filesystem command and keep the output.

Anything you cannot prove is marked **FABRICATED** in the draft. Do not quietly delete it and do not soften it into a vague sentence. List the fabricated items, then revise, then present.

When finalizing a plan or spec (right before presenting the final plan for approval), save it under `docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md` or `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. That folder is a separate PRIVATE git repo (`AHKFlowApp-plans`). It is cloned into the public repo, but the public repo git-ignores the path. So commit the plan from inside `docs/superpowers/`, not from the main repo root. `git add` from the root silently skips that path, so a root commit saves the plan nowhere. Never save a plan only in a local folder outside `docs/superpowers/`.

Only commit plans/specs to the private `docs/superpowers/` repo when they relate to project improvements — code, features, infra, deployment, tests, repo tooling that affects contributors. Skip writing (or keep out-of-repo) plans for agent optimization, personal workflow tuning, agent housekeeping, or one-off context/config cleanups.

## Verification After Implementation

This fires when implementation of a feature, fix, or plan task completes — **before reporting it done**, not only before commit, push, or PR. A change that has never been exercised is not finished. Don't leave defects for a review agent to find.

Default to a **durable test** as the verification artifact. Driving the app by hand proves it once; a test keeps proving it.

| Surface changed | Verification artifact | Command |
|---|---|---|
| Blazor UI flow, assertable | Add or extend a `*FlowTests.cs` in `tests/AHKFlowApp.E2E.Tests` | `pwsh .\scripts\test-fast.ps1 -Mode E2E` |
| UI, visual or exploratory only | Drive the running app with the `playwright-cli` skill, capture a screenshot | Read the worktree's own `launchSettings.json` for ports |
| API, use case, EF Core | Integration test (`Category=Integration` trait, or `API.Tests`) | `pwsh .\scripts\test-fast.ps1 -Mode Integration` |
| CLI behavior | `CLI.Tests` integration flow | `pwsh .\scripts\test-fast.ps1 -Mode Integration` |
| Emitted `.ahk` output | Assert the generated text. Add manual steps **only when the change emits a construct the repo has not shipped before** — new option flag, new escaping path, new action kind. Running `.ahk` is out of scope, so for proven constructs the assertion is the contract | `pwsh .\scripts\test-fast.ps1 -Mode Fast` |
| Domain rule, validator | Unit test | `pwsh .\scripts\test-fast.ps1 -Mode Fast` |
| Real Azure AD login, visual judgment call | Numbered manual steps for the user | — |

Which slice to run, test templates, and the canonical pre-PR gate: [`docs/development/testing-workflow.md`](docs/development/testing-workflow.md).

### The only exemptions

1. **Docs, skills, or plan files only** — nothing compiled. Targeted text checks plus diff review.
2. **Internal-only, no observable surface** — no UI, no API contract, no emitted `.ahk` change, no schema change.
3. **Pure refactor, no behavior change** — to claim this, name the existing tests that cover the changed code and paste their fresh pass output. No named coverage, no exemption; verify at runtime instead.

State the verdict either way. Naming an exemption is fine; saying nothing is not.

### When manual steps are the answer

Ask the user only for the cases the table sends to them. Then always provide:

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

- Propagate `CancellationToken` through the entire call chain; async all the way — no `.Result` / `.Wait()` (only exception: `Program.cs` top-level statements); `TimeProvider` over `DateTime.Now` / `DateTime.UtcNow`; `IHttpClientFactory` over `new HttpClient()`.
- Disable retries for unsafe HTTP methods (`options.Retry.DisableForUnsafeHttpMethods()`) when a client makes non-idempotent calls.
- Cross-cutting HTTP concerns (auth, correlation IDs, logging) belong in `DelegatingHandler`s, not call sites.

### Security

- Never hardcode secrets. Use `dotnet user-secrets` locally and Azure App Service Configuration in deployed environments. Never commit `.env` files, `appsettings.Development.json` with real credentials, or `credentials.json`.
- Blazor WASM `wwwroot/appsettings*.json` is public (downloadable by any user) — never treat it as secret.
- Options classes bind via `.BindConfiguration().ValidateDataAnnotations().ValidateOnStart()` — fail fast at startup.
- Always add `[Authorize]` or `[AllowAnonymous]` explicitly on every controller/endpoint.
- Parameterized queries only — EF Core `$""` interpolation is safe; `ExecuteSqlRaw` with concatenation is not.

## CI/CD

Workflows live in `.github/workflows/` under self-describing names. `ci.yml` is the PR gate — build, test, format check, Bicep lint. `provision.yml` is Bicep-only provisioning (advanced path; initial setup always requires `deploy.ps1`). `release-cli.yml` fires on `v*` tags and publishes `ahkflow-win-x64.zip` as a GitHub Release asset.

- **DEV** — local (`ASPNETCORE_ENVIRONMENT=Development`), LocalDB or Docker SQL, no Azure resources
- **TEST** auto-deploys on push to `main`; **PROD** deploys manually via `workflow_dispatch`. Resource suffix `-test` / `-prod`
- Provisioned per-environment with `.\scripts\deploy.ps1` — each gets its own resource group, SQL database, App Service, and Static Web App. See `docs/deployment/getting-started.md`
- Environment settings in `appsettings.{Environment}.json`. Frontend `appsettings.json` is committed (public, no secrets); backend secrets live in Azure App Service Configuration

## Environment URLs

**DEV (local):** API `http://localhost:5600` (single port for all backend scenarios: VS, docker-compose, Docker-only), frontend `http://localhost:5601`.

These are the **main checkout** ports. Agent git worktrees are assigned their own offset ports so a
worktree can run alongside the main checkout — read the worktree's own `launchSettings.json` rather
than assuming (e.g. API 5602 / frontend 5603 / SQL 14330, with a per-worktree `COMPOSE_PROJECT_NAME`).

**Local auth:** the main checkout runs real MSAL (Azure AD) by default. Agent git worktrees run
**no-auth** (test provider, always signed in as "Test User") automatically — `setup-worktree-local-dev.ps1`
writes both `appsettings.Development.json` files with `Auth:UseTestProvider=true`, so Playwright/E2E get
full CRUD with no login. Humans in the main checkout opt into no-auth by running
`pwsh .\scripts\run-frontend.ps1 -NoAuth`, paired with the API's `Docker SQL (No Auth)` backend
launch profile.

**TEST / PROD (Azure):** App Service and SQL Server names include a short deterministic suffix (e.g.
`ahkflowapp-api-test-ab12cd`) to avoid Azure's global-name collisions, so never guess them — read the
exact names/URLs from `scripts/.env.test` / `scripts/.env.prod`, written by `deploy.ps1`. API health is
the API URL + `/health`. SWA hostname:
`az staticwebapp show --name ahkflowapp-swa-<env> --query defaultHostname -o tsv`.

## Git Workflow

GitHub Flow — feature branches from `main`, PR required for all merges.
Branch naming: `feature/NNN-short-description`, `fix/short-description`, `hotfix/issueid-short-description`
Branches created in agent git worktrees insert `wt-` after the type prefix: `fix/wt-<topic>`, `feature/wt-NNN-<topic>` — marks worktree-born branches for grepping/cleanup.
Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:` — body explains "why", not "what".
Atomic commits: one logical change per commit; feature + its tests = one commit. Don't bundle unrelated changes.
Finishing a `backlog/` item: tick its acceptance boxes **and** `git mv` the file into `backlog/done/` in the same PR that does the work. Merging that PR is what completes the item, so the move belongs there. Never open a separate PR just to mark an item done.
Never force-push to main/master. Run the canonical pre-PR gate before creating a PR — [`docs/development/testing-workflow.md`](docs/development/testing-workflow.md#canonical-pre-pr-gate).
Keep PRs focused on a single concern; split large changes into stacked PRs.

Confirm the base before branching. A new branch starts from the main checkout's current HEAD, so
work that builds on unmerged work must say so explicitly: pass `-BaseRef <branch>` to
`scripts/new-worktree.ps1`. Check which branch actually contains the spec, plan, or code you are
building on rather than defaulting to `main` — branching from `main` while the prerequisite sits on
an open branch produces a diff full of unrelated commits after the first rebase. Claude Code's native
worktree creation cannot pass a base ref, so stacked work must call the script directly; see the
`worktrees` skill.

The AHKFlowApp main checkout is human-owned. A session running **in main** may inspect, edit,
build, test, and format there. A session running in a managed worktree may read main, but a shell
command that writes, moves, or deletes a path under main is refused. The guard gates a Git command
only when it could change the human's HEAD, index, or working tree in main. Most of these mutations need a managed linked worktree. Run from main
instead, and most now get an in-session approval prompt. A short list of operations — such as
`git worktree prune` or deleting an already-merged branch — always run from main, no prompt.
`git commit` is the one exception. It always needs a worktree, or a session-wide
`AHKFLOW_ALLOW_MAIN=1` set before the session starts. It never gets a prompt. Use
`scripts/new-worktree.ps1`, or the native `EnterWorktree` tool — that tool fires the
`WorktreeCreate` hook, which runs the same script. See `docs/agents/cross-agent-git-guardrails.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `s205109/AHKFlowApp`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — [`CONTEXT.md`](CONTEXT.md) (domain-term glossary; use its vocabulary) + [`docs/adr/`](docs/adr/) at the repo root. See `docs/agents/domain.md`.

The AHK v2 syntax we emit — option flags, escaping, `#HotIf`, bodies per kind — is documented in [`docs/development/ahk-v2-syntax.md`](docs/development/ahk-v2-syntax.md); read it before changing an emitter.

## Prerequisites

One-time setup — Windows Developer Mode, `git config core.symlinks true`, and the symlink / cross-agent skill scripts — is in [`docs/development/prerequisites.md`](docs/development/prerequisites.md). Symlinks fail silently without it. Codex captures skills at session start, so restart Codex after skill changes.

**Roslyn Navigator MCP** (`CWM.RoslynNavigator`) powers the code-navigation calls in the `dck-verify`, `dck-build-fix`, and `dck-de-sloppify` skills — install with `dotnet tool install -g CWM.RoslynNavigator` (registered in the repo's `.mcp.json`). Without it, those skills fall back to Grep/Roslyn LSP instead of the richer diagnostics.
