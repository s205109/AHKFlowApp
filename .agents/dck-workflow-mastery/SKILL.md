---
name: dck-workflow-mastery
description: Use when optimizing AHKFlowApp agent workflow, worktrees, planning, verification loops, context budget, or tool usage.
---

# Workflow Mastery

## Core Principles

1. **Plan non-trivial work** - For tasks touching several files or architecture, save or review a concrete plan before editing.
2. **Use isolated branches/worktrees** - Never start implementation on `main`; see the `worktrees` skill for creating/removing them, never bare `git worktree add`.
3. **Verify with commands** - `dotnet build`, `dotnet test`, `dotnet format`, setup scripts, and targeted greps are the proof.
4. **Spend context deliberately** - Read files you will edit; use search, Roslyn MCP, and concise summaries for broad exploration.
5. **Project rules win** - `AGENTS.md` and `.claude/rules/*` define AHKFlowApp conventions.

## Worktrees

See the `worktrees` skill for creating, removing, and troubleshooting AHKFlowApp git worktrees (Claude Code, Codex, and Copilot).

## Planning Strategy

Use an implementation plan for:

- architecture changes
- migrations
- feature slices touching API, Application, Infrastructure, UI, or tests together
- cross-agent skill or plugin changes

Review the plan against the live checkout before executing. Stop if project paths, architecture, or verification steps are stale.

## Verification Loop

Use `dck-verify` for the full pipeline. Short version:

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
dotnet format AHKFlowApp.slnx --verify-no-changes
git diff --check
```

For skill changes, also run:

```bash
pwsh -NoProfile -File scripts/agents/setup-cross-agent-skills.ps1
```

## Code Navigation

The live `.claude/rules/agents.md` says to use the Roslyn LSP (from the `dotnet` plugin) or Grep for type lookups, and `dotnet build`/`dotnet test` for regression checks. Roslyn Navigator MCP is now available as an additional option, not a mandate.

Use the cheapest reliable lookup:

| Need | Tool |
|---|---|
| Find symbol/type | Roslyn MCP, Roslyn LSP, or `rg` |
| Find references | Roslyn MCP or `rg` |
| Confirm compiler state | `dotnet build` |
| Confirm behavior | `dotnet test` |
| Inspect exact edit target | Read the file fully |

## Context Discipline

- Start with `rg --files` and targeted `rg -n`.
- Do not read generated files, migrations, or whole directories unless needed.
- Prefer contracts and public APIs before implementations.
- Re-read files you will edit immediately before patching.
- If context gets heavy, summarize known facts and narrow the remaining task.

## Anti-Patterns

- Working on `main`.
- Treating stale plan text as more authoritative than live files.
- Loading many skills or large file trees "just in case".
- Claiming success without fresh command output.
- Creating subagents or worktrees for trivial one-step tasks.
- Assuming MCP is required when grep/build/test gives better evidence.

## Decision Guide

| Scenario | Approach |
|---|---|
| 3+ files or architecture | Plan first |
| Simple targeted fix | Edit and run focused verification |
| Large unknown area | Search/Roslyn first, then read exact files |
| Skill/plugin change | Setup script plus mirror/cache verification |
| Repeated failure | Stop, compare evidence, re-plan |
