# Cross-Tool AI Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share AI agent configuration (instructions, rules, skills, hooks) between Claude Code and GitHub Copilot CLI using AGENTS.md as a bridge file and symlinks for skills.

**Architecture:** AGENTS.md at repo root holds all shared instructions + 5 inlined rules. Claude Code imports it via `@../AGENTS.md` in `.claude/CLAUDE.md`. Copilot CLI reads it natively. 22 portable skills symlinked from `.github/skills/` → `.claude/skills/`. Copilot hook config in `.github/hooks/hooks.json` references `.claude/hooks/` scripts.

**Tech Stack:** Git symlinks, PowerShell, AGENTS.md standard, Claude Code `@import`

**Spec:** `docs/superpowers/specs/2026-04-01-cross-tool-ai-config-design.md`

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `AGENTS.md` | Shared instructions + 5 inlined rules (source of truth) |
| Modify | `.claude/CLAUDE.md` | `@../AGENTS.md` import + Claude-specific sections only |
| Delete | `.claude/rules/naming.md` | Content moved to AGENTS.md `## Rules > ### Naming` |
| Delete | `.claude/rules/packages.md` | Content moved to AGENTS.md `## Rules > ### Packages` |
| Delete | `.claude/rules/performance.md` | Content moved to AGENTS.md `## Rules > ### Performance` |
| Delete | `.claude/rules/security.md` | Content moved to AGENTS.md `## Rules > ### Security` |
| Delete | `.claude/rules/testing.md` | Content moved to AGENTS.md `## Rules > ### Testing` |
| Create | `.github/hooks/hooks.json` | Copilot CLI hook config referencing `.claude/hooks/` scripts |
| Create | `.github/instructions/.gitkeep` | Preserve empty dir for future path-scoped instructions |
| Create | `scripts/setup-copilot-symlinks.ps1` | Setup script: validates prereqs, creates 22 skill symlinks |
| Create | `.github/skills/` (22 symlinks) | Symlinks to `.claude/skills/` portable skills |

---

### Task 1: Create Feature Branch and Set Git Config

**Files:**
- Modify: `.git/config` (local git setting)

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feature/cross-tool-ai-config
```

- [ ] **Step 2: Enable symlinks in git config**

```bash
git config core.symlinks true
```

- [ ] **Step 3: Verify setting**

```bash
git config core.symlinks
```

Expected: `true`

---

### Task 2: Create AGENTS.md

**Files:**
- Create: `AGENTS.md`

This is the largest task. Content is moved from `.claude/CLAUDE.md` plus 5 rule files inlined under `## Rules`.

**Note:** `## Code Conventions > ### Naming` (6 items from CLAUDE.md) and `## Rules > ### Naming` (8 items from `.claude/rules/naming.md`) have overlapping content. This is intentional — the Code Conventions section is the concise reference, the Rules section is the enforced superset with Validators and EF configurations. Do not deduplicate during implementation.

- [ ] **Step 1: Create AGENTS.md with shared content**

Write the following to `AGENTS.md` at repo root. Content is the shared sections from CLAUDE.md plus the 5 portable rules inlined as subsections:

