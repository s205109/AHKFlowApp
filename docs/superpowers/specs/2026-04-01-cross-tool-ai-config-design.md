# Cross-Tool AI Agent Configuration: Claude Code + GitHub Copilot CLI

**Date:** 2026-04-01
**Status:** Draft
**Goal:** Single source of truth for AI agent instructions, rules, skills, and hooks — shared between Claude Code and GitHub Copilot CLI.

## Prerequisites

- **Windows Developer Mode** must be enabled (required for symlinks without admin)
- **`git config core.symlinks true`** must be set per-repo (default is `false` on Windows)

## Approach

**AGENTS.md bridge** — create `AGENTS.md` at repo root as the shared instruction contract. Claude Code imports it via `@../AGENTS.md` in `.claude/CLAUDE.md` (relative path — CLAUDE.md lives in `.claude/`, AGENTS.md at repo root). Copilot CLI reads it natively. Source of truth for all configuration remains in `.claude/`.

## File Layout (Target State)

```
AHKFlowApp/
├── AGENTS.md                              # NEW — shared instructions + 5 inlined rules
├── .claude/CLAUDE.md                      # MODIFIED — @../AGENTS.md import + Claude-specific only
├── .github/
│   ├── instructions/                      # EXISTING — empty, .gitkeep for future use
│   │   └── .gitkeep
│   ├── hooks/
│   │   └── hooks.json                     # NEW — Copilot hook config → .claude/hooks/ scripts
│   └── skills/                            # NEW — 22 symlinks → .claude/skills/
│       ├── cck-api-versioning/        →   ../../.claude/skills/cck-api-versioning/
│       ├── cck-authentication/        →   ../../.claude/skills/cck-authentication/
│       ├── cck-blazor-mudblazor/      →   ../../.claude/skills/cck-blazor-mudblazor/
│       ├── cck-build-fix/             →   ../../.claude/skills/cck-build-fix/
│       ├── cck-ci-cd/                 →   ../../.claude/skills/cck-ci-cd/
│       ├── cck-clean-architecture/    →   ../../.claude/skills/cck-clean-architecture/
│       ├── cck-configuration/         →   ../../.claude/skills/cck-configuration/
│       ├── cck-dependency-injection/  →   ../../.claude/skills/cck-dependency-injection/
│       ├── cck-docker/                →   ../../.claude/skills/cck-docker/
│       ├── cck-ef-core/               →   ../../.claude/skills/cck-ef-core/
│       ├── cck-error-handling/        →   ../../.claude/skills/cck-error-handling/
│       ├── cck-httpclient-factory/    →   ../../.claude/skills/cck-httpclient-factory/
│       ├── cck-logging/               →   ../../.claude/skills/cck-logging/
│       ├── cck-migration-workflow/    →   ../../.claude/skills/cck-migration-workflow/
│       ├── cck-modern-csharp/         →   ../../.claude/skills/cck-modern-csharp/
│       ├── cck-openapi/               →   ../../.claude/skills/cck-openapi/
│       ├── cck-project-structure/     →   ../../.claude/skills/cck-project-structure/
│       ├── cck-resilience/            →   ../../.claude/skills/cck-resilience/
│       ├── cck-scaffolding/           →   ../../.claude/skills/cck-scaffolding/
│       ├── cck-security-scan/         →   ../../.claude/skills/cck-security-scan/
│       ├── cck-testing/               →   ../../.claude/skills/cck-testing/
│       └── cck-verify/                →   ../../.claude/skills/cck-verify/
├── .claude/
│   ├── skills/                            # UNCHANGED — source of truth for all 26 skills
│   ├── rules/                             # TRIMMED — keep only agents.md, hooks.md
│   ├── hooks/                             # UNCHANGED — source of truth for hook scripts
│   └── settings.json                      # UNCHANGED
├── scripts/
│   └── setup-copilot-symlinks.ps1         # NEW — one-time setup + validation
```

## Component Details

### 1. AGENTS.md (New File)

Single source of truth for shared instructions. Both tools read it — Copilot natively, Claude Code via `@import`.

