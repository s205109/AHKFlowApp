# Codebase Simplification Roadmap — Design

**Date:** 2026-04-21
**Status:** Draft (awaiting user review)

## Goal

Simplify the AHKFlowApp codebase, scripts, and documentation through six small, independent plans. Each plan ships as its own PR. No grand rewrite.

## Principles

- Simplify only what exists. Don't design for backlog features.
- Delete before abstracting. Prefer removing code over introducing patterns.
- Each plan has a clear entry/exit state and lands independently.
- Scale ambition to the stage: foundation-only codebase; avoid speculative design.

## Roadmap

Six sequential plans. Each one writes its own implementation plan via the `writing-plans` skill when it starts.

| # | Plan | Output | Size |
|---|---|---|---|
| 1 | Audit & decide | Decisions doc; PR #66 landed | S |
| 2 | Targeted coverage uplift | Tiered thresholds enforced in CI | M |
| 3 | Code simplification | Low-value complexity removed; at most 1-2 patterns | M-L |
| 4 | Script + deploy.ps1 overhaul | Single `/scripts/` folder; PS v5; preflight; frontend auto-trigger | M |
| 5 | Local-install docs | README "Run locally" section backed by working compose | S |
| 6 | Docs + consistency sweep | Aligned README / AGENTS / `.claude/` / `.github/` | S |

### Sequencing rationale

1. **Audit first** so plans 2-6 know what survives.
2. **Coverage second** — test surviving code, not code about to be deleted.
3. **Simplify third** on well-tested code.
4. **Scripts, local-install docs, consistency sweep last** — they reference the new shape.

## Per-plan scope

### Plan 1 — Audit & decide (S)

In scope:
- Land PR #66 (unique-suffix fix on globally-scoped Azure resources) to unblock plan 4.
- Run `dotnet list package --outdated` — record stale packages; do not upgrade.
- One pass with the `cck-security-scan` skill — record findings; fixes go in later plans.
- Output: a short decisions doc capturing what survives, what goes, what moves.

Not in scope:
- Any code changes beyond merging PR #66.
- Package upgrades.
- Security fixes (recorded only; fixed in later plans).

### Plan 2 — Targeted coverage uplift (M)

In scope:
- Per-project coverage thresholds in CI:
  - Domain / Application: **85 % line, 70 % branch**
  - Infrastructure: **70 % line, 50 % branch**
  - API: **75 % line, 55 % branch**
  - UI.Blazor: **65 % line, 45 % branch**
- Cull low-value bUnit tests (DTO rendering, trivial pass-throughs) before raising the UI bar.
- Add tests only where the coverage gap sits on code plan 1 says is surviving.

Not in scope:
- Blanket per-repo numbers.
- Test framework migration.
- Re-architecting integration tests (Testcontainers already in use).

### Plan 3 — Code simplification (M-L)

In scope:
- Sweep the C# code for and remove: dead code, unused DI registrations, speculative abstractions, over-generic helpers, catch-rethrow blocks, defensive null checks past system boundaries.
- Flag at most 1-2 C# pattern opportunities; discuss each before applying. A likely candidate: a small Result-to-HTTP mapping helper in controllers, only if it removes more code than it adds.
- Pattern candidates for scripts (e.g., a phase structure inside `deploy.ps1`) are owned by plan 4, not this plan.

Not in scope:
- Renaming.
- Re-organising layer folders.
- New features, new abstractions beyond the 1-2 discussed.

### Plan 4 — Script + deploy.ps1 overhaul (M)

In scope:
- Consolidate `docs/scripts/*` → `/scripts/` (single folder).
- PowerShell 5.1 compatibility sweep on all scripts — no null-coalescing, no ternary, no PS 7-only syntax.
- `deploy.ps1` (currently ~692 lines):
  - Preflight block checking: .NET 10 SDK, Azure CLI, Bicep, jq, GitHub CLI, PowerShell version. Fail fast with remediation guidance; support `-SkipPrereqCheck`.
  - Phase-separated structure — discussed and confirmed in this plan before applying.
  - On successful Azure deploy, trigger `deploy-frontend.yml` via `gh workflow run` for the target environment.
  - Ordering of post-provision calls: DB migrate → API deploy → health probe passes → then trigger frontend workflow.

Not in scope:
- Bicep rewrites.
- New Azure resource types or topology changes.
- Key Vault introduction (tracked separately).

### Plan 5 — Local-install docs (S)

In scope:
- README section "Run locally without Azure": prerequisites (Docker Desktop or Docker Engine), `docker compose up`, local URLs, seed notes.
- Verify `docker-compose.yml` works end-to-end on a clean checkout.

Not in scope:
- A separate `run-local.ps1` / `deploy-local.ps1` script.
- A new compose profile.
- Raspberry Pi-specific tuning.

### Plan 6 — Docs + consistency sweep (S)

In scope:
- Cross-check and align: `README.md`, `AGENTS.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, `.github/*`, `docs/**`.
- Fix stale commands, broken links, drifted tech-stack versions, contradictions.
- Single Prerequisites page linked from README.

Not in scope:
- Rewriting architecture docs.
- Adding new guides.

## Success criteria (overall)

- Every plan ships as one PR, reviewable in under 30 minutes.
- `scripts/` is one folder. Every script parses under Windows PowerShell 5.1.
- `deploy.ps1` starts with a preflight block and, on success, triggers the frontend CD workflow without manual action.
- CI enforces per-project coverage thresholds; no blanket number.
- README has a "Run locally" path that works on a fresh clone via `docker compose up`.
- No contradictions between `README.md`, `AGENTS.md`, `.claude/`, `.github/`.

## Non-goals

- New features. Hotstring / Hotkey / Profile CRUD stays in backlog.
- New abstractions beyond the 1-2 patterns discussed in plan 3.
- Bicep topology changes or new Azure resources.
- A separate local-deploy script.
- Migrating off MediatR, Ardalis.Result, FluentValidation, or MudBlazor.
- Package upgrades (recorded in plan 1, deferred).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Plan 3 breaks untested behaviour | Plan 2 lands first and raises targeted coverage. |
| `deploy.ps1` preflight false-positives block working setups | Check version floors (not exact matches); support `-SkipPrereqCheck`. |
| Auto-triggered frontend deploy runs before DB migration | Order: migrate DB → deploy API → health probe → then trigger frontend workflow. |
| PS v5 sweep breaks PS 7 callers | Target PS 5.1 syntax — it works on PS 7 too. |
| PR #66 rebase conflicts with plan 4 edits | Land PR #66 as the first act of plan 1, before plan 4 starts. |

## Decisions made during brainstorming

| Question | Decision |
|---|---|
| Coverage blanket vs tiered | Tiered per project. |
| UI.Blazor bUnit strategy | Cull low-value tests; threshold 65 / 45. |
| Local install approach | Docs-only. No new script. |
| PR #66 handling | Land as-is before plan 4. |
| `old_project_reference/` | Already removed manually; no repo action. |
| Backlog items 013-029 | Ignored during simplification; adapt to new shape when implemented. |
| Repo root cruft | All locally-gitignored; nothing to clean in repo. |
| Pattern opportunities | Cap at 1-2; each discussed before applying. |

## Open questions

None at design level. Per-plan questions surface during each plan's `writing-plans` step.