```markdown
# AGENTS.md - AHKFlowApp

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
- `MediatR.Extensions.Microsoft.DependencyInjection` was merged into `MediatR` — only `MediatR` is needed.
- Microsoft.* packages targeting .NET 10 use 10.x versions (EF Core, Extensions, AspNetCore).
- When writing `<PackageReference>`, use `dotnet add package` first to resolve the correct version.
- With `Directory.Packages.props` (CPM), individual .csproj files must NOT specify `Version=`.
- Never downgrade a package unless explicitly asked. Prefer release over preview/RC.

### Performance

- Always propagate `CancellationToken` through the entire call chain.
- Async all the way — no `.Result` or `.Wait()`. Only exception: `Program.cs` top-level statements.
- `TimeProvider` over `DateTime.Now` / `DateTime.UtcNow` — injectable and testable.
- `IHttpClientFactory` over `new HttpClient()` — prevents socket exhaustion.
- `ArrayPool<T>` / `MemoryPool<T>` for buffer-heavy operations.
- Compiled queries (`EF.CompileAsyncQuery`) for hot-path EF Core queries.
- `ValueTask<T>` over `Task<T>` for high-throughput paths that often complete synchronously.

### Security

- Never hardcode secrets. Use `dotnet user-secrets` locally, Azure Key Vault in deployed environments.
- Never commit `.env` files, `appsettings.Development.json` with real credentials, or `credentials.json`.
- Validate all external input at system boundaries (FluentValidation / validation attributes).
- Parameterized queries only — never string concatenation for SQL. EF Core `$""` interpolation is safe; `ExecuteSqlRaw` with concatenation is not.
- Always add `[Authorize]` or `[AllowAnonymous]` explicitly on every controller/endpoint.
- HTTPS everywhere — enforce via HSTS, redirect HTTP to HTTPS.
- Data Protection API for encrypting user data at rest — never roll your own encryption.
- CORS: explicit origins only, never `AllowAnyOrigin()` in production.

### Testing

- **Integration tests first** — WebApplicationFactory + Testcontainers catches serialization, middleware, DI, and query bugs.
- **Never `UseInMemoryDatabase`** — different behavior from real providers. Always use Testcontainers (SQL Server).
- **NSubstitute for third-party boundaries only** — don't mock what you own (no mocking DbContext, repositories, or internal services).
- Test naming: `MethodName_Scenario_ExpectedResult`.
- AAA pattern (Arrange/Act/Assert) with blank line separation; one assertion concept per test.
- Assert on `Result.IsSuccess` / `Result.Status` in handler unit tests.
- Shared fixtures: `IClassFixture<T>`, `ICollectionFixture<T>` for expensive setup (containers).
- Frameworks: xUnit, FluentAssertions, NSubstitute, Testcontainers.

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

## Prerequisites

- **Windows Developer Mode** must be enabled (required for symlinks without admin privileges)
- **`git config core.symlinks true`** must be set per-repo (default is `false` on Windows)

Run `scripts/setup-copilot-symlinks.ps1` after cloning to configure symlinks for GitHub Copilot CLI skill discovery.
```

- [ ] **Step 2: Verify AGENTS.md was created**

```bash
test -f AGENTS.md && echo "OK" || echo "MISSING"
```

Expected: `OK`

- [ ] **Step 3: Commit AGENTS.md**

```bash
git add AGENTS.md
git commit -m "feat: add AGENTS.md as shared AI agent instructions"
```

---

### Task 3: Refactor CLAUDE.md

**Files:**
- Modify: `.claude/CLAUDE.md` (lines 1-216 → slim down to ~30 lines)

Replace the entire content of `.claude/CLAUDE.md` with Claude-specific sections only. All shared content is now in `AGENTS.md` via `@../AGENTS.md` import.

- [ ] **Step 1: Replace CLAUDE.md with Claude-specific content**

Write the following to `.claude/CLAUDE.md`:

```markdown
Be concise in all interactions. Optimize for readability when writing documentation. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Plans

At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

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

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — ordered work items (implement in backlog order)
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
```

- [ ] **Step 2: Verify CLAUDE.md contains @import**

```bash
grep -q '@../AGENTS.md' .claude/CLAUDE.md && echo "OK" || echo "MISSING"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "refactor: slim CLAUDE.md, import shared content from AGENTS.md"
```

---

### Task 4: Delete Ported Rule Files

**Files:**
- Delete: `.claude/rules/naming.md`
- Delete: `.claude/rules/packages.md`
- Delete: `.claude/rules/performance.md`
- Delete: `.claude/rules/security.md`
- Delete: `.claude/rules/testing.md`

- [ ] **Step 1: Delete the 5 ported rule files**

