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
- CLI authentication — see backlog item 029

## Project Configuration

- Rules (always loaded): `.claude/rules/`
- Skills (on demand): `.claude/skills/`
- Backlog: `.claude/backlog/` — ordered work items (implement in backlog order)
- Frontend instructions: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`
- Private/local config: `.claude/CLAUDE.local.md` (gitignored)
- Documentation: `docs/` — architecture, azure, development guides