**Content (moved from CLAUDE.md):**

| Section | Source |
|---|---|
| Overview | CLAUDE.md `## Overview` |
| Tech Stack | CLAUDE.md `## Tech Stack` |
| Project Structure | CLAUDE.md `## Project Structure` |
| Commands | CLAUDE.md `## Commands` |
| Architecture Rules | CLAUDE.md `## Architecture Rules` |
| Code Conventions | CLAUDE.md `## Code Conventions` (naming, patterns we use, patterns we don't use) |
| Request Flow | CLAUDE.md `## Request Flow` |
| Testing | CLAUDE.md `## Testing` |
| CI/CD | CLAUDE.md `## CI/CD` |
| Git Workflow | CLAUDE.md `## Git Workflow` |
| GitHub | CLAUDE.md `## GitHub` |
| Domain Terms | CLAUDE.md `## Domain Terms` |
| Local URLs | CLAUDE.md `## Local URLs` |

**Rules inlined as subsections under `## Rules`:**

| Rule | Source |
|---|---|
| `### Naming` | `.claude/rules/naming.md` |
| `### Packages` | `.claude/rules/packages.md` |
| `### Performance` | `.claude/rules/performance.md` |
| `### Security` | `.claude/rules/security.md` |
| `### Testing` | `.claude/rules/testing.md` |

These 5 files are **deleted** from `.claude/rules/` after inlining — AGENTS.md is the single source.

### 2. CLAUDE.md (Refactored)

Slimmed down to Claude-Code-specific configuration only.

```markdown
Be concise in all interactions. Optimize for readability when writing documentation. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Plans
(kept — Claude-specific plan format preferences)

## Workflow Preferences
(kept — memory files, instruction storage)

## Out of Scope
(kept — backlog scope guard)

## Project Configuration
- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — ordered work items (implement in backlog order)
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
```

**Notes:**
- First line is the existing concise-style directive — kept in CLAUDE.md (applies to both tools via import chain, but primarily a Claude Code concern)
- `@../AGENTS.md` resolves relative to `.claude/CLAUDE.md`'s directory, reaching the repo-root `AGENTS.md`
- `Project Configuration` paths corrected to match actual directory structure (removed stale `/claude-code-kit/` subpath references)

**Rules remaining in `.claude/rules/` (Claude-specific, not inlined):**
- `agents.md` — subagent/model selection guidance
- `hooks.md` — hook interaction rules

### 3. Skill Symlinks

**22 portable skills** symlinked from `.github/skills/` → `.claude/skills/`.

**4 excluded (Claude-specific):**

| Skill | Reason |
|---|---|
| `cck-context-discipline` | Claude Code context window management (empty — no SKILL.md) |
| `cck-de-sloppify` | References Claude Code MCP tools (get_diagnostics, find_dead_code, etc.) |
| `cck-model-selection` | Claude model selection (Opus/Sonnet/Haiku) (empty — no SKILL.md) |
| `mp-grill-me` | Claude Code interaction pattern |

**Note:** `cck-context-discipline` and `cck-model-selection` have empty directories (no SKILL.md file). They are excluded regardless — even if populated later, their content would be Claude-specific.

Symlinks are relative paths so they work across machines:

```powershell
# Example: one symlink
New-Item -ItemType SymbolicLink `
  -Path ".github/skills/cck-api-versioning" `
  -Target "../../.claude/skills/cck-api-versioning"
```

### 4. Hooks

Hook **scripts** stay in `.claude/hooks/` (source of truth). Claude Code wires them via `.claude/settings.json`. Copilot CLI wires them via `.github/hooks/hooks.json`.

**`.github/hooks/hooks.json`:**

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

**Provisional schema:** The hooks.json format above is based on Copilot CLI documentation for hook configuration. The exact schema must be validated against the current Copilot CLI version during implementation. If the schema differs, adjust the JSON structure to match — the underlying scripts remain the same.

**Dual-tool hook strategy:** The hook scripts currently rely on Claude Code environment variables (`CLAUDE_TOOL_INPUT`, `CLAUDE_EDITED_FILE`, etc.). For Copilot CLI compatibility, scripts will use a detection pattern:

1. Check for Claude Code env vars first (e.g., `if ($env:CLAUDE_TOOL_INPUT)`)
2. Fall back to Copilot CLI's input mechanism (JSON on stdin)
3. If neither is present, exit gracefully (no-op)

This keeps backward compatibility with Claude Code while adding Copilot support. The detection logic will be added during implementation and tested with both tools.

### 5. Setup Script

`scripts/setup-copilot-symlinks.ps1` — run once after cloning or by CI.

**Responsibilities:**
1. Verify Windows Developer Mode is enabled (fail with instructions if not)
2. Verify/set `git config core.symlinks true` for the repo
3. Create `.github/skills/` directory
4. Create 22 symlinks (skip if already exist)
5. Report results

**Error handling:**
- Fail fast with actionable error messages
- Idempotent — safe to re-run

**Note:** The `scripts/` directory does not exist yet — create it as part of implementation.

### 6. Rules Cleanup

| File | Action |
|---|---|
| `.claude/rules/naming.md` | Delete — inlined in AGENTS.md |
| `.claude/rules/packages.md` | Delete — inlined in AGENTS.md |
| `.claude/rules/performance.md` | Delete — inlined in AGENTS.md |
| `.claude/rules/security.md` | Delete — inlined in AGENTS.md |
| `.claude/rules/testing.md` | Delete — inlined in AGENTS.md |
| `.claude/rules/agents.md` | Keep — Claude-specific |
| `.claude/rules/hooks.md` | Keep — Claude-specific |

### 7. .gitignore / .gitattributes

No changes to `.gitignore` needed — symlinks are committed.

No `.gitattributes` needed — git handles symlinks natively. The setup script ensures `core.symlinks=true`.

**CI note:** GitHub Actions Linux runners handle symlinks natively. If a future CI workflow needs to read `.github/skills/` symlinks on a Windows runner, add `git config core.symlinks true` + re-checkout as a workflow step.

## How Each Tool Reads the Configuration

### Claude Code

```
.claude/CLAUDE.md
  └── @../AGENTS.md (imported — shared instructions + 5 rules)
  └── Claude-specific sections (plans, workflow, out-of-scope, config paths)
.claude/rules/agents.md     (always loaded — subagent guidance)
.claude/rules/hooks.md      (always loaded — hook rules)
.claude/skills/*/SKILL.md   (on-demand — all 26 skills)
.claude/settings.json       (hooks, permissions, plugins)
```

### GitHub Copilot CLI

```
AGENTS.md                           (native — shared instructions + 5 rules)
.claude/CLAUDE.md                   (native cross-tool — Claude-specific sections included but benign)
.github/skills/*/SKILL.md           (native — 22 symlinked portable skills)
.github/hooks/hooks.json            (native — references .claude/hooks/ scripts)
```

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Copilot CLI symlink issues (#1090) | Medium | Skills not loaded | Setup script validates symlinks; fall back to copies if broken |
| Hook input/output contract mismatch | Medium | Hooks don't fire correctly in Copilot | Add tool-detection logic in scripts; test during implementation |
| `core.symlinks=false` on clone | High (Windows default) | Symlinks become text files | Setup script fixes this; document in AGENTS.md and README |
| AGENTS.md + CLAUDE.md overlap in Copilot | Low | Minor instruction noise | CLAUDE.md header clarifies Claude-specific scope |
| Rule drift (AGENTS.md vs deleted .claude/rules/) | Low | N/A — single source | Rules only exist in AGENTS.md; no duplication |

## Out of Scope

- Porting to other tools (Codex, Gemini CLI, Cursor) — AGENTS.md enables this for free later
- Copilot custom agents (`.github/agents/*.agent.md`) — future enhancement
- Copilot custom prompts (`.github/prompts/`) — not yet supported in CLI
- Moving source of truth from `.claude/` to `.github/`
