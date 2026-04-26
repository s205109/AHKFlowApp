# Plan 6 — Docs + consistency sweep

**Roadmap:** `docs/superpowers/specs/2026-04-21-codebase-simplification-roadmap-design.md`
**Date:** 2026-04-26
**Size:** S
**Status:** Approved

## Context

Plans 1–5 of the simplification roadmap have shipped. Plan 5 (local-install via `Auth:UseTestProvider`) is the most recent — it added a docker-compose Blazor service, a synthetic-auth toggle, and an `appsettings.Local.json` bake-in for the Blazor image. Plan 4 (script overhaul) consolidated `/scripts/`. Several supporting docs still describe the pre-Plan-4/5 shape and contain commands that no longer work.

This plan closes the loop: align the docs surface with what the code actually does. Pure docs work — no code or test changes. Goal is one PR, reviewable in well under 30 minutes.

## Sources of truth (cross-checked)

- `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` — actual launch profile names
- `docker-compose.yml` — actual SA password and services
- `scripts/` — actual script names
- `.gitignore` — what's actually committed
- README.md — already correct after Plan 5; treat as the canonical "Run locally" reference

## Scope

**In:**
- Fix stale commands, broken file references, and contradictions across `README.md`, `AGENTS.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, `.github/*`, `docs/**` (excluding `docs/superpowers/` historical content).
- Single local-dev prerequisites page at `docs/development/prerequisites.md`, linked from README. Azure-deploy prereqs stay inline in `docs/deployment/getting-started.md` (different audience; `deploy.ps1` validates them).
- AGENTS.md gains one line pointing to README's "Run locally without Azure" section.

**Out:**
- Rewriting architecture docs (`docs/architecture/*`).
- New guides.
- Code, config, test, or workflow changes.
- Memory-file maintenance (auto-memory, not in repo).
- `.github/copilot-instructions.md` (intentional stub redirecting to AGENTS.md — leave alone).
- PR template additions.

## Concrete file changes

### 1. `AGENTS.md` (highest impact — wrong dev command)
- **L57** Replace `--launch-profile "https + Docker SQL (Recommended)"` with `--launch-profile "Docker SQL (Recommended)"`.
- **L62** Update compose comment from `(SQL Server + API)` to `(SQL Server + API + Blazor UI)`.
- Under **Commands**, add one line: `# Local-only stack (no Azure AD): see README "Run locally without Azure"`.

### 2. `docs/environments.md`
- **L25–33** Fix launch-profile block. Replace `--launch-profile https` (Option 1) with `--launch-profile "LocalDB SQL"`. Replace `--launch-profile "https + Docker SQL (Recommended)"` (Option 2) with `--launch-profile "Docker SQL (Recommended)"`.
- **Frontend appsettings table (~L177–183)** Mark `appsettings.Development.json` as gitignored (per `.gitignore:436`); add `appsettings.Local.json` row for the local-install path (Plan 5).
- **L268–275 (Next Steps)** Replace bullets pointing to nonexistent `scripts/azure/01-provision-azure.md` and `02-configure-github-oidc.md` with a single bullet referencing `.\scripts\deploy.ps1 -Environment {test|prod}` and link to `docs/deployment/getting-started.md`.
- Add brief "Local-only / homelab" subsection under DEV with link to README's "Run locally without Azure".

### 3. `docs/development/docker-setup.md`
- **L72–78 (Option B SA password)** Change `SA_PASSWORD=AHKFlowApp_Dev!2026` to `SA_PASSWORD=Dev!LocalOnly_2026` to match `docker-compose.yml` and `launchSettings.json`.
- Add a short pointer at the top to README's "Run locally without Azure" section.

### 4. `docs/deployment/getting-started.md`
- **L31–42 (resource name table)** Update name patterns to include the deterministic `<token>` suffix where it actually applies: `ahkflowapp-api-{env}-<token>`, `ahkflowapp-sql-{env}-<token>`, `ahkflowapp-db` (not `ahkflowapp-db-{env}`). Match `docs/environments.md`.

### 5. `docs/development/prerequisites.md` (new file)
Single canonical page for local-dev prereqs. Sections:
- **Required:** .NET 10 SDK, Docker Desktop (or Docker Engine on Linux), Git.
- **Windows-specific:** Windows Developer Mode enabled, `git config core.symlinks true`. Reason: cross-tool AI-config symlinks.
- **Optional:** SQL Server LocalDB (Visual Studio install), Visual Studio 2022+ (for launch profiles in IDE).
- **Post-clone setup:** run `scripts/setup-copilot-symlinks.ps1` (Windows) to wire AI-tool symlinks.
- Cross-link: "Deploying to Azure? See `docs/deployment/getting-started.md` for deploy prereqs (Azure CLI, GitHub CLI, sqlcmd)."

### 6. `README.md`
- Replace the inline `### Prerequisites` block (L5–8) with a link to `docs/development/prerequisites.md` (keeping a one-line summary).

### 7. `.claude/CLAUDE.md`, `.claude/rules/*.md`
- Verify-only. No drift expected.

### 8. `.github/*`
- `copilot-instructions.md` — intentional stub. Skip.
- Workflow files / PR template — out of scope.

## Verification

1. **Link check.** Every link in modified docs resolves; every script reference exists.
2. **Dev start command from AGENTS.md works verbatim:** `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"`.
3. **Local-only stack:** `docker compose up --build` brings up sqlserver + api + ui; `http://localhost:5601` loads as `Local User`.
4. **Grep checks (expect 0 hits in tracked files):**
   - `rg "https \+ Docker SQL"`
   - `rg "scripts/azure/0[12]-"`
   - `rg "AHKFlowApp_Dev!2026"`
   - `rg "old_project_reference"`

## PR shape

- Single PR, branch `feature/plan-6-docs-consistency-sweep`.
- Conventional commits per logical group.
- Description links the roadmap.

## Unresolved questions

None at design level. Prereqs page = local-dev + tooling only. AGENTS.md local-install = one-line link.
