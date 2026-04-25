# Claude Configuration & Setup Improvements for AHKFlow

## Context

Comprehensive audit of the Claude Code configuration (rules, skills, hooks, plugins, MCP servers, docs, backlog). The setup is already mature — 5 rules, 28 skills, 4 hooks, 14 plugins, 1 MCP server, 28 backlog items. This plan addresses gaps, inconsistencies, overlaps, and missing backlog items found during the audit.

---

## 1. Rules — Fix & Add

### 1a. Fix `hooks.md` — references nonexistent hooks [LOW]
**File:** `.claude/rules/claude-code-kit/hooks.md`

Remove these two lines that reference hooks that don't exist:
- "Review post-test-analyze hook output for actionable insights." → no post-test hook exists
- "Wait for post-scaffold-restore to complete after `.csproj` changes before building." → no post-scaffold hook exists

### 1b. Add `testing.md` rule [HIGH]
**File:** `.claude/rules/claude-code-kit/testing.md`

Extract core testing constraints from CLAUDE.md into an always-loaded rule. Key points:
- Integration tests first (WebApplicationFactory + Testcontainers)
- Never `UseInMemoryDatabase`
- NSubstitute for third-party boundaries only — don't mock what you own
- Test naming: `MethodName_Scenario_ExpectedResult`
- AAA pattern, one assertion concept per test

This prevents the #1 AI mistake: suggesting InMemoryDatabase or mocking owned types.

### 1c. Add `naming.md` rule [MEDIUM]
**File:** `.claude/rules/claude-code-kit/naming.md`

Extract naming conventions from CLAUDE.md:
- Controllers: plural (`HotstringsController`)
- DTOs: `{Entity}Dto`, `Create{Entity}Dto`
- Commands/Queries: `Create{Entity}Command`, `Get{Entity}Query`
- Handlers: `{Command/Query}Handler`
- Async methods: `*Async` suffix

Currently buried in CLAUDE.md's 200+ lines — AI frequently misses these.

---

## 2. Skills — Consolidate & Add

### 2a. Merge `logging` + `serilog` skills [MEDIUM]
AHKFlow uses Serilog exclusively. Merge `serilog` content into `logging` (or rename to `observability`). Delete the standalone `serilog` skill.

**Files:**
- `.claude/skills/claude-code-kit/logging/SKILL.md` — absorb serilog content
- `.claude/skills/claude-code-kit/serilog/` — delete

### 2b. Demote `model-selection` and `context-discipline` to docs [LOW]
These teach Claude how to use itself — 400+ lines of guidance Claude already knows. Move to `docs/development/` as reference material. Delete from skills.

**Files to delete:**
- `.claude/skills/claude-code-kit/model-selection/`
- `.claude/skills/claude-code-kit/context-discipline/`

**Files to create:**
- `docs/development/model-selection.md`
- `docs/development/context-discipline.md`

### 2c. Add `blazor-mudblazor` skill [HIGH]
Backlog items 014 and 022 are UI CRUD features coming soon. The frontend CLAUDE.md (66 lines) covers basics but lacks a proper skill with:
- MudTable server-side pagination pattern
- MudForm validation with FluentValidation
- MudDialog CRUD workflow (create/edit/delete confirmation)
- MudSnackbar feedback patterns
- Common anti-patterns (missing `@bind-Value`, forgetting `For` lambda)

**File:** `.claude/skills/claude-code-kit/blazor-mudblazor/SKILL.md`

### 2d. Resolve `code-review-workflow` skill vs `code-review` plugin [MEDIUM]
Both exist. The skill references Roslyn MCP tools that don't exist yet. The plugin provides a working review workflow.

**Action:** Remove the `code-review-workflow` skill. Keep the `code-review` plugin as the single code review path.

**File to delete:** `.claude/skills/claude-code-kit/code-review-workflow/`

---

## 3. Hooks — Optimize

### 3a. Pre-commit hooks fire on every Bash call [MEDIUM]
`pre-commit-format.ps1` and `pre-commit-antipattern.ps1` have matcher `"Bash"` — they spin up PowerShell for every `ls`, `git status`, `dotnet build`, etc. They fast-exit on non-commit commands, but the PowerShell startup cost adds up.

**Option A (recommended):** Add a fast bash wrapper that checks if the command starts with `git commit` before launching PowerShell. This avoids the PowerShell startup penalty for non-commit commands.

**Option B:** Accept the overhead if measured latency is negligible.

**Files:** `.claude/settings.json` (hook commands), potentially new wrapper scripts

---

## 4. Plugins — Clean Up

### 4a. Decide on `pr-review-toolkit` [MEDIUM]
Currently "temporarily disabled" with no documented reason.

