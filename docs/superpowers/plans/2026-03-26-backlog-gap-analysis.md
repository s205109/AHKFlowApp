# Backlog Gap Analysis — AHKFlow

## Context

The user asked for an assessment of the current backlog (items 001-026) to identify gaps, missing items, or improvements. This is not an implementation task — the output is a recommendation set to inform whether new items should be added.

---

## Current State (What Is Already Built)

Based on the codebase exploration, items 001-012 are largely complete:

| Status | Items |
|--------|-------|
| Done | 001 (Azure backlog), 002 (GitHub Flow), 003 (scaffold), 004 (test infra), 005 (MinVer), 006 (Serilog), 007 (EF Core), 008 (health checks/Problem Details), 009 (Docker), 010 (CI/CD) |
| Partial | 011 (App Insights — wired, not all docs), 012 (Auth — wired but not enforced on endpoints) |
| Not started | 013–026 (all domain/feature items) |

The Application layer is completely empty (no commands, queries, handlers, MediatR, or FluentValidation pipeline). No business entities exist beyond a scaffold `TestMessage` entity.

---

## Backlog Coverage Assessment

### Strongly Covered

- All product vision "in scope" features have dedicated items: hotstrings (013-019), hotkeys (020-021), profiles (022-023), script generation (024), download (025-026)
- Every foundation concern has an item: testing, logging, versioning, Docker, CI/CD, auth, observability
- Testing standards (unit + integration per feature) are reflected in every feature item's AC

### Gaps Found

#### 1. Missing: CLI scaffold item (critical prerequisite)

CLAUDE.md marks `src/Tools/AHKFlow.CLI` as "planned, directory not yet created." Yet items 012, 015, 017, and 026 all have CLI as an interface. There is no item to create the CLI project, set up the console app, wire authentication, or configure the API HttpClient for CLI use.

**Recommendation:** Add **027 - Scaffold CLI project** (Epic: Foundation), placed before item 012 (auth) in the ordered backlog. It would cover: create `src/Tools/AHKFlow.CLI`, wire API HttpClient, basic command structure (e.g., Spectre.Console or System.CommandLine), and `--profile` argument handling.

#### 2. Missing: Hotkeys search & filtering

Item 018 covers hotstring search/filtering across UI, API, and CLI. There is no equivalent for hotkeys. If search becomes important for a profile with many hotkeys, this would be a gap.

**Recommendation:** Add **028 - Hotkeys search & filtering** (Epic: Hotkeys), mirroring 018's structure scoped to hotkeys. Could be deferred and marked explicitly out of scope in 021 if search is not planned for hotkeys.

#### 3. Minor: Hotkeys validation/Problem Details embedded, not standalone

Items 015 and 016 are standalone items for hotstring validation and Problem Details. For hotkeys, item 020 says "consistent with hotstrings" — the work is implied but not broken out. This is fine for a small backlog, but consider whether the AC in item 020 makes it explicit enough.

**Recommendation:** No new item needed; verify 020's AC covers it (it currently does).

#### 4. Minor: TestMessage scaffold entity cleanup

The codebase has a `TestMessage` entity, `TestMessageConfiguration`, and one migration that seeded scaffold data. This needs to be removed when real domain entities are added. It's likely handled naturally in item 013 (first real entity), but not called out anywhere.

**Recommendation:** Add a note to item 013's AC: "Remove `TestMessage` scaffold entity, configuration, and migration; replace with initial `Hotstring` entity migration."

#### 5. Observation: No bulk operations item

018 covers search/filtering. There is no item for bulk import/export of hotstrings. Items 013 and 018 both say "Bulk import/export" is out of scope. This is consistent and fine — just confirming it's a deliberate omission.

#### 6. Observation: No rate limiting item

Not currently in the backlog. Standard for public-facing APIs. Omission is reasonable for a personal-use tool at this stage.

---

## Summary Table

| # | Recommendation | Priority |
|---|----------------|----------|
| Add 027 | Scaffold CLI project | High — prerequisite for 012, 017, 026 |
| Add 028 | Hotkeys search & filtering | Low — can be deferred or noted as out of scope in 021 |
| Update 013 | Add AC to remove TestMessage scaffold | Low — cleanup note |
| No action | Hotkeys validation (covered in 020 AC) | — |
| No action | Bulk operations (explicitly out of scope) | — |
| No action | Rate limiting (out of scope for now) | — |

---

## Files to Modify (if approved)

- `.claude/backlog/027-scaffold-cli-project.md` (new)
- `.claude/backlog/028-hotkeys-search-filtering.md` (new, if approved)
- `.claude/backlog/013-hotstrings-api-crud-openapi.md` (add AC for TestMessage cleanup)