```bash
git rm .claude/rules/naming.md .claude/rules/packages.md .claude/rules/performance.md .claude/rules/security.md .claude/rules/testing.md
```

- [ ] **Step 2: Verify only Claude-specific rules remain**

```bash
ls .claude/rules/
```

Expected: `agents.md  hooks.md` (only these two)

- [ ] **Step 3: Commit**

```bash
git add -A .claude/rules/
git commit -m "refactor: remove ported rules, now inlined in AGENTS.md"
```

---

### Task 5: Create Copilot Hooks Configuration

**Files:**
- Create: `.github/hooks/hooks.json`

- [ ] **Step 1: Create .github/hooks/ directory**

```bash
mkdir -p .github/hooks
```

- [ ] **Step 2: Create hooks.json**

Write the following to `.github/hooks/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "postToolUse": [
      {
        "type": "command",
        "powershell": ".claude/hooks/post-edit-format.ps1",
        "comment": "Auto-format .cs files after edits"
      }
    ],
    "preToolUse": [
      {
        "type": "command",
        "bash": ".claude/hooks/pre-bash-guard.sh",
        "comment": "Block destructive bash commands"
      },
      {
        "type": "command",
        "powershell": ".claude/hooks/pre-commit-antipattern.ps1",
        "comment": "Detect bad C# patterns before commit"
      },
      {
        "type": "command",
        "powershell": ".claude/hooks/pre-commit-format.ps1",
        "comment": "Verify formatting before commit"
      }
    ]
  }
}
```

**Note:** This schema is provisional — based on Copilot CLI docs. Validate against current Copilot CLI version during testing. If the schema differs, adjust the JSON structure; the underlying scripts remain the same.

- [ ] **Step 3: Create .github/instructions/.gitkeep**

```bash
mkdir -p .github/instructions
touch .github/instructions/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git add .github/hooks/hooks.json .github/instructions/.gitkeep
git commit -m "feat: add Copilot CLI hooks config and instructions placeholder"
```

---

### Task 6: Create Setup Script

**Files:**
- Create: `scripts/setup-copilot-symlinks.ps1`

- [ ] **Step 1: Create scripts/ directory**

```bash
mkdir -p scripts
```

- [ ] **Step 2: Create setup-copilot-symlinks.ps1**

Write the following to `scripts/setup-copilot-symlinks.ps1`:

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Sets up GitHub Copilot CLI skill symlinks pointing to .claude/skills/.
.DESCRIPTION
    Creates symbolic links in .github/skills/ for portable skills.
    Requires Windows Developer Mode and git core.symlinks=true.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "Not inside a git repository."
    exit 1
}

