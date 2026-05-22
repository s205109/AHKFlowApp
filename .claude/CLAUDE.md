Be concise in all interactions. Optimize for readability when writing documentation. In commit messages, be extremely concise — sacrifice grammar for brevity.

@../AGENTS.md

# Claude Code Configuration

> Sections below are specific to Claude Code. Shared instructions are in AGENTS.md.

## Plans

At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

## Workflow Preferences

- When asked to store instructions or rules, put them in CLAUDE.md (not memory files) unless explicitly told otherwise.
- Browser/UI verification: use the `playwright-cli` skill for any task needing visual confirmation in a browser (frontend changes, UI smoke tests). Invoke it via the Skill tool.
- Before claiming a tool or capability is unavailable, check `.claude/skills/` and available skills. Never assume browser automation is missing — `playwright-cli` is installed.

## Out of Scope

- Runtime execution of AutoHotkey scripts — intentionally excluded (the app generates `.ahk` files, never runs them)

Pending features are tracked in `.claude/backlog/`.

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — ordered work items (implement in backlog order)
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
