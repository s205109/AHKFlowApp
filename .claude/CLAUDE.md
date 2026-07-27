Be concise in all interactions. For documentation and app-facing text, follow **Plain English** in AGENTS.md — when short and easy-to-read fight, easy-to-read wins. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Workflow Preferences

- When asked to store instructions or rules, put them in CLAUDE.md (not memory files) unless explicitly told otherwise.
- Verifying finished work is governed by **Verification After Implementation** in AGENTS.md. Invoke the `playwright-cli` skill via the Skill tool when that routing calls for a browser drive.
- Before claiming a tool or capability is unavailable, check `.claude/skills/` and available skills. Never assume browser automation is missing — `playwright-cli` is installed.

## Out of Scope

- Runtime execution of AutoHotkey scripts — intentionally excluded (the app generates `.ahk` files, never runs them)

Pending features are tracked in `.claude/backlog/`.

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — open items; completed items live in `done/`
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