**Action:** Remove it from settings.json entirely. If needed later, re-add with a documented reason.

**File:** `.claude/settings.json`

### 4b. Remove `claude-code-setup` plugin [LOW]
Setup phase is complete. This plugin is for initial configuration which is already done.

**File:** `.claude/settings.json`

---

## 5. Documentation — Fix Gaps

### 5a. Delete `docs/instructions/` [MEDIUM]
5 files confirmed unused (leftover, not consumed by Copilot or any tool). They duplicate skills and CLAUDE.md:
- `clean-architecture.instructions.md`
- `entity-framework-core.instructions.md`
- `aspnet-core-webapi.instructions.md`
- `blazor-webassembly.instructions.md`
- `dotnet-csharp.instructions.md`

Also remove references to these from `.slnx` if present.

### 5b. Enhance PR template [LOW]
Current template is 3 lines. Add sections for upcoming UI work:
- Summary of changes
- Testing approach
- Screenshots (for UI changes)

**File:** `.github/PULL_REQUEST_TEMPLATE.md`

---

## 6. Configuration

### 6a. Switch default model to Sonnet [MEDIUM]
**File:** `C:\Users\btase\.claude\settings.json`

Change `"model": "opus"` → `"model": "sonnet"`. Use `/model opus` for architecture/planning sessions.

---

## 7. New Backlog Items

### 7a. `029-add-build-infrastructure` [HIGH]
Add `global.json` (pin SDK), `Directory.Build.props` (shared build props: nullable, implicit usings, warnings as errors), `Directory.Packages.props` (Central Package Management). The `packages.md` rule already references CPM but the infrastructure doesn't exist.

### 7b. `030-write-readme` [HIGH]
README is currently `# AHKFlow`. Extract content from `docs/architecture/product-vision.md` and CLAUDE.md: project description, tech stack, prerequisites, quick start, project structure, license.

### 7c. `031-add-github-issue-templates` [MEDIUM]
No `.github/ISSUE_TEMPLATE/` exists. Add bug report and feature request templates.

### 7d. `032-consolidate-documentation` [MEDIUM]
Clean up docs/: remove instructions/ folder, move orphaned reference docs, establish single source of truth for architectural guidance.

### 7e. `033-add-pagination-skill` [MEDIUM]
Backlog items 019 (search/filtering) and 023 (hotkeys search) need server-side pagination. Skill covering: `IQueryable` extensions, `PaginatedList<T>`, query parameters, MudTable server-side pagination integration.

---

## Summary by Priority

| # | Action | Priority | Effort |
|---|--------|----------|--------|
| 1b | Add `testing.md` rule | HIGH | Low |
| 2c | Add `blazor-mudblazor` skill | HIGH | Medium |
| 7a | Backlog: build infrastructure (global.json, CPM) | HIGH | Low |
| 7b | Backlog: write README | HIGH | Low |
| 1c | Add `naming.md` rule | MEDIUM | Low |
| 2a | Merge logging + serilog skills | MEDIUM | Low |
| 2d | Remove code-review-workflow skill | MEDIUM | Low |
| 3a | Optimize pre-commit hook performance | MEDIUM | Medium |
| 4a | Remove pr-review-toolkit plugin | MEDIUM | Low |
| 5a | Delete docs/instructions/ | MEDIUM | Low |
| 6a | Switch default model to Sonnet | MEDIUM | Low |
| 7c | Backlog: GitHub issue templates | MEDIUM | Low |
| 7d | Backlog: consolidate docs | MEDIUM | Low |
| 7e | Backlog: pagination skill | MEDIUM | Low |
| 1a | Fix hooks.md stale references | LOW | Low |
| 2b | Demote model-selection + context-discipline to docs | LOW | Low |
| 4b | Remove claude-code-setup plugin | LOW | Low |
| 5b | Enhance PR template | LOW | Low |

---

## Verification

After implementation:
1. `dotnet build --configuration Release` — ensure no build breaks from any .props changes
2. `dotnet test --configuration Release` — ensure tests still pass
3. Start a new Claude Code session and verify:
   - New rules load (check with `/rules` or observe behavior)
   - Deleted skills no longer appear
   - Merged skills work correctly
   - Hooks still fire on `git commit` but not on other Bash commands (if 3a implemented)
4. Verify backlog items follow the template format in `000-backlog-item-template.md`
5. Verify `.slnx` doesn't reference deleted files

## Unresolved Questions

- Measure pre-commit hook PowerShell startup overhead before deciding on 3a — is it actually noticeable?
- Should backlog items 029-033 go before or after item 012 (auth)? They're infrastructure, not features.
