# First-Release Cleanup Roadmap — Design

**Date:** 2026-07-04
**Status:** Approved
**Supersedes:** [2026-04-21 Codebase Simplification Roadmap](2026-04-21-codebase-simplification-roadmap-design.md)

## Goal

Get AHKFlowApp release-ready through three small cleanup plans plus one feature-ideation spec. Carry forward only what the 2026-04-21 roadmap left open; address gaps that appeared since (explicit-use-case migration, version history, CLI + winget).

## Status of the superseded roadmap

All six plans of the 2026-04-21 roadmap are **executed**:

| Old plan | Evidence |
|---|---|
| 1 Audit & decide | `docs/superpowers/audits/2026-04-21-baseline-audit.md` |
| 2 Coverage uplift | Tiered thresholds enforced by `scripts/check-coverage-thresholds.py` in `ci.yml` |
| 3 Code simplification | Landed; later superseded by explicit-use-case migration + MediatR removal |
| 4 Script/deploy overhaul | Single `scripts/` folder; `deploy.ps1` phased prereq checks + `-SkipPrereqCheck` |
| 5 Local install, no Azure | README "Run locally without Azure", `Auth:UseTestProvider`, Dev-only guard |
| 6 Docs consistency sweep | Landed 2026-04-26; active docs carry zero stale MediatR references |

## Principles

- Simplify only what exists. Don't design for backlog features.
- Delete before abstracting; archive before deleting when history helps.
- Each plan lands as one PR, sized for one session, independently verifiable.
- The worktree/local-dev tooling is one contract (`new-worktree.ps1`, `setup-/remove-worktree-local-dev.ps1`, `prune-worktree-*.ps1`, `worktree-*.common.ps1`, `.worktreeinclude`, `scripts/.env.worktree`, `scripts/.env.local`): change together or not at all. This roadmap does not touch it.
- No frontend visual design work; usability observations are recorded as findings only.

## Plan index

| Plan | Depends on | Session size | Verification | Supersedes |
|---|---|---|---|---|
| A [Backend code consistency](../plans/2026-07-04-backend-code-consistency.md) | — | one (M) | `dotnet build AHKFlowApp.slnx` + `scripts/test-fast.ps1` + `dotnet format AHKFlowApp.slnx --verify-no-changes` | extends old plan 3 |
| B [Scripts organization + friendly output](../plans/2026-07-04-scripts-organization-friendly-output.md) | — | one (M) | PS parse check + `scripts/test-fast.ps1` + `scripts/run-coverage.ps1` + CI green + worktree smoke | extends old plan 4 |
| C [Docs current-state simplification](../plans/2026-07-04-docs-current-state-simplification.md) | A, B | one (S-M) | link check + spot-run quoted commands | supersedes old plan 6 |
| D [First-release feature shortlist](2026-07-04-first-release-feature-shortlist.md) (spec, ideation only) | — | one (S) | user approval; nothing built | new |

A and B are independent and can run in either order. C runs last so it documents the final code shape and script paths. D is a ranked ideation spec — nothing is built until the user approves items from it.

## Per-plan scope

### Plan A — Backend code consistency (M)

In scope (from the 2026-07-04 backend audit):
- Hotstring↔Hotkey vertical drift: create-handler post-save reloads, `ValidationError.Identifier` shape, validator-helper naming, update-handler category-junction asymmetry.
- Shared helper for the copy-pasted ProfileIds/CategoryIds existence checks (4 handlers).
- Move `DownloadsController` zip assembly into a use case.
- Remove `TestMessage` scaffolding (entity, EF config + seed, DbSet, DropTable migration).