Push-Location $repoRoot
try {
    # --- Prerequisite: Windows Developer Mode ---
    $devMode = Get-ItemPropertyValue `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
        -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
    if ($devMode -ne 1) {
        Write-Error @"
Windows Developer Mode is not enabled.
Enable it: Settings > System > For developers > Developer Mode = On
"@
        exit 1
    }
    Write-Host "[OK] Windows Developer Mode is enabled." -ForegroundColor Green

    # --- Prerequisite: git core.symlinks ---
    $symlinks = git config core.symlinks 2>$null
    if ($symlinks -ne 'true') {
        Write-Host "[FIX] Setting git config core.symlinks = true" -ForegroundColor Yellow
        git config core.symlinks true
    }
    Write-Host "[OK] git core.symlinks = true" -ForegroundColor Green

    # --- Create .github/skills/ directory ---
    $skillsDir = Join-Path $repoRoot '.github' 'skills'
    if (-not (Test-Path $skillsDir)) {
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    }

    # --- Portable skills to symlink (excludes Claude-specific) ---
    $portableSkills = @(
        'cck-api-versioning'
        'cck-authentication'
        'cck-blazor-mudblazor'
        'cck-build-fix'
        'cck-ci-cd'
        'cck-clean-architecture'
        'cck-configuration'
        'cck-dependency-injection'
        'cck-docker'
        'cck-ef-core'
        'cck-error-handling'
        'cck-httpclient-factory'
        'cck-logging'
        'cck-migration-workflow'
        'cck-modern-csharp'
        'cck-openapi'
        'cck-project-structure'
        'cck-resilience'
        'cck-scaffolding'
        'cck-security-scan'
        'cck-testing'
        'cck-verify'
    )

    $created = 0
    $skipped = 0
    foreach ($skill in $portableSkills) {
        $linkPath = Join-Path $skillsDir $skill
        $targetPath = Join-Path $repoRoot '.claude' 'skills' $skill

        if (Test-Path $linkPath) {
            $skipped++
            continue
        }

        if (-not (Test-Path $targetPath)) {
            Write-Warning "Source skill not found: $targetPath"
            continue
        }

        # Relative target for portability: ../../.claude/skills/<skill>
        $relativeTarget = "../../.claude/skills/$skill"
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $relativeTarget | Out-Null
        $created++
    }

    Write-Host ""
    Write-Host "Symlinks: $created created, $skipped already existed." -ForegroundColor Cyan
    Write-Host "[DONE] Copilot CLI skill symlinks are ready." -ForegroundColor Green
}
finally {
    Pop-Location
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-copilot-symlinks.ps1
git commit -m "feat: add setup script for Copilot CLI skill symlinks"
```

---

### Task 7: Run Setup Script and Create Symlinks

**Files:**
- Create: `.github/skills/` (22 symlinks)

- [ ] **Step 1: Run the setup script**

```bash
powershell -ExecutionPolicy Bypass -File scripts/setup-copilot-symlinks.ps1
```

Expected output:
```
[OK] Windows Developer Mode is enabled.
[OK] git core.symlinks = true
Symlinks: 22 created, 0 already existed.
[DONE] Copilot CLI skill symlinks are ready.
```

- [ ] **Step 2: Verify symlinks were created**

```bash
ls -la .github/skills/ | head -25
```

Expected: 22 entries, each showing `->` pointing to `../../.claude/skills/<name>`

- [ ] **Step 3: Verify a symlink resolves correctly**

```bash
test -f .github/skills/cck-testing/SKILL.md && echo "OK" || echo "BROKEN"
```

Expected: `OK`

- [ ] **Step 4: Commit symlinks**

```bash
git add .github/skills/
git commit -m "feat: add 22 Copilot CLI skill symlinks to .claude/skills"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Verify .claude/rules/ has only Claude-specific rules**

```bash
ls .claude/rules/
```

Expected: `agents.md  hooks.md`

- [ ] **Step 2: Verify AGENTS.md exists at root and has key sections**

```bash
grep -c "^## " AGENTS.md
```

Expected: `15` (the number of `##` heading sections)

- [ ] **Step 3: Verify CLAUDE.md imports AGENTS.md**

```bash
grep '@../AGENTS.md' .claude/CLAUDE.md
```

Expected: `@../AGENTS.md`

- [ ] **Step 4: Verify .github/hooks/hooks.json exists**

```bash
test -f .github/hooks/hooks.json && echo "OK" || echo "MISSING"
```

Expected: `OK`

- [ ] **Step 5: Verify symlink count**

```bash
find .github/skills/ -maxdepth 1 -type l | wc -l
```

Expected: `22`

- [ ] **Step 6: Verify project still builds**

```bash
dotnet build --configuration Release
```

Expected: Build succeeded

- [ ] **Step 7: Run the setup script again (idempotency check)**

```bash
powershell -ExecutionPolicy Bypass -File scripts/setup-copilot-symlinks.ps1
```

Expected:
```
[OK] Windows Developer Mode is enabled.
[OK] git core.symlinks = true
Symlinks: 0 created, 22 already existed.
[DONE] Copilot CLI skill symlinks are ready.
```