Out of scope: CLI work, renames beyond the validator helper (`Behaviors/`→`Decorators/` rename skipped per decision #4), new patterns, frontend.

Verified-clean areas the audit says NOT to spend time on: naming/Result/validator uniformity, controller thinness + explicit auth, TimeProvider usage, CancellationToken propagation, warning suppressions.

### Plan B — Scripts organization + friendly output (M)

In scope:
- Partial subfolders: `scripts/ci/` (check-coverage-thresholds.py, generate-changelog-json.ps1) and `scripts/agents/` (setup-copilot-symlinks, check-symlinks, setup-cross-agent-skills.ps1/.sh); update every reference.
- Move `create-github-issues.ps1` (one-time backlog seeding, long done) to `scripts/agents/`.
- `scripts/README.md` index grouping user-facing / test / CI / agents / worktree-internal.
- Consistent, friendly status output on user-facing manual scripts via the existing `Common.ps1` helpers — no logic changes.

Out of scope: any change to the worktree contract set; behavior changes; PowerShell version changes (generate-changelog-json.ps1 stays PS 7, documented).

### Plan C — Docs current-state simplification (S-M)

In scope (from the 2026-07-04 docs audit):
- README: one coherent quickstart (drop the manual `dotnet ef database update` step that contradicts auto-migrate-at-startup); one "recommended" local path consistent across README / AGENTS.md / docker-setup.md; a short end-user Getting Started front door.
- Staleness: playwright-setup.md port 7601→5601; product-vision.md Current Scope adds version history / recycle bin / changelog; AGENTS.md CI/CD list adds `release-cli.yml`; configuration-strategy.md trimmed, dated, UseTestProvider path added.
- Merge the two worktree-*-manual-testing docs into one.
- Archive historical material: `docs/development/github-setup.md` and `docs/copilot/*` → `docs/superpowers/plans/`; completed `.claude/backlog/` items → `.claude/backlog/done/`; re-check the satisfied deferral boxes in items 015/017.
- Post-A/B reference sweep for moved script paths.

Out of scope: rewriting architecture docs; new guides beyond the small Getting Started section.

### Plan D — First-release feature shortlist (S, spec only)

Ranked value/effort ideation: CLI vertical completion (hotkeys/categories/profiles), winget community-feed submission (the open remainder of backlog 031), hotkey blacklisting, bulk import/export, onboarding hints, plus anything surfaced while writing. No UI design, no build without explicit user approval per item.

## Sequencing rationale

1. **A and B first, in parallel or either order** — they touch disjoint files (C# vs scripts).
2. **C last** — docs describe the post-A code shape and post-B script paths; doing it earlier means re-editing.
3. **D anytime** — it only reads the audit and product vision.

## Success criteria

- Hotstring and Hotkey verticals behave identically for create/update association handling; a fix in one can't silently miss the other pattern again (shared helper).
- `TestMessage` gone from Domain, Infrastructure, and the database schema.
- `scripts/` top level contains only user-facing and worktree-contract files; internals live in `scripts/ci/` and `scripts/agents/`; `scripts/README.md` indexes everything; CI stays green through the moves.
- README serves an end user's first five minutes and a contributor's first run without contradiction.
- No active doc references a moved/removed file, port 7601, or a shipped-feature-as-pending backlog item.
- Feature shortlist exists, ranked, awaiting user approval — nothing built from it.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| TestMessage DropTable migration surprises TEST/PROD | Migration reviewed in PR; deploy pipeline already runs migrations; table carries only seed data |
| Moving CI scripts breaks workflows | Plan B task 1 inventories every reference before any move; CI must be green on the PR |
| Scripts "friendly output" pass accidentally changes behavior | Output-only edits via existing Common.ps1 helpers; parse check + test-fast + coverage script runs |
| Docs plan edits paths that plan B then changes | C depends on A and B; runs last |
| Create/Update handler fixes change API responses clients rely on | Changes covered by integration tests asserting DTO contents before/after |

## Decisions (2026-07-04, user)

1. **CLI scope:** build full command parity and make the CLI production-ready — a separate first-class initiative, not a cleanup plan. See [CLI Production Readiness — Design](2026-07-04-cli-production-readiness-design.md).
2. **Winget community submission:** dropped — no release planned. Existing packaging stays correct via related code/docs only; backlog 031's community-feed items stay unchecked.
3. **`create-github-issues.ps1`:** move to `scripts/agents/` (not deleted).
4. **`Behaviors/`→`Decorators/` rename:** skipped — not worth the churn.
5. **`measure-tests.ps1`:** left as-is (excluded from plan B's friendly-output pass).
6. **Archive home:** `docs/superpowers/plans/` (no new `docs/history/`).
